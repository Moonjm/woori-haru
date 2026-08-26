import Foundation

/// 대상 사이트 주소. **HTTP다** — `Info.plist`의 ATS 예외가 이 호스트에 걸려 있다.
enum VisitorCarSite {
    static let host = "dasanesesang.iptime.org"
    static let base = "http://\(host)/nxpmsc"

    static func url(path: String) -> URL? {
        URL(string: base + path)
    }
}

/// 한 번의 왕복 결과. **302를 그대로 들고 온다** — 따라가지 않는 것이 이 계층의 요점이다.
struct VisitorCarHTTPResponse: Sendable {
    let status: Int
    let location: String?
    let body: Data

    var text: String { String(decoding: body, as: UTF8.self) }

    /// 세션이 끊겼는가. 사이트는 **401을 주지 않는다** — JSON 엔드포인트까지
    /// 302로 로그인 페이지를 가리킨다. 상대 경로로 올 수도 있어 경로만 본다.
    var isLoginRedirect: Bool {
        guard status == 302, let location else { return false }
        let path = URLComponents(string: location)?.path ?? location
        // `;jsessionid=…`가 경로에 붙어 오므로 정확히 같기를 요구하지 않는다.
        // 다만 `book-car/login-history` 같은 것을 삼키지 않도록 접두만 본다.
        return path == "/nxpmsc/login" || path.hasPrefix("/nxpmsc/login;")
    }
}

/// 사이트를 두드리는 저수준 계층. **테스트는 이 자리를 가짜로 바꾼다.**
protocol VisitorCarTransport: Sendable {
    /// `application/x-www-form-urlencoded` POST. 로그인·등록·수정·삭제가 이 모양이다.
    func form(path: String, fields: [String: String]) async throws -> VisitorCarHTTPResponse
    /// JSON POST. 목록 조회 둘이 이 모양이다.
    func json(path: String, body: any Encodable & Sendable) async throws -> VisitorCarHTTPResponse
    /// HTML GET. 잔여시간을 긁을 때 쓴다.
    func page(path: String) async throws -> VisitorCarHTTPResponse
    /// 로그아웃 — 쿠키를 버린다.
    func clearCookies() async
}

/// **리다이렉트를 따라가지 않게 막는 델리게이트. 이게 이 계층의 핵심이다.**
///
/// `URLSession`은 기본으로 302를 따라가는데, 그러면 세션이 끊겼을 때 로그인 **HTML이
/// 200으로** 돌아온다. JSON 디코딩이 실패하면서 「파싱 오류」로 보이고 진짜 원인은
/// 어디에도 안 남는다. `nil`을 돌려주면 302가 응답 그대로 손에 들어온다.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

final class VisitorCarHTTPTransport: VisitorCarTransport {
    private let session: URLSession
    private let delegate = NoRedirectDelegate()

    init() {
        // **`.ephemeral`이다.** 쿠키가 이 세션 안에만 살아서 앱 공용 저장소
        // (`SessionManager`가 쓰는 `.shared`)와 자동으로 갈린다 — 남의 사이트
        // `JSESSIONID`가 거기 섞이면 두 세션의 수명이 서로 얽힌다.
        // 앱을 껐다 켜면 쿠키가 사라지지만, 자격증명이 Keychain에 있어 조용히 다시 붙는다.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func form(path: String, fields: [String: String]) async throws -> VisitorCarHTTPResponse {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = VisitorCarFormEncoder.encode(fields)
        // **바디를 로그에 찍지 않는다** — 로그인 필드에 비밀번호가 들어 있다.
        return try await send(request)
    }

    func json(path: String, body: any Encodable & Sendable) async throws -> VisitorCarHTTPResponse {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    func page(path: String) async throws -> VisitorCarHTTPResponse {
        var request = try makeRequest(path: path)
        request.httpMethod = "GET"
        return try await send(request)
    }

    func clearCookies() async {
        guard let storage = session.configuration.httpCookieStorage else { return }
        storage.removeCookies(since: .distantPast)
    }

    // MARK: - Private

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = VisitorCarSite.url(path: path) else {
            throw VisitorCarError.network("주소가 잘못되었습니다.")
        }
        var request = URLRequest(url: url)
        // 서버가 `X-Requested-With`를 보고 갈래를 바꾸지는 않지만, DataTables가
        // 보내는 것과 같은 모양을 유지해 두면 나중에 갈렸을 때 원인을 좁히기 쉽다.
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return request
    }

    private func send(_ request: URLRequest) async throws -> VisitorCarHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw VisitorCarError.network("응답을 읽지 못했습니다.")
            }
            return VisitorCarHTTPResponse(
                status: http.statusCode,
                location: http.value(forHTTPHeaderField: "Location"),
                body: data
            )
        } catch let error as VisitorCarError {
            throw error
        } catch {
            throw VisitorCarError.network(error.localizedDescription)
        }
    }
}
