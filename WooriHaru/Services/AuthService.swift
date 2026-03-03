import Foundation

struct AuthService {
    private let api = APIClient.shared

    func login(username: String, password: String) async throws {
        try await api.postVoid("/auth/login", body: ["username": username, "password": password])
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
        let response: DataResponse<User> = try await api.patch("/users/me", body: request)
        guard let user = response.data else { throw APIError.unauthorized }
        return user
    }
}
