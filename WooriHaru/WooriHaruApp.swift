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
    @State private var pendingDeepLink: StudyDeepLink?

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
            .alert("확인", isPresented: .init(
                get: { pendingDeepLink != nil },
                set: { if !$0 { pendingDeepLink = nil } }
            )) {
                Button(pendingDeepLink == .pause ? "일시정지" : "종료", role: .destructive) {
                    let link = pendingDeepLink
                    pendingDeepLink = nil
                    Task {
                        switch link {
                        case .pause: await studyTimerVM.pause()
                        case .end: await studyTimerVM.end()
                        default: break
                        }
                    }
                }
                Button("취소", role: .cancel) { pendingDeepLink = nil }
            } message: {
                Text("아직 1분이 지나지 않았습니다.\n정말 \(pendingDeepLink == .pause ? "일시정지" : "종료")하시겠습니까?")
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let deepLink = StudyDeepLink(url: url) else { return }
        switch deepLink {
        case .pause, .end:
            if studyTimerVM.elapsedSeconds < StudyTimerViewModel.earlyConfirmSeconds {
                pendingDeepLink = deepLink
            } else {
                Task {
                    if deepLink == .pause { await studyTimerVM.pause() }
                    else { await studyTimerVM.end() }
                }
            }
        case .resume:
            Task { await studyTimerVM.resume() }
        }
    }
}
