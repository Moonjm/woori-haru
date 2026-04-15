import Foundation
import Observation
import os

/// deinit(비격리)에서도 접근 가능하도록 observer를 감싸는 박스.
private final class ObserverBox: @unchecked Sendable {
    var observer: (any NSObjectProtocol)?
}

@MainActor
@Observable
final class AuthViewModel {
    var user: User?
    var isLoading = true
    var isLoggedIn = false
    var errorMessage: String?

    private let authService = AuthService()
    private let observerBox = ObserverBox()

    init() {
        observerBox.observer = NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.user = nil
                self.isLoggedIn = false
            }
        }
    }

    deinit {
        if let observer = observerBox.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

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
            Logger.session.error("로그아웃 실패: \(error.localizedDescription)")
        }
        user = nil
        isLoggedIn = false
    }
}
