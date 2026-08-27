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
        // **기록과 응답 결정을 같은 잠금 안에서 한다.** 따로면 두 스레드가 엇갈려
        // `calls` 순서와 `formFields` 순서가 갈릴 수 있다.
        try lock.withLock {
            formFields.append((path, fields))
            return try recordCallAndRespond(path)
        }
    }

    func json(path: String, body: any Encodable & Sendable) async throws -> VisitorCarHTTPResponse {
        let data = try JSONEncoder().encode(body)
        return try lock.withLock {
            jsonBodies.append((path, data))
            return try recordCallAndRespond(path)
        }
    }

    func page(path: String) async throws -> VisitorCarHTTPResponse {
        try lock.withLock { try recordCallAndRespond(path) }
    }

    func clearCookies() async {
        lock.withLock { clearCookiesCount += 1 }
    }

    /// **항상 `lock.withLock` 안에서만 부른다** — `NSLock`은 재진입이 안 되므로
    /// 여기서 다시 잠그면 교착이다.
    private func recordCallAndRespond(_ path: String) throws -> VisitorCarHTTPResponse {
        calls.append(path)
        if sessionAware, path != "/do-login", !loggedIn {
            return Self.loginRedirect()
        }

        let response = try dequeue(path)

        // **응답이 로그인 성공(로그인 페이지가 아닌 리다이렉트)일 때만 세션을 세운다.**
        // `/do-login`이 불리기만 하면 스텁 응답과 무관하게 세우면, 재로그인 실패를
        // 다루는 테스트가 실제로는 성공한 것처럼 거짓 초록을 준다.
        if sessionAware, path == "/do-login", !response.isLoginRedirect {
            loggedIn = true
        }
        return response
    }

    private func dequeue(_ path: String) throws -> VisitorCarHTTPResponse {
        if var queue = queues[path], !queue.isEmpty {
            let head = queue.removeFirst()
            queues[path] = queue
            lastResponses[path] = head
            return head
        }
        guard let last = lastResponses[path] else { throw FakeError.unstubbed(path) }
        return last
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

/// **`VisitorCarServing`이 있는 이유가 이것이다** — 설계 문서가 「테스트가 여기를 가짜로
/// 바꾼다」고 적어 둔 자리(P1). 뷰모델이 서비스가 던지는 특정 오류를 어떻게 접는지만
/// 보고 싶을 때, `VisitorCarService` + `FakeVisitorCarTransport`로 실제 재진입 경쟁을
/// 재현하는 대신(스케줄링에 기대게 된다) 이 대역이 원하는 결과를 곧바로 돌려준다.
final class FakeVisitorCarServing: VisitorCarServing, @unchecked Sendable {
    var loginError: (any Error)?
    private(set) var loginCallCount = 0

    func login(id: String, password: String) async throws {
        loginCallCount += 1
        if let loginError { throw loginError }
    }

    func logout() async {}
    func remainingMinutes() async throws -> Int { 0 }
    func household() async throws -> VisitorCarHousehold {
        VisitorCarHousehold(dong: "", ho: "", parkingLot: "", parkingZone: "")
    }
    func register(_ request: VisitorCarRegisterRequest) async throws {}
    func update(id: Int, _ request: VisitorCarRegisterRequest) async throws {}
    func delete(id: Int) async throws {}
    func bookings(
        from: Date, to: Date, carNo: String, page: Int, size: Int
    ) async throws -> VisitorCarPage<VisitorCarBooking> {
        VisitorCarPage(content: [], totalElements: 0, totalPages: 0, number: 0, last: true)
    }
    func entries(
        from: Date, to: Date, carNo: String, page: Int, size: Int
    ) async throws -> VisitorCarPage<VisitorCarEntry> {
        VisitorCarPage(content: [], totalElements: 0, totalPages: 0, number: 0, last: true)
    }
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
