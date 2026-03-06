import Foundation
import Observation

@MainActor
@Observable
final class UserManagementViewModel {
    var users: [User] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    // Create form
    var newUsername: String = ""
    var newName: String = ""
    var newPassword: String = ""

    // Edit
    var editingId: Int?
    var editName: String = ""
    var editPassword: String = ""
    var editAuthority: Authority = .user

    private let userService = UserService()

    func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            users = try await userService.fetchUsers()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "사용자 목록을 불러오지 못했습니다."
        }
    }

    func createUser() async {
        guard !newUsername.isEmpty, !newName.isEmpty, !newPassword.isEmpty else {
            errorMessage = "모든 항목을 입력해주세요."
            return
        }
        errorMessage = nil
        successMessage = nil

        do {
            try await userService.createUser(CreateUserRequest(username: newUsername, name: newName, password: newPassword))
            newUsername = ""
            newName = ""
            newPassword = ""
            successMessage = "사용자를 추가했어요."
            await loadUsers()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "사용자 생성에 실패했습니다."
        }
    }

    func updateUser() async {
        guard let id = editingId else { return }
        errorMessage = nil
        successMessage = nil

        let request = AdminUpdateUserRequest(
            name: editName.isEmpty ? nil : editName,
            password: editPassword.isEmpty ? nil : editPassword,
            authority: editAuthority
        )

        do {
            try await userService.updateUser(id: id, request)
            editingId = nil
            successMessage = "사용자 정보를 저장했어요."
            await loadUsers()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "사용자 수정에 실패했습니다."
        }
    }

    func startEditing(_ user: User) {
        editingId = user.id
        editName = user.name ?? ""
        editPassword = ""
        editAuthority = user.authority
    }

    func deleteUser(_ user: User) async {
        errorMessage = nil
        successMessage = nil

        do {
            try await userService.deleteUser(id: user.id)
            successMessage = "사용자를 삭제했어요."
            await loadUsers()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "사용자 삭제에 실패했습니다."
        }
    }

    func cancelEditing() {
        editingId = nil
    }
}
