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
        try await api.postVoid("/auth/logout", body: nil)
    }

    func fetchMe() async throws -> User {
        let response: DataResponse<User> = try await api.get("/users/me", query: [:])
        guard let user = response.data else { throw APIError.unauthorized }
        return user
    }

    func updateMe(_ request: UpdateMeRequest) async throws -> User {
        let response: DataResponse<User> = try await api.patch("/users/me", body: request)
        guard let user = response.data else { throw APIError.unauthorized }
        return user
    }
}
