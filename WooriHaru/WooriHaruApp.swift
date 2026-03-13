import SwiftUI
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct WooriHaruApp: App {
    @State private var authVM = AuthViewModel()
    @State private var studyTimerVM = StudyTimerViewModel()
    @State private var pairStore = PairStore()
    @State private var categoryStore = CategoryStore()
    @State private var subjectStore = SubjectStore()
    @State private var pauseTypeStore = PauseTypeStore()
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.isLoading {
                    ProgressView()
                } else if authVM.isLoggedIn {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environment(authVM)
            .environment(studyTimerVM)
            .environment(pairStore)
            .environment(categoryStore)
            .environment(subjectStore)
            .environment(pauseTypeStore)
            .task {
                await authVM.checkSession()
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let deepLink = StudyDeepLink(url: url) else { return }
        Task {
            switch deepLink {
            case .pause: await studyTimerVM.pause()
            case .resume: await studyTimerVM.resume()
            case .end: await studyTimerVM.end()
            }
        }
    }
}
