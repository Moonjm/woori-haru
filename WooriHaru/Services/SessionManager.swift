import Foundation
import os

extension Notification.Name {
    static let sessionExpired = Notification.Name("sessionExpired")
}

/// 세션 관리 — 401 감지, 토큰 갱신, 세션 만료 노티피케이션
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    private let session: URLSession
    private var refreshTask: Task<Bool, Never>?
    private let baseURL = APIConfig.baseURL

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = .shared
        self.session = URLSession(configuration: config)
    }

    /// URLSession (APIClient가 요청 시 사용)
    var urlSession: URLSession { session }

    /// 응답이 401이면 토큰 갱신 후 재시도 여부 판단
    /// - Returns: `true`면 재시도 필요, `false`면 갱신 실패(세션 만료)
    func handleUnauthorized() async -> Bool {
        Logger.session.info("401 수신 — 토큰 갱신 시도")
        let refreshed = await refreshToken()
        if !refreshed {
            Logger.session.warning("세션 만료 — 토큰 갱신 실패")
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
        }
        return refreshed
    }

    // MARK: - Private

    private func refreshToken() async -> Bool {
        if let existing = refreshTask {
            return await existing.value
        }

        let task = Task<Bool, Never> {
            guard let url = URL(string: baseURL + "/auth/refresh") else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return false }
                let success = (200...299).contains(http.statusCode)
                if success {
                    Logger.session.info("토큰 갱신 성공")
                } else {
                    Logger.session.warning("토큰 갱신 실패 — status \(http.statusCode)")
                }
                return success
            } catch {
                Logger.session.error("토큰 갱신 네트워크 오류: \(error.localizedDescription)")
                return false
            }
        }

        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }
}
