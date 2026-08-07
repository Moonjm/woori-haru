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
    private(set) var isSending = false
    /// 페이지 조회 실패만 담는다. **전송 실패는 여기 오지 않는다** — 말풍선에 「다시 시도」가
    /// 붙으므로 알럿까지 띄우면 같은 사실을 두 번 말한다.
    var errorMessage: String?

    /// 날짜별 하루. 칩 조립과 입력창 잠금이 앵커 날짜의 것을 본다.
    ///
    /// **들어올 때 받은 날짜는 화면이 넘겨준다**(`DietHomeView`가 이미 갖고 있다) — 앵커를
    /// 오늘로 되돌렸을 때만 새로 조회한다.
    private var daysByDate: [String: DailyDiet] = [:]

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

    /// 그날 기록이 없으면 서버가 400으로 거절한다. 플로팅 버튼이 늘 떠 있어서 기록 전에
    /// 누르는 일이 흔한데, 그때마다 오류 알럿을 띄우면 곤란하다.
    ///
    /// **하루를 아직 못 받았으면 잠그지 않는다.** 모르는 것을 「없다」로 단정하면 기록이 있는
    /// 날에도 입력창이 막힌다(`DietDayViewModel`이 프로필 조회 실패에서 같은 판단을 한다).
    var isInputLocked: Bool {
        guard let anchorDay else { return false }
        return anchorDay.meals.isEmpty
    }

    var lockedNotice: String? {
        isInputLocked ? "이 날은 기록이 없어서 물어볼 것이 없어요" : nil
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

        do {
            let page = try await service.fetchChatPage(before: cursor, size: ChatPolicy.pageSize)
            messages.insert(contentsOf: Array(page.messages.reversed()), at: 0)
            nextCursor = page.nextCursor
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDayIfNeeded(_ date: String) async {
        guard daysByDate[date] == nil else { return }
        do {
            daysByDate[date] = try await service.fetchDay(date: date)
        } catch {
            // 하루를 못 받아도 스트림은 그대로 읽을 수 있다. 칩이 안 뜨고 잠금 판단만 보류된다.
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

    /// 「다시 시도」. **서버는 실패하면 아무것도 저장하지 않으므로**(질문·답을 한 트랜잭션에
    /// 쓴다) 같은 문장을 다시 보내도 중복이 남지 않는다.
    func retry() async {
        guard let pending, pending.failed, !isSending else { return }
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
