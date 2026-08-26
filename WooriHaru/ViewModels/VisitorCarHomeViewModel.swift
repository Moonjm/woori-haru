import Foundation
import Observation

@MainActor @Observable
final class VisitorCarHomeViewModel {
    enum State: Equatable {
        case loading
        case needsLogin
        case ready(minutes: Int)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var loginError: String?
    private(set) var isSubmitting = false

    private let service: any VisitorCarServing

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service
    }

    /// 참고 화면과 같은 꼴로 적는다. **음수는 「남음」이 아니라 「초과」다** —
    /// 웹도 갈라 말하고, 「-120분 남음」은 읽는 사람을 헷갈리게 한다.
    static func remainingText(minutes: Int) -> String {
        let magnitude = abs(minutes)
        let text = "\(magnitude / 60)시간 \(magnitude % 60)분"
        return minutes < 0 ? "\(text) 초과" : "\(text) 남음"
    }

    func load() async {
        state = .loading
        do {
            state = .ready(minutes: try await service.remainingMinutes())
        } catch VisitorCarError.notLoggedIn, VisitorCarError.sessionExpired {
            // 로그인이 풀린 것은 「실패」가 아니라 「다시 붙어야 한다」다.
            state = .needsLogin
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func login(id: String, password: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        loginError = nil
        defer { isSubmitting = false }

        do {
            try await service.login(id: id, password: password)
            await load()
        } catch {
            loginError = error.localizedDescription
            state = .needsLogin
        }
    }

    func logout() async {
        await service.logout()
        loginError = nil
        state = .needsLogin
    }
}
