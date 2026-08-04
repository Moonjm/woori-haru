import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct NutritionProfileViewModelTests {
    @Test func 기존_프로필을_읽어_입력란을_채운다() async {
        let service = FakeDietService()
        service.profile = makeProfile(weightKg: 68.5)
        let vm = NutritionProfileViewModel(service: service)

        await vm.load()

        #expect(vm.heightText == "175")
        #expect(vm.weightText == "68.5")
        #expect(vm.activityLevel == .moderate)
        #expect(vm.goal == .maintain)
        #expect(vm.profile?.targetKcal == 2509)
    }

    @Test func 프로필이_없어도_오류가_아니다() async {
        let service = FakeDietService()
        service.profile = nil
        let vm = NutritionProfileViewModel(service: service)

        await vm.load()

        #expect(vm.profile == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func 저장하면_서버가_계산한_목표를_다시_읽어_보여준다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        let vm = NutritionProfileViewModel(service: service)
        vm.heightText = "175"
        vm.weightText = "70"
        vm.activityLevel = .active
        vm.goal = .lose

        await vm.save()

        #expect(service.savedProfiles.count == 1)
        #expect(service.savedProfiles.first?.heightCm == 175)
        #expect(service.savedProfiles.first?.weightKg == 70)
        #expect(service.savedProfiles.first?.activityLevel == .active)
        #expect(service.savedProfiles.first?.goal == .lose)
        #expect(vm.didSave)
        #expect(vm.profile?.targetKcal == 2509)
    }

    @Test func 키나_몸무게가_비면_저장할_수_없다() {
        let vm = NutritionProfileViewModel(service: FakeDietService())

        vm.heightText = ""
        vm.weightText = "70"
        #expect(!vm.canSave)

        vm.heightText = "175"
        vm.weightText = "abc"
        #expect(!vm.canSave)

        vm.weightText = "70"
        #expect(vm.canSave)
    }

    /// **서버가 거절할 값은 보내지 않는다.** 키 100~250cm·몸무게 20~300kg 밖이면 400이
    /// 돌아오는데, 그때는 무엇이 잘못됐는지 알 길이 없다.
    @Test func 서버_허용_범위_밖이면_저장할_수_없다() {
        let vm = NutritionProfileViewModel(service: FakeDietService())

        // 양끝은 포함이다(`@DecimalMin`/`@DecimalMax`).
        vm.heightText = "100"
        vm.weightText = "20"
        #expect(vm.canSave)

        vm.heightText = "250"
        vm.weightText = "300"
        #expect(vm.canSave)

        vm.heightText = "99"
        vm.weightText = "70"
        #expect(!vm.canSave)
        #expect(vm.heightRangeHint != nil)
        #expect(vm.weightRangeHint == nil)

        vm.heightText = "251"
        #expect(!vm.canSave)

        vm.heightText = "175"
        vm.weightText = "19"
        #expect(!vm.canSave)
        #expect(vm.weightRangeHint != nil)

        vm.weightText = "-5"
        #expect(!vm.canSave)

        vm.weightText = "301"
        #expect(!vm.canSave)
    }

    /// **빈 칸에는 경고를 달지 않는다** — 아직 입력을 시작하지도 않은 자리에 빨간 문구를
    /// 띄우는 것은 재촉일 뿐이다. 저장은 `canSave`가 따로 막는다.
    @Test func 빈_칸에는_범위_안내를_띄우지_않는다() {
        let vm = NutritionProfileViewModel(service: FakeDietService())

        #expect(vm.heightRangeHint == nil)
        #expect(vm.weightRangeHint == nil)
        #expect(!vm.canSave)
    }

    @Test func 키가_0이면_저장하지_않는다() async {
        let service = FakeDietService()
        let vm = NutritionProfileViewModel(service: service)
        vm.heightText = "0"
        vm.weightText = "70"

        await vm.save()

        #expect(service.savedProfiles.isEmpty)
        #expect(!vm.didSave)
    }

    /// 성별·생년월일이 없으면 서버가 `INVALID_REQUEST`로 거절한다 — 「내 정보」로 안내해야 한다.
    @Test func 성별_생년월일이_없으면_내_정보로_안내한다() async {
        let service = FakeDietService()
        service.errors["saveProfile"] = dietServerError("INVALID_REQUEST")
        let vm = NutritionProfileViewModel(service: service)
        vm.heightText = "175"
        vm.weightText = "70"

        await vm.save()

        #expect(!vm.didSave)
        #expect(vm.needsUserInfo)
    }
}

@MainActor
struct DietDayViewModelTests {
    /// 폴링이 **성공**하는 걸 보는 테스트용 프로필. 간격은 짧게 두되(대역이 몇 회 만에
    /// 응답을 채우므로) 데드라인은 넉넉한 몇 초로 잡는다 — 병렬로 여러 스위트가 함께 도는
    /// 상황에서 스케줄러가 밀려도 진짜 실패(타임아웃)로 잘못 넘어가지 않게 하기 위해서다.
    private func makeVM(
        _ service: FakeDietService,
        energy: FakeActiveEnergyFetcher = .init(),
        pollInterval: Duration = .milliseconds(1),
        pollTimeout: Duration = .seconds(5)
    ) -> DietDayViewModel {
        DietDayViewModel(
            service: service,
            energyFetcher: energy,
            pollInterval: pollInterval,
            pollTimeout: pollTimeout
        )
    }

    @Test func 하루_요약을_읽는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.day?.dayScore == 74)
        #expect(vm.day?.meals.count == 1)
        #expect(vm.profile?.targetKcal == 2509)
        #expect(!vm.needsProfile)
        #expect(vm.hasLoaded)
    }

    /// 목표가 없으면 점수를 낼 수 없으므로 프로필을 먼저 띄운다.
    @Test func 프로필이_없으면_프로필_화면을_먼저_띄운다() async {
        let service = FakeDietService()
        service.profile = nil
        service.days = [makeDay(dayScore: nil, feedback: nil, meals: [])]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.needsProfile)
    }

    /// **화면을 붙잡지 않는다** — 점수와 끼니는 이미 보이고 피드백 영역만 로딩이다.
    @Test func 피드백이_null이면_화면을_붙잡지_않고_뒤에서_채운다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(feedback: nil), makeDay(feedback: nil), makeDay(feedback: "다 채웠습니다.")]
        let vm = makeVM(service)

        await vm.load()
        // 첫 응답 시점에 점수는 이미 있고 피드백만 비어 있다.
        #expect(vm.day?.dayScore == 74)
        #expect(vm.isFeedbackPending)

        await vm.waitForFeedbackPolling()

        #expect(vm.day?.feedback == "다 채웠습니다.")
        #expect(!vm.isFeedbackPending)
        #expect(!vm.isFeedbackDelayed)
    }

    /// 타임아웃은 실패가 아니다. **재시도 버튼을 두지 않는다.**
    ///
    /// 여기서는 데드라인이 **실제로** 지나는 걸 확인해야 하므로 성공 경로용 넉넉한 프로필 대신
    /// 짧은 값을 직접 준다. 5ms 간격에 150ms 데드라인이면 간격의 30배쯤 되는 여유가 있어
    /// 면도날처럼 아슬아슬하지 않으면서도, 응답이 계속 `nil`인 이 테스트에서는 몇 초씩
    /// 기다리지 않고도 신뢰성 있게 타임아웃에 도달한다.
    @Test func 피드백이_안_오면_지연으로_두고_재시도_버튼을_두지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(feedback: nil)]
        let vm = makeVM(service, pollInterval: .milliseconds(5), pollTimeout: .milliseconds(150))

        await vm.load()
        await vm.waitForFeedbackPolling()

        #expect(vm.day?.feedback == nil)
        #expect(vm.isFeedbackDelayed)
        #expect(!vm.isFeedbackPending)
    }

    /// 폴링 중이던 로드가 실패로 끝나면 "피드백 만드는 중" 표시가 방치되면 안 된다 — 취소한
    /// 이전 폴링의 흔적으로 화면이 무한 로딩에 갇힌다.
    @Test func 재로딩이_실패하면_피드백_대기_표시를_끈다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(feedback: nil)]
        let vm = makeVM(service)

        await vm.load()
        #expect(vm.isFeedbackPending)

        service.errors["fetchDay"] = dietServerError("SERVER_ERROR", status: 500)
        await vm.reload()

        #expect(!vm.isFeedbackPending)
    }

    /// 끼니가 없는 날은 서버가 피드백을 만들지 않으므로 폴링하지 않는다.
    @Test func 끼니가_없으면_폴링하지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(dayScore: nil, feedback: nil, meals: [])]
        let vm = makeVM(service)

        await vm.load()
        await vm.waitForFeedbackPolling()

        #expect(!vm.isFeedbackPending)
        #expect(!vm.isFeedbackDelayed)
        #expect(service.fetchedDates.count == 1)
    }

    /// 날짜를 바꾸면 이전 날짜의 늦은 응답을 버린다.
    ///
    /// 여기서는 두 번의 `load()`가 순차로(하나가 완전히 끝난 뒤 다음이 시작) 실행돼 사실은
    /// 재조회가 맞게 되는지만 본다 — `generation` 가드 자체는 이 테스트를 지워도 통과한다.
    /// 가드가 실제로 하는 일(진행 중이던 응답을 버리는 것)은 아래
    /// `진행중이던_이전_날짜_응답은_generation_토큰으로_버려진다`가 검증한다.
    @Test func 날짜를_바꾸면_이전_응답을_버린다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: "2026-07-29"), makeDay(date: "2026-07-28", dayScore: 55)]
        let vm = makeVM(service)

        await vm.load()
        await vm.select(Date.from("2026-07-28")!)

        #expect(vm.day?.date == "2026-07-28")
        #expect(vm.day?.dayScore == 55)
        #expect(service.fetchedDates.contains("2026-07-28"))
    }

    /// **`generation` 가드를 실제로 겹치게 만들어 검증한다.** 위 테스트는 매 호출을 끝까지
    /// 기다리고 나서 다음을 시작하므로, 모든 `guard token == generation` 줄을 지워도 통과한다
    /// — 응답이 실제로 뒤바뀌어 도착하는 경우를 재현해야 가드의 존재 이유가 드러난다.
    /// A의 `fetchDay`를 게이트로 붙잡아 둔 채 B로 넘어가 완전히 끝내고, 그다음에야 A를
    /// 풀어 준다. 가드가 없다면 A의 응답이 나중에 도착해 B의 결과를 덮어썼을 것이다.
    @Test func 진행중이던_이전_날짜_응답은_generation_토큰으로_버려진다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [
            makeDay(date: "2026-07-29", feedback: "A"),
            makeDay(date: "2026-07-28", dayScore: 55, feedback: "B")
        ]
        let gate = AsyncGate()
        service.fetchDayGates["2026-07-29"] = gate
        let vm = DietDayViewModel(
            service: service,
            energyFetcher: FakeActiveEnergyFetcher(),
            date: Date.from("2026-07-29")!,
            pollInterval: .milliseconds(1),
            pollTimeout: .seconds(5)
        )

        let loadTask = Task { await vm.load() }
        await gate.waitUntilBlocked() // A의 fetchDay가 게이트 안에서 멈춘 걸 확인하고서야 다음으로 넘어간다.

        await vm.select(Date.from("2026-07-28")!) // B는 게이트가 없어 곧바로 끝난다.
        #expect(vm.day?.date == "2026-07-28")
        #expect(vm.day?.dayScore == 55)

        await gate.open() // 이제야 A의 응답을 흘려보낸다.
        await loadTask.value

        // generation 토큰이 없었다면 A의 뒤늦은 응답이 여기서 화면을 다시 덮어썼을 것이다.
        #expect(vm.day?.date == "2026-07-28")
        #expect(vm.day?.dayScore == 55)
    }

    /// 진입할 때마다 편하게 올려도 된다 — 서버가 이 값으로 피드백을 재생성하지 않는다.
    @Test func 활동_에너지를_올린다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let energy = FakeActiveEnergyFetcher()
        energy.kcal = 2412.6
        let vm = makeVM(service, energy: energy)

        await vm.load()
        await vm.syncActivity()

        #expect(service.activityCalls.count == 1)
        #expect(service.activityCalls.first?.kcal == 2413)
    }

    /// HealthKit 조회 중에 사용자가 날짜를 바꿔도, 업로드는 **조회를 시작한 날짜**로 가야
    /// 한다 — 끝나고 나서 `selectedDate`를 다시 읽으면 이미 바뀐 뒤라 어제 소모량이 오늘
    /// 날짜로 올라간다.
    /// **새 날짜 라벨 아래 이전 날짜의 끼니가 남으면 안 된다.** 화면은 `day`가 있으면 스피너를
    /// 감추고 끼니 카드를 그대로 열어 주므로(`NavigationLink`), 그 사이 사용자가 다른 날짜의
    /// 끼니를 이 날짜 것으로 알고 고치거나 지운다. 활동량 동기화와 하루 조회를 기다리는
    /// 내내 열려 있는 창이라 좁지 않다.
    @Test func 날짜를_바꾸면_이전_날짜의_하루를_바로_감춘다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: "2026-07-29"), makeDay(date: "2026-07-28", dayScore: 55)]
        let energy = FakeActiveEnergyFetcher()
        let gate = AsyncGate()
        let vm = DietDayViewModel(
            service: service,
            energyFetcher: energy,
            date: Date.from("2026-07-29")!,
            pollInterval: .milliseconds(1),
            pollTimeout: .seconds(5)
        )
        await vm.load()
        #expect(vm.day?.date == "2026-07-29")

        // 활동량 조회에서 멈춘다 — 하루 조회는 아직 시작도 안 한 시점이다.
        energy.gate = gate
        let selecting = Task { await vm.select(Date.from("2026-07-28")!) }
        await gate.waitUntilBlocked()

        #expect(vm.day == nil)
        // 화면이 「기록이 없는 날」이 아니라 불러오는 중으로 보여야 한다.
        #expect(vm.isLoading)

        await gate.open()
        await selecting.value

        #expect(vm.day?.date == "2026-07-28")
        #expect(!vm.isLoading)
    }

    @Test func 활동_에너지_조회_중_날짜가_바뀌어도_시작한_날짜로_올린다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: "2026-07-29"), makeDay(date: "2026-07-28", dayScore: 55)]
        let energy = FakeActiveEnergyFetcher()
        let gate = AsyncGate()
        energy.gate = gate
        let vm = DietDayViewModel(
            service: service,
            energyFetcher: energy,
            date: Date.from("2026-07-29")!,
            pollInterval: .milliseconds(1),
            pollTimeout: .seconds(5)
        )
        await vm.load()

        let syncTask = Task { await vm.syncActivity() }
        await gate.waitUntilBlocked() // HealthKit 조회가 멈춘 걸 확인하고서야 날짜를 바꾼다.

        // `select(_:)`도 그날의 활동량을 올리므로 같은 게이트를 지난다 — 따로 띄워 두고
        // 게이트를 열어 두 호출이 함께 풀리게 한다. 먼저 시작한 조회가 멈춰 있는 동안
        // 날짜가 바뀌는 상황이 이 테스트가 재현하려는 경합이다.
        let selectTask = Task { await vm.select(Date.from("2026-07-28")!) }
        await gate.open()
        await syncTask.value
        await selectTask.value

        // 날짜마다 정확히 한 번씩 올라간다. **먼저 시작한 조회가 시작 시점의 07-29로 올라가는
        // 것이 핵심이다** — 끝나고 나서 `selectedDate`를 다시 읽으면 둘 다 07-28로 올라간다.
        #expect(service.activityCalls.map(\.date).sorted() == ["2026-07-28", "2026-07-29"])
    }

    /// HealthKit이 없는 기기에서도 하루 화면은 정상이어야 한다.
    @Test func 활동_에너지_실패는_화면을_막지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let energy = FakeActiveEnergyFetcher()
        energy.errorToThrow = SwimWorkoutError.healthDataUnavailable
        let vm = makeVM(service, energy: energy)

        await vm.load()
        await vm.syncActivity()

        #expect(vm.errorMessage == nil)
        #expect(service.activityCalls.isEmpty)
    }

    /// **권한을 요청하지 않고 읽으면 미승인 기기가 매번 0을 올린다.** HealthKit은 권한이
    /// 없어도 에러 없이 빈 결과(0)로 응답하므로, 조회 전에 권한을 요청했는지 자체를 본다.
    @Test func 활동_에너지_동기화_전에_권한을_요청한다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let energy = FakeActiveEnergyFetcher()
        let vm = makeVM(service, energy: energy)

        await vm.load()
        await vm.syncActivity()

        #expect(energy.didRequestAuthorization)
    }

    /// **0은 "진짜 0"과 "권한 없음"을 구분할 수 없다.** 권한이 없는 기기가 매 방문마다
    /// 활동 에너지 0을 서버에 올려 하루 마감 피드백의 근거를 오염시키면 안 된다.
    @Test func 활동_에너지가_0이면_업로드하지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let energy = FakeActiveEnergyFetcher()
        energy.kcal = 0
        let vm = makeVM(service, energy: energy)

        await vm.load()
        await vm.syncActivity()

        #expect(service.activityCalls.isEmpty)
    }

    /// 방금 올린 소모량이 새로고침 없이 바로 보여야 한다 — 그 날 첫 진입에서 하루 조회는
    /// 업로드보다 먼저 끝나므로, 화면이 쥔 값을 갱신하지 않으면 소모 줄이 비어 있다가
    /// 수동 새로고침을 해야만 나타난다.
    @Test func 활동_에너지를_올리면_새로고침_없이_화면에_반영된다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: "2026-07-29", activeEnergyKcal: nil)]
        let energy = FakeActiveEnergyFetcher()
        energy.kcal = 500
        // `makeVM`은 실제 오늘 날짜로 vm을 만든다 — `syncActivity()`가 반영 여부를 판단할 때
        // `day.date`와 비교하는 날짜이므로, `makeDay`의 날짜와 맞춰야 한다.
        let vm = DietDayViewModel(
            service: service,
            energyFetcher: energy,
            date: Date.from("2026-07-29")!,
            pollInterval: .milliseconds(1),
            pollTimeout: .seconds(5)
        )

        await vm.load()
        #expect(vm.day?.activeEnergyKcal == nil)

        await vm.syncActivity()

        #expect(vm.day?.activeEnergyKcal == 500)
        // 두 번째 왕복(재조회) 없이 반영됐는지 — fetchDay는 load() 한 번만 불렀어야 한다.
        #expect(service.fetchedDates.count == 1)
    }

    /// 몸무게만 고치고 목표를 다시 읽는다. **과거 점수는 바뀌지 않는다**(서버가 스냅샷을 남긴다).
    @Test func 몸무게를_고치면_목표를_다시_읽는다() async {
        let service = FakeDietService()
        service.profile = makeProfile(weightKg: 70)
        service.days = [makeDay(), makeDay()]
        let vm = makeVM(service)
        await vm.load()

        service.profile = makeProfile(weightKg: 68)
        await vm.updateWeight(68)

        #expect(service.savedWeights == [68])
        #expect(vm.profile?.weightKg == 68)
    }

    /// **저장에 실패하면 `false`를 돌려준다.** 화면이 이 값을 안 보고 재조회하면 `load()`가
    /// 시작하자마자 오류를 지워서, 이미 닫힌 시트 뒤로 「저장이 안 됐다」가 아무 데도 안 남는다.
    @Test func 몸무게_저장이_실패하면_실패를_알린다() async {
        let service = FakeDietService()
        service.profile = makeProfile(weightKg: 70)
        service.days = [makeDay(), makeDay()]
        let vm = makeVM(service)
        await vm.load()

        service.errors["updateWeight"] = dietServerError("INTERNAL_ERROR", status: 500)
        let saved = await vm.updateWeight(68)

        #expect(!saved)
        #expect(vm.errorMessage != nil)
        #expect(vm.profile?.weightKg == 70)
    }

    @Test func 몸무게_저장이_성공하면_성공을_알린다() async {
        let service = FakeDietService()
        service.profile = makeProfile(weightKg: 70)
        service.days = [makeDay(), makeDay()]
        let vm = makeVM(service)
        await vm.load()

        service.profile = makeProfile(weightKg: 68)

        #expect(await vm.updateWeight(68))
    }

    /// **`generation` 가드를 실제로 겹치게 만들어 검증한다.** 몸무게 저장·재조회가 끝나기
    /// 전에 더 새로운 `load()`가 끼어들면, 늦게 돌아온 몸무게 갱신 결과가 화면을 덮어써
    /// `needsProfile`을 잘못 세우면 안 된다 — 그러면 프로필 화면이 저절로 다시 뜬다.
    @Test func 몸무게_갱신_중_새_load가_끼어들면_늦은_응답을_버린다() async {
        let service = FakeDietService()
        service.profile = makeProfile(weightKg: 70)
        service.days = [makeDay(), makeDay()]
        let gate = AsyncGate()
        service.updateWeightGate = gate
        let vm = makeVM(service)
        await vm.load()

        let updateTask = Task { await vm.updateWeight(68) }
        await gate.waitUntilBlocked() // 몸무게 저장 호출이 응답을 못 받고 멈춘 걸 확인하고서야 다음으로 넘어간다.

        // 몸무게 갱신이 아직 끝나지 않은 사이 새로운 load()가 최신 프로필(75kg)을 읽어 들인다.
        service.profile = makeProfile(weightKg: 75)
        await vm.load()
        #expect(vm.profile?.weightKg == 75)

        // 게이트를 열면 몸무게 갱신 쪽의 `fetchProfile`이 그 뒤에 등록된 값(99kg)을 읽어
        // 오지만, generation 토큰이 어긋나 있으니 반영되면 안 된다.
        service.profile = makeProfile(weightKg: 99)
        await gate.open()
        await updateTask.value

        #expect(vm.profile?.weightKg == 75)
        #expect(!vm.needsProfile)
    }

    /// 조회 자체가 실패하면 표시를 남겨 둔다 — 알림을 닫아도 화면이 "기록 없음"으로 오인되지
    /// 않으려면 이 표식과 `day == nil`을 함께 봐야 한다.
    @Test func 하루_조회가_실패하면_loadFailed를_켠다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.errors["fetchDay"] = dietServerError("SERVER_ERROR", status: 500)
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.loadFailed)
        #expect(vm.day == nil)
    }

    /// **하루 조회가 실패해도 프로필 결과는 살아 있어야 한다.** 둘을 튜플로 함께 `try` 하면
    /// 성공한 프로필까지 버려져 `needsProfile`이 false로 남고, 화면이 「목표부터 정하기」 대신
    /// 기록 메뉴를 연다 — 사용자가 사진 인식(유료)까지 다 하고 확정에서 거절된다.
    @Test func 하루_조회가_실패해도_프로필_없음을_알아챈다() async {
        let service = FakeDietService()
        service.profile = nil   // 프로필 조회는 성공하고 「없음」을 돌려준다
        service.errors["fetchDay"] = dietServerError("SERVER_ERROR", status: 500)
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.needsProfile)
        #expect(vm.loadFailed)
    }

    /// 프로필 조회만 실패한 경우는 반대다 — **모르는 것을 「없다」로 단정하면** 프로필이 있는
    /// 사용자에게 입력 화면을 들이민다. 하루 화면도 막지 않는다(프로필은 목표 막대에만 쓴다).
    @Test func 프로필_조회만_실패하면_없다고_단정하지_않는다() async {
        let service = FakeDietService()
        service.errors["fetchProfile"] = dietServerError("SERVER_ERROR", status: 500)
        service.days = [makeDay()]
        let vm = makeVM(service)

        await vm.load()

        #expect(!vm.needsProfile)
        #expect(vm.day?.dayScore == 74)
        #expect(!vm.loadFailed)
    }

    /// 실패 뒤 다시 시도해 성공하면 실패 표시가 꺼져야 재시도 카드가 사라진다.
    @Test func 재조회가_성공하면_loadFailed를_끈다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.errors["fetchDay"] = dietServerError("SERVER_ERROR", status: 500)
        let vm = makeVM(service)
        await vm.load()
        #expect(vm.loadFailed)

        service.errors["fetchDay"] = nil
        service.days = [makeDay()]
        await vm.reload()

        #expect(!vm.loadFailed)
        #expect(vm.day?.dayScore == 74)
    }

    /// **날짜를 바꾼 뒤 실패하면 이전 날짜의 데이터를 화면에 남기면 안 된다.** `select(_:)`는
    /// `selectedDate`를 먼저 바꾸고 나서 `load()`를 부르므로, 지우지 않으면 주 스트립은 28일을
    /// 가리키는데 점수·끼니 목록은 29일 것이 그대로 남아 그 끼니 상세로 들어가 다른 날의
    /// 기록을 고치거나 지울 수 있다.
    @Test func 날짜를_바꾼_뒤_조회가_실패하면_이전_날짜_데이터를_남기지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: "2026-07-29")]
        let vm = DietDayViewModel(
            service: service,
            energyFetcher: FakeActiveEnergyFetcher(),
            date: Date.from("2026-07-29")!,
            pollInterval: .milliseconds(1),
            pollTimeout: .seconds(5)
        )
        await vm.load()
        #expect(vm.day?.date == "2026-07-29")

        service.errors["fetchDay"] = dietServerError("SERVER_ERROR", status: 500)
        await vm.select(Date.from("2026-07-28")!)

        #expect(vm.loadFailed)
        #expect(vm.day == nil)
    }

    /// 반대로 **같은 날짜를 새로고침하다 실패한 경우**는 화면에 있는 데이터가 여전히 맞는
    /// 값이므로 지우면 오히려 퇴행이다 — 오류는 그대로 알리되 데이터는 유지한다.
    @Test func 같은_날짜_새로고침이_실패하면_기존_데이터를_유지한다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: "2026-07-29")]
        let vm = DietDayViewModel(
            service: service,
            energyFetcher: FakeActiveEnergyFetcher(),
            date: Date.from("2026-07-29")!,
            pollInterval: .milliseconds(1),
            pollTimeout: .seconds(5)
        )
        await vm.load()
        #expect(vm.day?.date == "2026-07-29")

        service.errors["fetchDay"] = dietServerError("SERVER_ERROR", status: 500)
        await vm.reload()

        #expect(vm.loadFailed)
        #expect(vm.day?.date == "2026-07-29")
    }
}

@MainActor
struct MealDetailViewModelTests {
    private func makeVM(_ service: FakeDietService) -> MealDetailViewModel {
        MealDetailViewModel(
            mealId: 1, service: service,
            pollInterval: .milliseconds(1), pollTimeout: .milliseconds(30)
        )
    }

    // MARK: - 끼니 타입 수정

    /// **같은 타입이면 아무것도 하지 않는다.** 저장 한 번에 LLM 호출 한 번이 나가므로,
    /// 메뉴에서 지금 타입을 눌렀다고 유료 호출이 나가면 안 된다.
    @Test func 같은_타입이면_아무것도_안_한다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.resolveTypeChange(to: .snack) == nil)
        #expect(service.changedMealTypes.isEmpty)
    }

    /// **합쳐질 상황은 확인을 받는다.** 되돌릴 수 없는 병합이라 조용히 지나가면 안 된다.
    @Test func 합쳐질_상황이면_확인을_요구한다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        // 그날에 이미 저녁이 있다.
        service.days = [makeDay(meals: [makeMeal(id: 9, mealType: .dinner)])]
        let vm = makeVM(service)
        await vm.load()

        let action = await vm.resolveTypeChange(to: .dinner)

        guard case let .confirm(_, message) = action else {
            Issue.record("확인을 요구해야 한다: \(String(describing: action))")
            return
        }
        #expect(message.contains("합쳐져요"))
        // 아직 보내지 않는다 — 사용자가 확인을 눌러야 나간다.
        #expect(service.changedMealTypes.isEmpty)
    }

    /// 합쳐질 것이 없으면 묻지 않는다 — 잃는 것도 놀랄 것도 없다.
    @Test func 합쳐질_것이_없으면_바로_보낸다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        service.days = [makeDay(meals: [makeMeal(mealType: .snack)])]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.resolveTypeChange(to: .dinner) == .change)
    }

    /// **저녁 → 간식은 묻지 않는다.** 간식은 본래 여러 번이라 합쳐지지 않는다
    /// (`MealType.mergesWithinDay`). 합치기를 대칭으로 생각하면 여기서 틀린다.
    @Test func 간식으로_바꿀_때는_묻지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .dinner)]
        // 그날에 이미 간식이 있어도 합쳐지지 않는다.
        service.days = [makeDay(meals: [makeMeal(id: 9, mealType: .snack)])]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.resolveTypeChange(to: .snack) == .change)
    }

    /// **「합쳐진다」와 「모르겠다」는 다른 말이다.** 같은 문구를 쓰면 사용자가 확인 버튼을
    /// 누를 때 무엇을 승인하는지 모른다.
    @Test func 그날_조회에_실패하면_다른_문구로_묻는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        service.errors["fetchDay"] = dietServerError("INTERNAL_ERROR", status: 500)
        let vm = makeVM(service)
        await vm.load()

        let action = await vm.resolveTypeChange(to: .dinner)

        guard case let .confirm(_, message) = action else {
            Issue.record("확인을 요구해야 한다: \(String(describing: action))")
            return
        }
        #expect(message.contains("있다면"))
        #expect(!message.contains("합쳐져요"))
    }

    /// **돌려받은 id가 다르면 합쳐진 것이다.** 보던 끼니가 사라졌으므로 화면을 닫아야 한다.
    @Test func 합쳐졌으면_닫으라고_알린다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(id: 1, mealType: .snack)]
        service.changedMealTypeSurvivorId = 42
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.changeMealType(to: .dinner) == .merged)
    }

    @Test func 안_합쳐졌으면_화면에_남는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(id: 1, mealType: .snack), makeMeal(id: 1, mealType: .dinner)]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.changeMealType(to: .dinner) == .changed)
        // 다시 조회해 제목이 바뀐다.
        #expect(vm.meal?.mealType == .dinner)
    }

    /// **낡은 화면에서도 타입은 바꿀 수 있다.** 항목 편집은 목록을 통째로 보내기 때문에 막지만
    /// (`저장_뒤_재조회가_실패하면_다음_편집을_받지_않는다`), 타입 변경은 **항목을 아예 안
    /// 보낸다** — 되살릴 목록 자체가 없다.
    @Test func 낡은_화면에서도_타입을_바꿀_수_있다() async {
        let service = FakeDietService()
        let kept = makeMealItem(id: 1, name: "밥")
        let target = makeMealItem(id: 2, name: "제육볶음")
        service.meals = [makeMeal(id: 1, mealType: .snack, items: [kept, target])]
        let vm = makeVM(service)
        await vm.load()

        // 저장은 성공하고 그 뒤 재조회만 실패한다 — 이것이 isStale이다.
        service.errors["fetchMeal"] = dietServerError("INTERNAL_ERROR", status: 500)
        _ = await vm.deleteItem(target)
        #expect(vm.isStale)

        let outcome = await vm.changeMealType(to: .dinner)

        #expect(outcome != .failed)
        #expect(service.changedMealTypes.count == 1)
    }

    @Test func 실패하면_화면에_남고_오류가_뜬다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        service.errors["changeMealType"] = dietServerError("INTERNAL_ERROR", status: 500)
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.changeMealType(to: .dinner) == .failed)
        #expect(vm.errorMessage != nil)
    }

    /// **실패 이유가 시트까지 와야 한다.** 시트가 상세를 덮고 있어 상세의 알럿은 안 보인다 —
    /// 그냥 닫아 버리면 사용자는 저장된 줄 알고 나간다.
    @Test func 수량_저장에_실패하면_이유를_담아_돌려준다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()
        guard let item = vm.meal?.items.first, let edited = vm.editableItem(matching: item) else {
            Issue.record("항목을 찾지 못했다")
            return
        }

        service.errors["updateMealItems"] = dietServerError("INTERNAL_ERROR", status: 500)
        let outcome = await vm.saveQuantity(item, with: edited)

        guard case let .failed(message) = outcome else {
            Issue.record("실패를 담아 돌려줘야 한다: \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        // 시트가 띄웠으므로 상세에 남겨 두면 닫은 뒤 한 번 더 뜬다.
        #expect(vm.errorMessage == nil)
    }

    /// 저장은 성공했는데 그 뒤 재조회가 실패하면 화면의 끼니가 서버 상태와 다르다.
    /// **그 상태에서 또 편집을 받으면 낡은 `editableItems`로 만든 목록이 방금 성공한 변경을
    /// 덮어쓴다** — 항목 전체 교체 방식이라 그렇다. 다시 읽기 전까지 편집을 막아야 한다.
    @Test func 저장_뒤_재조회가_실패하면_다음_편집을_받지_않는다() async {
        let service = FakeDietService()
        let kept = makeMealItem(id: 1, name: "밥")
        let target = makeMealItem(id: 2, name: "제육볶음")
        service.meals = [makeMeal(items: [kept, target])]
        let vm = makeVM(service)
        await vm.load()

        // 저장은 성공하고 그 뒤 재조회만 실패한다 — 제육볶음을 지운다.
        service.errors["fetchMeal"] = dietServerError("INTERNAL_ERROR", status: 500)
        let saved = await vm.deleteItem(target)

        // PUT 자체는 성공했으므로 하루 화면은 다시 조회해야 한다.
        #expect(saved)
        #expect(vm.isStale)
        #expect(service.updatedItems.count == 1)
        #expect(service.updatedItems[0].items.map(\.foodName) == ["밥"])

        // 낡은 스냅샷에는 제육볶음이 아직 있다. 여기서 밥을 지우면 **제육볶음이 되살아난
        // 목록**이 서버로 나가 방금 성공한 삭제가 뒤집힌다 — 아예 받으면 안 된다.
        let second = await vm.deleteItem(kept)

        #expect(!second)
        #expect(service.updatedItems.count == 1)
        #expect(vm.errorMessage != nil)
    }

    /// **첫 조회가 실패하면 화면이 통째로 비어 있다.** 그때 `meal`이 nil이라 `isStale`은
    /// false로 남는데, 화면이 그것만 보면 다시 불러올 길이 없어 알럿을 닫는 순간 빈 화면에
    /// 갇힌다 — 나갔다 들어오는 것 말고는 방법이 없다.
    @Test func 첫_조회가_실패해도_다시_불러올_길을_남긴다() async {
        let service = FakeDietService()
        service.errors["fetchMeal"] = dietServerError("INTERNAL_ERROR", status: 500)
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.meal == nil)
        #expect(!vm.isStale)
        #expect(vm.loadFailed)
        #expect(vm.loadFailureText == "끼니를 불러오지 못했어요.")

        // 낡은 경우와 문구가 달라야 한다 — 앞은 아무것도 못 받았고 뒤는 받아 둔 게 낡았다.
        service.errors["fetchMeal"] = nil
        service.meals = [makeMeal()]
        await vm.load()
        #expect(vm.loadFailureText == nil)

        service.errors["fetchMeal"] = dietServerError("INTERNAL_ERROR", status: 500)
        await vm.load()
        #expect(vm.isStale)
        #expect(vm.loadFailureText == "최신 상태를 불러오지 못했어요. 지금 보이는 내용이 서버와 다를 수 있어요.")
    }

    /// 다시 불러오는 데 성공하면 편집이 풀린다 — 안 풀리면 화면을 나갔다 오는 수밖에 없다.
    @Test func 다시_불러오면_편집이_풀린다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(), makeMeal(score: 88)]
        let vm = makeVM(service)
        await vm.load()

        service.errors["fetchMeal"] = dietServerError("INTERNAL_ERROR", status: 500)
        await vm.replaceItems(vm.editableItems)
        #expect(vm.isStale)

        service.errors["fetchMeal"] = nil
        await vm.load()

        #expect(!vm.isStale)

        let after = await vm.replaceItems(vm.editableItems)
        #expect(after)
        #expect(service.updatedItems.count == 2)
    }

    // MARK: - 사진

    /// presigned URL은 10분 만료다. 상세를 열어 둔 채 시간이 지나면 전체화면 보기가 실패하는데,
    /// **주소를 다시 받을 길이 없으면 화면을 나갔다 오는 수밖에 없다.**
    @Test func 사진_주소를_다시_받는다() async {
        let service = FakeDietService()
        service.meals = [
            makeMeal(photos: [MealPhoto(fileId: 11, url: "https://example.com/old.jpg", sortOrder: 0)]),
            makeMeal(photos: [MealPhoto(fileId: 11, url: "https://example.com/new.jpg", sortOrder: 0)])
        ]
        let vm = makeVM(service)
        await vm.load()

        let refreshed = await vm.refreshedPhotoURL(fileId: 11)

        #expect(refreshed == "https://example.com/new.jpg")
        #expect(service.fetchedMealIds == [1, 1])

        // 그 사이 사라진 사진이면 줄 주소가 없다.
        #expect(await vm.refreshedPhotoURL(fileId: 99) == nil)
    }

    // MARK: - 사진 삭제

    @Test func 사진을_지우면_그_끼니를_다시_읽는다() async {
        let service = FakeDietService()
        let first = MealPhoto(fileId: 11, url: "https://example.com/1.jpg", sortOrder: 0)
        let second = MealPhoto(fileId: 12, url: "https://example.com/2.jpg", sortOrder: 1)
        service.meals = [makeMeal(photos: [first, second]), makeMeal(photos: [first])]
        let vm = makeVM(service)
        await vm.load()

        let deleted = await vm.deletePhoto(fileId: 12)

        #expect(deleted)
        // **지목한 한 장만 나간다.** mealId까지 확인해야 "전부 지우기"로 잘못 짜도 통과하는 일이 없다.
        #expect(service.deletedPhotos.map(\.mealId) == [1])
        #expect(service.deletedPhotos.map(\.fileId) == [12])
        // presigned URL은 10분 만료라 남은 사진 주소를 다시 받아야 한다.
        #expect(service.fetchedMealIds == [1, 1])
        #expect(vm.meal?.photos.map(\.fileId) == [11])
    }

    /// 지우는 동안 같은 버튼을 또 누르면 **이미 사라진 사진의 `fileId`가 한 번 더 나간다** —
    /// 서버는 404로 답하고 화면에는 없는 오류가 뜬다.
    @Test func 삭제가_끝나기_전에는_두_번째_삭제를_보내지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()

        let gate = AsyncGate()
        service.deleteMealPhotoGate = gate
        let running = Task { await vm.deletePhoto(fileId: 11) }
        await gate.waitUntilBlocked() // 첫 요청이 응답을 못 받고 멈춘 걸 확인하고서야 넘어간다.

        #expect(vm.isSaving)
        // 가드가 없으면 이 호출이 게이트에 걸려 영영 돌아오지 않는다 — 실패가 아니라
        // **정지**로 나타난다(`저장이_진행_중이면_두_번째_변경을_보내지_않는다`와 같다).
        let second = await vm.deletePhoto(fileId: 11)
        #expect(!second)

        await gate.open()
        #expect(await running.value)
        #expect(service.deletedPhotos.count == 1)
    }

    /// 재조회가 실패한 화면은 서버와 다를 수 있다 — 그 상태에서 지우면 **엉뚱한 장을 가리킨다.**
    @Test func 낡은_화면에서는_사진을_지우지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()

        service.errors["fetchMeal"] = dietServerError("INTERNAL_ERROR", status: 500)
        await vm.load()
        #expect(vm.isStale)

        let deleted = await vm.deletePhoto(fileId: 11)

        #expect(!deleted)
        #expect(service.deletedPhotos.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test func 사진_삭제에_실패하면_알리고_화면을_그대로_둔다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()

        service.errors["deleteMealPhoto"] = dietServerError("RESOURCE_NOT_FOUND", status: 404)
        let deleted = await vm.deletePhoto(fileId: 11)

        #expect(!deleted)
        #expect(vm.errorMessage != nil)
        // 실패했으면 다시 읽지 않는다 — 바뀐 것이 없는데 화면만 깜빡인다.
        #expect(service.fetchedMealIds == [1])
        #expect(vm.meal?.photos.map(\.fileId) == [11])
    }

    @Test func 끼니를_읽는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.meal?.score == 76)
        #expect(vm.meal?.scoreBasis?.macros.count == 3)
        #expect(!vm.isFeedbackPending)
    }

    /// **확정 직후 피드백 폴링이 화면을 붙잡지 않는다** — 점수는 이미 표시된다.
    @Test func 피드백_대기중에도_점수는_보인다() async {
        let service = FakeDietService()
        service.meals = [
            makeMeal(status: .pending, feedback: nil),
            makeMeal(status: .completed, feedback: "잘 드셨어요.")
        ]
        let vm = makeVM(service)

        await vm.load()
        #expect(vm.meal?.score == 76)
        #expect(vm.isFeedbackPending)

        await vm.waitForFeedbackPolling()

        #expect(vm.meal?.feedback == "잘 드셨어요.")
        #expect(!vm.isFeedbackPending)
    }

    /// 끼니 피드백은 실패하면 재시도 여지가 있다 — 다만 앱은 `POST /meals/{id}/retry`를 부르지 않는다.
    @Test func 피드백_생성_실패는_점수를_지우지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(status: .failed, feedback: nil)]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.meal?.score == 76)
        #expect(vm.meal?.feedback == nil)
        #expect(!vm.isFeedbackPending)
    }

    /// 폴링 중이던 로드가 실패로 끝나면 "피드백 만드는 중" 표시가 방치되면 안 된다 — 취소한
    /// 이전 폴링의 흔적으로 화면이 무한 로딩에 갇힌다. `DietDayViewModel`의 같은 사고와 같은 수정.
    @Test func 재로딩이_실패하면_피드백_대기_표시를_끈다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(status: .pending, feedback: nil)]
        let vm = makeVM(service)

        await vm.load()
        #expect(vm.isFeedbackPending)

        service.errors["fetchMeal"] = dietServerError("SERVER_ERROR", status: 500)
        await vm.load()

        #expect(!vm.isFeedbackPending)
    }

    @Test func 항목을_교체하면_재계산_결과를_다시_읽는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(), makeMeal(score: 88)]
        let vm = makeVM(service)
        await vm.load()

        let items = [NutritionMath.manualItem(
            name: "닭가슴살", quantityG: 150, kcal: 165, carbsG: 0,
            proteinG: 31, fatG: 3.6, sugarG: 0, sodiumMg: 74, fiberG: 0
        )]
        await vm.replaceItems(items)

        #expect(service.updatedItems.count == 1)
        #expect(service.updatedItems.first?.items.first?.sodiumMg == 74)
        #expect(vm.meal?.score == 88)
    }

    /// 서버가 빈 배열을 거절하므로(`PUT /items`) 앱은 애초에 보내지 않는다 — 다 지우고 싶으면
    /// 끼니를 통째로 삭제해야 한다.
    @Test func 항목을_모두_지우면_요청을_보내지_않고_삭제를_안내한다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()

        let sent = await vm.replaceItems([])

        #expect(!sent)
        #expect(service.updatedItems.isEmpty)
        #expect(vm.errorMessage == "항목을 모두 지우려면 끼니를 삭제해 주세요.")
    }

    /// **같은 음식을 두 번 담은 끼니에서 삭제는 id로만 골라야 한다.** 이름·수량이 완전히 같은
    /// 두 항목을 두고(사진 두 장에서 같은 메뉴가 인식되거나, 같은 걸 두 번 기록한 경우) `id`만
    /// 다르게 둔다 — 이름·수량 매칭으로 퇴행하면 이름·수량이 같으니 어느 쪽을 지목해도 항상
    /// `firstIndex`가 첫 자리(0번)만 찾아 **뒤쪽(second)을 지우려 해도 앞쪽(first)이 지워진다.**
    /// 두 항목을 구분할 값이 화면에는 없으므로, 요청에 실리는 나트륨 값을 표식으로만 쓴다
    /// (이름·수량 매칭과 id 매칭이 실제로 갈라지는 유일한 조건이 이것이다).
    @Test func 같은_음식이_두_번_있어도_id로_구분해_하나만_지운다() async {
        let service = FakeDietService()
        let first = makeMealItem(id: 1, quantityG: 200, sodium: 500)
        let second = makeMealItem(id: 2, quantityG: 200, sodium: 900)
        service.meals = [makeMeal(items: [first, second])]
        let vm = makeVM(service)
        await vm.load()

        // 뒤쪽(second, id 2)을 지목해서 지운다 — 이름·수량 매칭이었다면 항상 앞쪽(first)이
        // 지워지므로, 남는 게 first(나트륨 500)인지 second(나트륨 900)인지로 구별된다.
        await vm.deleteItem(second)

        let sent = try! #require(service.updatedItems.first?.items)
        #expect(sent.count == 1)
        #expect(sent.first?.sodiumMg == 500) // first가 남아야 한다.
    }

    /// 같은 조건에서 교체도 마찬가지다 — 뒤쪽(second)을 지목했는데 이름·수량 매칭이면 항상
    /// 앞쪽(first) 자리가 바뀐다.
    @Test func 같은_음식이_두_번_있어도_id로_구분해_하나만_바꾼다() async {
        let service = FakeDietService()
        let first = makeMealItem(id: 1, quantityG: 200, sodium: 500)
        let second = makeMealItem(id: 2, quantityG: 200, sodium: 900)
        service.meals = [makeMeal(items: [first, second])]
        let vm = makeVM(service)
        await vm.load()

        let replacement = NutritionMath.manualItem(
            name: "닭가슴살", quantityG: 200, kcal: 330, carbsG: 0,
            proteinG: 62, fatG: 7.2, sugarG: 0, sodiumMg: 999, fiberG: 0
        )
        await vm.replaceItem(second, with: replacement)

        let sent = try! #require(service.updatedItems.first?.items)
        #expect(sent.count == 2)
        #expect(sent[0].sodiumMg == 500) // 앞자리(first)는 그대로여야 한다.
        #expect(sent[1].sodiumMg == 999) // 뒷자리(second)만 바뀌어야 한다.
    }

    /// **항목 편집 하나하나가 각자 네트워크 왕복이다.** 첫 변경이 아직 응답을 못 받았는데 두
    /// 번째 변경을 보내면, 둘 다 같은 이전 스냅샷에서 출발해 나중에 끝난 쪽이 먼저 것을
    /// 덮어쓴다 — 그래서 진행 중에는 두 번째 요청을 아예 보내지 않아야 한다.
    @Test func 저장이_진행_중이면_두_번째_변경을_보내지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(), makeMeal(score: 88)]
        let gate = AsyncGate()
        service.updateMealItemsGate = gate
        let vm = makeVM(service)
        await vm.load()

        let firstItems = [NutritionMath.manualItem(
            name: "닭가슴살", quantityG: 150, kcal: 165, carbsG: 0,
            proteinG: 31, fatG: 3.6, sugarG: 0, sodiumMg: 74, fiberG: 0
        )]
        let firstTask = Task { await vm.replaceItems(firstItems) }
        await gate.waitUntilBlocked() // 첫 요청이 응답을 못 받고 멈춘 걸 확인하고서야 다음으로 넘어간다.

        #expect(vm.isSaving)
        let secondSent = await vm.replaceItems(vm.editableItems)
        #expect(!secondSent)
        #expect(service.updatedItems.count == 1)

        await gate.open()
        _ = await firstTask.value
    }

    /// **삭제 뒤에는 하루 요약을 다시 조회해야 한다** — 점수·합계·`nutrientLimits`가 전부 달라지고
    /// 피드백은 `null`로 돌아와 다시 생성이 걸린다. 화면이 그 신호로 쓸 `didDelete`를 세운다.
    @Test func 끼니를_삭제하면_삭제_표식을_남긴다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()

        await vm.deleteMeal()

        #expect(service.deletedMealIds == [1])
        #expect(vm.didDelete)
    }

    /// 타인 소유 리소스는 404다 — "찾을 수 없습니다"로 같게 다룬다.
    @Test func 없는_끼니는_찾을_수_없다고_안내한다() async {
        let service = FakeDietService()
        service.errors["fetchMeal"] = dietServerError("RESOURCE_NOT_FOUND", status: 404)
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.meal == nil)
        #expect(vm.errorMessage != nil)
    }
}

@MainActor
struct DietActivityMergeTests {
    /// 활동 에너지를 올린 **뒤에 도착한 조회 응답**이 그 값을 지우면 안 된다. 서버 응답은
    /// 업로드보다 먼저 나갔을 수 있고, 그러면 응답에는 아직 활동량이 없다.
    @Test func 올린_소모_칼로리를_나중_조회가_지우지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        // 두 응답 모두 활동량이 비어 있다 — 업로드보다 먼저 나간 응답을 흉내낸다.
        service.days = [
            makeDay(date: "2026-07-29", activeEnergyKcal: nil),
            makeDay(date: "2026-07-29", activeEnergyKcal: nil)
        ]
        let fetcher = FakeActiveEnergyFetcher()
        fetcher.kcal = 2400
        let vm = DietDayViewModel(
            service: service, energyFetcher: fetcher, date: Date.from("2026-07-29")!
        )

        await vm.load()
        #expect(vm.day?.activeEnergyKcal == nil)

        await vm.syncActivity()
        #expect(vm.day?.activeEnergyKcal == 2400)

        await vm.reload()

        #expect(vm.day?.activeEnergyKcal == 2400)
        #expect(service.activityCalls.map(\.kcal) == [2400])
    }

    /// 같은 일이 **피드백 폴링 응답**에서도 일어난다 — Codex가 짚은 자리다.
    @Test func 피드백_폴링_응답도_올린_소모_칼로리를_지우지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [
            makeDay(date: "2026-07-29", feedback: nil, activeEnergyKcal: nil),
            makeDay(date: "2026-07-29", feedback: "잘 드셨어요", activeEnergyKcal: nil)
        ]
        let fetcher = FakeActiveEnergyFetcher()
        fetcher.kcal = 2400
        let vm = DietDayViewModel(
            service: service, energyFetcher: fetcher, date: Date.from("2026-07-29")!,
            // 폴링이 첫 회차를 자는 동안 `syncActivity()`가 끝나도록 넉넉히 준다.
            pollInterval: .milliseconds(50), pollTimeout: .seconds(5)
        )

        await vm.load()
        await vm.syncActivity()
        await vm.waitForFeedbackPolling()

        #expect(vm.day?.feedback == "잘 드셨어요")
        #expect(vm.day?.activeEnergyKcal == 2400)
    }

    /// **날짜를 바꿀 때도 활동량을 올린다.** 화면 진입의 `.task`에서만 부르면, 그 뒤에 고른
    /// 날짜들은 소모 칼로리가 영영 비어 있다 — 어제를 열어 봐도 채워지지 않는다.
    @Test func 날짜를_바꾸면_그_날의_활동량도_올린다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [
            makeDay(date: "2026-07-29", activeEnergyKcal: nil),
            makeDay(date: "2026-07-30", activeEnergyKcal: nil)
        ]
        let fetcher = FakeActiveEnergyFetcher()
        fetcher.kcal = 2400
        let vm = DietDayViewModel(
            service: service, energyFetcher: fetcher, date: Date.from("2026-07-29")!
        )
        await vm.load()

        await vm.select(Date.from("2026-07-30")!)

        // 옮겨 간 날짜로 올라가야 한다 — 이전 날짜로 올리면 어제 소모량이 오늘에 붙는다.
        #expect(service.activityCalls.map(\.date) == ["2026-07-30"])
        #expect(vm.day?.activeEnergyKcal == 2400)
    }

    /// **올린 값은 날짜별로 따로 담는다.** 하나만 들고 있으면 날짜를 오갈 때 나중에 방문한
    /// 날짜가 앞의 것을 밀어내고, 돌아왔을 때 그 날의 소모 칼로리가 사라진다.
    @Test func 날짜를_오가도_각_날의_소모_칼로리가_남는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [
            makeDay(date: "2026-07-29", activeEnergyKcal: nil),
            makeDay(date: "2026-07-30", activeEnergyKcal: nil),
            makeDay(date: "2026-07-29", activeEnergyKcal: nil)
        ]
        let fetcher = FakeActiveEnergyFetcher()
        fetcher.kcal = 2400
        let vm = DietDayViewModel(
            service: service, energyFetcher: fetcher, date: Date.from("2026-07-29")!
        )

        await vm.load()
        await vm.syncActivity()
        #expect(vm.day?.activeEnergyKcal == 2400)

        fetcher.kcal = 1000
        await vm.select(Date.from("2026-07-30")!)
        #expect(vm.day?.activeEnergyKcal == 1000)

        // 다시 07-29로. 건강 앱에 새로 읽을 게 없어도(0은 올리지 않는다) 그날 올렸던
        // 2400이 남아 있어야 한다 — 캐시가 하나뿐이면 07-30의 1000이 밀어내 비어 버린다.
        fetcher.kcal = 0
        await vm.select(Date.from("2026-07-29")!)

        #expect(vm.day?.date == "2026-07-29")
        #expect(vm.day?.activeEnergyKcal == 2400)
    }

    /// 날짜가 다르면 씌우지 않는다 — 어제 소모량이 오늘 화면에 남으면 안 된다.
    @Test func 다른_날짜의_조회에는_올린_값을_씌우지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [
            makeDay(date: "2026-07-29", activeEnergyKcal: nil),
            makeDay(date: "2026-07-30", activeEnergyKcal: nil)
        ]
        let fetcher = FakeActiveEnergyFetcher()
        fetcher.kcal = 2400
        let vm = DietDayViewModel(
            service: service, energyFetcher: fetcher, date: Date.from("2026-07-29")!
        )

        await vm.load()
        await vm.syncActivity()
        #expect(vm.day?.activeEnergyKcal == 2400)

        // 옮겨 간 날은 건강 앱에 활동 기록이 없다(0은 올리지 않는다). 그러니 화면도 비어야
        // 한다 — 여기서 2400이 보이면 어제 소모량이 오늘에 눌어붙은 것이다.
        fetcher.kcal = 0
        await vm.select(Date.from("2026-07-30")!)

        #expect(vm.day?.date == "2026-07-30")
        #expect(vm.day?.activeEnergyKcal == nil)
        #expect(service.activityCalls.map(\.date) == ["2026-07-29"])
    }
}

@MainActor
struct DietWeekStripTests {
    /// 스트립의 기준일과 선택 날짜를 분리한 이유가 전부 여기 있다 — 주를 넘기는 것은
    /// 「보기」이고 조회가 아니다.
    private func makeVM(on dateString: String) -> (DietDayViewModel, FakeDietService) {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: dateString)]
        let date = Date.from(dateString)!
        return (DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher(), date: date), service)
    }

    @Test func 다음_주로_넘기면_보이는_주만_7일_뒤로_간다() async {
        let (vm, _) = makeVM(on: "2026-07-15")   // 수요일
        await vm.load()
        let before = vm.weekDates

        vm.showNextWeek()

        #expect(vm.selectedDate == Date.from("2026-07-15"))
        for (old, new) in zip(before, vm.weekDates) {
            #expect(Calendar.current.dateComponents([.day], from: old, to: new).day == 7)
        }
    }

    @Test func 이전_주로_넘기면_보이는_주만_7일_앞으로_간다() async {
        let (vm, _) = makeVM(on: "2026-07-15")
        await vm.load()
        let before = vm.weekDates

        vm.showPreviousWeek()

        #expect(vm.selectedDate == Date.from("2026-07-15"))
        for (old, new) in zip(before, vm.weekDates) {
            #expect(Calendar.current.dateComponents([.day], from: old, to: new).day == -7)
        }
    }

    /// **스와이프에 네트워크가 붙으면 안 된다.** 주를 세 번 넘기는 동안 조회가 세 번 나가면
    /// 화면이 매번 갈아엎힌다.
    @Test func 주를_넘겨도_서버를_다시_부르지_않는다() async {
        let (vm, service) = makeVM(on: "2026-07-15")
        await vm.load()
        let callCount = service.fetchedDates.count

        vm.showNextWeek()
        vm.showNextWeek()
        vm.showPreviousWeek()

        #expect(service.fetchedDates.count == callCount)
    }

    /// 넘긴 주에 선택 날짜가 없으면 「오늘」 버튼이 떠야 한다.
    @Test func 주를_넘기면_선택한_주를_보고_있지_않다() async {
        let (vm, _) = makeVM(on: "2026-07-15")
        await vm.load()

        #expect(vm.isViewingSelectedWeek)

        vm.showNextWeek()
        #expect(!vm.isViewingSelectedWeek)

        vm.showPreviousWeek()
        #expect(vm.isViewingSelectedWeek)
    }

    /// 주를 넘긴 뒤 날짜를 탭하면 기준일이 **그 날짜의 주로** 맞춰진다.
    /// **보이는 주 바깥의 날짜를 고른다** — 보이는 주 안의 날짜를 고르면 기준일을
    /// 안 건드려도 통과해서 아무것도 검증하지 못한다.
    @Test func 날짜를_고르면_기준일이_그_주로_맞춰진다() async {
        let (vm, service) = makeVM(on: "2026-07-15")
        service.days = [makeDay(date: "2026-07-15"), makeDay(date: "2026-07-16")]
        await vm.load()

        vm.showNextWeek()                            // 보이는 주: 7/19~7/25
        #expect(!vm.isViewingSelectedWeek)

        await vm.select(Date.from("2026-07-16")!)    // 그 주 바깥의 날짜

        #expect(vm.selectedDate == Date.from("2026-07-16"))
        #expect(vm.isViewingSelectedWeek)            // 기준일이 7/12~7/18 주로 되돌아왔다
        #expect(service.fetchedDates.last == "2026-07-16")
    }

    /// 몇 주를 넘긴 뒤 돌아올 길. 선택과 기준일이 함께 오늘로 돌아온다.
    /// **시작점을 오늘 기준 상대 날짜로 잡는다** — 고정 날짜로 두면 실행 시점에 따라
    /// 넘어간 주가 오늘의 주와 겹쳐 아무것도 검증하지 못하는 날이 생긴다.
    @Test func 오늘_버튼은_선택과_기준일을_함께_되돌린다() async {
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let (vm, _) = makeVM(on: start.dateString)
        await vm.load()

        vm.showNextWeek()
        vm.showNextWeek()
        vm.showNextWeek()                            // 오늘보다 39일 전 — 절대 오늘의 주가 아니다
        #expect(!vm.isViewingSelectedWeek)

        await vm.goToToday()

        #expect(Calendar.current.isDateInToday(vm.selectedDate))
        #expect(vm.isViewingSelectedWeek)
    }

    /// 스트립 위 월 표시. 주를 넘겨 달이 바뀌면 표시도 따라간다.
    @Test func 월_표시는_보이는_주를_따라간다() async {
        let (vm, _) = makeVM(on: "2026-07-29")   // 수요일
        await vm.load()

        #expect(vm.visibleMonthText == "7월")

        vm.showNextWeek()   // 8/2~8/8 주
        #expect(vm.visibleMonthText == "8월")
    }
}
