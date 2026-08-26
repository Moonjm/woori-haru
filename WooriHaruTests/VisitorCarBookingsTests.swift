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
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.stub("/book-car/delete", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let deleted = await viewModel.delete(id: 1)

        #expect(deleted)
        #expect(viewModel.bookings.map(\.id) == [2])
    }

    /// **입차 후에는 서버가 거절한다.** 앱이 그 조건을 흉내 내지 않고, 거절 문구를 그대로 띄운다.
    @Test func 삭제가_거절되면_목록을_건드리지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.stub(
            "/book-car/delete",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"입차 후 삭제 불가능합니다."}"#)
        )
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let deleted = await viewModel.delete(id: 1)

        #expect(!deleted)
        #expect(viewModel.bookings.map(\.id) == [1, 2])
        #expect(viewModel.errorMessage == "입차 후 삭제 불가능합니다.")
    }
}
