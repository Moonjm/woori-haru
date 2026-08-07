import Foundation

/// 아직 서버에 실리지 않은 내 말풍선.
///
/// **낙관적으로 먼저 붙인다** — LLM이 수 초 걸려서, 안 붙이면 내가 뭘 보냈는지 화면에서
/// 사라진다. 실패해도 지우지 않는다(`failed`) — 지우면 사용자가 다시 타이핑해야 한다.
struct PendingChatMessage: Identifiable, Hashable {
    var id = UUID()
    /// 앵커 날짜 — 「어느 날 밥 얘기인가」.
    let date: String
    let text: String
    var failed = false
    /// 왜 못 보냈는지. **전송 실패는 알럿을 띄우지 않으므로**(말풍선이 그 자리를 지킨다)
    /// 이유가 여기 없으면 사용자는 영영 알 수 없고 같은 본문으로 재시도만 반복한다.
    var failureReason: String?
    /// 다시 보낼 만한 실패인가. **실패한 순간에 정한다.**
    ///
    /// 지금 앵커 날짜로 판단하면 안 된다 — 8월 1일이 빈 날이라 거절당한 뒤 `✕`로 앵커를
    /// 오늘로 되돌리면 오늘 기준으로 잠금이 풀려 재시도가 열리고, 그 재시도는 여전히
    /// **8월 1일로** 나가 같은 400을 맞는다.
    var isRetryable = true
}

/// 스트림에 그려지는 한 줄. **뷰가 아니라 뷰모델이 조립한다** — 구분선을 어디서 끊을지,
/// 배지를 붙일지가 뷰에 있으면 테스트가 못 닿는다.
enum ChatRow: Identifiable {
    /// `createdAt` 기준 "2026-08-06".
    case dateSeparator(day: String)
    case message(ChatMessage, badge: String?)
    case pending(PendingChatMessage, badge: String?)
    /// 답을 기다리는 코치 자리.
    case awaitingReply

    var id: String {
        switch self {
        case .dateSeparator(let day): "separator-\(day)"
        case .message(let message, _): "message-\(message.id)"
        case .pending(let pending, _): "pending-\(pending.id.uuidString)"
        case .awaitingReply: "awaiting-reply"
        }
    }
}

/// 코치 타임라인 — 페이징·전송·낙관적 말풍선·추천 질문 칩·빈 날 잠금.
///
/// **날짜가 두 축이다.** 날짜 구분선은 `createdAt`(언제 물었나), 말풍선 배지는 `date`(어느 날
/// 밥 얘기인가)를 쓴다. 8월 6일에 8월 1일을 물으면 그 말풍선은 8월 6일 구분선 아래에 앉고
/// `08-01` 배지가 붙는다.
@MainActor
@Observable
final class DietChatViewModel {
    /// 오래된 것이 먼저 — 화면에 그리는 순서다. 서버는 최신부터 주므로 받아서 뒤집는다.
    private(set) var messages: [ChatMessage] = []
    private(set) var pending: PendingChatMessage?
    /// 플로팅 버튼을 누른 순간의 날짜. 질문이 어느 날에 대한 것인지를 정한다.
    private(set) var anchorDate: Date
    /// null이면 더 없다. 그때 무한 스크롤을 멈춘다.
    private(set) var nextCursor: Int?
    private(set) var hasLoaded = false
    /// 첫 장 조회 자체가 실패했는지. **알럿을 닫아도 남아 있어야 한다** — 안 그러면 조회 실패가
    /// 「쌓인 것이 없음」과 똑같은 빈 화면으로 보인다(`DietHomeView.failureState`와 같은 이유).
    private(set) var loadFailed = false
    private(set) var isLoadingPage = false
    /// 다음 장 조회가 실패했다. **스피너를 계속 돌리지 않는다** — 실패한 뒤에도 돌면 영영
    /// 불러오는 중인 것처럼 보인다. 그 자리에 다시 시도할 길을 둔다.
    private(set) var nextPageFailed = false
    private(set) var isSending = false
    /// 페이지 조회 실패만 담는다. **전송 실패는 여기 오지 않는다** — 말풍선에 「다시 시도」가
    /// 붙으므로 알럿까지 띄우면 같은 사실을 두 번 말한다.
    var errorMessage: String?

    /// 날짜별 하루. 칩 조립과 입력창 잠금이 앵커 날짜의 것을 본다.
    ///
    /// **들어올 때 받은 날짜는 화면이 넘겨준다**(`DietHomeView`가 이미 갖고 있다) — 앵커를
    /// 오늘로 되돌렸을 때만 새로 조회한다.
    private var daysByDate: [String: DailyDiet] = [:]

    /// 하루를 받고 있는 날짜들. **전역 플래그 하나로는 안 된다** — 진입 조회와 「오늘로
    /// 돌아가기」가 겹치면 먼저 끝난 쪽이 플래그를 내려, 지금 앵커의 하루는 아직 오는 중인데
    /// 입력창이 열린다.
    private var loadingDates: Set<String> = []

    /// 서버가 질문을 거절한 날짜. **하루 조회와 별개로 든다** — 이유를 확인하려는 재조회까지
    /// 실패하면 `daysByDate`로는 판단할 수 없어 잠금이 풀리고, 같은 400을 다시 만든다.
    private var rejectedDates: Set<String> = []

    /// 낙관적 말풍선이 스트림에 들어갈 때 쓰는 id. **음수다** — 서버 id와 겹치지 않기만 하면
    /// 되고, 화면을 다시 열면 서버가 준 진짜 행으로 대체된다.
    private var localIdSeed = 0

    private let service: any DietServing

    init(
        service: any DietServing = DietService(),
        anchorDate: Date = Date(),
        day: DailyDiet? = nil
    ) {
        self.service = service
        self.anchorDate = anchorDate
        if let day {
            daysByDate[day.date] = day
        }
    }

    // MARK: - 앵커

    var anchorDateString: String { anchorDate.dateString }

    var isAnchorToday: Bool { Calendar.current.isDateInToday(anchorDate) }

    /// 「8월 1일에 대해 묻는 중」. **오늘이면 nil이다** — 오늘이 기본값이라 늘 띄우면 자리만 먹는다.
    ///
    /// 보고 있던 날짜와 스트림 맨 아래가 다르기 때문에 필요하다 — 8월 1일을 보다가 열면
    /// 맨 아래는 최근 대화이고 8월 1일 카드는 저 위에 있어, 지금 어느 날을 묻는 중인지 알 수 없다.
    var anchorChipText: String? {
        guard !isAnchorToday else { return nil }
        return "\(anchorDate.monthDayText)에 대해 묻는 중"
    }

    /// 앵커 칩의 `✕`. **오늘로 돌아간다** — 그때 칩은 사라진다.
    func resetAnchorToToday() async {
        anchorDate = Date()
        await loadDayIfNeeded(anchorDateString)
    }

    private var anchorDay: DailyDiet? { daysByDate[anchorDateString] }

    // MARK: - 잠금·칩

    /// 앵커 날짜에 기록이 있는가. **모르면 nil이다** — 「모른다」와 「없다」를 같은 값으로
    /// 만들지 않는다.
    private var anchorHasMeals: Bool? {
        anchorDay.map { !$0.meals.isEmpty }
    }

    /// 그날 기록이 없으면 서버가 400으로 거절한다. 플로팅 버튼이 늘 떠 있어서 기록 전에
    /// 누르는 일이 흔한데, 그때마다 오류 알럿을 띄우면 곤란하다.
    ///
    /// **받는 중에는 잠근다** — 그 창에서 보내면 빈 날일 때 그대로 400을 맞는다. 앵커를
    /// 오늘로 되돌린 직후가 특히 그렇다.
    ///
    /// **못 받았으면 잠그지 않는다.** 모르는 것을 「없다」로 단정하면 하루 조회가 한 번
    /// 실패한 날에는 기록이 있어도 입력창이 영영 막힌다(`DietDayViewModel`이 프로필 조회
    /// 실패에서 같은 판단을 한다). 대신 그 상태로 보냈다가 거절당하면 그때 하루를 다시 받아
    /// 잠근다(`deliver`) — 그래서 같은 400이 두 번 나지 않는다.
    var isInputLocked: Bool {
        if isLoadingDay { return true }
        if rejectedDates.contains(anchorDateString) { return true }
        return anchorHasMeals == false
    }

    /// 앵커 날짜의 하루를 받는 중인가. **날짜별로 본다** — 다른 날짜의 조회가 먼저 끝나도
    /// 여기가 풀리면 안 된다.
    var isLoadingDay: Bool { loadingDates.contains(anchorDateString) }

    /// **받는 중에는 띄우지 않는다** — 아직 모르는 것을 「기록이 없다」고 말하면 거짓말이 된다.
    /// 거절당했지만 이유를 확인하지 못한 날은 **이유를 지어내지 않는다.**
    var lockedNotice: String? {
        if anchorHasMeals == false { return "이 날은 기록이 없어서 물어볼 것이 없어요" }
        if rejectedDates.contains(anchorDateString) { return "이 날은 지금 물어볼 수 없어요" }
        return nil
    }

    // MARK: - 스트림

    var hasMore: Bool { nextCursor != nil }

    /// 구분선·배지·낙관적 말풍선까지 얹은 최종 목록.
    var rows: [ChatRow] {
        var result: [ChatRow] = []
        var currentDay: String?

        for message in messages where Self.isRenderable(message) {
            let day = message.createdAtDay
            if day != currentDay {
                result.append(.dateSeparator(day: day))
                currentDay = day
            }
            result.append(.message(message, badge: Self.badge(for: message.date, under: day)))
        }

        if let pending {
            let day = Date().dateString
            if day != currentDay {
                result.append(.dateSeparator(day: day))
                currentDay = day
            }
            result.append(.pending(pending, badge: Self.badge(for: pending.date, under: day)))
            // 실패한 말풍선 아래에는 기다리는 자리를 두지 않는다 — 오지 않을 답이다.
            if !pending.failed {
                result.append(.awaitingReply)
            }
        }

        return result
    }

    /// **둘이 다를 때만 붙인다.** 같은 날 얘기를 같은 날 하는 경우가 대부분이라 늘 붙이면
    /// 노이즈가 되고, 안 붙이면 과거 날짜 질문이 정체 없이 앉는다.
    private static func badge(for date: String, under separatorDay: String) -> String? {
        guard date != separatorDay else { return nil }
        // "2026-08-01" → "08-01"
        return String(date.suffix(5))
    }

    /// 모르는 `type`은 건너뛴다 — 서버가 카드를 늘려도 페이지 전체가 날아가지 않는다.
    /// 알맹이가 없는 카드 행도 같이 건너뛴다(서버가 매달린 참조를 거르지 못한 경우) —
    /// 빈 카드는 서버가 무언가를 빠뜨린 것처럼 읽힌다.
    private static func isRenderable(_ message: ChatMessage) -> Bool {
        switch message.type {
        case .text: message.content != nil
        case .mealCard: message.meal != nil
        case .daySummary: message.day != nil
        case .unknown: false
        }
    }

    // MARK: - 페이징

    func load() async {
        await loadDayIfNeeded(anchorDateString)
        await loadFirstPage()
    }

    private func loadFirstPage() async {
        guard !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        errorMessage = nil
        loadFailed = false

        do {
            // **첫 장은 커서 없이 부른다.**
            let page = try await service.fetchChatPage(before: nil, size: ChatPolicy.pageSize)
            messages = Array(page.messages.reversed())
            nextCursor = page.nextCursor
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            loadFailed = true
        }
    }

    /// 조회에 실패했을 때의 「다시 시도」.
    func reload() async {
        await loadFirstPage()
    }

    /// 아직 쌓인 것이 없다. **조회에 성공했을 때만 참이다** — 실패했거나 아직 안 끝났을 때
    /// 이 문구를 띄우면 「없음」과 「못 받음」이 뒤섞여 보인다.
    ///
    /// 서버가 배포 전의 끼니·총평에 대한 카드를 **소급해 만들지 않아서**, 배포 직후에는
    /// 이 상태가 정상이다.
    var isEmpty: Bool { hasLoaded && !loadFailed && rows.isEmpty }

    /// 맨 위에 닿았을 때. **`nextCursor`가 nil이면 더 부르지 않고**, **로딩 중에도 부르지
    /// 않는다** — 스크롤이 위쪽에 머무는 동안 `onAppear`가 여러 번 뜬다.
    func loadNextPage() async {
        guard !isLoadingPage, let cursor = nextCursor else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        nextPageFailed = false

        do {
            let page = try await service.fetchChatPage(before: cursor, size: ChatPolicy.pageSize)
            messages.insert(contentsOf: Array(page.messages.reversed()), at: 0)
            nextCursor = page.nextCursor
        } catch is CancellationError {
            return
        } catch {
            // **알럿을 띄우지 않는다.** 스크롤하다 실패할 때마다 알럿이 튀어나오면 읽는 것을
            // 방해한다 — 맨 위의 「다시 시도」가 같은 사실을 조용히 말한다.
            nextPageFailed = true
        }
    }

    private func loadDayIfNeeded(_ date: String) async {
        guard daysByDate[date] == nil else { return }
        await reloadDay(date)
    }

    /// **이미 들고 있어도 다시 받는다** — 화면이 넘겨준 하루가 낡아서 거절당했을 수 있다.
    ///
    /// **실패해도 들고 있던 것을 버리지 않는다.** 먼저 지우고 받으면, 받기까지 실패했을 때
    /// 알고 있던 것마저 잃어 잠금이 풀린다. 취소도 이 자리로 떨어지는데 같은 처리로 충분하다 —
    /// 화면이 사라지며 끊긴 것이라 다음 진입이 새 뷰모델로 다시 받는다.
    private func reloadDay(_ date: String) async {
        loadingDates.insert(date)
        defer { loadingDates.remove(date) }
        do {
            daysByDate[date] = try await service.fetchDay(date: date)
        } catch {
            // 하루를 못 받아도 스트림은 그대로 읽을 수 있다. **여기서 잠그지 않는다** —
            // 모르는 것을 「없다」로 단정하면 기록이 있는 날에도 막힌다(`isInputLocked`).
        }
    }

    // MARK: - 전송

    /// **전송 중에는 다시 못 보낸다** — `MealConfirmViewModel.isSaving`과 같은 가드다.
    var canSend: Bool { !isSending && !isInputLocked }

    /// 이 문장을 지금 보낼 수 있는가. **길이까지 여기서 본다** — 서버가 거절할 본문을
    /// 내보내면 「보내지 못했어요」만 남고 재시도는 같은 본문으로 영원히 실패한다
    /// (`ChatPolicy.maxMessageLength`).
    func isSendable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return canSend && !trimmed.isEmpty && trimmed.utf16.count <= ChatPolicy.maxMessageLength
    }

    /// 상한을 넘었을 때만 준다. **잠긴 이유를 적어 준다** — 안 알려 주면 눌리지 않는 버튼만
    /// 남는다(`MealItemEditView.manualHint`가 같은 자리를 메운다).
    func lengthNotice(for text: String) -> String? {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        guard count > ChatPolicy.maxMessageLength else { return nil }
        return "\(ChatPolicy.maxMessageLength)자까지 보낼 수 있어요 (지금 \(count)자)"
    }

    func send(_ text: String) async {
        guard isSendable(text) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await deliver(PendingChatMessage(date: anchorDateString, text: trimmed))
    }

    /// 「다시 시도」를 띄울지. **말풍선 자신의 판정을 본다** — 지금 앵커 날짜의 잠금을 보면,
    /// 8월 1일이 거절당한 뒤 `✕`로 오늘로 돌아왔을 때 재시도가 열리고 그 재시도는 여전히
    /// 8월 1일로 나가 같은 400을 맞는다.
    var canRetry: Bool {
        guard let pending, pending.failed else { return false }
        return pending.isRetryable && !isSending
    }

    /// **서버는 실패하면 아무것도 저장하지 않으므로**(질문·답을 한 트랜잭션에 쓴다) 같은
    /// 문장을 다시 보내도 중복이 남지 않는다.
    func retry() async {
        guard canRetry, let pending else { return }
        await deliver(PendingChatMessage(date: pending.date, text: pending.text))
    }

    private func deliver(_ message: PendingChatMessage) async {
        pending = message
        isSending = true
        defer { isSending = false }

        do {
            let answer = try await service.askChat(date: message.date, message: message.text)
            // 질문 행도 서버가 저장하지만 응답에는 답만 온다 — 이미 띄운 말풍선을 그대로
            // 스트림에 옮긴다.
            messages.append(localMessage(message))
            messages.append(answer)
            pending = nil
        } catch is CancellationError {
            pending = nil
        } catch {
            // **말풍선을 남긴다.** 지우면 사용자가 다시 타이핑해야 한다.
            pending?.failed = true

            if error.dietErrorCode == .invalidRequest {
                await handleDateRejection(message.date)
            } else {
                pending?.failureReason = Self.failureReason(for: error)
            }
        }
    }

    /// 서버가 이 날짜의 질문을 거절했다.
    ///
    /// **이유를 단정하지 않는다.** `INVALID_REQUEST`는 범용 코드라, 오늘은 「그날 기록된
    /// 끼니가 없습니다」 하나뿐이지만 언제든 다른 검증 실패가 같은 코드로 올 수 있다. 그날
    /// 하루를 다시 받아 **정말 빈 날일 때만** 그렇게 안내한다.
    ///
    /// **어느 쪽이든 그 날짜를 잠근다.** 같은 본문·같은 날짜로 다시 보내도 같은 거절이다.
    private func handleDateRejection(_ date: String) async {
        await reloadDay(date)
        rejectedDates.insert(date)
        pending?.isRetryable = false
        if daysByDate[date]?.meals.isEmpty == true {
            pending?.failureReason = "이 날은 기록이 없어서 물어볼 수 없어요"
        }
        // 확인하지 못했으면 이유를 비워 둔다 — 말풍선이 「보내지 못했어요」만 단다.
    }

    /// 「보내지 못했어요」만으로는 왜인지 알 수 없다 — 서버가 이유를 밝힌 경우에는 그것을 쓴다.
    /// 모르는 오류는 nil이라 말풍선이 기본 문구만 단다.
    private static func failureReason(for error: any Error) -> String? {
        switch error.dietErrorCode {
        case .chatFailed: "답을 만들지 못했어요. 잠시 후 다시 시도해 주세요"
        case .llmUnavailable: "코치가 아직 준비되지 않았어요"
        default: nil
        }
    }

    private func localMessage(_ message: PendingChatMessage) -> ChatMessage {
        localIdSeed -= 1
        return ChatMessage(
            id: localIdSeed,
            type: .text,
            date: message.date,
            role: .user,
            createdAt: Self.localTimestampFormatter.string(from: Date()),
            content: message.text,
            meal: nil,
            day: nil
        )
    }

    /// 서버 `LocalDateTime`과 같은 모양으로 찍는다 — 구분선이 `createdAt` 앞 10자를 본다.
    private static let localTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
