import Foundation

struct UserService {
    private let api = APIClient.shared

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
