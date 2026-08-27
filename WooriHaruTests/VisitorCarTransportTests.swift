import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarTransportTests {

    private func response(status: Int, location: String?) -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: status, location: location, body: Data())
    }

    /// **세션 만료가 401로 오지 않는다.** 302 + `Location: …/nxpmsc/login`이다.
    /// 이걸 못 가리면 로그인 HTML을 JSON으로 읽으려다 「파싱 오류」로 둔갑한다.
    @Test func 로그인_리다이렉트를_알아본다() {
        let expired = response(
            status: 302,
            location: "http://dasanesesang.iptime.org/nxpmsc/login;jsessionid=ABC?result=x"
        )
        #expect(expired.isLoginRedirect)
    }

    /// 로그인 **성공**도 302다. 여기로 가면 세션이 살아 있다는 뜻이다.
    @Test func 성공_리다이렉트는_로그인이_아니다() {
        let ok = response(status: 302, location: "http://dasanesesang.iptime.org/nxpmsc/book-car")
        #expect(!ok.isLoginRedirect)
    }

    @Test func 이백_응답은_로그인이_아니다() {
        #expect(!response(status: 200, location: nil).isLoginRedirect)
    }

    /// `Location`이 상대 경로로 올 수도 있다 — 스프링 버전에 따라 갈린다.
    @Test func 상대경로_리다이렉트도_알아본다() {
        #expect(response(status: 302, location: "/nxpmsc/login").isLoginRedirect)
    }

    /// `book-car`가 경로 **뒤쪽**에 들어간 주소를 로그인으로 오해하면 안 된다.
    @Test func 로그인이_아닌_경로를_오해하지_않는다() {
        #expect(!response(status: 302, location: "/nxpmsc/book-car/login-history").isLoginRedirect)
    }

    /// **`URLComponents`가 파싱하지 못하면 fail-closed다.** 파싱 실패를 「로그인 리다이렉트가
    /// 아니다」로 읽으면, 로그인 중에는 틀린 자격증명이 성공으로 둔갑해 Keychain에 저장된다.
    /// `http://[invalid...`는 `URLComponents(string:)`가 통째로 `nil`을 돌려주는 자리다.
    @Test func 파싱_실패한_리다이렉트도_원문에서_로그인을_알아본다() {
        let malformed = "http://[invalid/nxpmsc/login"
        #expect(URLComponents(string: malformed) == nil)
        #expect(response(status: 302, location: malformed).isLoginRedirect)
    }

    @Test func 본문을_문자열로_읽는다() {
        let html = VisitorCarHTTPResponse(status: 200, location: nil, body: Data("<html>가</html>".utf8))
        #expect(html.text == "<html>가</html>")
    }

    /// 경로를 컨텍스트에 붙여 절대 URL을 만든다. `/web` 갈래도 같은 규칙이다.
    @Test func 사이트_경로를_만든다() {
        #expect(VisitorCarSite.url(path: "/do-login")?.absoluteString
                == "http://dasanesesang.iptime.org/nxpmsc/do-login")
        #expect(VisitorCarSite.url(path: "/web/book-car/pageList")?.absoluteString
                == "http://dasanesesang.iptime.org/nxpmsc/web/book-car/pageList")
    }
}
