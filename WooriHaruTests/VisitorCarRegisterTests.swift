import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarRegisterTests {

    private func makeService(transport: FakeVisitorCarTransport) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀")),
            defaults: UserDefaults(suiteName: "visitorcar.register.\(UUID().uuidString)")!
        )
    }

    private func readyTransport() -> FakeVisitorCarTransport {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/post", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        return transport
    }

    @Test func 차량번호가_비면_보낼_수_없다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))

        #expect(!viewModel.canSubmit)
        // 아직 아무것도 안 쳤을 때는 붉은 글씨를 띄우지 않는다 — 처음부터 혼내지 않는다.
        #expect(viewModel.validationError == nil)
    }

    @Test func 잘못된_차량번호를_짚어준다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))
        viewModel.carNo = "12가 3456"

        #expect(viewModel.validationError == "차량번호에 공백을 넣을 수 없습니다.")
        #expect(!viewModel.canSubmit)
    }

    @Test func 종료일이_앞서면_보낼_수_없다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))
        viewModel.carNo = "12가3456"
        viewModel.endDate = viewModel.startDate.addingTimeInterval(-86_400)

        #expect(viewModel.validationError == "종료일이 시작일보다 앞설 수 없습니다.")
        #expect(!viewModel.canSubmit)
    }

    @Test func 멀쩡하면_보낼_수_있다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))
        viewModel.carNo = "12가3456"

        #expect(viewModel.validationError == nil)
        #expect(viewModel.canSubmit)
    }

    @Test func 등록에_성공하면_성공_표시가_선다() async {
        let transport = readyTransport()
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        await viewModel.submit()

        #expect(viewModel.didSucceed)
        #expect(viewModel.errorMessage == nil)
        #expect(transport.callCount("/book-car/post") == 1)
    }

    /// **거절 문구는 서버 것을 그대로 띄운다.**
    @Test func 거절되면_서버_문구를_띄운다() async {
        let transport = readyTransport()
        transport.stub(
            "/book-car/post",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"잔여 시간이 없습니다."}"#)
        )
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        await viewModel.submit()

        #expect(!viewModel.didSucceed)
        #expect(viewModel.errorMessage == "잔여 시간이 없습니다.")
    }

    /// **동·호를 못 읽으면 등록을 막는다** — 빈 값으로 보내면 다른 세대 이름으로 예약이 들어간다.
    @Test func 세대_정보를_못_읽으면_보내지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok("<html>바뀐 화면</html>"))
        transport.stub("/book-car/post", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        await viewModel.submit()

        #expect(viewModel.errorMessage == "세대 정보를 불러오지 못했습니다.")
        #expect(transport.callCount("/book-car/post") == 0)
    }

    /// 두 번 눌러도 한 번만 나간다.
    @Test func 보내는_중에는_다시_보내지_않는다() async {
        let transport = readyTransport()
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        async let first: Void = viewModel.submit()
        async let second: Void = viewModel.submit()
        _ = await (first, second)

        #expect(transport.callCount("/book-car/post") == 1)
    }

    @Test func 자주_쓰는_차량을_고르면_번호가_채워진다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))

        viewModel.apply(FrequentCar(nickname: "아빠차", carNo: "12가3456"))

        #expect(viewModel.carNo == "12가3456")
    }
}
