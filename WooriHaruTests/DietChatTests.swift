import Foundation
import Testing
@testable import WooriHaru

// MARK: - 행 읽기 도우미

private func separatorDays(_ rows: [ChatRow]) -> [String] {
    rows.compactMap { row -> String? in
        guard case .dateSeparator(let day, _) = row else { return nil }
        return day
    }
}

/// 말풍선마다의 배지. **`nil`도 한 자리를 차지한다** — 「안 붙는다」를 확인해야 해서
/// `compactMap`으로 지우면 안 된다.
private func badges(_ rows: [ChatRow]) -> [String?] {
    rows.compactMap { row -> String?? in
        switch row {
        case .message(_, let badge): return .some(badge)
        case .pending(_, let badge): return .some(badge)
        default: return nil
        }
    }
}

private func messageIds(_ rows: [ChatRow]) -> [Int] {
    rows.compactMap { row -> Int? in
        guard case .message(let message, _) = row else { return nil }
        return message.id
    }
}

private func hasPending(_ rows: [ChatRow]) -> Bool {
    rows.contains { row in
        guard case .pending = row else { return false }
        return true
    }
}

private func hasAwaitingReply(_ rows: [ChatRow]) -> Bool {
    rows.contains { row in
        guard case .awaitingReply = row else { return false }
        return true
    }
}

/// 스트림에 그려지는 문장들 — 서버 메시지와 못 보낸 말풍선을 섞어 순서를 본다.
@MainActor
private func streamTexts(_ vm: DietChatViewModel) -> [String] {
    vm.rows.compactMap { row -> String? in
        switch row {
        case .pending(let pending, _): return pending.text
        case .message(let message, _): return message.content
        default: return nil
        }
    }
}

/// 대부분의 테스트는 못 보낸 말풍선이 하나뿐이다.
@MainActor
private func onlyPending(_ vm: DietChatViewModel) -> PendingChatMessage? {
    vm.pendingMessages.first
}

@MainActor
private func canRetryOnly(_ vm: DietChatViewModel) -> Bool {
    vm.pendingMessages.first.map { vm.canRetry($0) } ?? false
}

@MainActor
private func retryOnly(_ vm: DietChatViewModel) async {
    guard let id = vm.pendingMessages.first?.id else { return }
    await vm.retry(id)
}

/// 앵커가 오늘인 뷰모델. 잠금·전송 테스트가 쓴다 — 「오늘」 판정이 `Calendar`에 달려 있어
/// 고정 날짜로는 재현할 수 없다.
@MainActor
private func makeTodayViewModel(
    service: FakeDietService,
    meals: [Meal]? = nil
) -> DietChatViewModel {
    let today = Date().dateString
    let day = makeDay(date: today, meals: meals ?? [makeMeal(date: today)])
    return DietChatViewModel(service: service, anchorDate: Date(), day: day)
}

// MARK: - 날짜 두 축

@MainActor
struct DietChatDateAxisTests {
    /// 8월 6일에 8월 1일을 물으면 그 말풍선은 8월 6일 자리에 앉는다 — 정체를 밝히는 배지가 필요하다.
    @Test func 얘기하는_날짜가_구분선과_다르면_배지가_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [
            makeChatMessage(id: 1, date: "2026-08-01", createdAt: "2026-08-06T12:00:00")
        ], nextCursor: nil)]
        let vm = DietChatViewModel(service: service, anchorDate: Date.from("2026-08-06")!, day: makeDay())

        await vm.load()

        #expect(badges(vm.rows) == ["08-01"])
    }

    /// **늘 붙이는 구현이면 여기서 빨개진다.** 같은 날 얘기를 같은 날 하는 경우가 대부분이라
    /// 늘 붙이면 노이즈가 된다.
    @Test func 같은_날_얘기면_배지가_없다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [
            makeChatMessage(id: 1, date: "2026-08-06", createdAt: "2026-08-06T12:00:00")
        ], nextCursor: nil)]
        let vm = DietChatViewModel(service: service, anchorDate: Date.from("2026-08-06")!, day: makeDay())

        await vm.load()

        #expect(badges(vm.rows) == [nil])
    }

    /// 구분선은 `createdAt`이다 — `date`만 다른 메시지 둘은 **한 구분선 아래** 앉는다.
    @Test func 구분선은_얘기한_날짜가_아니라_말한_시각_기준이다() async {
        let service = FakeDietService()
        // 서버는 최신부터 준다(`id DESC`) — 앱이 뒤집어 아래에 붙인다.
        service.chatPages = [ChatPage(messages: [
            makeChatMessage(id: 2, date: "2026-08-06", createdAt: "2026-08-06T13:00:00"),
            makeChatMessage(id: 1, date: "2026-08-01", createdAt: "2026-08-06T12:00:00")
        ], nextCursor: nil)]
        let vm = DietChatViewModel(service: service, anchorDate: Date.from("2026-08-06")!, day: makeDay())

        await vm.load()

        #expect(separatorDays(vm.rows) == ["2026-08-06"])
        #expect(badges(vm.rows) == ["08-01", nil])
    }

    /// **못 보낸 말풍선의 구분선도 「쓴 시각」이다.** 벽시계를 읽으면 23:59에 쓴 말풍선이
    /// 자정을 넘기며 구분선만 다음 날로 옮겨 가고, 재시도해 성공하면 그 행이 `createdAt`으로
    /// 실려 다시 어제 구분선 아래로 돌아간다.
    @Test func 못_보낸_말풍선도_쓴_시각_구분선_아래에_앉는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        // **시계를 어제 23:59로 고정한다.** 기대값을 검사 대상에서 읽어 오면 구현이 벽시계를
        // 읽든 `date`를 읽든 그대로 통과한다 — 그 버그로 빨개지지 않는 테스트는 없느니만 못하다.
        let writtenAt = Date().addingTimeInterval(-60 * 60 * 24)
        let vm = DietChatViewModel(
            service: service,
            anchorDate: Date(),
            day: makeDay(date: Date().dateString, meals: [makeMeal(date: Date().dateString)]),
            now: { writtenAt }
        )
        await vm.load()
        await vm.send("못 보낸 질문")

        // 앵커(오늘)도 벽시계(오늘)도 아닌 **쓴 날(어제)** 아래에 앉는다.
        #expect(separatorDays(vm.rows) == [writtenAt.dateString])
        #expect(separatorDays(vm.rows) != [Date().dateString])
        #expect(vm.pendingMessages[0].date == Date().dateString)
    }

    /// **`ForEach`가 쓰는 id는 유일해야 한다.** 구분선 id가 날짜뿐이라, 스트림 중간에 다른
    /// 날짜가 끼면 같은 id가 두 번 나올 수 있다 — SwiftUI에서 그건 정의되지 않은 렌더링이다.
    @Test func 행_id가_겹치지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [
            makeChatMessage(id: 3, createdAt: "2026-08-06T12:00:00", content: "어제 A"),
            makeChatMessage(id: 2, createdAt: "2026-08-05T12:00:00", content: "그저께"),
            makeChatMessage(id: 1, createdAt: "2026-08-06T09:00:00", content: "어제 B")
        ], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("못 보낸 질문")

        let ids = vm.rows.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// **위로 스크롤할 때 되돌아올 앵커는 메시지여야 한다.** 구분선 id는 날짜뿐이라, 앞에
    /// 붙은 장의 마지막 날짜가 지금 첫 줄과 같으면 같은 id가 맨 위로 옮겨 가 「되돌리기」가
    /// 「최상단으로 튀기」가 되고, 위쪽 로더가 다시 보여 대화 전량을 연쇄로 내려받는다.
    @Test func 스크롤_앵커는_구분선이_아니라_메시지다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [makeChatMessage(id: 20, createdAt: "2026-08-06T12:00:00")], nextCursor: 20),
            // 앞에 붙는 이전 장이 **같은 날짜**다 — 구분선을 앵커로 잡으면 여기서 무너진다.
            ChatPage(messages: [makeChatMessage(id: 19, createdAt: "2026-08-06T09:00:00")], nextCursor: nil)
        ]
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: makeDay())
        await vm.load()

        let anchor = vm.firstMessageRowId
        #expect(anchor == "message-20")

        await vm.loadNextPage()

        // 앵커가 가리키던 줄이 여전히 그 메시지다 — 맨 위(19)로 옮겨 가지 않았다.
        #expect(vm.firstMessageRowId == "message-19")
        #expect(vm.rows.contains { $0.id == anchor })
        // 구분선을 앵커로 잡았다면 이 값이 새 첫 줄과 같아져 최상단으로 튄다.
        #expect(vm.rows.first?.id == "separator-0-2026-08-06")
    }

    /// 카드도 같다 — 8월 1일 끼니를 8월 3일에 뒤늦게 확정하면 카드는 8월 3일 자리에 앉는다.
    @Test func 뒤늦게_확정한_끼니_카드에도_배지가_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [
            makeChatMessage(
                id: 1, type: .mealCard, date: "2026-08-01", role: .assistant,
                createdAt: "2026-08-03T09:00:00", content: nil, meal: makeChatMealCard()
            )
        ], nextCursor: nil)]
        let vm = DietChatViewModel(service: service, anchorDate: Date.from("2026-08-03")!, day: makeDay())

        await vm.load()

        #expect(separatorDays(vm.rows) == ["2026-08-03"])
        #expect(badges(vm.rows) == ["08-01"])
    }
}

// MARK: - 페이징

@MainActor
struct DietChatPagingTests {
    @Test func 첫_장은_커서_없이_부른다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [makeChatMessage()], nextCursor: 40)]
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: makeDay())

        await vm.load()

        #expect(service.chatPageCursors == [nil])
    }

    /// 서버가 최신부터 주므로 앱이 뒤집어 아래에 붙인다 — 다음 장은 **위에** 붙는다.
    @Test func 다음_장은_커서를_그대로_넘기고_위에_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [makeChatMessage(id: 20), makeChatMessage(id: 19)], nextCursor: 19),
            ChatPage(messages: [makeChatMessage(id: 18), makeChatMessage(id: 17)], nextCursor: nil)
        ]
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: makeDay())

        await vm.load()
        #expect(messageIds(vm.rows) == [19, 20])

        await vm.loadNextPage()

        #expect(service.chatPageCursors == [nil, 19])
        #expect(messageIds(vm.rows) == [17, 18, 19, 20])
    }

    /// **실패한 뒤에도 스피너를 돌리면 영영 불러오는 중인 것처럼 보인다.** 커서는 남겨
    /// 두어야 「다시 시도」가 같은 자리를 다시 부를 수 있다.
    @Test func 다음_장_조회가_실패하면_다시_시도할_자리를_남긴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: 19)]
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: makeDay())
        await vm.load()

        service.errors["fetchChatPage"] = dietServerError("INVALID_REQUEST")
        await vm.loadNextPage()

        #expect(vm.nextPageFailed)
        #expect(vm.hasMore)
        // 스크롤 중에 알럿이 튀어나오면 읽는 것을 방해한다 — 맨 위 줄이 대신 말한다.
        #expect(vm.errorMessage == nil)

        service.errors["fetchChatPage"] = nil
        service.chatPages = [ChatPage(messages: [makeChatMessage(id: 18)], nextCursor: nil)]
        await vm.loadNextPage()

        #expect(!vm.nextPageFailed)
        #expect(messageIds(vm.rows) == [18, 20])
    }

    /// **첫 장을 다시 받으면 다음 장 실패도 함께 내려간다.** 안 내리면 맨 위에 「다시 시도」가
    /// 남아 자동 페이징이 꺼진 채 손으로 눌러야만 도는 상태가 된다.
    @Test func 첫_장을_다시_받으면_다음_장_실패_표시가_내려간다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: 19)]
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: makeDay())
        await vm.load()

        service.errors["fetchChatPage"] = dietServerError("INVALID_REQUEST")
        await vm.loadNextPage()
        #expect(vm.nextPageFailed)

        service.errors["fetchChatPage"] = nil
        service.chatPages = [ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: 19)]
        await vm.reload()

        #expect(!vm.nextPageFailed)
    }

    @Test func 다음_커서가_없으면_더_부르지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [makeChatMessage()], nextCursor: nil)]
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: makeDay())

        await vm.load()
        #expect(!vm.hasMore)

        await vm.loadNextPage()

        #expect(service.chatPageCursors.count == 1)
    }

    /// 스크롤이 위쪽에 머무는 동안 `onAppear`가 여러 번 뜬다 — 가드가 없으면 같은 장을 두 번 받는다.
    @Test func 로딩_중에는_또_부르지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: 19),
            ChatPage(messages: [makeChatMessage(id: 18)], nextCursor: 17)
        ]
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: makeDay())
        await vm.load()

        let gate = AsyncGate()
        service.chatPageGate = gate
        let first = Task { await vm.loadNextPage() }
        await gate.waitUntilBlocked()

        // 첫 요청이 아직 안 돌아왔다 — 여기서 나가면 같은 커서로 두 번 나간다.
        await vm.loadNextPage()

        await gate.open()
        await first.value

        #expect(service.chatPageCursors == [nil, 19])
    }
}

// MARK: - 전송

@MainActor
struct DietChatSendTests {
    /// **LLM이 수 초 걸린다.** 안 붙이면 내가 뭘 보냈는지 화면에서 사라진다.
    @Test func 답을_기다리는_동안_내_말풍선이_먼저_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "나트륨이 기준을 넘었어요")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let gate = AsyncGate()
        service.askChatGate = gate
        let sending = Task { await vm.send("점심 왜 낮아?") }
        await gate.waitUntilBlocked()

        #expect(onlyPending(vm)?.text == "점심 왜 낮아?")
        #expect(hasPending(vm.rows))
        #expect(hasAwaitingReply(vm.rows))

        await gate.open()
        await sending.value
    }

    @Test func 답이_오면_내_말풍선_아래에_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "나트륨이 기준을 넘었어요")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        #expect(vm.pendingMessages.isEmpty)
        #expect(vm.messages.map(\.content) == ["점심 왜 낮아?", "나트륨이 기준을 넘었어요"])
        #expect(vm.messages.map(\.role) == [.user, .assistant])
        #expect(!hasAwaitingReply(vm.rows))
        // 질문은 앵커 날짜로 나간다.
        #expect(service.askedChats.map(\.date) == [Date().dateString])
    }

    /// **지우면 사용자가 다시 타이핑해야 한다.**
    @Test func 실패하면_내_말풍선이_남고_다시_시도가_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("CHAT_FAILED", status: 503)
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        #expect(onlyPending(vm)?.text == "점심 왜 낮아?")
        #expect(onlyPending(vm)?.failed == true)
        #expect(hasPending(vm.rows))
        // 오지 않을 답을 기다리는 자리를 남기지 않는다.
        #expect(!hasAwaitingReply(vm.rows))
        // 말풍선이 사실을 이미 말하고 있다 — 알럿까지 띄우면 같은 말을 두 번 한다.
        #expect(vm.errorMessage == nil)
    }

    /// 서버는 실패하면 질문도 저장하지 않으므로(한 트랜잭션) 재시도가 안전하다.
    @Test func 다시_시도하면_같은_문장을_다시_보낸다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("CHAT_FAILED", status: 503)
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("점심 왜 낮아?")

        service.errors["askChat"] = nil
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "나트륨이 기준을 넘었어요")]
        await retryOnly(vm)

        #expect(service.askedChats.map(\.message) == ["점심 왜 낮아?", "점심 왜 낮아?"])
        #expect(vm.pendingMessages.isEmpty)
        #expect(vm.messages.map(\.content) == ["점심 왜 낮아?", "나트륨이 기준을 넘었어요"])
    }

    /// **서버가 거절할 본문은 보내지 않는다**(`@Size(max = 500)`). 보내 버리면 말풍선에
    /// 「보내지 못했어요」만 남는데, 전송 실패는 알럿을 띄우지 않아서 왜 실패했는지 알 길이
    /// 없고 「다시 시도」는 같은 본문으로 영원히 실패한다.
    @Test func 상한을_넘는_문장은_나가지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let tooLong = String(repeating: "가", count: ChatPolicy.maxMessageLength + 1)
        #expect(!vm.isSendable(tooLong))
        #expect(vm.lengthNotice(for: tooLong) != nil)

        await vm.send(tooLong)

        #expect(service.askedChats.isEmpty)
        #expect(vm.pendingMessages.isEmpty)
    }

    /// 경계는 포함이다 — 한 글자 차이로 보내지 못하면 상한이 실제보다 좁아진다.
    @Test func 상한과_같은_길이는_보낸다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let exact = String(repeating: "가", count: ChatPolicy.maxMessageLength)
        #expect(vm.isSendable(exact))
        #expect(vm.lengthNotice(for: exact) == nil)

        await vm.send(exact)

        #expect(service.askedChats.map(\.message) == [exact])
    }

    /// 서버 `@Size`는 자바 `String.length`(UTF-16 코드 단위)를 본다 — 문자 수로 재면
    /// 이모지가 섞였을 때 앱은 통과시키고 서버가 거절한다.
    @Test func 길이는_서버와_같은_단위로_센다() {
        let vm = makeTodayViewModel(service: FakeDietService())

        // 이모지 하나가 UTF-16으로 두 칸이라, 문자 수로는 상한 안이지만 서버는 거절한다.
        let emojiHeavy = String(repeating: "🍚", count: ChatPolicy.maxMessageLength / 2 + 1)
        #expect(emojiHeavy.count <= ChatPolicy.maxMessageLength)
        #expect(!vm.isSendable(emojiHeavy))
    }

    @Test func 전송_중에는_다시_보낼_수_없다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let gate = AsyncGate()
        service.askChatGate = gate
        let sending = Task { await vm.send("첫 질문") }
        await gate.waitUntilBlocked()

        #expect(!vm.canSend)
        await vm.send("두 번째 질문")

        await gate.open()
        await sending.value

        #expect(service.askedChats.map(\.message) == ["첫 질문"])
    }
}

// MARK: - 잠금·칩

@MainActor
struct DietChatLockTests {
    /// 서버도 400으로 막지만, 플로팅 버튼이 늘 떠 있어서 기록 전에 누르는 일이 흔하다 —
    /// 그때마다 오류 알럿을 띄우면 곤란하다.
    @Test func 기록이_없는_날은_입력창이_잠긴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [makeChatMessage()], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service, meals: [])

        await vm.load()

        #expect(vm.isInputLocked)
        #expect(!vm.canSend)
        #expect(vm.lockedNotice != nil)
        // **스트림은 그대로 보여준다** — 과거 대화를 읽는 데는 문제가 없다.
        #expect(messageIds(vm.rows) == [1])
    }

    @Test func 잠긴_날에는_보내도_나가지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service, meals: [])
        await vm.load()

        await vm.send("점심 왜 낮아?")

        #expect(service.askedChats.isEmpty)
        #expect(vm.pendingMessages.isEmpty)
        // **잠겨서 안 나간 것임을 못 박는다.** 이것이 없으면 다른 이유로 조회가 실패해
        // 전송이 막혔을 때도 그대로 통과한다.
        #expect(vm.isInputLocked)
        #expect(vm.hasLoaded)
    }

    /// **하루를 받는 동안에는 잠근다.** 앵커를 오늘로 되돌린 직후가 특히 그렇다 — 그 창에서
    /// 보내면 오늘이 빈 날일 때 그대로 400을 맞는다.
    @Test func 하루를_받는_동안에는_잠긴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.days = [makeDay(date: Date().dateString, meals: [])]
        let vm = DietChatViewModel(
            service: service,
            anchorDate: Date.from("2026-08-01")!,
            day: makeDay(date: "2026-08-01", meals: [makeMeal(date: "2026-08-01")])
        )
        await vm.load()
        #expect(!vm.isInputLocked)

        let gate = AsyncGate()
        service.fetchDayGates[Date().dateString] = gate
        let resetting = Task { await vm.resetAnchorToToday() }
        await gate.waitUntilBlocked()

        #expect(vm.isInputLocked)
        // 아직 모르는 것을 「기록이 없다」고 말하면 거짓말이 된다.
        #expect(vm.lockedNotice == nil)

        await gate.open()
        await resetting.value
    }

    /// **모르는 것을 「없다」로 단정하지 않는다.** 하루 조회가 실패한 날까지 잠그면 기록이
    /// 있어도 영영 물어볼 수 없다(`DietDayViewModel`이 프로필 조회 실패에서 같은 판단을 한다).
    @Test func 하루를_못_받았으면_잠그지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["fetchDay"] = dietServerError("RESOURCE_NOT_FOUND", status: 404)
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: nil)

        await vm.load()

        #expect(!vm.isInputLocked)
        #expect(vm.lockedNotice == nil)
    }

    /// 그 대신 **한 번 거절당하면 그때 잠근다** — 안 그러면 「다시 시도」가 같은 400을
    /// 무한히 만든다.
    @Test func 빈_날로_거절당하면_하루를_다시_받아_잠근다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["fetchDay"] = dietServerError("RESOURCE_NOT_FOUND", status: 404)
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: nil)
        await vm.load()
        #expect(!vm.isInputLocked)

        // 서버는 그날 기록이 없다고 400을 준다. 이번에는 하루 조회가 성공한다.
        service.errors["askChat"] = dietServerError("INVALID_REQUEST")
        service.errors["fetchDay"] = nil
        service.days = [makeDay(date: Date().dateString, meals: [])]

        await vm.send("오늘 뭐가 부족했어?")

        #expect(vm.isInputLocked)
        #expect(onlyPending(vm)?.failureReason == "이 날은 기록이 없어서 물어볼 수 없어요")
        // 눌러도 같은 거절이 돌아오는 재시도는 두지 않는다.
        #expect(!canRetryOnly(vm))

        await retryOnly(vm)
        #expect(service.askedChats.count == 1)
    }

    /// **못 보낸 문장이 다음 전송에 지워지면 안 된다.** 단수로 들면 `deliver`가 그대로
    /// 덮어써서, 「지우면 다시 타이핑해야 한다」로 막으려던 상태로 돌아간다.
    @Test func 실패한_말풍선은_새_질문을_보내도_남는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("첫 질문")
        #expect(vm.pendingMessages.count == 1)

        service.errors["askChat"] = nil
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        await vm.send("두 번째 질문")

        // 실패한 첫 질문이 그대로 남아 있고, 두 번째만 스트림으로 옮겨졌다.
        #expect(vm.pendingMessages.map(\.text) == ["첫 질문"])
        #expect(vm.messages.map(\.content) == ["두 번째 질문", "답"])
        #expect(canRetryOnly(vm))
    }

    /// **먼저 쓴 문장이 위에 앉아야 한다.** 못 보낸 것을 끝에 몰아 붙이면 화면이
    /// 「B 질문 → B 답변 → 실패한 A」가 되어 A가 제일 최근 것처럼 보인다.
    @Test func 실패한_말풍선이_나중에_보낸_대화_위에_남는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("A 질문")

        service.errors["askChat"] = nil
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "B 답변")]
        await vm.send("B 질문")

        // rows에서 실패한 A가 B보다 먼저 나온다.
        #expect(streamTexts(vm) == ["A 질문", "B 질문", "B 답변"])
    }

    /// **재시도가 말풍선을 지웠다 새로 만들면 안 된다.** 취소로 끝났을 때 새로 만든 것만
    /// 사라져 원래 문장이 통째로 없어지고, 자리도 맨 아래로 튄다.
    @Test func 재시도는_같은_말풍선을_그대로_쓴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("CHAT_FAILED", status: 503)
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("점심 왜 낮아?")
        let id = onlyPending(vm)?.id

        // 다시 실패해도 같은 말풍선이다.
        await retryOnly(vm)

        #expect(vm.pendingMessages.count == 1)
        #expect(id != nil)
        #expect(onlyPending(vm)?.id == id)
        #expect(onlyPending(vm)?.failed == true)
        #expect(service.askedChats.count == 2)
    }

    /// 같은 시점에 둘 다 실패하면 자리가 같다 — 그 안에서도 **쓴 순서**가 지켜져야 한다.
    /// 먼저 쓴 A를 재시도해 성공시켰을 때 B가 A의 대화 위로 올라가면 안 된다.
    @Test func 같은_자리의_말풍선끼리도_쓴_순서를_지킨다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("A 질문")
        await vm.send("B 질문")
        // 둘 다 스트림이 비어 있을 때 쓰였다 — 기준점이 없어 같은 자리에 앉는다.
        #expect(vm.pendingMessages.allSatisfy { $0.anchorMessageId == nil })

        service.errors["askChat"] = nil
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "A 답변")]
        await vm.retry(vm.pendingMessages[0].id)

        #expect(streamTexts(vm) == ["A 질문", "A 답변", "B 질문"])
    }

    /// 반대로 나중에 쓴 B를 먼저 재시도하면 A가 그 **위에** 남아야 한다 —
    /// 단순히 비교를 뒤집는 것으로는 이 두 경우를 함께 만족시킬 수 없다.
    @Test func 나중_것을_먼저_보내도_먼저_쓴_것이_위에_남는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("A 질문")
        await vm.send("B 질문")

        service.errors["askChat"] = nil
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "B 답변")]
        await vm.retry(vm.pendingMessages[1].id)

        #expect(streamTexts(vm) == ["A 질문", "B 질문", "B 답변"])
    }

    /// **첫 장을 받기 전에는 못 보낸다.** 먼저 보내 성공하면 뒤늦게 온 첫 장이 `messages`를
    /// 통째로 갈아끼워 방금 나눈 대화가 사라진다.
    @Test func 첫_장을_받기_전에는_보낼_수_없다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)

        let gate = AsyncGate()
        service.chatPageGate = gate
        let loading = Task { await vm.load() }
        await gate.waitUntilBlocked()

        #expect(!vm.canSend)
        await vm.send("점심 왜 낮아?")
        #expect(service.askedChats.isEmpty)

        await gate.open()
        await loading.value
        #expect(vm.canSend)
    }

    /// 첫 장을 다시 받으면 스트림이 통째로 갈린다 — 못 보낸 말풍선이 거기서 사라지면 안 된다.
    @Test func 첫_장을_다시_받아도_못_보낸_말풍선이_남는다() async {
        let service = FakeDietService()
        let history = ChatPage(messages: [
            makeChatMessage(id: 20, content: "과거 A"),
            makeChatMessage(id: 19, content: "과거 B")
        ], nextCursor: nil)
        service.chatPages = [history, history]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("새 질문")
        #expect(vm.pendingMessages.first?.anchorMessageId == 20)

        await vm.reload()

        // 기준점(20) 바로 뒤 — 사라지지도, 과거 기록 위로 올라가지도 않는다.
        #expect(streamTexts(vm) == ["과거 B", "과거 A", "새 질문"])
    }

    /// **앞에 이전 장을 붙여도 기준점이 자리를 지킨다.** 붙은 건수만큼 통째로 밀면,
    /// 기준점이 서로 다른 말풍선들이 모두 같은 만큼 밀려 자리가 어긋난다.
    @Test func 이전_장을_붙여도_기준점이_자리를_지킨다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [makeChatMessage(id: 30, content: "최신")], nextCursor: 30),
            ChatPage(messages: [
                makeChatMessage(id: 29, content: "옛것 B"),
                makeChatMessage(id: 28, content: "옛것 A")
            ], nextCursor: nil)
        ]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("못 보낸 질문")
        #expect(streamTexts(vm) == ["최신", "못 보낸 질문"])

        await vm.loadNextPage()

        // 앞에 두 건이 붙어도 여전히 기준점(30) 바로 뒤다.
        #expect(streamTexts(vm) == ["옛것 A", "옛것 B", "최신", "못 보낸 질문"])
    }

    /// **먼저 쓴 것이 나중 대화 아래로 내려가면 안 된다.** 전부 맨 끝으로 몰면 A가 실패하고
    /// B가 성공해 서버에 저장된 뒤 다시 받았을 때 순서가 뒤집힌다.
    @Test func 첫_장을_다시_받아도_먼저_쓴_말풍선이_위에_남는다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [], nextCursor: nil),
            // 다시 받으면 서버에 저장된 B의 질문·답이 실려 온다 — **A를 쓸 때 스트림이
            // 비어 있었으므로**(기준점 nil) A가 그 위에 남아야 한다.
            ChatPage(messages: [
                makeChatMessage(id: 9, role: .assistant, content: "B 답변"),
                makeChatMessage(id: 8, content: "B 질문")
            ], nextCursor: nil)
        ]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("A 질문")

        service.errors["askChat"] = nil
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "B 답변")]
        await vm.send("B 질문")
        #expect(streamTexts(vm) == ["A 질문", "B 질문", "B 답변"])

        await vm.reload()

        #expect(streamTexts(vm) == ["A 질문", "B 질문", "B 답변"])
    }

    /// 기준점이 새 장에 없으면(그만큼 새 메시지가 쌓여 밀려났으면) 실려 온 것이 전부
    /// 나중 것이라는 뜻이라 맨 위에 둔다.
    @Test func 기준점이_새_장에_없으면_맨_위에_둔다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [makeChatMessage(id: 5, content: "옛 기록")], nextCursor: nil),
            // 그 사이 새 메시지가 쌓여 기준점(5)이 첫 장 밖으로 밀렸다.
            ChatPage(messages: [
                makeChatMessage(id: 41, content: "새 기록 B"),
                makeChatMessage(id: 40, content: "새 기록 A")
            ], nextCursor: 40)
        ]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("못 보낸 질문")
        #expect(vm.pendingMessages.first?.anchorMessageId == 5)

        await vm.reload()

        #expect(streamTexts(vm) == ["못 보낸 질문", "새 기록 A", "새 기록 B"])
    }

    /// **재시도도 갈아끼우는 중에는 막는다** — 새 전송과 같은 경합이다.
    @Test func 첫_장을_다시_받는_동안에는_재시도도_막힌다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [], nextCursor: nil),
            ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: nil)
        ]
        service.errors["askChat"] = dietServerError("CHAT_FAILED", status: 503)
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("점심 왜 낮아?")
        #expect(canRetryOnly(vm))

        let gate = AsyncGate()
        service.chatPageGate = gate
        let reloading = Task { await vm.reload() }
        await gate.waitUntilBlocked()

        #expect(!canRetryOnly(vm))
        await retryOnly(vm)
        #expect(service.askedChats.count == 1)

        await gate.open()
        await reloading.value
        #expect(canRetryOnly(vm))
    }

    /// 반대편도 막아야 배타가 성립한다 — 전송이 성공해 두 행이 붙은 직후에 첫 장 응답이
    /// 도착하면 그것을 지운다.
    @Test func 전송_중에는_첫_장을_갈아끼우지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [], nextCursor: nil),
            ChatPage(messages: [makeChatMessage(id: 20, content: "서버 기록")], nextCursor: nil)
        ]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let gate = AsyncGate()
        service.askChatGate = gate
        let sending = Task { await vm.send("점심 왜 낮아?") }
        await gate.waitUntilBlocked()

        await vm.reload()
        // 전송이 끝나기 전에는 나가지도 않는다.
        #expect(service.chatPageCursors.count == 1)

        await gate.open()
        await sending.value
        #expect(streamTexts(vm) == ["점심 왜 낮아?", "답"])
    }

    /// **한 번 받은 뒤 다시 받는 동안에도 못 보낸다.** `hasLoaded`는 그때도 참이라,
    /// 그 창에서 보내 성공하면 뒤이어 도착한 응답이 방금 나눈 대화를 지운다.
    @Test func 첫_장을_다시_받는_동안에는_보낼_수_없다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [], nextCursor: nil),
            ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: nil)
        ]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        #expect(vm.canSend)

        let gate = AsyncGate()
        service.chatPageGate = gate
        let reloading = Task { await vm.reload() }
        await gate.waitUntilBlocked()

        #expect(vm.hasLoaded)
        #expect(!vm.canSend)
        await vm.send("점심 왜 낮아?")
        #expect(service.askedChats.isEmpty)

        await gate.open()
        await reloading.value
        #expect(vm.canSend)
    }

    /// **취소는 「안 보냈다」가 아니다.** 그 시점에 요청은 이미 나가 있었으므로 서버가
    /// LLM을 부르고 저장까지 끝냈을 수 있다 — 다시 보내면 돈이 두 번 나간다.
    @Test func 전송_도중_취소되면_다시_보내지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        // 요청이 나간 뒤 끊긴 상황 — `APIClient`가 URLSession 취소를 이 오류로 바꾼다.
        service.errors["askChat"] = CancellationError()
        await vm.send("점심 왜 낮아?")

        // 문장은 남기되 다시 보낼 수는 없다.
        #expect(onlyPending(vm)?.text == "점심 왜 낮아?")
        #expect(!canRetryOnly(vm))
        #expect(onlyPending(vm)?.failureReason == "보냈는지 확인하지 못했어요")
    }

    /// **기준점은 배열 마지막이 아니라 본 것 중 최댓값이다.** 실패했던 A를 나중에 재시도해
    /// 성공하면 그 답(더 큰 id)이 B 앞에 꽂혀 배열 마지막은 여전히 B의 답이다 — 그것을
    /// 기준점으로 잡으면 다음 질문이 이미 본 대화보다 앞에 앉는다.
    @Test func 다음_질문의_기준점은_본_것_중_가장_큰_id다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("A 질문")

        // B가 먼저 성공한다(답 id 102).
        service.errors["askChat"] = nil
        service.chatAnswers = [
            makeChatMessage(id: 102, role: .assistant, content: "B 답변"),
            makeChatMessage(id: 104, role: .assistant, content: "A 답변")
        ]
        await vm.send("B 질문")
        // 이어서 A를 재시도해 성공한다(답 id 104) — 그 쌍이 B 앞에 꽂힌다.
        await retryOnly(vm)
        #expect(streamTexts(vm) == ["A 질문", "A 답변", "B 질문", "B 답변"])

        // 배열 마지막은 102지만 기준점은 104여야 한다. 접수만 보면 되므로 전송은 붙잡아 둔다.
        let gate = AsyncGate()
        service.askChatGate = gate
        #expect(vm.accept("C 질문"))
        #expect(vm.pendingMessages.last?.anchorMessageId == 104)
        #expect(streamTexts(vm) == ["A 질문", "A 답변", "B 질문", "B 답변", "C 질문"])

        await gate.open()
        await vm.waitForDelivery()
    }

    /// **접수되고 나서 비운다.** 먼저 비우고 나중에 보내면, 그 사이 전송이 거절될 때
    /// 사용자가 쓴 문장만 사라진다.
    @Test func 보낼_수_없을_때는_접수하지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service, meals: [])
        await vm.load()

        #expect(!vm.accept("점심 왜 낮아?"))
        #expect(vm.pendingMessages.isEmpty)
    }

    /// **접수하는 순간 소유권을 잡는다.** 접수와 실제 전송 사이에는 화면의 `Task` 경계가
    /// 있어서, 그 창이 열려 있으면 첫 장 교체가 끼어들어 GET·POST가 다시 겹친다.
    @Test func 접수와_전송_사이에_첫_장을_갈아끼우지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [
            ChatPage(messages: [], nextCursor: nil),
            ChatPage(messages: [makeChatMessage(id: 20)], nextCursor: nil)
        ]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let gate = AsyncGate()
        service.askChatGate = gate
        #expect(vm.accept("점심 왜 낮아?"))
        #expect(vm.isSending)

        await vm.reload()
        #expect(service.chatPageCursors.count == 1)

        await gate.open()
        await vm.waitForDelivery()
        #expect(streamTexts(vm) == ["점심 왜 낮아?", "답"])
    }

    /// 그 창에서 두 번째 접수가 통과하면 전송 두 건이 겹친다.
    @Test func 접수와_전송_사이에_다시_접수되지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let gate = AsyncGate()
        service.askChatGate = gate
        #expect(vm.accept("첫 질문"))
        #expect(!vm.accept("두 번째 질문"))
        #expect(vm.pendingMessages.map(\.text) == ["첫 질문"])

        await gate.open()
        await vm.waitForDelivery()
        // **유료 POST가 한 번만 나갔다.**
        #expect(service.askedChats.map(\.message) == ["첫 질문"])
    }

    /// 재시도도 같은 예약을 거쳐야 한다 — 두 길이 같은 잠금을 쓰지 않으면 서로를 못 막는다.
    @Test func 접수와_전송_사이에_재시도가_끼어들지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("실패한 질문")
        let failedId = vm.pendingMessages[0].id
        #expect(canRetryOnly(vm))

        service.errors["askChat"] = nil
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let gate = AsyncGate()
        service.askChatGate = gate
        #expect(vm.accept("새 질문"))

        #expect(!vm.canRetry(vm.pendingMessages[0]))
        await vm.retry(failedId)
        #expect(service.askedChats.count == 1)

        await gate.open()
        await vm.waitForDelivery()
        #expect(service.askedChats.map(\.message) == ["실패한 질문", "새 질문"])
    }

    /// **나가는 중에 또 나가지 않는다.** 예약을 「나가는 중」으로 한 번만 넘기므로, 같은
    /// 말풍선이든 새 질문이든 두 번째 POST가 통과하지 못한다.
    @Test func 나가는_중에는_두_번째_전송이_실제로_나가지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let gate = AsyncGate()
        service.askChatGate = gate
        #expect(vm.accept("첫 질문"))
        await gate.waitUntilBlocked()

        // 첫 POST가 아직 안 돌아왔다 — 여기서 나가면 유료 호출이 두 번 나간다.
        await vm.send("두 번째 질문")
        #expect(service.askedChats.count == 1)

        await gate.open()
        await vm.waitForDelivery()
        #expect(service.askedChats.map(\.message) == ["첫 질문"])
        #expect(!vm.isSending)
    }

    /// **같은 예약으로 두 번 들어와도 POST는 한 번이다.** 앞선 테스트는 두 번째 시도가
    /// `isSending`에서 걸려 `reserved → delivering` 전이를 건드리지도 못했다 — 그 전이가
    /// 지키는 것이 「유료 호출은 한 번」이라 그 계약을 직접 확인한다.
    @Test func 같은_예약으로_두_번_들어와도_한_번만_보낸다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.chatAnswers = [makeChatMessage(id: 9, role: .assistant, content: "답")]
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        let gate = AsyncGate()
        service.askChatGate = gate
        #expect(vm.accept("점심 왜 낮아?"))
        let id = vm.pendingMessages[0].id
        await gate.waitUntilBlocked()

        // 이미 나가는 중인 같은 예약으로 다시 들어온다.
        await vm.deliver(id)
        #expect(service.askedChats.count == 1)
        // **중복 호출이 남의 잠금을 풀지 않는다.**
        #expect(vm.isSending)

        await gate.open()
        await vm.waitForDelivery()

        #expect(service.askedChats.map(\.message) == ["점심 왜 낮아?"])
        #expect(!vm.isSending)
        #expect(streamTexts(vm) == ["점심 왜 낮아?", "답"])
    }

    /// 취소로 끝나도 소유권이 풀려야 한다 — 안 풀리면 입력창이 영영 잠긴다.
    @Test func 취소로_끝나도_소유권이_풀린다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = CancellationError()
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        #expect(!vm.isSending)
        #expect(vm.canSend)
    }

    /// 다시 보낼 수 없는 실패로 끝나도 마찬가지다.
    @Test func 다시_보낼_수_없는_실패로_끝나도_소유권이_풀린다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("LLM_UNAVAILABLE", status: 503)
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        #expect(!vm.isSending)
        #expect(vm.canSend)
        #expect(!canRetryOnly(vm))
    }

    /// **다시 보낼 수 없는 실패는 치울 수 있어야 한다** — 그러지 않으면 화면에 영영 남는다.
    /// 재시도가 있는 말풍선은 치우지 않는다 — 잘못 누르면 문장을 잃는다.
    @Test func 다시_보낼_수_없는_실패만_치울_수_있다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()
        await vm.send("다시 보낼 수 있는 질문")

        // 재시도가 붙은 말풍선은 치워지지 않는다.
        vm.dismiss(vm.pendingMessages[0].id)
        #expect(vm.pendingMessages.count == 1)

        service.errors["askChat"] = dietServerError("LLM_UNAVAILABLE", status: 503)
        await vm.send("다시 보낼 수 없는 질문")
        #expect(vm.pendingMessages.count == 2)

        vm.dismiss(vm.pendingMessages[1].id)
        #expect(vm.pendingMessages.map(\.text) == ["다시 보낼 수 있는 질문"])
    }

    /// **서버 설정 문제에는 재시도를 두지 않는다** — 배포가 바뀌기 전에는 눌러도 그대로다.
    @Test func 설정_실패에는_다시_시도가_붙지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("LLM_UNAVAILABLE", status: 503)
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        #expect(onlyPending(vm)?.failureReason == "코치가 아직 준비되지 않았어요")
        #expect(!canRetryOnly(vm))
    }

    /// 생성만 실패했다 — 다음 호출은 될 수 있다.
    @Test func 답_생성_실패에는_다시_시도가_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("CHAT_FAILED", status: 503)
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        // **전송이 실제로 일어났음을 먼저 고정한다.** 이것이 없으면 전송이 거절돼
        // 말풍선이 아예 안 생겨도 `canRetryOnly`가 false라 통과한다.
        #expect(service.askedChats.count == 1)
        #expect(vm.pendingMessages.count == 1)
        #expect(canRetryOnly(vm))
    }

    /// **못 보낸 것이 아니라 못 읽은 것이다.** 서버는 질문과 답을 이미 저장했으므로 다시
    /// 보내면 LLM 호출이 한 번 더 나가고 같은 대화가 두 벌이 된다.
    @Test func 응답을_못_읽었으면_다시_보내지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.decodingError(URLError(.cannotParseResponse))
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        // **전송이 실제로 일어났음을 먼저 고정한다.** 이것이 없으면 전송이 거절돼
        // 말풍선이 아예 안 생겨도 `canRetryOnly`가 false라 통과한다.
        #expect(service.askedChats.count == 1)
        #expect(vm.pendingMessages.count == 1)
        #expect(!canRetryOnly(vm))
    }

    /// **요청이 나가지도 못한 경우만 안전하다.** 서버는 아무것도 모른다.
    @Test func 연결이_없어_못_나갔으면_다시_시도가_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        // **전송이 실제로 일어났음을 먼저 고정한다.** 이것이 없으면 전송이 거절돼
        // 말풍선이 아예 안 생겨도 `canRetryOnly`가 false라 통과한다.
        #expect(service.askedChats.count == 1)
        #expect(vm.pendingMessages.count == 1)
        #expect(canRetryOnly(vm))
    }

    /// **타임아웃은 안전하지 않다.** 서버에 닿아 LLM을 부르고 저장까지 끝낸 뒤 응답만 못
    /// 받았을 수 있다 — 다시 보내면 돈이 두 번 나가고 대화가 두 벌이 된다.
    @Test func 타임아웃에는_다시_시도를_두지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.timedOut))
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        // **전송이 실제로 일어났음을 먼저 고정한다.** 이것이 없으면 전송이 거절돼
        // 말풍선이 아예 안 생겨도 `canRetryOnly`가 false라 통과한다.
        #expect(service.askedChats.count == 1)
        #expect(vm.pendingMessages.count == 1)
        #expect(!canRetryOnly(vm))
    }

    /// 저장 도중 죽은 500도 같다 — 유료 호출은 이미 나갔다.
    @Test func 서버_오류에는_다시_시도를_두지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.serverError(statusCode: 500, message: nil)
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        // **전송이 실제로 일어났음을 먼저 고정한다.** 이것이 없으면 전송이 거절돼
        // 말풍선이 아예 안 생겨도 `canRetryOnly`가 false라 통과한다.
        #expect(service.askedChats.count == 1)
        #expect(vm.pendingMessages.count == 1)
        #expect(!canRetryOnly(vm))
    }

    /// **확인용 재조회까지 실패해도 잠금이 풀리면 안 된다.** `daysByDate`로만 판단하면
    /// 아무것도 못 받은 상태로 돌아가 같은 400을 다시 만든다.
    @Test func 거절_이유를_확인하지_못해도_그_날짜는_잠긴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["fetchDay"] = dietServerError("RESOURCE_NOT_FOUND", status: 404)
        service.errors["askChat"] = dietServerError("INVALID_REQUEST")
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: nil)
        await vm.load()

        await vm.send("오늘 뭐가 부족했어?")

        #expect(vm.isInputLocked)
        #expect(!canRetryOnly(vm))
        // **이유를 지어내지 않는다** — 빈 날인지 확인하지 못했다.
        #expect(onlyPending(vm)?.failureReason == nil)
        #expect(vm.lockedNotice == "이 날은 지금 물어볼 수 없어요")
    }

    /// `INVALID_REQUEST`는 범용 코드다 — 끼니가 있는데 거절당했으면 「기록이 없어서」는
    /// 거짓말이 된다.
    @Test func 끼니가_있는데_거절당하면_빈_날이라고_말하지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("INVALID_REQUEST")
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        // 확인해 보니 그날 끼니가 멀쩡히 있다.
        service.days = [makeDay(date: Date().dateString, meals: [makeMeal(date: Date().dateString)])]
        await vm.send("오늘 뭐가 부족했어?")

        #expect(service.askedChats.count == 1)
        #expect(vm.pendingMessages.count == 1)
        #expect(onlyPending(vm)?.failureReason == nil)
        // **그 문장만의 문제였다는 뜻이다** — 같은 날의 다른 질문까지 막으면 애먼 것을 막는다.
        #expect(!vm.isInputLocked)
        #expect(vm.lockedNotice == nil)
        // 그래도 같은 본문을 다시 보내는 것은 같은 거절이다.
        #expect(!canRetryOnly(vm))
    }

    /// 잠갔으면 푸는 길이 있어야 한다 — 그 사이 끼니를 기록했으면 다시 물을 수 있다.
    @Test func 기록이_확인되면_거절_잠금이_풀린다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["fetchDay"] = dietServerError("RESOURCE_NOT_FOUND", status: 404)
        service.errors["askChat"] = dietServerError("INVALID_REQUEST")
        let vm = DietChatViewModel(service: service, anchorDate: Date(), day: nil)
        await vm.load()
        await vm.send("오늘 뭐가 부족했어?")
        #expect(vm.isInputLocked)

        // 끼니를 기록하고 화면이 앵커를 다시 세운다 — 이번에는 하루가 돌아온다.
        let today = Date().dateString
        service.errors["fetchDay"] = nil
        service.days = [makeDay(date: today, meals: [makeMeal(date: today)])]
        await vm.resetAnchorToToday()

        #expect(!vm.isInputLocked)
        #expect(vm.lockedNotice == nil)
    }

    /// **실패 뒤 앵커를 오늘로 되돌려도 재시도가 열리면 안 된다.** 재시도는 여전히 8월 1일로
    /// 나가 같은 400을 맞는다 — 판정은 앵커가 아니라 그 말풍선의 것이다.
    @Test func 앵커를_바꿔도_거절당한_말풍선은_다시_보내지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = dietServerError("INVALID_REQUEST")
        service.days = [
            // 거절 확인용(8월 1일: 빈 날) → 오늘로 되돌릴 때(오늘: 기록 있음)
            makeDay(date: "2026-08-01", meals: []),
            makeDay(date: Date().dateString, meals: [makeMeal(date: Date().dateString)])
        ]
        let vm = DietChatViewModel(
            service: service,
            anchorDate: Date.from("2026-08-01")!,
            day: makeDay(date: "2026-08-01", meals: [makeMeal(date: "2026-08-01")])
        )
        await vm.load()

        await vm.send("점심 왜 낮아?")
        #expect(!canRetryOnly(vm))

        // `✕` — 오늘은 기록이 있어 입력창이 풀린다. 그래도 저 말풍선은 다시 못 보낸다.
        await vm.resetAnchorToToday()
        #expect(!vm.isInputLocked)
        #expect(!canRetryOnly(vm))

        await retryOnly(vm)
        #expect(service.askedChats.count == 1)
    }

    /// **날짜별 진행 상태여야 한다.** 전역 플래그 하나면 먼저 끝난 조회가 그것을 내려,
    /// 지금 앵커의 하루는 아직 오는 중인데 입력창이 열린다.
    @Test func 다른_날짜_조회가_끝나도_현재_앵커가_로딩_중이면_잠긴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let today = Date().dateString
        service.days = [
            makeDay(date: "2026-08-01", meals: [makeMeal(date: "2026-08-01")]),
            makeDay(date: today, meals: [makeMeal(date: today)])
        ]
        let pastGate = AsyncGate()
        let todayGate = AsyncGate()
        service.fetchDayGates["2026-08-01"] = pastGate
        service.fetchDayGates[today] = todayGate

        let vm = DietChatViewModel(service: service, anchorDate: Date.from("2026-08-01")!, day: nil)
        let loading = Task { await vm.load() }
        await pastGate.waitUntilBlocked()

        // 8월 1일이 아직 오는 중인데 오늘로 되돌린다 — 두 조회가 겹친다.
        let resetting = Task { await vm.resetAnchorToToday() }
        await todayGate.waitUntilBlocked()

        // 먼저 끝나는 쪽은 이제 관심 밖인 8월 1일이다.
        await pastGate.open()
        await loading.value

        // **여기가 판정이다.** 전역 플래그였다면 여기서 잠금이 풀려 있다.
        #expect(vm.isLoadingDay)
        #expect(vm.isInputLocked)

        await todayGate.open()
        await resetting.value
        #expect(!vm.isInputLocked)
    }

    /// 앵커가 오늘이면 잠금을 판단하는 데 새 호출이 들지 않는다 — 화면이 하루를 넘겨준다.
    @Test func 앵커_날짜의_하루는_다시_조회하지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service)

        await vm.load()

        // 화면이 실제로 열렸음을 먼저 고정한다 — 아무것도 안 했어도 빈 배열이다.
        #expect(vm.hasLoaded)
        #expect(!vm.isInputLocked)
        #expect(service.fetchedDates.isEmpty)
    }

    /// 앵커 칩은 오늘이 아닐 때만 뜬다 — 오늘이 기본값이라 늘 띄우면 자리만 먹는다.
    @Test func 앵커를_오늘로_되돌리면_칩이_사라진다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.days = [makeDay(date: Date().dateString, meals: [makeMeal(date: Date().dateString)])]
        let vm = DietChatViewModel(
            service: service,
            anchorDate: Date.from("2026-08-01")!,
            day: makeDay(date: "2026-08-01", meals: [makeMeal(date: "2026-08-01")])
        )
        await vm.load()
        #expect(vm.anchorChipText == "8월 1일에 대해 묻는 중")

        await vm.resetAnchorToToday()

        #expect(vm.anchorChipText == nil)
        #expect(vm.anchorDateString == Date().dateString)
        // 오늘 하루는 갖고 있지 않았으므로 그때 한 번 조회한다.
        #expect(service.fetchedDates == [Date().dateString])
    }
}

// MARK: - 구성비 막대

/// **`MacroBar`와 다른 격자다** — 저쪽은 목표 대비, 이쪽은 구성비다.
///
/// 뷰 계층은 이 저장소에 뷰 검사 도구가 없어 직접 확인하지 못한다. 대신 뷰가 쓰는 판단을
/// 전부 순수 함수로 꺼내 두고 그것을 확인한다(`MacroBar.ratio`/`fill`이 같은 모양이다).
struct MacroStackBarTests {
    private func macro(_ name: String, _ percent: Double) -> MacroBasis {
        MacroBasis(name: name, percent: percent, rangeMin: 0, rangeMax: 100, status: .inRange, penalty: 0)
    }

    /// 합이 100이 아닐 수 있다(반올림) — 합으로 나눠야 막대가 폭을 꽉 채운다.
    /// **합만 보면 순서가 뒤집혀도 통과하므로** 칸마다의 폭을 하나씩 본다.
    @Test func 칸마다_제_비율의_폭을_갖는다() {
        let widths = MacroStackBar.widths(
            [macro("탄수화물", 45), macro("단백질", 17), macro("지방", 36)],
            in: 98
        )

        let total = 45.0 + 17 + 36
        #expect(widths.count == 3)
        #expect(abs(widths[0] - 98 * CGFloat(45 / total)) < 0.001)
        #expect(abs(widths[1] - 98 * CGFloat(17 / total)) < 0.001)
        #expect(abs(widths[2] - 98 * CGFloat(36 / total)) < 0.001)
        // 순서가 그대로다 — 가장 큰 칸이 첫째, 가장 작은 칸이 둘째.
        #expect(widths[0] > widths[2])
        #expect(widths[2] > widths[1])
        #expect(abs(widths.reduce(0, +) - 98) < 0.001)
    }

    /// 그릴 것이 없으면 빈 배열이다 — 0으로 나누지 않는다.
    @Test func 합이_0이면_그리지_않는다() {
        #expect(MacroStackBar.widths([macro("탄수화물", 0), macro("지방", 0)], in: 100).isEmpty)
        #expect(MacroStackBar.widths([], in: 100).isEmpty)
    }

    /// **성한 값만 나가야 한다.** 결과가 그대로 `frame(width:)`로 들어가는데, 음수·무한대·NaN이
    /// 거기 닿으면 레이아웃이 정의되지 않는다.
    @Test func 비정상_입력에도_성한_폭만_내보낸다() {
        // 음수 폭 → 0
        #expect(MacroStackBar.widths([macro("탄수화물", 50)], in: -80) == [0])
        // 무한대 폭 → 0
        #expect(MacroStackBar.widths([macro("탄수화물", 50)], in: .infinity) == [0])
        // NaN·무한대 퍼센트는 그 칸만 0이 되고 나머지 비율은 그대로다.
        let mixed = MacroStackBar.widths(
            [macro("탄수화물", .nan), macro("단백질", 50), macro("지방", .infinity)],
            in: 100
        )
        #expect(mixed == [0, 100, 0])
        #expect(mixed.allSatisfy { $0.isFinite && $0 >= 0 })
        // 전부 비정상이면 그릴 것이 없다.
        #expect(MacroStackBar.widths([macro("탄수화물", .nan)], in: 100).isEmpty)
    }

    /// 간격은 칸 사이에만 들어간다 — 칸 수만큼 빼면 폭이 모자란다.
    @Test func 간격은_칸_사이에만_들어간다() {
        #expect(MacroStackBar.availableWidth(in: 100, count: 3) == 100 - MacroStackBar.spacing * 2)
        #expect(MacroStackBar.availableWidth(in: 100, count: 1) == 100)
        // 폭보다 간격이 크면 음수가 아니라 0이다.
        #expect(MacroStackBar.availableWidth(in: 1, count: 10) == 0)
        #expect(MacroStackBar.availableWidth(in: .infinity, count: 3) == 0)
    }

    /// **아주 얇은 칸에는 숫자를 넣지 않는다.** 억지로 넣으면 줄어들다 못해 이웃을 침범한다.
    @Test func 얇은_칸은_숫자를_담지_못한다() {
        let widths = MacroStackBar.widths(
            [macro("탄수화물", 97), macro("단백질", 2), macro("지방", 1)],
            in: 200
        )
        let minimum = MacroStackBar.baseMinimumLabelWidth

        #expect(MacroStackBar.showsLabel(width: widths[0], minimum: minimum))
        #expect(!MacroStackBar.showsLabel(width: widths[1], minimum: minimum))
        #expect(!MacroStackBar.showsLabel(width: widths[2], minimum: minimum))
    }

    /// **기준이 글자 크기를 따라 커진다.** 고정 26pt였다면 접근성 크기에서 30pt짜리 칸이
    /// 검사를 통과해 놓고도 「100%」를 못 담아 다시 잘린다.
    @Test func 글자가_커지면_기준도_함께_커진다() {
        let width: CGFloat = 30
        #expect(MacroStackBar.showsLabel(width: width, minimum: MacroStackBar.baseMinimumLabelWidth))
        // `@ScaledMetric`이 접근성 크기에서 키운 기준(대략 두 배)에서는 통과하지 못한다.
        #expect(!MacroStackBar.showsLabel(width: width, minimum: MacroStackBar.baseMinimumLabelWidth * 2))
        // 성하지 않은 폭은 어떤 기준에서도 통과하지 못한다.
        #expect(!MacroStackBar.showsLabel(width: .nan, minimum: 0))
    }

    /// `Int(_:)`는 `Int.max`를 넘으면 트랩이다 — 서버 값이라 성한지 알 수 없다.
    @Test func 문구가_비정상_값에_죽지_않는다() {
        #expect(MacroStackBar.labelText(for: 46.4) == "46%")
        #expect(MacroStackBar.labelText(for: -3) == "0%")
        #expect(MacroStackBar.labelText(for: .nan) == "-")
        #expect(MacroStackBar.labelText(for: 1e300) == "1000%")
    }

    /// **숫자를 뺀 칸도 목소리로는 읽혀야 한다.** 막대 전체가 한 요소로 읽힌다.
    @Test func 막대_전체를_한_문장으로_읽어_준다() {
        let text = MacroStackBar.accessibilityText([
            macro("탄수화물", 46), macro("단백질", 17), macro("지방", 37)
        ])

        #expect(text == "탄수화물 46퍼센트, 단백질 17퍼센트, 지방 37퍼센트")

        // 성하지 않은 값에서 숫자만 빠진 문장(「탄수화물 퍼센트」)이 읽히면 안 된다.
        #expect(MacroStackBar.accessibilityText([macro("탄수화물", .nan)]) == "탄수화물 알 수 없음")
    }
}

// MARK: - 서비스 경계

/// **경로·쿼리·본문이 서버 계약과 맞아야 한다.** 어긋나면 실기기에서 400이나 404로만 보이고
/// 앱 로그에는 이유가 안 남는다(`MealTypeChangeServiceTests.경로와_본문이_맞다`와 같은 이유).
struct DietChatServiceTests {
    @Test func 첫_장은_before를_쿼리에서_아예_뺀다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/chat", result: DataResponse(data: ChatPage(messages: [], nextCursor: nil)))
        let service = DietService(api: api)

        _ = try await service.fetchChatPage(before: nil, size: 30)

        let call = try #require(api.getCalls.first)
        #expect(call.path == "/diet/chat")
        #expect(call.query["size"] == "30")
        // **빈 문자열을 보내면 서버가 `Long` 변환에 실패해 400을 준다** — 키 자체가 없어야 한다.
        #expect(call.query["before"] == nil)
    }

    @Test func 다음_장은_커서를_쿼리에_싣는다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/chat", result: DataResponse(data: ChatPage(messages: [], nextCursor: nil)))
        let service = DietService(api: api)

        _ = try await service.fetchChatPage(before: 19, size: 30)

        let call = try #require(api.getCalls.first)
        #expect(call.query["before"] == "19")
    }

    @Test func 질문은_날짜_경로와_message_본문으로_나간다() async throws {
        let api = MockAPIClient()
        api.stubPost(
            "/diet/days/2026-08-06/chat",
            result: DataResponse(data: makeChatMessage(id: 9, role: .assistant, content: "답"))
        )
        let service = DietService(api: api)

        _ = try await service.askChat(date: "2026-08-06", message: "점심 왜 낮아?")

        let call = try #require(api.postCalls.first)
        #expect(call.path == "/diet/days/2026-08-06/chat")
        let body = try #require(call.body as? ChatAskRequest)
        #expect(body.message == "점심 왜 낮아?")
    }

    /// **감싸는 봉투까지 그대로 읽는다.** 서버는 `DataResponseBody`로 한 겹 싸서 준다 —
    /// 안쪽 모양만 맞고 봉투가 어긋나면 실기기에서 빈 화면으로만 보인다.
    @Test func 응답_봉투를_그대로_읽는다() async throws {
        let api = MockAPIClient()
        let json = """
        {"status":200,"message":"성공","data":{"messages":[
          {"id":20,"type":"TEXT","date":"2026-08-06","role":"USER",
           "createdAt":"2026-08-06T09:10:00","content":"점심 왜 낮아?"}
        ],"nextCursor":null}}
        """
        let envelope = try JSONDecoder().decode(DataResponse<ChatPage>.self, from: Data(json.utf8))
        api.stubGet("/diet/chat", result: envelope)
        let service = DietService(api: api)

        let page = try await service.fetchChatPage(before: nil, size: 30)

        #expect(page.nextCursor == nil)
        #expect(page.messages.map(\.content) == ["점심 왜 낮아?"])
    }

    /// 서버 응답을 있는 그대로 디코딩한다. **`createdAt`이 `Date`가 아니라 문자열인 이유가
    /// 여기 있다** — `APIClient`의 디코더에 날짜 전략이 없어 `Date`로 받으면 숫자를 기대하다
    /// 실패한다. 카드 행의 `content`가 null인 것도 함께 못 박는다.
    @Test func 서버_응답_모양을_그대로_읽는다() throws {
        let json = """
        {"messages":[
          {"id":21,"type":"MEAL_CARD","date":"2026-08-01","role":"ASSISTANT",
           "createdAt":"2026-08-03T09:12:33.123456","content":null,
           "meal":{"mealId":7,"mealType":"LUNCH","score":74,
             "scoreBasis":{"standard":"KDRIs","macros":[
               {"name":"탄수화물","percent":46,"rangeMin":50,"rangeMax":65,"status":"UNDER","penalty":4}]},
             "totalKcal":696,"carbsG":80,"proteinG":27,"fatG":29,
             "photoUrl":"https://example.com/1.jpg","feedback":null}},
          {"id":20,"type":"TEXT","date":"2026-08-01","role":"USER",
           "createdAt":"2026-08-03T09:10:00","content":"점심 왜 낮아?"}
        ],"nextCursor":19}
        """
        let page = try JSONDecoder().decode(ChatPage.self, from: Data(json.utf8))

        #expect(page.nextCursor == 19)
        let card = try #require(page.messages.first)
        #expect(card.type == .mealCard)
        #expect(card.content == nil)
        #expect(card.meal?.score == 74)
        // 피드백 생성 중이면 null이다 — 그 자리를 「코치가 보고 있어요」로 채운다.
        #expect(card.meal?.feedback == nil)
        #expect(card.meal?.scoreBasis?.macros.first?.percent == 46)
        // 날짜 구분선이 쓰는 값. 마이크로초가 붙어도 앞 10자를 그대로 읽는다.
        #expect(card.createdAtDay == "2026-08-03")
        #expect(page.messages.last?.content == "점심 왜 낮아?")
    }
}

// MARK: - 빈 상태·조회 실패

@MainActor
struct DietChatEmptyStateTests {
    /// 서버가 배포 전의 끼니·총평에는 카드를 **소급해 만들지 않는다** — 배포 직후에는
    /// 비어 있는 것이 정상이다. 화면이 그때 아무 말도 안 하면 고장으로 읽힌다.
    @Test func 쌓인_것이_없으면_빈_상태다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service)

        await vm.load()

        #expect(vm.isEmpty)
        #expect(!vm.loadFailed)
    }

    /// **조회 실패를 「없음」과 구분한다.** 알럿을 닫고 나면 둘 다 빈 화면이라 사용자는
    /// 대화가 없어진 줄로 읽는다.
    @Test func 조회에_실패하면_빈_상태가_아니라_실패다() async {
        let service = FakeDietService()
        service.errors["fetchChatPage"] = dietServerError("INVALID_REQUEST")
        let vm = makeTodayViewModel(service: service)

        await vm.load()

        #expect(vm.loadFailed)
        #expect(!vm.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test func 다시_시도해서_성공하면_실패_표시가_사라진다() async {
        let service = FakeDietService()
        service.errors["fetchChatPage"] = dietServerError("INVALID_REQUEST")
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        service.errors["fetchChatPage"] = nil
        service.chatPages = [ChatPage(messages: [makeChatMessage()], nextCursor: nil)]
        await vm.reload()

        #expect(!vm.loadFailed)
        #expect(!vm.isEmpty)
        #expect(messageIds(vm.rows) == [1])
    }
}

// MARK: - 모르는 타입

@MainActor
struct DietChatUnknownTypeTests {
    /// 서버가 카드 종류를 늘리면 옛 앱에 모르는 `type`이 내려온다.
    /// **페이지 전체가 비면 빨개진다.**
    @Test func 모르는_타입은_건너뛰고_나머지를_보여준다() async {
        let service = FakeDietService()
        let unknown = try! JSONDecoder().decode(ChatMessage.self, from: Data("""
        {"id":5,"type":"WEIGHT_CARD","date":"2026-08-06","role":"ASSISTANT",
         "createdAt":"2026-08-06T10:00:00","content":null}
        """.utf8))
        service.chatPages = [ChatPage(messages: [
            makeChatMessage(id: 6, createdAt: "2026-08-06T11:00:00"),
            unknown
        ], nextCursor: nil)]
        let vm = DietChatViewModel(service: service, anchorDate: Date.from("2026-08-06")!, day: makeDay())

        await vm.load()

        #expect(unknown.type == .unknown)
        #expect(messageIds(vm.rows) == [6])
    }

    /// 알맹이가 없는 카드도 건너뛴다 — 빈 카드는 서버가 무언가를 빠뜨린 것처럼 읽힌다.
    @Test func 알맹이가_없는_카드는_그리지_않는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [
            makeChatMessage(id: 2),
            makeChatMessage(id: 1, type: .mealCard, role: .assistant, content: nil, meal: nil)
        ], nextCursor: nil)]
        let vm = DietChatViewModel(service: service, anchorDate: Date.from("2026-08-06")!, day: makeDay())

        await vm.load()

        #expect(messageIds(vm.rows) == [2])
    }
}
