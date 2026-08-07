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

/// 앵커가 오늘인 뷰모델. 잠금·칩·전송 테스트가 쓴다 — 「오늘」 판정이 `Calendar`에 달려 있어
/// 고정 날짜로는 재현할 수 없다.
@MainActor
private func makeTodayViewModel(
    service: FakeDietService,
    meals: [Meal]? = nil,
    nutrientLimits: [NutrientLimit]? = nil
) -> DietChatViewModel {
    let today = Date().dateString
    let day = makeDay(
        date: today,
        meals: meals ?? [makeMeal(date: today)],
        nutrientLimits: nutrientLimits
    )
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

        #expect(vm.pending?.text == "점심 왜 낮아?")
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

        #expect(vm.pending == nil)
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

        #expect(vm.pending?.text == "점심 왜 낮아?")
        #expect(vm.pending?.failed == true)
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
        await vm.retry()

        #expect(service.askedChats.map(\.message) == ["점심 왜 낮아?", "점심 왜 낮아?"])
        #expect(vm.pending == nil)
        #expect(vm.messages.map(\.content) == ["점심 왜 낮아?", "나트륨이 기준을 넘었어요"])
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
        #expect(vm.suggestedQuestions.isEmpty)
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
        #expect(vm.pending == nil)
    }

    @Test func 주의_영양소가_있으면_그_이름이_든_칩이_생긴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service, nutrientLimits: [
            NutrientLimit(name: "당류", intake: 40, unit: "g", standardText: "125g 이하", status: .ok),
            NutrientLimit(name: "나트륨", intake: 3200, unit: "mg", standardText: "2,300mg 이하", status: .warn)
        ])

        await vm.load()

        #expect(vm.suggestedQuestions.contains("나트륨이 왜 높아?"))
    }

    /// 식이섬유는 **모자라서** `WARN`이다 — 「왜 높아?」로 물으면 거짓말이 된다.
    @Test func 하한_기준_영양소는_부족한지를_묻는다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let vm = makeTodayViewModel(service: service, nutrientLimits: [
            NutrientLimit(name: "식이섬유", intake: 8, unit: "g", standardText: "30g 이상", status: .warn)
        ])

        await vm.load()

        #expect(vm.suggestedQuestions.contains("식이섬유가 왜 부족해?"))
    }

    @Test func 점수가_가장_낮은_끼니의_칩이_생긴다() async {
        let service = FakeDietService()
        service.chatPages = [ChatPage(messages: [], nextCursor: nil)]
        let today = Date().dateString
        let vm = makeTodayViewModel(service: service, meals: [
            makeMeal(id: 1, date: today, mealType: .lunch, score: 47),
            makeMeal(id: 2, date: today, mealType: .dinner, score: 82)
        ])

        await vm.load()

        #expect(vm.suggestedQuestions.contains("점심이 왜 47점이야?"))
        #expect(!vm.suggestedQuestions.contains("저녁이 왜 82점이야?"))
    }

    /// 앵커가 오늘이면 칩을 띄우는 데 새 호출이 들지 않는다 — 화면이 하루를 넘겨준다.
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
