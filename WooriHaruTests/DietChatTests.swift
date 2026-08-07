import Foundation
import Testing
@testable import WooriHaru

// MARK: - 행 읽기 도우미

private func separatorDays(_ rows: [ChatRow]) -> [String] {
    rows.compactMap { row -> String? in
        guard case .dateSeparator(let day) = row else { return nil }
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
    @Test func 기록이_없는_날은_입력창이_잠기고_칩이_안_뜬다() async {
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
        service.errors["askChat"] = APIError.networkError(URLError(.timedOut))
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

        #expect(!canRetryOnly(vm))
    }

    /// 네트워크가 끊긴 것은 일시적이다.
    @Test func 네트워크_실패에는_다시_시도가_붙는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        service.errors["askChat"] = APIError.networkError(URLError(.notConnectedToInternet))
        let vm = makeTodayViewModel(service: service)
        await vm.load()

        await vm.send("점심 왜 낮아?")

        #expect(canRetryOnly(vm))
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
