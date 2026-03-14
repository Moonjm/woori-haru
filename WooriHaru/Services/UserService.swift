import Foundation

struct UserService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func fetchUsers() async throws -> [User] {
        let response: DataResponse<[User]> = try await api.get("/users")
        return response.data ?? []
    }

    func createUser(_ request: CreateUserRequest) async throws {
        try await api.postVoid("/users", body: request)
    }

    func updateUser(id: Int, _ request: AdminUpdateUserRequest) async throws {
        try await api.putVoid("/users/\(id)", body: request)
    }

    func deleteUser(id: Int) async throws {
        try await api.deleteVoid("/users/\(id)")
    }
}
