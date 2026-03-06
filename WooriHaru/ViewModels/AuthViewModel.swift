import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    var user: User?
    var isLoading = true
    var isLoggedIn = false
    var errorMessage: String?

    private let authService = AuthService()

    func checkSession() async {
        isLoading = true
        do {
            user = try await authService.fetchMe()
            isLoggedIn = true
        } catch {
            isLoggedIn = false
            user = nil
        }
        isLoading = false
    }

    func login(username: String, password: String) async {
        errorMessage = nil
        isLoading = true
        do {
            try await authService.login(username: username, password: password)
            user = try await authService.fetchMe()
            isLoggedIn = true
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "로그인에 실패했습니다."
        }
        isLoading = false
    }

    func updateProfile(_ request: UpdateMeRequest) async throws {
        let updatedUser = try await authService.updateMe(request)
        user = updatedUser
    }

    func logout() async {
        do {
            try await authService.logout()
        } catch {
            print("Logout failed: \(error.localizedDescription)")
        }
        user = nil
        isLoggedIn = false
    }
}
