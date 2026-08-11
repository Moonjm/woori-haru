import Foundation

/// 사진 여러 장 업로드 → 인식 요청 → 인식 폴링.
///
/// **이 폴링은 하루 피드백 폴링과 성격이 다르다** — 기다려야 확인 화면으로 갈 수 있고,
/// 실패하면 재시도 없이는 진행이 막히므로 버튼을 둔다.
@MainActor
@Observable
final class MealCaptureViewModel {
    enum Phase: Equatable {
        case idle
        case uploading
        case analyzing
        /// 확인 화면으로 갈 수 있다(사진 일부가 실패했어도 나머지 결과가 있다).
        case completed
        /// 전부 실패했거나 업로드가 끊겼다.
        case failed
        /// 60초 안에 안 끝났다. **실패로 단정하지 않는다.**
        case delayed
        /// 서버에 LLM 키가 없다. 나머지 기능은 전부 정상이다.
        case llmUnavailable
    }

    /// **고르기 전에는 nil이다.** 확인 화면이 이 값을 그대로 받고, 거기서 저장이 막힌다.
    var mealType: MealType?
    private(set) var photoDataList: [Data] = []
    private(set) var uploadedCount = 0
    private(set) var phase: Phase = .idle
    private(set) var analysis: MealAnalysis?
    /// 실패한 사진이 있을 때만 재시도할 것이 있다.
    private(set) var canRetry = false
    /// 앨범에서 고른 사진을 읽는 중이다. **iCloud에 있는 원본은 실제로 내려받으므로 초 단위가
    /// 걸린다** — 그동안 앨범을 다시 열 수 있으면 두 묶음이 함께 들어와 5장 상한에서 나중
    /// 것이 소리 없이 버려진다. 화면은 이 값으로 앨범·카메라 버튼을 잠근다.
    private(set) var isLoadingPicks = false
    private(set) var isRetrying = false
    var errorMessage: String?

    private let service: any DietServing
    private let pollInterval: Duration
    private let pollTimeout: Duration
    /// 폴링 대상 인식 id. **재시도는 `analysis`가 아니라 이 값으로 한다** — 폴링 중 네트워크
    /// 오류로 `fetchAnalysis`가 한 번도 성공하지 못하면 `analysis`는 계속 nil이라, `analysis.id`에
    /// 기대면 재시도 버튼이 보여도 눌렀을 때 아무 일도 안 일어난다.
    private var currentAnalysisId: Int?

    init(
        service: any DietServing = DietService(),
        pollInterval: Duration = DietPolicy.pollInterval,
        pollTimeout: Duration = DietPolicy.pollTimeout
    ) {
        self.service = service
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    var remainingSlots: Int { max(0, DietPolicy.maxPhotos - photoDataList.count) }

    /// "3장 중 2장 올리는 중" — 사진 수만큼 시간이 늘어나므로 진행 상황이 안 보이면 멈춘 것처럼 느껴진다.
    var progressText: String? {
        switch phase {
        case .uploading: "\(photoDataList.count)장 중 \(uploadedCount + 1)장 올리는 중"
        case .analyzing: "음식을 인식하고 있어요"
        default: nil
        }
    }

    var isBusy: Bool { phase == .uploading || phase == .analyzing }

    /// **상한을 넘겨 담지 않는다.** `PhotosPicker`의 `maxSelectionCount`로도 막지만 카메라 경로가 있다.
    func append(_ dataList: [Data]) {
        guard !dataList.isEmpty else { return }
        photoDataList = Array((photoDataList + dataList).prefix(DietPolicy.maxPhotos))
        invalidateRetry()
    }

    func remove(at index: Int) {
        guard photoDataList.indices.contains(index) else { return }
        photoDataList.remove(at: index)
        invalidateRetry()
    }

    /// 앨범에서 고른 사진을 읽어 담는다. **읽는 동안 두 번째 선택을 받지 않는다** — 받아 주면
    /// 두 묶음이 각자 `append`로 들어와 5장 상한(`prefix`)에서 늦게 끝난 쪽이 소리 없이
    /// 버려진다. 사용자에게는 「고른 사진이 안 들어갔다」로만 보인다.
    func loadPicks(_ produce: () async -> [Data]) async {
        guard !isLoadingPicks else { return }
        isLoadingPicks = true
        defer { isLoadingPicks = false }
        append(await produce())
    }

    /// 사진 구성이 바뀌면 앞선 인식은 **다른 사진들의 결과**다. 재시도는 서버에 남은 그
    /// 인식을 다시 돌리는 것이라 방금 담은 사진이 끝내 들어가지 않는다 — 길을 열어 두면
    /// 「다시 인식」이 바뀐 사진을 조용히 빼놓은 결과를 가져온다.
    ///
    /// 화면은 이 값으로 「다시 인식」과 「인식 시작」 중 무엇을 띄울지 고른다. 여기서 꺼야
    /// 사진을 바꾼 사용자가 새 인식을 낼 길을 되찾는다.
    private func invalidateRetry() {
        canRetry = false
        currentAnalysisId = nil
    }

    // MARK: - 업로드 → 인식

    func start() async {
        guard !photoDataList.isEmpty, !isBusy else { return }
        phase = .uploading
        uploadedCount = 0
        errorMessage = nil
        // 지금부터 만드는 것은 **새 인식**이다. 여기서 안 지우면 업로드가 실패했을 때
        // 예전 `analysisId`가 `canRetry`와 함께 남아, 「다시 인식」이 이번 사진과 무관한
        // 옛 인식을 되살린다.
        invalidateRetry()

        // **순차로 올린다.** 병렬로 5장을 밀어넣으면 라즈베리파이에서 멀티파트 5개가 동시에
        // 처리되고, 어느 하나가 실패했을 때 어디까지 올라갔는지 추적이 지저분해진다.
        var fileIds: [Int] = []
        for data in photoDataList {
            do {
                fileIds.append(try await service.uploadPhoto(data))
                uploadedCount += 1
            } catch is CancellationError {
                return
            } catch {
                // **이미 올린 파일은 그대로 둔다** — 확정되지 않은 파일은 서버가 24시간 뒤 수거한다.
                phase = .failed
                errorMessage = "사진을 올리지 못했습니다. 다시 시도해 주세요."
                return
            }
        }

        do {
            let analysisId = try await service.createAnalysis(fileIds: fileIds)
            phase = .analyzing
            await poll(analysisId: analysisId)
        } catch is CancellationError {
            return
        } catch {
            if error.dietErrorCode == .llmUnavailable {
                // 나머지 기능은 전부 정상이다 — "서버 오류"로 뭉뚱그리지 않는다.
                phase = .llmUnavailable
            } else {
                phase = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    private func poll(analysisId: Int) async {
        currentAnalysisId = analysisId
        let deadline = ContinuousClock.now + pollTimeout

        while ContinuousClock.now < deadline {
            do {
                let result = try await service.fetchAnalysis(id: analysisId)
                analysis = result

                switch result.status {
                case .pending:
                    try await Task.sleep(for: pollInterval)
                case .completed:
                    // 일부 사진만 실패했으면 나머지 결과로 확인 화면을 띄우고 그 사진만 다시 시도한다.
                    canRetry = result.hasFailedPhoto
                    phase = .completed
                    return
                case .failed:
                    canRetry = true
                    phase = .failed
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                // **네트워크 등 일시적 오류도 확정된 실패와 똑같이 재시도를 연다.** 순간적인
                // 접속 끊김 때문에 사진 5장을 처음부터 다시 올리고 비용을 다시 치르게 하면 안 된다.
                phase = .failed
                canRetry = true
                errorMessage = error.localizedDescription
                return
            }
        }

        // 타임아웃은 실패가 아니다 — 서버는 계속 처리 중일 수 있다. **재시도 여지를 남겨
        // 둔다** — 같은 「다시 인식」 버튼이 `retryAnalysis`를 부르고, 서버가 아직 처리
        // 중이면 `ANALYSIS_IN_PROGRESS`로 답해 폴링만 다시 시작한다(두 번째 LLM 호출이
        // 나가지 않는다). `canRetry = false`로 두면 새로고침할 방법이 사진 재업로드뿐이라
        // 이미 낸 비용을 다시 치르게 된다.
        phase = .delayed
        canRetry = true
    }

    // MARK: - 재시도

    /// **누르는 즉시 잠근다.** 서버가 `PENDING`인 동안 들어온 재시도를 `ANALYSIS_IN_PROGRESS`로
    /// 거절하므로 중복 유료 호출은 안 나가지만, 잠그지 않으면 연타할 때마다 오류 알럿이 뜬다.
    func retry() async {
        guard let currentAnalysisId, canRetry, !isRetrying else { return }
        isRetrying = true
        errorMessage = nil
        defer { isRetrying = false }

        do {
            try await service.retryAnalysis(id: currentAnalysisId)
        } catch is CancellationError {
            return
        } catch {
            switch error.dietErrorCode {
            case .analysisInProgress:
                // 이미 서버가 처리 중이라는 뜻이지 실패가 아니다 — 알럿 대신 폴링을 다시 시작한다.
                break
            case .analysisNotRetryable:
                // **다시 시도할 실패 사진이 없다는 뜻이지 결과가 없다는 뜻이 아니다.** 폴링이
                // 네트워크 오류로 끊긴 사이 서버가 인식을 끝내면 여기로 떨어진다. 그냥 버튼만
                // 감추고 끝내면 `phase`가 `.failed`인 채로 `analysis`가 비어 있어 **이미 성공해
                // 서버에 있는 결과를 영영 못 쓰고** 사진을 처음부터 다시 올려 유료 호출을 한 번
                // 더 내게 된다. 진행 중일 때와 같은 길로 보내면 `poll()`이 현재 상태를 읽어
                // 알맞게 전이시킨다(완료면 확인 화면이 열리고, `canRetry`도 거기서 맞춰진다).
                break
            case .llmUnavailable:
                // 서버에 키가 없으면 재시도도 503으로 거절된다 — 눌러도 안 되니 버튼을 감추고
                // 인식 요청과 같은 안내로 바꾼다.
                canRetry = false
                phase = .llmUnavailable
                return
            default:
                errorMessage = error.localizedDescription
                return
            }
        }

        phase = .analyzing
        await poll(analysisId: currentAnalysisId)
    }

    // MARK: - 확인 화면 이탈

    /// 확인 화면에서 **저장하지 않고 나왔을 때.** `MealConfirmView`가 나가기 전에 "저장하지
    /// 않으면 이 기록은 남지 않아요"라고 이미 경고했으므로, 여기 온 이상 그 인식 결과는 쓴
    /// 것으로 본다.
    ///
    /// `.completed`로 남겨 두면 안 된다 — 캡처 화면의 상태 섹션은 `.completed`를 "확인
    /// 화면으로 가 있는 중"으로 알고 빈 패널을 그리므로, 그대로 두면 사용자가 아무것도
    /// 못 하는 화면에 갇힌다. 그렇다고 `.completed`인 채 다른 값만 바꾸면, 확인 화면은
    /// `phase`가 **새로** `.completed`가 될 때만 다시 뜨므로(재시도 중 화면을 다시 만들지
    /// 않으려고 그렇게 만들었다) 이 경로로는 다시 열릴 수도 없다. `.idle`로 돌려 사진은
    /// 그대로 든 채 「인식 시작」을 다시 누를 수 있게 한다.
    func discard() {
        phase = .idle
        analysis = nil
        canRetry = false
        currentAnalysisId = nil
        errorMessage = nil
    }
}
