import Foundation
import Testing
@testable import WooriHaru

/// 접속이 잠깐 끊긴 상황. 서버가 준 도메인 오류와 구분하려고 따로 둔다.
private struct RetryableCaptureError: LocalizedError {
    var errorDescription: String? { "일시적인 오류입니다." }
}

@MainActor
struct MealCaptureViewModelTests {
    /// 폴링이 **성공**하는 걸 보는 테스트용 프로필. 간격은 짧게 두되(대역이 몇 회 만에
    /// 응답을 채우므로) 데드라인은 넉넉한 몇 초로 잡는다 — 병렬로 여러 스위트가 함께 도는
    /// 상황에서 스케줄러가 밀려도 진짜 실패(타임아웃)로 잘못 넘어가지 않게 하기 위해서다.
    /// (`DietDayTests.swift`의 `DietDayViewModelTests.makeVM`과 같은 이유로 같은 모양을 쓴다.)
    private func makeVM(
        _ service: FakeDietService,
        pollInterval: Duration = .milliseconds(1),
        pollTimeout: Duration = .seconds(5)
    ) -> MealCaptureViewModel {
        MealCaptureViewModel(service: service, pollInterval: pollInterval, pollTimeout: pollTimeout)
    }

    private func photos(_ count: Int) -> [Data] {
        (0..<count).map { Data(repeating: UInt8($0), count: 100) }
    }

    @Test func 사진_N장을_순차로_올리고_인식을_요청한다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12, 13]
        service.analyses = [makeAnalysis(status: .pending), makeAnalysis(status: .completed)]
        let vm = makeVM(service)
        vm.append(photos(3))

        await vm.start()

        #expect(service.uploadedByteCounts.count == 3)
        #expect(service.createdFileIds == [[11, 12, 13]])
        #expect(vm.phase == .completed)
        #expect(vm.analysis?.status == .completed)
    }

    /// 중간에 실패하면 **이미 올린 파일을 되돌리려 하지 않는다** — 확정되지 않은 파일은 서버가 수거한다.
    @Test func 업로드_중_실패하면_중단하고_되돌리지_않는다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12, 13]
        service.errors["uploadPhoto#1"] = APIError.networkError(URLError(.timedOut))
        let vm = makeVM(service)
        vm.append(photos(3))

        await vm.start()

        #expect(service.uploadedByteCounts.count == 2)
        #expect(service.createdFileIds.isEmpty)
        #expect(vm.phase == .failed)
        #expect(vm.errorMessage != nil)
        #expect(service.deletedMealIds.isEmpty)
    }

    /// 업로드는 사진 수만큼 시간이 걸리므로 진행 중에 몇 번째를 올리고 있는지 실제로 보여야
    /// 한다 — 첫 업로드를 게이트로 붙잡아 두고 그 순간의 `progressText`를 확인한다.
    @Test func 업로드_진행률이_보인다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12]
        service.analyses = [makeAnalysis()]
        let gate = AsyncGate()
        service.uploadGates[0] = gate
        let vm = makeVM(service)
        vm.append(photos(2))

        #expect(vm.progressText == nil)
        let startTask = Task { await vm.start() }
        await gate.waitUntilBlocked() // 첫 번째 업로드가 게이트 안에서 멈춘 걸 확인하고서야 들여다본다.

        #expect(vm.progressText == "2장 중 1장 올리는 중")
        #expect(vm.uploadedCount == 0)

        await gate.open()
        await startTask.value

        #expect(vm.uploadedCount == 2)
    }

    /// 사진은 최대 5장이다 — 서버가 사진마다 LLM을 호출하므로 장수가 곧 비용·대기시간이다.
    @Test func 다섯_장을_넘겨_담지_않는다() {
        let vm = makeVM(FakeDietService())
        vm.append(photos(7))

        #expect(vm.photoDataList.count == 5)
        #expect(vm.remainingSlots == 0)
    }

    /// 전부 실패했을 때만 확인 화면 대신 실패 상태다.
    @Test func 전부_실패하면_실패_상태다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [makeAnalysis(status: .failed, photos: [
            AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])
        ])]
        let vm = makeVM(service)
        vm.append(photos(1))

        await vm.start()

        #expect(vm.phase == .failed)
        #expect(vm.canRetry)
    }

    /// **iCloud에 있는 원본은 실제로 내려받으므로 초 단위가 걸린다.** 그동안 앨범을 다시 열 수
    /// 있으면 두 묶음이 각자 `append`로 들어와 5장 상한에서 늦게 끝난 쪽이 소리 없이 버려진다 —
    /// 사용자에게는 「고른 사진이 안 들어갔다」로만 보인다.
    @Test func 사진을_읽는_동안_두_번째_선택을_받지_않는다() async {
        let vm = makeVM(FakeDietService())
        let gate = AsyncGate()

        let loading = Task {
            await vm.loadPicks {
                await gate.hold()
                return self.photos(3)
            }
        }
        await gate.waitUntilBlocked()
        #expect(vm.isLoadingPicks)

        // 첫 묶음을 읽는 중에 앨범을 다시 열어 고른 경우.
        await vm.loadPicks { self.photos(3) }

        await gate.open()
        await loading.value

        #expect(vm.photoDataList.count == 3)
        #expect(!vm.isLoadingPicks)
    }

    /// **재시도는 서버에 남은 그 인식을 다시 돌리는 것이다** — 사진을 바꾼 뒤에도 열어 두면
    /// 방금 담은 사진이 끝내 안 들어간 결과를 가져온다. 화면은 이 값으로 「다시 인식」과
    /// 「인식 시작」 중 하나만 띄우므로, 여기서 꺼야 새 인식을 낼 길이 돌아온다.
    @Test func 사진을_바꾸면_예전_인식으로_재시도하지_않는다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12]
        service.analyses = [makeAnalysis(status: .failed, photos: [
            AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: []),
            AnalyzedPhoto(fileId: 12, url: nil, failed: true, items: [])
        ])]
        let vm = makeVM(service)
        vm.append(photos(2))
        await vm.start()
        #expect(vm.canRetry)

        vm.remove(at: 0)

        #expect(!vm.canRetry)
        await vm.retry()
        #expect(service.retriedAnalysisIds.isEmpty)

        // 사진을 새로 담아도 마찬가지다.
        vm.append(photos(1))
        #expect(!vm.canRetry)
    }

    /// 「인식 시작」을 다시 눌렀는데 업로드에서 실패하면, 예전 `analysisId`가 `canRetry`와 함께
    /// 남아 **이번 사진과 무관한 옛 인식**을 되살릴 수 있다.
    @Test func 인식을_다시_시작하면_예전_인식_id가_남지_않는다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [makeAnalysis(status: .failed, photos: [
            AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])
        ])]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()
        #expect(vm.canRetry)

        service.errors["uploadPhoto"] = APIError.networkError(URLError(.timedOut))
        await vm.start()

        #expect(vm.phase == .failed)
        #expect(!vm.canRetry)
        await vm.retry()
        #expect(service.retriedAnalysisIds.isEmpty)
    }

    /// 사진 일부만 실패하면 나머지 결과로 확인 화면을 띄운다. **실패한 사진을 감추지 않는다.**
    @Test func 일부만_실패하면_확인_화면으로_가되_재시도를_열어_둔다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12]
        service.analyses = [makeAnalysis(status: .completed, photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: []),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: true, items: [])
        ])]
        let vm = makeVM(service)
        vm.append(photos(2))

        await vm.start()

        #expect(vm.phase == .completed)
        #expect(vm.analysis?.photos.count == 2)
        #expect(vm.canRetry)
    }

    /// 60초 타임아웃은 실패가 아니다 — 서버는 계속 처리 중일 수 있다.
    ///
    /// 여기서는 데드라인이 **실제로** 지나는 걸 확인해야 하므로 성공 경로용 넉넉한 프로필 대신
    /// 짧은 값을 직접 준다. 5ms 간격에 150ms 데드라인이면 간격의 30배쯤 되는 여유가 있어
    /// 면도날처럼 아슬아슬하지 않으면서도, 응답이 계속 PENDING인 이 테스트에서는 몇 초씩
    /// 기다리지 않고도 신뢰성 있게 타임아웃에 도달한다.
    @Test func 타임아웃은_실패가_아니라_지연이다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [makeAnalysis(status: .pending)]
        let vm = makeVM(service, pollInterval: .milliseconds(5), pollTimeout: .milliseconds(150))
        vm.append(photos(1))

        await vm.start()

        #expect(vm.phase == .delayed)
        // **재시도 여지를 남겨 둔다** — 사진을 처음부터 다시 올려 두 번째 LLM 인식 비용을
        // 치르지 않고도, 같은 버튼으로 서버가 이미 끝냈는지 무료로 확인할 수 있어야 한다.
        #expect(vm.canRetry)
    }

    /// 타임아웃 뒤 「다시 인식」을 눌러도 서버가 여전히 처리 중이면 `ANALYSIS_IN_PROGRESS`로
    /// 답한다 — 이건 실패가 아니라 "폴링만 다시 하면 된다"는 신호다. 사진을 다시 올리거나
    /// 두 번째 LLM 호출을 내보내지 않고 같은 인식 결과를 무료로 이어받는지 확인한다.
    @Test func 타임아웃_뒤_재시도는_폴링만_무료로_재개한다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [makeAnalysis(status: .pending)]
        let vm = makeVM(service, pollInterval: .milliseconds(5), pollTimeout: .milliseconds(150))
        vm.append(photos(1))

        await vm.start()
        #expect(vm.phase == .delayed)
        #expect(vm.canRetry)

        service.retryErrorOnce = dietServerError("ANALYSIS_IN_PROGRESS")
        service.analyses = [makeAnalysis(status: .completed)]
        await vm.retry()

        #expect(vm.phase == .completed)
        #expect(vm.errorMessage == nil)
        // 재시도가 서버에 한 번은 물어봤지만(`retryAnalysis`), 두 번째 인식 요청
        // (`createAnalysis`)은 나가지 않았다 — 사진 재업로드 없이 같은 분석을 이어받는다.
        #expect(service.retriedAnalysisIds == [service.createdAnalysisId])
        #expect(service.createdFileIds.count == 1)
    }

    /// 폴링이 네트워크 오류로 끊긴 사이 서버가 인식을 끝내면, 「다시 인식」은
    /// `ANALYSIS_NOT_RETRYABLE`로 거절당한다(실패한 사진이 남아 있지 않으므로).
    /// **이건 「결과가 없다」가 아니라 「고칠 게 없다」는 뜻이다** — 이미 성공해 서버에 있는
    /// 결과를 그대로 이어받아야 하고, 사진을 다시 올려 유료 호출을 또 내면 안 된다.
    @Test func 재시도할_실패가_없다면_완성된_결과를_이어받는다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        // 첫 폴링이 네트워크 오류로 끊긴다.
        service.errors["fetchAnalysis"] = RetryableCaptureError()
        let vm = makeVM(service, pollInterval: .milliseconds(5), pollTimeout: .milliseconds(150))
        vm.append(photos(1))

        await vm.start()
        #expect(vm.phase == .failed)
        #expect(vm.canRetry)
        #expect(vm.analysis == nil)

        // 그 사이 서버는 인식을 끝냈다 — 고칠 실패 사진이 없어 재시도를 거절한다.
        service.errors["fetchAnalysis"] = nil
        service.retryErrorOnce = dietServerError("ANALYSIS_NOT_RETRYABLE")
        service.analyses = [makeAnalysis(status: .completed)]

        await vm.retry()

        #expect(vm.phase == .completed)
        #expect(vm.analysis != nil)
        #expect(vm.errorMessage == nil)
        // 두 번째 인식 요청이 나가지 않았다 — 이미 낸 비용을 다시 치르지 않는다.
        #expect(service.createdFileIds.count == 1)
    }

    /// **재시도 버튼은 누르는 즉시 잠근다.** 연타해도 호출이 한 번만 나간다.
    @Test func 재시도_연타는_한_번만_나간다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])]),
            makeAnalysis(status: .completed)
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()

        async let first: Void = vm.retry()
        async let second: Void = vm.retry()
        _ = await (first, second)

        #expect(service.retriedAnalysisIds.count == 1)
    }

    /// `ANALYSIS_IN_PROGRESS`는 **실패가 아니다** — 알럿 대신 폴링을 다시 시작한다.
    @Test func 진행중_응답이면_알럿_대신_폴링을_재개한다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])]),
            makeAnalysis(status: .completed)
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()

        service.retryErrorOnce = dietServerError("ANALYSIS_IN_PROGRESS")
        await vm.retry()

        #expect(vm.errorMessage == nil)
        #expect(vm.phase == .completed)
    }

    /// `ANALYSIS_NOT_RETRYABLE`은 재시도할 것이 없다는 뜻이라 버튼을 감춘다.
    @Test func 재시도할_것이_없으면_버튼을_감춘다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])]),
            makeAnalysis(status: .completed)
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()

        service.retryErrorOnce = dietServerError("ANALYSIS_NOT_RETRYABLE")
        await vm.retry()

        #expect(!vm.canRetry)
        #expect(vm.errorMessage == nil)
    }

    /// **재시도 버튼에서도 503이 온다** — 눌러도 안 되니 버튼을 감추고 같은 안내로 바꾼다.
    @Test func 재시도도_LLM이_없으면_버튼을_감추고_같은_안내로_바꾼다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])])
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()
        #expect(vm.canRetry)

        service.retryErrorOnce = dietServerError("LLM_UNAVAILABLE", status: 503)
        await vm.retry()

        #expect(!vm.canRetry)
        #expect(vm.phase == .llmUnavailable)
        #expect(vm.errorMessage == nil)
    }

    /// 503이면 **나머지 기능은 전부 정상이다** — "사진 인식만 지금 안 된다"고 안내하고 직접 추가로 유도한다.
    @Test func LLM이_없으면_사진_인식만_막혔다고_안내한다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.errors["createAnalysis"] = dietServerError("LLM_UNAVAILABLE", status: 503)
        let vm = makeVM(service)
        vm.append(photos(1))

        await vm.start()

        #expect(vm.phase == .llmUnavailable)
        #expect(vm.errorMessage == nil)
    }

    /// 폴링 중 네트워크 오류도 서버가 확정한 실패와 똑같이 재시도를 연다 — 안 그러면 순간적인
    /// 접속 끊김 하나 때문에 사진 5장을 처음부터 다시 올려야 한다. 이 시점에는 `fetchAnalysis`가
    /// 한 번도 성공한 적이 없어 `analysis`가 여전히 nil이라, 재시도가 `analysis.id`가 아니라
    /// 별도로 기억해 둔 인식 id로 실제로 동작하는지까지 함께 확인한다.
    @Test func 폴링_중_네트워크_오류도_재시도를_연다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.errors["fetchAnalysis"] = APIError.networkError(URLError(.networkConnectionLost))
        let vm = makeVM(service)
        vm.append(photos(1))

        await vm.start()

        #expect(vm.phase == .failed)
        #expect(vm.canRetry)
        #expect(vm.errorMessage != nil)

        service.errors["fetchAnalysis"] = nil
        service.analyses = [makeAnalysis(status: .completed)]
        await vm.retry()

        #expect(vm.phase == .completed)
    }

    /// 확인 화면에서 저장 없이 나오면(discard) `.completed`로 남지 않아야 한다 — `.completed`는
    /// 캡처 화면에서 빈 패널이라 아무것도 할 수 없고, 사진은 그대로 든 채 다시 시도할 수
    /// 있는 상태로 돌아와야 한다.
    @Test func 확인_화면에서_저장_없이_나오면_다시_시도할_수_있는_상태로_돌아온다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [makeAnalysis(status: .completed)]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()
        #expect(vm.phase == .completed)

        vm.discard()

        #expect(vm.phase != .completed)
        #expect(vm.phase == .idle)
        #expect(!vm.canRetry)
        #expect(vm.analysis == nil)
        #expect(vm.photoDataList.count == 1)
    }
}
