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
    case studyRecord
}

struct ContentView: View {
    @Environment(PairStore.self) private var pairStore
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(SubjectStore.self) private var subjectStore
    @Environment(PauseTypeStore.self) private var pauseTypeStore
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
                    case .studyRecord: StudyRecordView()
                    }
                }
        }
        .task {
            async let pair: () = loadStore { try await pairStore.loadStatus() }
            async let categories: () = loadStore { try await categoryStore.load() }
            async let subjects: () = loadStore { try await subjectStore.load() }
            async let pauseTypes: () = loadStore { try await pauseTypeStore.load() }
            _ = await (pair, categories, subjects, pauseTypes)
        }
    }

    private func loadStore(_ operation: () async throws -> Void) async {
        do { try await operation() } catch { print("[ContentView] Store 초기 로딩 실패: \(error.localizedDescription)") }
    }
}
