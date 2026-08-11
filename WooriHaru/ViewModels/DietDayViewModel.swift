import Foundation

/// 프로필 자격. **「모른다」를 별도의 상태로 둔다.**
///
/// 조회가 실패했을 때 「있다」로 읽으면 사용자가 사진 인식(유료)까지 다 하고 확정 단계에서
/// 거절되고, 「없다」로 읽으면 프로필이 있는 사용자에게 입력 화면을 들이민다. 어느 쪽으로도
/// 단정할 수 없으므로 화면이 그 사실을 그대로 다루게 한다.
enum ProfileEligibility {
    /// 아직 못 받았거나 조회가 실패했다.
    case unknown
    case eligible
    case missing
}

/// 날짜별 하루 요약·끼니 목록·마감 피드백 폴링.
///
/// **피드백 폴링은 화면을 붙잡지 않는다.** 조회는 즉시 돌아오고 `feedback`이 `null`이면 서버가
/// 뒤에서 만들고 있다는 뜻이라 그 영역만 로딩으로 두었다가 채운다. **실패해도 재시도 버튼을
/// 두지 않는다** — 서버가 끼니가 바뀔 때까지 다시 부르지 않으므로(비용 방어) 사용자가 끼니를
/// 추가·수정하면 자연히 다시 만들어진다.
@MainActor
@Observable
final class DietDayViewModel {
    private(set) var selectedDate: Date
    /// 스트립에 보이는 주의 기준일. **`selectedDate`와 분리한다** — 스와이프는 「보기」의
    /// 변경이고 조회가 아니다. 둘이 붙어 있으면 주를 세 번 넘기는 동안 조회가 세 번 나간다.
    private(set) var visibleWeekAnchor: Date
    private(set) var day: DailyDiet?
    private(set) var profile: NutritionProfile?

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// 프로필을 받았는가·있는가. **조회가 실패하면 `.unknown`에 머문다** — 그 상태로
    /// 기록을 시작시키면 유료 인식을 다 하고 확정에서 거절된다.
    private(set) var profileEligibility: ProfileEligibility = .unknown

    /// 프로필이 없어 점수를 낼 수 없는 상태. 업로드보다 프로필 입력이 먼저다.
    /// **`.unknown`은 여기 해당하지 않는다** — 모르는 것을 「없다」로 단정하지 않는다.
    var needsProfile: Bool { profileEligibility == .missing }
    private(set) var isFeedbackPending = false
    /// 60초 안에 안 왔다. **실패가 아니다** — 서버는 계속 처리 중일 수 있다.
    private(set) var isFeedbackDelayed = false
    /// 하루 조회 자체가 실패했는지. 알림을 닫아도 남아 있어야 "기록 없음"으로 오인되지 않는다.
    private(set) var loadFailed = false
    var errorMessage: String?

    /// 진행 중인 조회·폴링을 무효화하는 표식. 날짜를 바꾸거나 새로고침이 끼어들면 값을 올려
    /// 뒤늦게 돌아온 이전 결과를 버린다.
    private var generation = 0
    private var feedbackTask: Task<Void, Never>?
    /// 예약해 둔 하루 조회. 스와이프가 이어지는 동안 취소하고 다시 잡는다.
    private var pendingSelection: Task<Void, Never>?
    /// `syncActivity()`가 서버에 올린 값. 폴링·재조회 응답이 이 업로드보다 먼저 나갔을 수 있어,
    /// 응답을 얹은 뒤 이 값을 다시 씌운다(`apply(_:)` 참조).
    ///
    /// **날짜별로 따로 담는다.** 하나만 들고 있으면 날짜를 오가며 동기화가 겹칠 때 이전 날짜의
    /// 느린 업로드가 현재 날짜의 값을 밀어내고, 그다음 조회 응답이 화면의 소모 칼로리를
    /// 낡은 값이나 빈 값으로 되돌린다.
    private var syncedActivity: [String: Int] = [:]

    private let service: any DietServing
    private let energyFetcher: any ActiveEnergyFetching
    private let pollInterval: Duration
    private let pollTimeout: Duration
    /// 하루 스와이프가 멈췄다고 보고 조회를 내기까지의 시간. 테스트가 줄여 쓴다.
    private let daySwipeDelay: Duration

    init(
        service: any DietServing = DietService(),
        energyFetcher: any ActiveEnergyFetching = HealthKitService(),
        date: Date = Date(),
        pollInterval: Duration = DietPolicy.pollInterval,
        pollTimeout: Duration = DietPolicy.pollTimeout,
        daySwipeDelay: Duration = .milliseconds(350)
    ) {
        self.service = service
        self.energyFetcher = energyFetcher
        self.selectedDate = date
        self.visibleWeekAnchor = date
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.daySwipeDelay = daySwipeDelay
    }

    /// 스트립에 보이는 주(일~토). **`selectedDate`가 아니라 `visibleWeekAnchor`에서 파생된다** —
    /// 좌우 스와이프로 주를 넘길 때 조회가 나가면 안 되고, 선택 날짜는 탭했을 때만 바뀐다.
    var weekDates: [Date] {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: visibleWeekAnchor)?.start else {
            return [visibleWeekAnchor]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// 「7월」 — 스트립 위에 붙는다. 주를 넘겨 달이 바뀌면 여기가 따라간다.
    var visibleMonthText: String {
        "\(Calendar.current.component(.month, from: visibleWeekAnchor))월"
    }

    /// 보이는 주에 선택 날짜가 있는가. 없으면 화면이 「오늘」 버튼을 띄운다 —
    /// 몇 주를 넘긴 뒤 돌아올 길이 필요하다.
    var isViewingSelectedWeek: Bool {
        Calendar.current.isDate(visibleWeekAnchor, equalTo: selectedDate, toGranularity: .weekOfYear)
    }

    /// 「오늘」 버튼을 띄울지. **`isViewingSelectedWeek`를 쓰면 안 된다** — 주를 넘겨 그 주의
    /// 날짜를 고르면 `select(_:)`가 기준일을 선택 날짜에 맞추므로 그 조건이 참이 되고,
    /// 2주 전을 보고 있는데 버튼이 사라져 오늘로 돌아올 길이 없어진다. 버튼이 하는 일이
    /// 「오늘로 간다」이므로 판단도 오늘을 기준으로 한다.
    var showsTodayButton: Bool {
        let calendar = Calendar.current
        let isTodaySelected = calendar.isDateInToday(selectedDate)
        let isTodayVisible = calendar.isDate(visibleWeekAnchor, equalTo: Date(), toGranularity: .weekOfYear)
        return !(isTodaySelected && isTodayVisible)
    }

    /// 보이는 주만 옮긴다. **네트워크 호출이 없다.**
    func showPreviousWeek() { shiftVisibleWeek(by: -7) }
    func showNextWeek() { shiftVisibleWeek(by: 7) }

    private func shiftVisibleWeek(by days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: visibleWeekAnchor) else { return }
        visibleWeekAnchor = moved
    }

    /// 하루 단위 이동(스트립 아래 좌우 스와이프). **화면은 즉시 옮기고 조회만 늦춘다** —
    /// `select(_:)` 한 번은 활동량 업서트와 하루 조회이고 그 조회가 서버의 하루 피드백
    /// 생성을 건다. 초당 서너 번 나가는 스와이프에 그대로 붙이면 왕복이 그만큼 늘어난다.
    func stepDay(by days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }

        selectedDate = moved
        // 선택이 화면 밖에 남지 않게 스트립도 따라간다.
        visibleWeekAnchor = moved

        // **이 방어는 조회와 함께 늦추면 안 된다.** 이전 날짜의 끼니가 새 날짜 라벨 아래
        // 남아 있으면 사용자가 그것을 이 날짜 것으로 알고 열어 고치거나 지운다
        // (`select(_:)`가 같은 이유로 같은 일을 한다).
        day = nil
        isLoading = true
        // 진행 중이던 조회·폴링을 여기서 무효화한다 — 늦게 온 이전 날짜 응답이 되채운다.
        generation += 1
        feedbackTask?.cancel()

        pendingSelection?.cancel()
        let delay = daySwipeDelay
        pendingSelection = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await syncActivity()
            await load()
        }
    }

    /// 예약된 하루 조회를 기다린다. **테스트가 쓴다** — 화면은 기다릴 일이 없다.
    func waitForPendingSelection() async {
        await pendingSelection?.value
    }

    /// 몇 주를 넘긴 뒤 돌아온다 — 선택과 기준일을 함께 오늘로 되돌린다.
    func goToToday() async {
        await select(Date())
    }

    var dateString: String { selectedDate.dateString }

    /// 서버가 `mealType` 순으로 정렬해 주므로 **앱이 다시 정렬하지 않는다.**
    var meals: [Meal] { day?.meals ?? [] }

    var estimatedNoticeText: String? {
        guard let count = day?.estimatedItemCount, count > 0 else { return nil }
        return "추정 \(count)건 포함"
    }

    // MARK: - Load

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        errorMessage = nil
        loadFailed = false
        feedbackTask?.cancel()
        isFeedbackDelayed = false
        // 폴링 중이던 이전 로드가 실패로 끝나면 "만드는 중" 표시가 방치된다 — 취소한
        // 자리에서 같이 꺼야 화면이 무한 로딩으로 남지 않는다.
        isFeedbackPending = false

        async let profileResult = service.fetchProfile()
        async let dayResult = service.fetchDay(date: selectedDate.dateString)

        // **둘을 따로 받는다.** 튜플로 함께 `try` 하면 하루 조회가 실패할 때 성공한 프로필
        // 결과까지 버려진다 — 프로필이 없는 첫 진입에서 하루 조회가 한 번 실패하면
        // `needsProfile`이 false로 남아, 화면이 「목표부터 정하기」 대신 기록 메뉴를 연다.
        // 그러면 사용자가 사진 인식(유료)까지 다 하고 확정 단계에서 거절된다.
        do {
            let loadedProfile = try await profileResult
            guard token == generation else { return }
            profile = loadedProfile
            profileEligibility = loadedProfile == nil ? .missing : .eligible
        } catch is CancellationError {
            return
        } catch {
            // **프로필 조회만 실패했으면 자격을 `.unknown`에 남긴다** — 「없다」로 단정하면
            // 프로필이 있는 사용자에게 입력 화면을 들이밀고, 「있다」로 단정하면 사진
            // 인식(유료)을 다 하고 확정 단계에서 거절된다. 화면이 그 모름을 그대로 다룬다
            // (`DietHomeView`가 기록 메뉴 대신 「목표 확인하기」를 띄운다).
            //
            // **한 번 확인된 자격은 내리지 않는다** — 이미 `.eligible`이면 그대로 둔다.
            // 하루 화면 자체는 막지 않는다(프로필은 목표 막대에만 쓴다).
        }

        do {
            let loadedDay = try await dayResult
            guard token == generation else { return }
            apply(loadedDay)
            loadFailed = false
            startFeedbackPollingIfNeeded(token: token)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            loadFailed = true
            // 화면에 남아 있는 하루가 지금 선택된 날짜의 것이 아니면 지운다. `select(_:)`가
            // `selectedDate`를 먼저 바꾸고 나서 `load()`를 부르므로, 여기서 실패하면 화면에는
            // "이전 날짜의 데이터 + 새 날짜 라벨"이 남는다 — 점수·끼니 목록이 다른 날의 것인데
            // 라벨만 새 날짜라 사용자가 그 끼니를 다른 날짜인 줄 모르고 고치거나 지울 수 있다.
            // 같은 날짜를 새로고침하다 실패한 경우는 `day.date`가 이미 `selectedDate`와 같으니
            // 지우지 않는다 — 그 데이터는 여전히 맞는 값이라 지우면 오히려 퇴행이다.
            if let day, day.date != selectedDate.dateString {
                self.day = nil
            }
        }
        guard token == generation else { return }
        hasLoaded = true
        isLoading = false
    }

    func select(_ date: Date) async {
        // **스와이프로 예약해 둔 조회를 취소한다.** 안 그러면 탭한 날짜 위에 0.35초 뒤
        // 스와이프가 겨눴던 날짜의 조회가 덮인다.
        //
        // **취소했으면 같은 날짜여도 조회를 내야 한다.** `stepDay`가 `selectedDate`를 미리
        // 옮겨 두므로 스와이프 직후의 탭은 「같은 날짜」로 들어오는데, 아래 가드에서 그냥
        // 빠져나가면 `stepDay`가 켜 둔 로딩과 빈 하루를 되돌릴 것이 아무것도 없다.
        let hadPendingSelection = pendingSelection != nil
        pendingSelection?.cancel()
        pendingSelection = nil

        // 조회를 건너뛰는 경우에도 기준일은 맞춰야 한다 — 주를 넘긴 뒤 이미 선택돼 있는
        // 날짜를 다시 탭했을 때 기준일이 그대로면 「오늘」 버튼이 계속 남는다.
        visibleWeekAnchor = date
        guard hadPendingSelection || !Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return }
        selectedDate = date

        // **이전 날짜의 하루를 새 날짜 라벨 아래 남겨 두지 않는다.** 화면은 `day`가 있으면
        // 스피너를 감추고 끼니 카드를 그대로 열어 주므로(`NavigationLink`), 그 사이 사용자가
        // 다른 날짜의 끼니를 이 날짜 것으로 알고 열어 고치거나 지운다. 아래 두 `await`는
        // HealthKit 권한·조회에 서버 업서트와 하루 조회까지 기다리므로 창이 넓다.
        // (`load()`의 실패 경로가 같은 이유로 이미 `day`를 지운다.)
        day = nil
        isLoading = true

        // **진행 중이던 조회·폴링을 여기서 무효화한다.** 위에서 `day`를 비워도, 아래 두 `await`가
        // 넓어서 그 사이 도착한 이전 날짜의 응답이 `apply(_:)`로 **되채운다** — 방금 세운 방어가
        // 그대로 되돌려지고, 화면은 「새 날짜 라벨 + 옛 날짜 끼니」가 된다.
        //
        // **`load()`가 올리는 것으로는 늦다.** 그때는 이미 `syncActivity()`를 다 기다린 뒤라,
        // 그 대기 구간이 통째로 열려 있다(HealthKit 권한·조회 + 서버 업서트).
        generation += 1

        // **날짜를 바꿀 때도 활동량을 올린다.** 화면 진입의 `.task`에서만 부르면 그 뒤에 고른
        // 날짜들은 소모 칼로리가 영영 비어 있다 — 어제를 열어 봐도 채워지지 않는다.
        //
        // **조회보다 먼저 올린다.** 하루 조회가 서버의 하루 피드백 생성을 걸어 놓는데, 활동량
        // 업서트는 그 캐시를 무효화하지 않는다(비용 방어). 순서가 뒤면 그날 피드백이 소모
        // 칼로리를 영영 빠뜨린 채로 굳는다.
        await syncActivity()
        await load()
    }

    /// 끼니를 저장·수정·삭제한 뒤. 점수·합계·`nutrientLimits`가 전부 달라지고 피드백은 다시 생성에 걸린다.
    func reload() async {
        await load()
    }

    // MARK: - 피드백 폴링

    private func startFeedbackPollingIfNeeded(token: Int) {
        // 끼니가 0건인 날은 서버가 피드백을 만들지 않는다 — 폴링하면 영원히 기다린다.
        guard let day, day.feedback == nil, !day.meals.isEmpty else {
            isFeedbackPending = false
            return
        }
        isFeedbackPending = true

        feedbackTask = Task { [weak self] in
            guard let self else { return }
            await self.pollFeedback(token: token)
        }
    }

    private func pollFeedback(token: Int) async {
        let deadline = ContinuousClock.now + pollTimeout

        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
                let refreshed = try await service.fetchDay(date: selectedDate.dateString)
                guard token == generation else { return }

                if refreshed.feedback != nil {
                    apply(refreshed)
                    isFeedbackPending = false
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                // 폴링 중 실패는 알리지 않는다 — 점수는 이미 보이고 있고 다음 회차가 있다.
                continue
            }
        }

        guard token == generation else { return }
        isFeedbackPending = false
        isFeedbackDelayed = true
    }

    /// 테스트에서 폴링이 끝나기를 기다린다.
    func waitForFeedbackPolling() async {
        await feedbackTask?.value
    }

    /// 서버가 준 하루를 화면에 얹는다. **방금 올린 소모 칼로리는 지킨다** — 첫 진입에서는
    /// 피드백 폴링과 `syncActivity()`가 동시에 도는데, 폴링 요청이 업로드보다 **먼저 나가서
    /// 나중에 돌아오면** 응답을 통째로 대입하는 순간 방금 반영한 값이 `nil`이나 옛 값으로
    /// 되돌아가고 다음 새로고침 전까지 그대로 남는다.
    private func apply(_ loaded: DailyDiet) {
        var merged = loaded
        if let kcal = syncedActivity[loaded.date] {
            merged.activeEnergyKcal = kcal
        }
        day = merged
    }

    // MARK: - 활동 에너지

    /// 진입할 때마다 올린다. **서버가 이 값으로 마감 피드백을 재생성하지 않으므로 비용이 늘지 않는다.**
    /// 목표 칼로리에는 반영되지 않고 표시·피드백 맥락으로만 쓰인다.
    func syncActivity() async {
        // 조회하는 동안 사용자가 날짜를 바꿀 수 있다 — 다시 읽지 않고 시작할 때 값을
        // 붙잡아 둬야 어제 소모량이 오늘 날짜로 올라가는 일이 없다.
        let date = selectedDate
        do {
            // **권한을 먼저 요청한다.** HealthKit은 권한이 없어도 에러를 던지지 않고 빈
            // 결과(0)로 응답한다 — 권한 요청 없이 읽으면 수영 기록을 한 번도 안 연 사용자는
            // 매번 활동 에너지 0을 서버에 올리게 된다.
            try await energyFetcher.requestActiveEnergyAuthorization()
            let kcal = try await energyFetcher.fetchActiveEnergy(on: date)
            // 0은 "진짜 0"과 "권한 없음/조회 실패"를 구분할 수 없다 — 업로드하지 않는 편이
            // 낫다. 잘못된 0이 하루 마감 피드백의 근거로 쓰이는 것보다 안 보이는 게 낫다.
            guard kcal > 0 else { return }
            let rounded = Int(kcal.rounded())
            try await service.upsertActivity(date: date.dateString, activeEnergyKcal: rounded)
            // 이 업로드보다 **먼저 나가서 나중에 돌아오는** 조회 응답이 있을 수 있다. 그런
            // 응답을 얹을 때 이 값을 다시 씌우려고 기억해 둔다(`apply(_:)` 참조).
            syncedActivity[date.dateString] = rounded

            // 방금 올린 값을 화면에도 바로 반영한다 — 안 그러면 이 날 첫 진입에서는 `load()`가
            // 이 값이 오르기 전에 이미 끝난 뒤라 새로고침 전까지 소모 줄이 비어 있다.
            // 그 사이 날짜가 바뀌었으면(현재 보이는 하루가 이 값을 조회한 날과 다르면)
            // 반영하지 않는다.
            guard var current = day, current.date == date.dateString else { return }
            current.activeEnergyKcal = rounded
            day = current
        } catch {
            // HealthKit을 못 쓰는 기기이거나 권한이 없을 수 있다. 하루 화면은 이것 없이도 정상이다.
            return
        }
    }

    // MARK: - 몸무게

    /// 몸무게만 갱신한다. **과거 점수는 바뀌지 않는다** — 서버가 확정 시점의 몸무게·목표를
    /// 끼니에 스냅샷으로 남기고, 하루 점수는 그날 첫 끼니의 스냅샷을 기준으로 계산한다.
    ///
    /// **성공했을 때만 `true`를 돌려준다.** 화면은 이 값으로만 하루 재조회를 걸어야 한다 —
    /// 실패해도 재조회하면 `load()`가 시작하자마자 `errorMessage`를 지워서, 시트는 이미
    /// 닫혔는데 저장이 안 됐다는 사실이 아무 데도 안 남는다.
    @discardableResult
    func updateWeight(_ weightKg: Double) async -> Bool {
        // 저장·재조회가 끝나기 전에 더 새로운 load()가 끼어들 수 있다 — 토큰이 다르면
        // 그 사이 화면이 이미 다른 날짜/상태로 넘어간 것이니 여기서 덮어쓰지 않는다.
        let token = generation
        do {
            try await service.updateWeight(weightKg)
            let refreshedProfile = try await service.fetchProfile()
            guard token == generation else { return false }
            profile = refreshedProfile
            profileEligibility = refreshedProfile == nil ? .missing : .eligible
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard token == generation else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
