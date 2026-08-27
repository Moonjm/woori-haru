import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarHomeTests {

    private func makeService(
        transport: FakeVisitorCarTransport,
        credentials: VisitorCarCredentials? = VisitorCarCredentials(id: "10010101", password: "비밀")
    ) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: credentials),
            defaults: UserDefaults(suiteName: "visitorcar.home.\(UUID().uuidString)")!
        )
    }

    // MARK: - 문구

    /// 참고 화면의 「100시간 0분 남음」과 같은 꼴.
    @Test func 잔여시간을_시간과_분으로_적는다() {
        #expect(VisitorCarHomeViewModel.remainingText(minutes: 6000) == "100시간 0분 남음")
        #expect(VisitorCarHomeViewModel.remainingText(minutes: 90) == "1시간 30분 남음")
        #expect(VisitorCarHomeViewModel.remainingText(minutes: 0) == "0시간 0분 남음")
    }

    /// **음수는 「남음」이 아니다.** 웹도 「N분 초과 사용하였습니다」로 갈라 말한다.
    @Test func 초과분은_다르게_적는다() {
        #expect(VisitorCarHomeViewModel.remainingText(minutes: -120) == "2시간 0분 초과")
        #expect(VisitorCarHomeViewModel.remainingText(minutes: -5) == "0시간 5분 초과")
    }

    // MARK: - 상태

    @Test func 저장된_계정이_없으면_로그인이_필요하다() async {
        let transport = FakeVisitorCarTransport()
        // 쿠키가 없으면 사이트는 **302로 로그인 페이지를 가리킨다.** 여기까지 와야
        // 서비스가 「저장된 계정이 없다」를 알아챈다.
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        let viewModel = VisitorCarHomeViewModel(
            service: makeService(transport: transport, credentials: nil)
        )

        await viewModel.load()

        #expect(viewModel.state == .needsLogin)
    }

    @Test func 잔여시간을_읽어_보여준다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        let viewModel = VisitorCarHomeViewModel(service: makeService(transport: transport))

        await viewModel.load()

        #expect(viewModel.state == .ready(minutes: 6000))
    }

    /// 세션이 끊겼는데 재로그인도 안 되면 **로그인 카드로 되돌린다.**
    @Test func 세션이_끊기면_로그인_카드로_되돌린다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let viewModel = VisitorCarHomeViewModel(service: makeService(transport: transport))

        await viewModel.load()

        #expect(viewModel.state == .needsLogin)
    }

    /// **`loginUnavailable`은 `needsLogin`으로 접지 않는다.** 자격증명은 서비스 쪽에서
    /// 지워지지 않고 남아 있으므로(R1), 로그인 카드로 되돌리면 있는 계정으로 다시
    /// 로그인하라고 요구하는 모양이 된다 — `failed`로 두어야 재시도가 자연스럽다.
    @Test func 재로그인_응답을_판단할_수_없으면_로그인_카드로_접지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", VisitorCarHTTPResponse(status: 500, location: nil, body: Data()))
        let viewModel = VisitorCarHomeViewModel(service: makeService(transport: transport))

        await viewModel.load()

        #expect(viewModel.state == .failed(VisitorCarError.loginUnavailable.localizedDescription ?? ""))
    }

    /// 마크업이 바뀐 경우는 로그인 문제가 아니다 — 카드를 지우지 않고 오류만 띄운다.
    @Test func 파싱이_깨지면_실패로_남는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.ok("<html>바뀐 화면</html>"))
        let viewModel = VisitorCarHomeViewModel(service: makeService(transport: transport))

        await viewModel.load()

        #expect(viewModel.state == .failed("잔여시간을 불러오지 못했습니다."))
    }

    // MARK: - 로그인

    @Test func 로그인에_성공하면_잔여시간을_읽는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        transport.stub("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        let viewModel = VisitorCarHomeViewModel(
            service: makeService(transport: transport, credentials: nil)
        )

        await viewModel.login(id: "10010101", password: "비밀")

        #expect(viewModel.state == .ready(minutes: 6000))
        #expect(viewModel.loginError == nil)
    }

    /// **서버가 준 한국어를 그대로 띄운다.**
    @Test func 로그인_실패_문구를_그대로_띄운다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginFailure(message: "아이디 또는 비밀번호가 잘못되었습니다."))
        let viewModel = VisitorCarHomeViewModel(
            service: makeService(transport: transport, credentials: nil)
        )

        await viewModel.login(id: "10010101", password: "틀린것")

        #expect(viewModel.loginError == "아이디 또는 비밀번호가 잘못되었습니다.")
        #expect(viewModel.state == .needsLogin)
    }

    /// **P1.** 로그인 도중 로그아웃이 끼어들면 서비스가 결과를 버리고 `notLoggedIn`을
    /// 던진다(`VisitorCarSessionTests`가 서비스 쪽을 결정론적으로 확인한다). 여기서는
    /// 그 신호를 뷰모델이 오류 문구 없이 로그인 카드로 접는지만 본다 — `FakeVisitorCarServing`으로
    /// 실제 재진입 경쟁을 재현할 필요 없이 서비스의 결과만 손으로 정한다.
    @Test func 로그인_도중_로그아웃하면_오류_문구_없이_로그인_카드로_남는다() async {
        let service = FakeVisitorCarServing()
        service.loginError = VisitorCarError.notLoggedIn
        let viewModel = VisitorCarHomeViewModel(service: service)

        await viewModel.login(id: "10010101", password: "비밀")

        #expect(viewModel.state == .needsLogin)
        #expect(viewModel.loginError == nil)
        #expect(service.loginCallCount == 1)
    }
}
