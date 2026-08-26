import Foundation
@testable import WooriHaru

/// 경로별 응답을 미리 쌓아 두고 호출을 기록하는 통신 대역.
/// 같은 경로에 여러 응답을 넣으면 부른 순서대로 하나씩 꺼내 준다 —
/// 「처음엔 302, 재로그인 뒤엔 200」을 그려야 해서 큐가 필요하다.
final class FakeVisitorCarTransport: VisitorCarTransport, @unchecked Sendable {
    enum FakeError: Error { case unstubbed(String) }

    private let lock = NSLock()
    private var queues: [String: [VisitorCarHTTPResponse]] = [:]
    private var lastResponses: [String: VisitorCarHTTPResponse] = [:]
    private var sessionAware = false
    private var loggedIn = false
    private(set) var calls: [String] = []
    private(set) var formFields: [(path: String, fields: [String: String])] = []
    private(set) var jsonBodies: [(path: String, body: Data)] = []
    private(set) var clearCookiesCount = 0

    /// 부를 때마다 하나씩 꺼낸다. 큐가 비면 마지막 응답을 되풀이한다.
    func enqueue(_ path: String, _ response: VisitorCarHTTPResponse) {
        lock.withLock { queues[path, default: []].append(response) }
    }

    /// 몇 번을 불러도 같은 응답.
    func stub(_ path: String, _ response: VisitorCarHTTPResponse) {
        lock.withLock { lastResponses[path] = response }
    }

    /// **세션을 흉내 낸다.** 켜 두면 로그인 전에는 무엇을 불러도 302로 튕기고,
    /// `/do-login`이 성공한 뒤에는 등록된 응답이 나간다 — 실제 사이트가 그렇게 움직인다.
    /// 동시성 테스트는 이 모드로만 뜻이 있다: 큐에 302를 넷 쌓아 두면 「로그인했는데도
    /// 여전히 튕기는」, 서버에서는 일어나지 않는 상황을 시험하게 된다.
    func enableSession() {
        lock.withLock { sessionAware = true }
    }

    static func ok(_ body: String) -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: 200, location: nil, body: Data(body.utf8))
    }

    static func loginRedirect() -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/login", body: Data())
    }

    static func loginSuccess() -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/book-car", body: Data())
    }

    static func loginFailure(message: String) -> VisitorCarHTTPResponse {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? message
        return VisitorCarHTTPResponse(
            status: 302,
            location: "/nxpmsc/login;jsessionid=ABC?result=\(encoded)",
            body: Data()
        )
    }

    func form(path: String, fields: [String: String]) async throws -> VisitorCarHTTPResponse {
        lock.withLock { formFields.append((path, fields)) }
        return try next(path)
    }

    func json(path: String, body: any Encodable & Sendable) async throws -> VisitorCarHTTPResponse {
        let data = try JSONEncoder().encode(body)
        lock.withLock { jsonBodies.append((path, data)) }
        return try next(path)
    }

    func page(path: String) async throws -> VisitorCarHTTPResponse {
        try next(path)
    }

    func clearCookies() async {
        lock.withLock { clearCookiesCount += 1 }
    }

    private func next(_ path: String) throws -> VisitorCarHTTPResponse {
        try lock.withLock {
            calls.append(path)
            if sessionAware {
                if path == "/do-login" {
                    loggedIn = true
                } else if !loggedIn {
                    return Self.loginRedirect()
                }
            }
            if var queue = queues[path], !queue.isEmpty {
                let head = queue.removeFirst()
                queues[path] = queue
                lastResponses[path] = head
                return head
            }
            guard let last = lastResponses[path] else { throw FakeError.unstubbed(path) }
            return last
        }
    }

    func callCount(_ path: String) -> Int {
        lock.withLock { calls.filter { $0 == path }.count }
    }
}

/// 메모리 자격증명 대역 — 서비스 테스트가 Keychain에 붙을 이유가 없다.
final class FakeCredentialStore: VisitorCarCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: VisitorCarCredentials?
    private(set) var saveCount = 0

    init(stored: VisitorCarCredentials? = nil) { self.stored = stored }

    func load() -> VisitorCarCredentials? { lock.withLock { stored } }

    func save(_ credentials: VisitorCarCredentials) throws {
        lock.withLock { stored = credentials; saveCount += 1 }
    }

    func clear() { lock.withLock { stored = nil } }
}

enum VisitorCarFixture {
    static let bookCarPage = #"<input type="hidden" id="reservedVehiclePointValue" value="6000"/>"#

    static let registerForm = """
    <input name="compName" value="1001" readonly />
    <input name="deptName" value="0101" readonly />
    <select name="parkingLot"><option value="1" selected="selected">○○아파트</option></select>
    <select name="parkingZone"><option value="1" selected="selected">기본 구역</option></select>
    """

    static let emptyBookingPage = """
    {"data":{"content":[],"totalElements":0,"totalPages":0,"number":0,"size":10,
      "first":true,"last":true}}
    """

    static let successResult = #"{"result":"success","message":"성공적으로 등록되었습니다."}"#
}
