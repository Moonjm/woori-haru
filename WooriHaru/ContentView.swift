import SwiftUI

enum AppDestination: Hashable {
    case stats
    case search
    case categories
    case pair
    case pairEvents
    case profile
    case admin
    case userManagement
    case studyTimer
    case studySessionLog
}

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            CalendarView(navPath: $path)
                .navigationDestination(for: AppDestination.self) { dest in
                    switch dest {
                    case .stats: StatsView()
                    case .search: SearchView()
                    case .categories: CategoriesView()
                    case .pair: PairView(navPath: $path)
                    case .pairEvents: PairEventsView()
                    case .profile: ProfileView()
                    case .admin: AdminView(navPath: $path)
                    case .userManagement: UserManagementView()
                    case .studyTimer: StudyTimerView()
                    case .studySessionLog: StudyRecordView()
                    }
                }
        }
    }
}
