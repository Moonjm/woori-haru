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
            .task {
                await authVM.checkSession()
            }
        }
    }
}
