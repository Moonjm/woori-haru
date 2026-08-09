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
    /// 쓴 시각. **아직 못 보낸 동안의 날짜 구분선이 이 값을 쓴다** — 서버에 실리고 나면
    /// 서버가 저장한 시각으로 바뀐다(`localMessage(_:savedAt:)`).
    ///
    /// **자리를 정하는 데는 쓰지 않는다** — 이 값은 기기 시계이고 서버 `createdAt`은 서버
    /// 시계라, 시간대나 오차가 있으면 순서가 뒤집힌다.
    let createdAt: String
    /// 쓸 때까지 본 **서버 메시지 id의 최댓값**. 그때 스트림이 비어 있었으면 nil이다.
    ///
    /// **자리를 정하는 유일한 값이다.** 인덱스를 따로 들고 다니면 스트림이 바뀌는 자리마다
    /// (전송 성공·앞에 붙이기·통째 교체) 그 값을 손으로 맞춰 줘야 하고, 한 군데만 빠뜨리면
    /// 순서가 조용히 틀어진다 — 그리는 시점에 이 값 하나로 계산한다.
    ///
    /// 서버 id는 단조 증가라 시계가 개입하지 않는다. **배열 마지막 id가 아니라 최댓값이다** —
    /// 실패했던 질문을 나중에 재시도해 성공하면 그 답(더 큰 id)이 배열 중간에 꽂힌다.
    var anchorMessageId: Int?
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
    /// `createdAt` 기준 "2026-08-06". `ordinal`은 **id를 유일하게 만들려고만** 있다 —
    /// 날짜만으로 id를 만들면 같은 날짜가 스트림에 두 번 끼는 순간 `ForEach`의 id가 겹치고,
    /// 그건 SwiftUI에서 정의되지 않은 렌더링이다(행 누락·런타임 경고). 화면은 `day`만 쓴다.
    case dateSeparator(day: String, ordinal: Int)
    case message(ChatMessage, badge: String?)
    case pending(PendingChatMessage, badge: String?)
    /// 답을 기다리는 코치 자리.
    case awaitingReply

    var id: String {
        switch self {
        case .dateSeparator(let day, let ordinal): "separator-\(ordinal)-\(day)"
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
    /// 아직 서버에 실리지 않은 말풍선들. **실패한 것이 쌓인다** — 단수로 들면 다음 전송이
    /// 못 보낸 문장을 덮어써서, 「지우면 사용자가 다시 타이핑해야 한다」로 막으려던 상태로
    /// 그대로 돌아간다. 보내는 중인 것은 언제나 최대 하나다(`Delivery` 예약).
    private(set) var pendingMessages: [PendingChatMessage] = []
    /// 플로팅 버튼을 누른 순간의 날짜. 질문이 어느 날에 대한 것인지를 정한다.
    private(set) var anchorDate: Date
    /// null이면 더 없다. 그때 무한 스크롤을 멈춘다.
    private(set) var nextCursor: Int?
    private(set) var hasLoaded = false
    /// 첫 장 조회 자체가 실패했는지. **알럿을 닫아도 남아 있어야 한다** — 안 그러면 조회 실패가
    /// 「쌓인 것이 없음」과 똑같은 빈 화면으로 보인다(`DietHomeView.failureState`와 같은 이유).
    private(set) var loadFailed = false
    private(set) var isLoadingPage = false
    /// 첫 장을 받는 중 — 그 응답이 `messages`를 통째로 갈아끼운다.
    private(set) var isReplacingStream = false
    /// 다음 장 조회가 실패했다. **스피너를 계속 돌리지 않는다** — 실패한 뒤에도 돌면 영영
    /// 불러오는 중인 것처럼 보인다. 그 자리에 다시 시도할 길을 둔다.
    private(set) var nextPageFailed = false
    /// 전송 소유권. **접수하는 순간 동기적으로 잡고, 실제로 보낼 때 한 번만 넘어간다.**
    ///
    /// 두 단계인 이유는 「예약됐다」와 「지금 나가는 중이다」가 다른 상태이기 때문이다.
    /// 하나로 두면 같은 말풍선으로 두 번 들어온 전송이 같은 검사를 통과해 **유료 POST가
    /// 두 번 나가고**, 먼저 끝난 쪽이 나머지가 진행 중인데도 잠금을 푼다.
    private enum Delivery {
        case reserved(UUID)
        case delivering(UUID)

        var id: UUID {
            switch self {
            case .reserved(let id), .delivering(let id): id
            }
        }
    }

    private var delivery: Delivery?

    /// 전송 중이거나 전송이 예약돼 있다. 입력창·재시도·첫 장 교체가 모두 이 값을 본다.
    var isSending: Bool { delivery != nil }

    /// **뷰모델이 전송 작업을 직접 든다.** 예약 id를 밖으로 내보내면 그 짝(반드시 실행)을
    /// 호출 규약으로만 지켜야 하고, 한 번 어긋나면 예약이 안 풀려 입력창이 영영 잠긴다.
    private var deliveryTask: Task<Void, Never>?

    /// 테스트에서 전송이 끝나기를 기다린다(`DietDayViewModel.waitForFeedbackPolling`과 같다).
    func waitForDelivery() async {
        await deliveryTask?.value
    }
    /// 페이지 조회 실패만 담는다. **전송 실패는 여기 오지 않는다** — 말풍선에 「다시 시도」가
    /// 붙으므로 알럿까지 띄우면 같은 사실을 두 번 말한다.
    var errorMessage: String?

    /// 날짜별 하루. 칩 조립과 입력창 잠금이 앵커 날짜의 것을 본다.
    ///
    /// **들어올 때 받은 날짜는 화면이 넘겨준다**(`DietHomeView`가 이미 갖고 있다) — 앵커를
    /// 오늘로 되돌렸을 때만 새로 조회한다.
    private var daysByDate: [String: DailyDiet] = [:]

    /// 하루를 받고 있는 날짜별 요청 수. **전역 플래그 하나로는 안 된다** — 진입 조회와
    /// 「오늘로 돌아가기」가 겹치면 먼저 끝난 쪽이 플래그를 내려, 지금 앵커의 하루는 아직
    /// 오는 중인데 입력창이 열린다.
    ///
    /// **`Set`이 아니라 카운터다.** 같은 날짜로 두 번 겹치면 먼저 끝난 쪽이 원소를 지워
    /// 같은 구멍이 다시 생긴다. 지금은 그렇게 겹치는 경로가 없지만, 여기를 손실 없는
    /// 셈으로 두면 나중에 생겨도 조용히 새지 않는다.
    private var dayLoadCounts: [String: Int] = [:]

    /// 날짜별 조회 세대. 늦게 돌아온 옛 응답이 최신 하루를 덮어쓰지 않게 한다
    /// (`DietDayViewModel.generation`과 같은 장치다).
    private var dayGenerations: [String: Int] = [:]

    /// 서버가 질문을 거절한 날짜. **하루 조회와 별개로 든다** — 이유를 확인하려는 재조회까지
    /// 실패하면 `daysByDate`로는 판단할 수 없어 잠금이 풀리고, 같은 400을 다시 만든다.
    private var rejectedDates: Set<String> = []

    /// 낙관적 말풍선이 스트림에 들어갈 때 쓰는 id. **음수다** — 서버 id와 겹치지 않기만 하면
    /// 되고, 화면을 다시 열면 서버가 준 진짜 행으로 대체된다.
    private var localIdSeed = 0

    /// 지금까지 본 서버 메시지 id의 최댓값. 새 말풍선의 기준점이 된다.
    ///
    /// **배열 마지막 id가 아니다.** 실패했던 질문을 나중에 재시도해 성공하면 그 답(더 큰 id)이
    /// 배열 중간에 꽂히므로, 마지막을 기준점으로 삼으면 다음 질문이 이미 본 것보다 앞에 앉는다.
    private var greatestSeenServerId: Int?

    private func noteSeen(_ items: [ChatMessage]) {
        for item in items where item.id > 0 {
            greatestSeenServerId = max(greatestSeenServerId ?? item.id, item.id)
        }
    }

    private let service: any DietServing

    /// 「지금」을 어디서 읽는가. **주입한다** — 못 보낸 말풍선이 쓴 시각으로 구분선 아래
    /// 앉는지는 벽시계를 고정하지 않으면 확인할 수 없다(23:59에 쓰고 자정을 넘기는 경우).
    private let now: () -> Date

    init(
        service: any DietServing = DietService(),
        anchorDate: Date = Date(),
        day: DailyDiet? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.service = service
        self.now = now
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
    var isLoadingDay: Bool { (dayLoadCounts[anchorDateString] ?? 0) > 0 }

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
        var separatorCount = 0

        func appendSeparator(_ day: String) {
            result.append(.dateSeparator(day: day, ordinal: separatorCount))
            separatorCount += 1
            currentDay = day
        }

        // **자리를 한 번만 계산한다.** 메시지마다 말풍선 전부를 훑으면 렌더 한 번이
        // 스트림 길이의 제곱으로 늘어난다.
        var pendingByPosition: [Int: [PendingChatMessage]] = [:]
        for message in pendingMessages {
            pendingByPosition[position(of: message), default: []].append(message)
        }

        /// 못 보낸 말풍선을 **쓴 자리에** 끼워 넣는다.
        func appendPending(at index: Int) {
            for message in pendingByPosition[index] ?? [] {
                // **쓴 시각으로 가른다.** 벽시계를 읽으면 23:59에 쓴 말풍선이 자정을 넘기며
                // 구분선만 다음 날로 옮겨 가고, 재시도해 성공하면 그 행이 `createdAt`(어제)로
                // 실려 다시 어제 구분선 아래로 돌아간다. 같은 이유로 `rows`가 시계에
                // 의존하지 않게 되어 테스트가 닿는다.
                let day = String(message.createdAt.prefix(10))
                if day != currentDay {
                    appendSeparator(day)
                }
                result.append(.pending(message, badge: Self.badge(for: message.date, under: day)))
                // 실패한 말풍선 아래에는 기다리는 자리를 두지 않는다 — 오지 않을 답이다.
                if !message.failed {
                    result.append(.awaitingReply)
                }
            }
        }

        for (index, message) in messages.enumerated() {
            appendPending(at: index)
            guard Self.isRenderable(message) else { continue }
            let day = message.createdAtDay
            if day != currentDay {
                appendSeparator(day)
            }
            result.append(.message(message, badge: Self.badge(for: message.date, under: day)))
        }
        appendPending(at: messages.count)

        return result
    }

    /// 위로 스크롤해 이전 장을 붙인 뒤 되돌아올 자리.
    ///
    /// **구분선이 아니라 메시지여야 한다.** 구분선 id는 날짜뿐이라(`ChatRow.id`), 앞에
    /// 붙은 장의 마지막 날짜가 지금 첫 줄과 같으면 **같은 id가 스트림 맨 위로 옮겨 간다** —
    /// 「읽던 자리로 되돌린다」가 「최상단으로 튄다」가 되고, 그러면 위쪽 로더가 다시 보여
    /// 다음 장을 또 부른다. 한 번 위로 올리면 대화 전량을 연쇄로 내려받는다.
    var firstMessageRowId: String? {
        rows.first { row in
            guard case .message = row else { return false }
            return true
        }?.id
    }

    /// 못 보낸 말풍선이 앉을 자리(`messages`의 인덱스).
    ///
    /// **그릴 때 계산한다.** 기준점 이하인 마지막 서버 행 바로 뒤다. 기준점이 없거나
    /// (쓸 때 스트림이 비어 있었다) 이 화면에 없으면(그만큼 새 메시지가 쌓여 밀려났으면)
    /// 실려 온 것이 전부 나중 것이라는 뜻이라 맨 위다.
    ///
    /// **로컬 행(음수 id)은 건너뛴다** — 서버 id끼리만 견줄 수 있다.
    private func position(of message: PendingChatMessage) -> Int {
        guard let anchorId = message.anchorMessageId,
              let index = messages.lastIndex(where: { $0.id > 0 && $0.id <= anchorId }) else {
            return 0
        }
        return index + 1
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
        // **취소됐으면 다음 조회로 넘어가지 않는다.** `reloadDay`는 취소도 「못 받았다」로
        // 삼키므로(그게 맞다) 여기서 따로 보지 않으면 화면이 사라진 뒤에도 첫 장을 부른다.
        guard !Task.isCancelled else { return }
        await loadFirstPage()
    }

    private func loadFirstPage() async {
        // **전송 중에는 갈아끼우지 않는다.** 반대편도 막아야 배타가 성립한다 — 전송이
        // 성공해 `messages`에 두 행이 붙은 직후에 이 응답이 도착하면 그것을 지운다.
        // 전송이 끝난 뒤 다시 부르면 된다(화면의 「다시 시도」가 그대로 살아 있다).
        guard !isLoadingPage, !isSending else { return }
        isLoadingPage = true
        // **이 조회는 스트림을 통째로 갈아끼운다.** 그 사이 전송이 성공하면 뒤이어 도착한
        // 응답이 방금 나눈 대화를 지운다 — 다음 장 조회(`loadNextPage`)는 위에 덧붙이기만
        // 하므로 이 구분이 필요하다.
        isReplacingStream = true
        defer {
            isLoadingPage = false
            isReplacingStream = false
        }
        errorMessage = nil
        loadFailed = false
        // **다음 장 실패도 함께 내린다.** 스트림을 통째로 갈아끼우면 그 커서로 실패했다는
        // 사실도 같이 사라진다 — 안 내리면 맨 위에 「다시 시도」가 남아 자동 페이징이 꺼진 채
        // 손으로 눌러야만 도는 상태가 된다.
        nextPageFailed = false

        do {
            // **첫 장은 커서 없이 부른다.**
            let page = try await service.fetchChatPage(before: nil, size: ChatPolicy.pageSize)
            // **못 보낸 말풍선의 자리를 손보지 않는다.** 자리는 기준점에서 그릴 때
            // 계산되므로(`position(of:)`) 스트림이 통째로 갈려도 저절로 따라온다.
            messages = Array(page.messages.reversed())
            noteSeen(messages)
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
            // 여기서도 말풍선의 자리를 손보지 않는다 — 앞에 몇 건이 붙든 기준점은 그대로다.
            let older = Array(page.messages.reversed())
            messages.insert(contentsOf: older, at: 0)
            noteSeen(older)
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
    /// 하루를 다시 받은 결과.
    ///
    /// **「못 받았다」와 「밀렸다」를 구분한다.** 둘 다 nil로 뭉뚱그리면, 더 새로운 조회가
    /// 이미 잠금을 푼 뒤에 늦게 돌아온 옛 요청이 「확인 실패」로 읽혀 그것을 다시 잠근다.
    private enum DayLoadResult {
        case fresh(DailyDiet)
        case failed
        /// 더 새로운 조회가 있었다. **아무 상태도 건드리지 않는다** — 그쪽이 이미 세웠다.
        case stale
    }

    /// **방금 받아 온 것만 돌려준다.** 부르는 쪽이 캐시를 새 결과로 착각하면, 낡은 「끼니
    /// 있음」 때문에 잠금이 풀려 같은 400을 반복하거나 낡은 「빈 날」로 엉뚱한 이유를 띄운다.
    @discardableResult
    private func reloadDay(_ date: String) async -> DayLoadResult {
        dayLoadCounts[date, default: 0] += 1
        // **날짜별 세대 표식.** 같은 날짜로 두 번 겹치면 먼저 나가고 늦게 돌아온 응답이
        // 최신 하루를 덮어쓴다 — 토큰이 다르면 그 결과를 버린다.
        let token = (dayGenerations[date] ?? 0) + 1
        dayGenerations[date] = token
        defer {
            let remaining = (dayLoadCounts[date] ?? 1) - 1
            dayLoadCounts[date] = remaining > 0 ? remaining : nil
        }
        do {
            let day = try await service.fetchDay(date: date)
            guard dayGenerations[date] == token else { return .stale }
            daysByDate[date] = day
            // **거절 잠금을 푸는 유일한 길이다.** 그 사이 끼니를 기록했으면 다시 물을 수 있다.
            if !day.meals.isEmpty {
                rejectedDates.remove(date)
            }
            return .fresh(day)
        } catch {
            // **실패에도 세대를 본다.** 더 새로운 조회가 이미 「끼니 있음」으로 잠금을 푼
            // 뒤인데 늦게 돌아온 옛 요청이 `.failed`로 읽히면 그 날짜를 다시 잠근다.
            guard dayGenerations[date] == token else { return .stale }
            // 하루를 못 받아도 스트림은 그대로 읽을 수 있다. **여기서 잠그지 않는다** —
            // 모르는 것을 「없다」로 단정하면 기록이 있는 날에도 막힌다(`isInputLocked`).
            return .failed
        }
    }

    // MARK: - 전송

    /// **전송 중에는 다시 못 보낸다** — `MealConfirmViewModel.isSaving`과 같은 가드다.
    ///
    /// **첫 장을 받는 동안에도 못 보낸다.** 먼저 보내 성공하면 뒤늦게 도착한 첫 장 응답이
    /// `messages`를 통째로 갈아끼워 **방금 나눈 대화가 화면에서 사라진다.** 반대 순서라도
    /// 자리가 틀린다 — 스트림이 비어 있을 때 만든 말풍선은 `streamIndex`가 0이라 과거 기록
    /// 전체보다 위에 앉는다.
    ///
    /// **`hasLoaded`만으로는 부족하다** — 한 번 받은 뒤 다시 받는 동안에는 그 값이 계속
    /// 참이라 같은 경합이 그대로 열린다. 첫 장이 실패하면 화면이 「다시 시도」를 띄우고
    /// 있으므로 그쪽이 먼저다.
    var canSend: Bool { hasLoaded && !isReplacingStream && !isSending && !isInputLocked }

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

    /// 질문을 **접수한다.** 받아들였으면 `true` — 화면은 그때만 입력창을 비운다.
    ///
    /// **판정과 접수가 한 번에 끝난다(중간에 `await`가 없다).** 화면이 이 결과를 보고
    /// 입력창을 비우기 때문이다 — 먼저 비우고 나중에 보내면, 그 사이 첫 장 교체가 시작돼
    /// 전송이 거절될 때 사용자가 쓴 문장만 사라진다.
    @discardableResult
    func accept(_ text: String) -> Bool {
        guard let message = reserve(text) else { return false }
        // **전송까지 여기서 건다.** 예약과 실행이 갈라져 있으면 그 사이가 창이 되고,
        // 실행이 한 번이라는 보장도 호출부에 맡기게 된다.
        deliveryTask = Task { [weak self] in await self?.deliver(message.id) }
        return true
    }

    /// 접수와 전송을 한 번에 기다린다. **지금은 테스트만 쓴다** — 화면은 입력창을 비울
    /// 시점을 알아야 해서 `accept`를 쓴다. 입력창을 비울 일이 없는 호출부(예: 화면 어딘가에서
    /// 문장을 그대로 보내는 버튼)가 생기면 이쪽이다.
    func send(_ text: String) async {
        guard let message = reserve(text) else { return }
        await deliver(message.id)
    }

    private func reserve(_ text: String) -> PendingChatMessage? {
        guard isSendable(text) else { return nil }
        let message = PendingChatMessage(
            date: anchorDateString,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Self.localTimestampFormatter.string(from: now()),
            anchorMessageId: greatestSeenServerId
        )
        pendingMessages.append(message)
        delivery = .reserved(message.id)
        return message
    }

    /// 「다시 시도」를 띄울지. **말풍선 자신의 판정을 본다** — 지금 앵커 날짜의 잠금을 보면,
    /// 8월 1일이 거절당한 뒤 `✕`로 오늘로 돌아왔을 때 재시도가 열리고 그 재시도는 여전히
    /// 8월 1일로 나가 같은 400을 맞는다.
    /// **첫 장을 갈아끼우는 중에는 재시도도 막는다** — 새 전송과 같은 경합이다. 성공한 뒤
    /// 뒤이어 도착한 응답이 방금 나눈 대화를 지운다.
    func canRetry(_ message: PendingChatMessage) -> Bool {
        message.failed && message.isRetryable && !isSending && !isReplacingStream
    }

    /// 다시 보낼 수 없는 실패를 화면에서 치운다. **재시도가 있는 말풍선은 치우지 않는다** —
    /// 지우는 버튼과 다시 보내는 버튼이 나란히 있으면 잘못 누르는 쪽이 문장을 잃는다.
    ///
    /// 서버에 닿았는지 모르는 실패(「보냈는지 확인하지 못했어요」)가 여기 걸린다 — 다시
    /// 보낼 수는 없고, 그렇다고 화면에 영영 남겨 둘 이유도 없다. 실제로 실렸는지는 화면을
    /// 다시 열면 서버가 알려 준다.
    func dismiss(_ id: UUID) {
        guard let message = pendingMessages.first(where: { $0.id == id }),
              message.failed, !message.isRetryable else { return }
        pendingMessages.removeAll { $0.id == id }
    }

    /// **서버는 실패하면 아무것도 저장하지 않으므로**(질문·답을 한 트랜잭션에 쓴다) 같은
    /// 문장을 다시 보내도 중복이 남지 않는다.
    /// **말풍선을 지우고 새로 만들지 않는다.** 지웠다가 다시 붙이면 취소로 끝났을 때 새로 만든
    /// 것만 사라져 **원래 실패한 문장이 통째로 없어지고**, 자리도 맨 아래로 튄다. 같은 id·같은
    /// 자리에서 상태만 되돌린다.
    func retry(_ id: UUID) async {
        guard !isSending,
              let index = pendingMessages.firstIndex(where: { $0.id == id }),
              canRetry(pendingMessages[index]) else { return }
        pendingMessages[index].failed = false
        pendingMessages[index].failureReason = nil
        // 새 전송과 같은 예약을 거친다 — 두 길이 같은 잠금을 쓰지 않으면 서로를 못 막는다.
        delivery = .reserved(id)
        await deliver(id)
    }

    /// **예약을 「나가는 중」으로 한 번만 넘긴다.** 그 전이에서 이긴 호출만 실제로 보낸다 —
    /// 예약 상태만 확인하면 같은 말풍선으로 두 번 들어온 전송이 둘 다 통과해 유료 POST가
    /// 두 번 나간다.
    ///
    /// **`private`이 아니다.** 지금 호출부는 셋(`accept`의 작업·`send`·`retry`)뿐이고 모두
    /// 직전에 예약을 잡으므로 같은 id로 두 번 들어올 길이 없지만, 그러면 이 전이 가드가
    /// 테스트에 안 닿는다 — 가드가 지키는 것이 「눌러도 유료 호출이 한 번」이라 그 계약은
    /// 확인할 수 있어야 한다. 화면에는 여전히 id가 나가지 않는다(`accept`는 `Bool`이다).
    func deliver(_ id: UUID) async {
        guard case .reserved(let reservedId) = delivery, reservedId == id,
              let message = pendingMessages.first(where: { $0.id == id }) else { return }
        delivery = .delivering(id)
        // 그 사이 다른 것이 예약을 가져갔으면 그쪽 잠금을 풀지 않는다.
        defer {
            if case .delivering(let deliveringId) = delivery, deliveringId == id {
                delivery = nil
            }
        }

        do {
            let answer = try await service.askChat(date: message.date, message: message.text)

            // **응답이 읽을 수 있는 답인지 먼저 본다.** 계약은 `TEXT` 한 건이지만, 아니면
            // `isRenderable`이 조용히 걸러 내 질문만 남고 답이 사라진다. 서버는 이미
            // 저장했으므로 다시 보내지는 않는다(`decodingError`와 같은 판단이다).
            guard answer.type == .text, answer.content != nil else {
                mutatePending(id) {
                    $0.failed = true
                    $0.isRetryable = false
                    $0.failureReason = "답을 받았지만 읽지 못했어요"
                }
                return
            }

            // **자리는 서버가 정한다.** 질문 행도 서버가 저장하지만 응답에는 답만 오므로
            // 이미 띄운 말풍선을 스트림으로 옮기되, **쓴 자리가 아니라 맨 끝에** 놓는다 —
            // 서버는 재시도한 시점에 저장하므로 그 대화가 가장 최신이고, 답 자체도 그 사이
            // 오간 대화를 히스토리에 넣고 만들어진 것이다. 쓴 자리에 꽂으면 화면을 다시 열
            // 때 서버가 준 자리로 옮겨 가 순서가 뒤바뀐다.
            messages.append(contentsOf: [localMessage(message, savedAt: answer.createdAt), answer])
            noteSeen([answer])

            // **뒤에 쓴 말풍선들의 기준점을 방금 실린 답으로 옮긴다.** 그것들은 이 대화보다
            // 나중에 쓰였는데, 기준점을 그대로 두면 같은 자리로 계산돼 이 대화 위에 앉는다.
            // `pendingMessages`의 순서가 곧 쓴 순서다(추가는 끝에만, 재시도는 제자리).
            if let deliveredIndex = pendingMessages.firstIndex(where: { $0.id == id }) {
                for index in pendingMessages.indices where index > deliveredIndex {
                    pendingMessages[index].anchorMessageId = answer.id
                }
                pendingMessages.remove(at: deliveredIndex)
            }
        } catch is CancellationError {
            // **지우지 않는다** — 지우면 사용자가 쓴 문장이 사라진다.
            //
            // **그러나 다시 보내게 두지도 않는다.** 취소된 시점에 요청은 이미 나가 있었으므로
            // 서버가 LLM을 부르고 저장까지 끝냈을 수 있다 — 다시 보내면 돈이 두 번 나가고
            // 같은 대화가 두 벌이 된다(`isRetryable`이 지키는 것과 같은 규칙이다).
            mutatePending(id) {
                $0.failed = true
                $0.isRetryable = false
                $0.failureReason = "보냈는지 확인하지 못했어요"
            }
        } catch {
            // **말풍선을 남긴다.** 지우면 사용자가 다시 타이핑해야 한다.
            mutatePending(id) {
                $0.failed = true
                $0.isRetryable = Self.isRetryable(error)
                $0.failureReason = Self.failureReason(for: error)
            }

            if error.dietErrorCode == .invalidRequest {
                await handleDateRejection(message.date, for: id)
            }
        }
    }

    private func mutatePending(_ id: UUID, _ change: (inout PendingChatMessage) -> Void) {
        guard let index = pendingMessages.firstIndex(where: { $0.id == id }) else { return }
        change(&pendingMessages[index])
    }

    /// 서버가 이 날짜의 질문을 거절했다.
    ///
    /// **이유를 단정하지 않는다.** `INVALID_REQUEST`는 범용 코드라, 오늘은 「그날 기록된
    /// 끼니가 없습니다」 하나뿐이지만 언제든 다른 검증 실패가 같은 코드로 올 수 있다. 그날
    /// 하루를 다시 받아 **확인한 것만 말하고, 확인한 만큼만 잠근다.**
    ///
    /// - 빈 날로 확인 → 날짜를 잠그고 그렇게 안내한다
    /// - 끼니가 있는 것으로 확인 → **날짜를 잠그지 않는다.** 그 문장만의 문제였다는 뜻이라,
    ///   같은 날의 다른 질문까지 막으면 애먼 것을 막는다
    /// - 확인하지 못함 → 날짜를 잠그되 이유는 지어내지 않는다. 안 잠그면 같은 400을 다시 만든다
    private func handleDateRejection(_ date: String, for id: UUID) async {
        // **캐시가 아니라 방금 받은 것만 본다.** 재조회가 실패했는데 들고 있던 낡은 값을
        // 새 결과로 읽으면 확인하지도 않고 판단하게 된다.
        switch await reloadDay(date) {
        case .fresh(let day):
            guard day.meals.isEmpty else { return }
            rejectedDates.insert(date)
            mutatePending(id) { $0.failureReason = "이 날은 기록이 없어서 물어볼 수 없어요" }
        case .failed:
            // 확인하지 못했다 — 잠그되 이유는 지어내지 않는다.
            rejectedDates.insert(date)
        case .stale:
            // 더 새로운 조회가 이미 이 날짜의 상태를 세웠다. 그 위에 옛 판단을 덮으면
            // 방금 푼 잠금이 다시 걸린다.
            break
        }
    }

    /// 다시 보낼 만한 실패인가.
    ///
    /// **이 엔드포인트는 멱등하지 않다.** 서버가 LLM을 부르고 그 결과를 저장하므로, 요청이
    /// 서버에 닿은 뒤 실패했다면 유료 호출이 이미 나갔고 대화가 저장돼 있을 수도 있다.
    /// 다시 보내면 돈이 두 번 나가고 같은 대화가 두 벌이 된다.
    ///
    /// **그래서 「안전하다고 아는 것」만 허용한다.** 실패를 뭉뚱그려 5xx면 재시도로 두면
    /// 저장 도중 죽은 500이 그대로 중복 결제가 된다.
    private static func isRetryable(_ error: any Error) -> Bool {
        // 서버가 「답을 못 만들었다」고 밝힌 경우다 — 저장 전에 끊겼음을 서버가 보증한다
        // (`DietChatService.ask`가 `append` 앞에서 던진다).
        if error.dietErrorCode == .chatFailed { return true }

        // 요청이 **나가지도 못한** 경우. 서버는 아무것도 모른다.
        // 타임아웃·연결 끊김은 여기 없다 — 서버에 닿은 뒤일 수 있다.
        if case .networkError(let underlying) = error as? APIError ?? .invalidURL,
           let urlError = underlying as? URLError {
            return [
                .notConnectedToInternet,
                .cannotFindHost,
                .cannotConnectToHost,
                .dataNotAllowed,
                .internationalRoamingOff
            ].contains(urlError.code)
        }

        return false
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

    /// 스트림에 옮겨 놓는 내 질문 행.
    ///
    /// **`savedAt`은 서버가 답을 저장한 시각이다** — 쓴 시각이 아니다. 서버는 질문과 답을
    /// 한 트랜잭션에 쓰므로 둘의 시각이 같고, 여기에 쓴 시각을 넣으면 날짜 구분선이 화면을
    /// 다시 열 때 서버 값으로 옮겨 간다(실패했다 다음 날 재시도한 질문이 특히 그렇다).
    private func localMessage(_ message: PendingChatMessage, savedAt: String) -> ChatMessage {
        localIdSeed -= 1
        return ChatMessage(
            id: localIdSeed,
            type: .text,
            date: message.date,
            role: .user,
            createdAt: savedAt,
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
