import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarBookingsTests {

    private static let path = "/web/book-car/pageList"

    private func page(ids: [Int], totalPages: Int, number: Int) -> String {
        let content = ids.map {
            """
            {"id":\($0),"compName":"1001","deptName":"0101","name":"","carNo":"12가3456",
             "tel":"","startDate":1784300400,"endDate":1784386799,"updateDate":1784356046,
             "userName":"10010101","insertType":"W","address":""}
            """
        }.joined(separator: ",")
        return """
        {"data":{"content":[\(content)],"totalElements":\(ids.count * totalPages),
          "totalPages":\(totalPages),"number":\(number),"size":10,
          "first":\(number == 0),"last":\(number == totalPages - 1)}}
        """
    }

    private func makeService(transport: FakeVisitorCarTransport) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀")),
            defaults: UserDefaults(suiteName: "visitorcar.bookings.\(UUID().uuidString)")!
        )
    }

    /// 기본 범위는 **오늘부터 한 달 뒤까지** — 방문 예약은 앞날을 잡는 일이다.
    @Test func 기본_조회_범위는_오늘부터_한_달이다() throws {
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: FakeVisitorCarTransport()))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!

        let expected = calendar.date(byAdding: .month, value: 1, to: viewModel.from)
        #expect(calendar.isDate(viewModel.to, inSameDayAs: try #require(expected)))
    }

    /// 선택기가 기간을 역전으로 둘 수 있다(`in:` 제약이 없다). 역전 기간을 서버로 보내면
    /// 오류나 빈 목록으로 「등록 내역이 사라졌다」는 오해를 산다 — 여기서 먼저 막는다.
    @Test func 시작일이_종료일보다_뒤면_조회하지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1], totalPages: 1, number: 0)))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()
        #expect(viewModel.bookings.map(\.id) == [1])
        let callsBefore = transport.callCount(Self.path)

        viewModel.from = Date(timeIntervalSince1970: 1784300400) // 2026-07-18
        viewModel.to = viewModel.from.addingTimeInterval(-86_400) // 2026-07-17
        await viewModel.search()

        #expect(viewModel.errorMessage == "종료일이 시작일보다 앞설 수 없습니다.")
        #expect(transport.callCount(Self.path) == callsBefore)
        // 검증 실패는 실패한 조회와 같은 규칙이다 — 보고 있던 목록을 지우지 않는다.
        #expect(viewModel.bookings.map(\.id) == [1])
    }

    @Test func 조회하면_목록을_채운다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()

        #expect(viewModel.bookings.map(\.id) == [1, 2])
        #expect(!viewModel.hasMore)
        #expect(viewModel.errorMessage == nil)
    }

    /// **더 보기**는 앞의 것을 지우지 않고 뒤에 잇는다.
    @Test func 더_보기는_뒤에_잇는다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 2, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [3, 4], totalPages: 2, number: 1)))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()
        #expect(viewModel.hasMore)

        await viewModel.loadMore()

        #expect(viewModel.bookings.map(\.id) == [1, 2, 3, 4])
        #expect(!viewModel.hasMore)
    }

    /// 다시 조회하면 **처음부터** 채운다 — 이어 붙이면 조건이 바뀐 결과와 섞인다.
    @Test func 다시_조회하면_처음부터_채운다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 2, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [3, 4], totalPages: 2, number: 1)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [9], totalPages: 1, number: 0)))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()
        await viewModel.loadMore()
        await viewModel.search()

        #expect(viewModel.bookings.map(\.id) == [9])
    }

    @Test func 삭제하면_목록에서_빠진다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        // 삭제 뒤에는 `delete(id:)`가 0쪽을 다시 읽는다 — 서버에서도 실제로 빠진
        // 상태를 흉내 낸다. 여기서 응답을 그대로 두면(같은 [1, 2]) 재조회가 지운
        // 줄을 되살려 버려 아래 단언이 실패한다.
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [2], totalPages: 1, number: 0)))
        transport.stub("/book-car/delete", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let deleted = await viewModel.delete(id: 1)

        #expect(deleted)
        #expect(viewModel.bookings.map(\.id) == [2])
    }

    /// **회귀 시험.** 서버는 offset으로 페이지를 나눈다 — 0쪽만 불러온 상태에서 지우면
    /// 아직 못 읽은 1쪽의 맨 앞 레코드가 0쪽 끝으로 한 칸 밀린다. `loadMore()`는 여전히
    /// `loadedPage + 1`(=1쪽)을 요청하므로, `await search()`로 0쪽부터 다시 맞추지
    /// 않으면 밀려온 레코드(여기서는 11번)는 어느 페이지 요청에도 걸리지 않고 사라진다.
    /// `delete(id:)`에서 `await search()`를 지우면 이 시험은 실패한다.
    @Test func 삭제하면_페이지매김을_0쪽부터_다시_맞춘다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: Array(1...10), totalPages: 2, number: 0)))
        // 삭제 뒤 재조회 — 1번이 빠지고, 1쪽 맨 앞이던 11번이 0쪽 끝으로 밀려온
        // 상태를 흉내 낸다.
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: Array(2...11), totalPages: 2, number: 0)))
        transport.stub("/book-car/delete", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()
        #expect(viewModel.hasMore)

        let deleted = await viewModel.delete(id: 1)

        #expect(deleted)
        // 0쪽 조회가 한 번 더 나갔다 — 삭제만으로 페이지매김을 손으로 기우지 않는다.
        #expect(transport.callCount(Self.path) == 2)
        // 11번은 삭제 전엔 1쪽에 있었다. 재조회 없이는 이 자리에 나타날 수 없다.
        #expect(viewModel.bookings.map(\.id) == Array(2...11))
    }

    /// **입차 후에는 서버가 거절한다.** 앱이 그 조건을 흉내 내지 않고, 거절 문구를 그대로 띄운다.
    /// 거절이면 지운 게 없으니 재조회로 페이지매김을 다시 맞출 이유도 없다 — 조회 호출이
    /// 늘지 않아야 한다.
    @Test func 삭제가_거절되면_목록을_건드리지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.stub(
            "/book-car/delete",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"입차 후 삭제 불가능합니다."}"#)
        )
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()
        let callsBefore = transport.callCount(Self.path)

        let deleted = await viewModel.delete(id: 1)

        #expect(!deleted)
        #expect(transport.callCount(Self.path) == callsBefore)
        #expect(viewModel.bookings.map(\.id) == [1, 2])
        #expect(viewModel.errorMessage == "입차 후 삭제 불가능합니다.")
    }

    /// `hasMore`가 이전 조회에서 켜진 채로 남으면, 실패한 재조회의 빈 목록 위에
    /// 「더 보기」가 남아 다음 페이지를 잘못 건너뛴다. 재조회는 `hasMore`도 되돌려야 한다.
    @Test func 재조회가_실패하면_hasMore를_되돌린다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 2, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok("{}"))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()
        #expect(viewModel.hasMore)

        // 조건을 바꾸고 재조회한다 — 이번엔 서버 응답이 깨져서 실패한다.
        // **과거로 되돌리지 않는다** — 기간 검증이 먼저 막아 서버까지 가지 않으면
        // 이 테스트가 확인하려는 「깨진 응답이 hasMore를 되돌리는지」를 시험할 수 없다.
        viewModel.to = viewModel.to.addingTimeInterval(86_400)
        await viewModel.search()

        #expect(!viewModel.hasMore)
        #expect(viewModel.errorMessage != nil)
    }

    /// 재조회가 실패했다고 **목록을 비워서는 안 된다** — 수정 성공 뒤 재조회가 일시적으로
    /// 끊기면, 저장은 됐는데 목록이 텅 비어 보이는 상황이 생긴다.
    @Test func 재조회가_실패해도_이전_목록을_그대로_둔다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok("{}"))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()
        #expect(viewModel.bookings.map(\.id) == [1, 2])

        // 조건을 바꾸고 재조회한다 — 이번엔 서버 응답이 깨져서 실패한다.
        // **과거로 되돌리지 않는다** — 기간 검증이 먼저 막아 서버까지 가지 않으면
        // 이 테스트가 확인하려는 「깨진 응답이 목록을 지우지 않는지」를 시험할 수 없다.
        viewModel.to = viewModel.to.addingTimeInterval(86_400)
        await viewModel.search()

        #expect(viewModel.bookings.map(\.id) == [1, 2])
        #expect(viewModel.errorMessage != nil)
    }

    @Test func 수정에_성공하면_목록을_다시_읽는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1], totalPages: 1, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/put", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let day = Date(timeIntervalSince1970: 1784300400)
        let updated = await viewModel.update(
            id: 1, carNo: "34나5678", startDate: day, endDate: day, visitReason: "택배"
        )

        #expect(updated)
        // 수정 결과를 손으로 기워 넣지 않는다 — 서버가 무엇을 바꿨는지 다시 읽어 확인한다.
        #expect(viewModel.bookings.map(\.id) == [1, 2])

        let sent = try #require(transport.formFields.last(where: { $0.path == "/book-car/put" })?.fields)
        #expect(sent["id"] == "1")
        #expect(sent["carNo"] == "34나5678")
    }

    /// **입차 후에는 서버가 거절한다.** 문구를 그대로 띄우고 목록은 건드리지 않는다.
    @Test func 수정이_거절되면_목록을_건드리지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1], totalPages: 1, number: 0)))
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub(
            "/book-car/put",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"입차 후 수정 불가능합니다."}"#)
        )
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let day = Date(timeIntervalSince1970: 1784300400)
        let updated = await viewModel.update(
            id: 1, carNo: "34나5678", startDate: day, endDate: day, visitReason: ""
        )

        #expect(!updated)
        #expect(viewModel.errorMessage == "입차 후 수정 불가능합니다.")
        #expect(viewModel.bookings.map(\.carNo) == ["12가3456"])
    }

    /// 검증은 등록 화면과 같은 규칙이다 — 잘못된 번호를 서버까지 보내지 않는다.
    @Test func 잘못된_차량번호로는_수정하지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1], totalPages: 1, number: 0)))
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/put", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let day = Date(timeIntervalSince1970: 1784300400)
        let updated = await viewModel.update(
            id: 1, carNo: "34나 5678", startDate: day, endDate: day, visitReason: ""
        )

        #expect(!updated)
        #expect(viewModel.errorMessage == "차량번호에 공백을 넣을 수 없습니다.")
        #expect(transport.callCount("/book-car/put") == 0)
    }
}
