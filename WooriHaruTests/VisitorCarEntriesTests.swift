import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarEntriesTests {

    private static let path = "/web/car/reserved-vehicle-entry-status-by-generation-page"

    private func makeService(transport: FakeVisitorCarTransport) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀")),
            defaults: UserDefaults(suiteName: "visitorcar.entries.\(UUID().uuidString)")!
        )
    }

    private static let onePage = """
    {"message":"200","data":{"content":[
      {"id":354751,"inDate":1784357197,"outDate":1784374505,"outChk":2,
       "carNo":"12가3456","name":"","startDate":1784300400,"endDate":1784386799,
       "updateDate":1784356046}],
      "totalElements":1,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
    """

    /// **마지막 쪽이 아니다** — `hasMore`가 재조회 실패로 되돌아가는지 보려면
    /// 실패 전에 켜져 있어야 뜻이 있다.
    private static let pageWithMore = """
    {"message":"200","data":{"content":[
      {"id":354751,"inDate":1784357197,"outDate":null,"outChk":0,
       "carNo":"12가3456","name":"","startDate":1784300400,"endDate":1784386799,
       "updateDate":1784356046}],
      "totalElements":20,"totalPages":2,"number":0,"size":10,"first":true,"last":false}}
    """

    // MARK: - 문구

    @Test func 주차시간을_시간과_분으로_적는다() {
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: 3600) == "1시간 0분")
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: 5_400) == "1시간 30분")
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: 59) == "0시간 0분")
    }

    /// 시계가 어긋나 음수가 나와도 「-1시간」을 띄우지 않는다.
    @Test func 음수_주차시간은_0으로_접는다() {
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: -600) == "0시간 0분")
    }

    // MARK: - 조회

    /// 기본 범위는 **오늘 하루**다 — 지금 들어와 있는지가 이 화면의 질문이다.
    @Test func 기본_조회_범위는_오늘_하루다() {
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: FakeVisitorCarTransport()))

        #expect(VisitorCarDateFormat.second.string(from: viewModel.from).hasSuffix("00:00:00"))
        #expect(VisitorCarDateFormat.second.string(from: viewModel.to).hasSuffix("23:59:59"))
    }

    /// 선택기가 기간을 역전으로 둘 수 있다(`in:` 제약이 없다). 역전 기간을 서버로 보내면
    /// 오류나 빈 목록으로 「입출차 내역이 사라졌다」는 오해를 산다 — 여기서 먼저 막는다.
    @Test func 시작일이_종료일보다_뒤면_조회하지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(Self.onePage))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))
        await viewModel.search()
        #expect(viewModel.entries.map(\.id) == [354751])
        let callsBefore = transport.callCount(Self.path)

        viewModel.from = Date(timeIntervalSince1970: 1784300400) // 2026-07-18
        viewModel.to = viewModel.from.addingTimeInterval(-86_400) // 2026-07-17
        await viewModel.search()

        #expect(viewModel.errorMessage == "종료일이 시작일보다 앞설 수 없습니다.")
        #expect(transport.callCount(Self.path) == callsBefore)
        // 검증 실패는 실패한 조회와 같은 규칙이다 — 보고 있던 목록을 지우지 않는다.
        #expect(viewModel.entries.map(\.id) == [354751])
    }

    @Test func 조회하면_목록을_채운다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(Self.onePage))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))

        await viewModel.search()

        #expect(viewModel.entries.map(\.id) == [354751])
        #expect(viewModel.entries[0].status == .exited)
        #expect(!viewModel.hasMore)
    }

    /// **F3 회귀.** 조회 뒤 사용자가 다음 조회를 위해 픽커만 미리 바꿔 둘 수 있다(조회
    /// 버튼은 안 누른 채). 「더 보기」는 그 새 값이 아니라 **방금 조회했던 기간**의
    /// 다음 페이지를 이어야 한다 — 자매 화면(등록 내역 조회)과 같은 회귀다.
    @Test func 더_보기는_조회_뒤_바뀐_픽커가_아니라_제출한_기간을_쓴다() async throws {
        let secondPage = """
        {"message":"200","data":{"content":[
          {"id":999999,"inDate":1784357197,"outDate":null,"outChk":0,
           "carNo":"34나5678","name":"","startDate":1784300400,"endDate":1784386799,
           "updateDate":1784356046}],
          "totalElements":20,"totalPages":2,"number":1,"size":10,"first":false,"last":true}}
        """
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(Self.pageWithMore))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(secondPage))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))
        let submittedFrom = viewModel.from
        let submittedTo = viewModel.to

        await viewModel.search()
        #expect(viewModel.hasMore)

        // 조회 버튼은 안 누른 채, 픽커만 완전히 다른 날(2026년 10월 즈음)로 바꿔 둔다.
        viewModel.from = Date(timeIntervalSince1970: 1_790_000_000)
        viewModel.to = Date(timeIntervalSince1970: 1_790_100_000)

        await viewModel.loadMore()

        // 방금 조회했던 기간의 다음 페이지가 이어 붙었다 — 픽커의 새 기간과 섞이지 않는다.
        #expect(viewModel.entries.map(\.id) == [354751, 999999])

        let secondRequest = try #require(transport.jsonBodies.filter { $0.path == Self.path }.dropFirst().first)
        let sent = try #require(try JSONSerialization.jsonObject(with: secondRequest.body) as? [String: Any])
        #expect(sent["startDate"] as? String == VisitorCarDateFormat.second.string(from: submittedFrom))
        #expect(sent["endDate"] as? String == VisitorCarDateFormat.second.string(from: submittedTo))
    }

    /// **아직 안 나간 차는 시간이 흘러야 한다.** `tick()`이 기준 시각을 밀어 준다.
    @Test func tick하면_기준_시각이_지금으로_바뀐다() {
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: FakeVisitorCarTransport()))
        let before = viewModel.now

        viewModel.tick()

        #expect(viewModel.now >= before)
    }

    @Test func 조회에_실패하면_문구를_남긴다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok("깨진 응답"))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))

        await viewModel.search()

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.errorMessage == "응답을 읽지 못했습니다.")
    }

    /// 재조회가 실패했다고 **목록을 비워서는 안 된다** — 자매 화면(예약 조회)과 같은 이유다.
    @Test func 재조회가_실패해도_이전_목록을_그대로_둔다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(Self.onePage))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok("깨진 응답"))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))

        await viewModel.search()
        #expect(viewModel.entries.map(\.id) == [354751])

        await viewModel.search()

        #expect(viewModel.entries.map(\.id) == [354751])
        #expect(viewModel.errorMessage != nil)
    }

    /// `hasMore`가 이전 조회에서 켜진 채로 남으면, 실패한 재조회의 목록 위에
    /// 「더 보기」가 남아 다음 페이지를 잘못 건너뛴다.
    @Test func 재조회가_실패하면_hasMore를_되돌린다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(Self.pageWithMore))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok("깨진 응답"))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))

        await viewModel.search()
        #expect(viewModel.hasMore)

        await viewModel.search()

        #expect(!viewModel.hasMore)
    }
}
