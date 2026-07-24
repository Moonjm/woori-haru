import SwiftUI
import UIKit

/// 홈 화면 앱 아이콘을 길게 눌렀을 때 뜨는 퀵 액션.
enum QuickAction: String, CaseIterable {
    case membershipCard
    case ledger
    case studyTimer

    init?(shortcutItem: UIApplicationShortcutItem) {
        self.init(rawValue: shortcutItem.type)
    }

    var shortcutItem: UIApplicationShortcutItem {
        switch self {
        case .membershipCard:
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: "회원카드",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "barcode")
            )
        case .ledger:
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: "가계부",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "wonsign.circle")
            )
        case .studyTimer:
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: "공부 타이머",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "timer")
            )
        }
    }
}

/// 델리게이트(콜드 런치·실행 중)에서 받은 퀵 액션을 SwiftUI 뷰가 소비할 때까지 보관한다.
/// 로그인 전에 눌렀다면 로그인 후 ContentView가 나타날 때 처리된다.
@Observable
final class QuickActionCenter {
    static let shared = QuickActionCenter()
    var pending: QuickAction?
}

final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = QuickAction.allCases.map(\.shortcutItem)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // 앱이 완전히 종료된 상태에서 퀵 액션으로 실행되면 여기로 들어온다.
        if let item = options.shortcutItem, let action = QuickAction(shortcutItem: item) {
            QuickActionCenter.shared.pending = action
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = QuickAction(shortcutItem: shortcutItem) else {
            completionHandler(false)
            return
        }
        QuickActionCenter.shared.pending = action
        completionHandler(true)
    }
}
