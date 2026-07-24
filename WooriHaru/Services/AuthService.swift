import Foundation

struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct AuthService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func login(username: String, password: String) async throws {
        try await api.postVoid("/auth/login", body: LoginRequest(username: username, password: password))
    }

    func logout() async throws {
        try await api.postVoid("/auth/logout")
    }

    func fetchMe() async throws -> User {
        let response: DataResponse<User> = try await api.get("/users/me")
        guard let user = response.data else { throw APIError.unauthorized }
        return user
    }

    func updateMe(_ request: UpdateMeRequest) async throws -> User {
        // 서버가 204(빈 응답)를 주므로 응답 디코드 없이 저장 후 내 정보를 다시 조회한다.
        try await api.patchVoid("/users/me", body: request)
        return try await fetchMe()
    }
}
