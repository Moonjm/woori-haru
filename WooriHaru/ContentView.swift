import os
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
    case storage
    case ledger
    case ledgerRecurring
    case ledgerApiKeys
    case ledgerInboundFailures
}

struct ContentView: View {
    @Environment(PairStore.self) private var pairStore
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(SubjectStore.self) private var subjectStore
    @Environment(PauseTypeStore.self) private var pauseTypeStore
    @State private var path = NavigationPath()
    @State private var quickActionCenter = QuickActionCenter.shared
    @State private var showMembershipCard = false

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
                    case .storage: StorageMainView()
                    case .ledger: LedgerView()
                    case .ledgerRecurring: LedgerRecurringView()
                    case .ledgerApiKeys: LedgerApiKeysView()
                    case .ledgerInboundFailures: LedgerInboundFailuresView()
                    }
                }
        }
        .sheet(isPresented: $showMembershipCard) {
            MembershipCardView()
        }
        .onAppear { consumeQuickAction() }
        .onChange(of: quickActionCenter.pending) { consumeQuickAction() }
        .task {
            async let pair: () = loadStore { try await pairStore.loadStatus() }
            async let categories: () = loadStore { try await categoryStore.load() }
            async let subjects: () = loadStore { try await subjectStore.load() }
            async let pauseTypes: () = loadStore { try await pauseTypeStore.load() }
            _ = await (pair, categories, subjects, pauseTypes)
        }
    }

    /// 홈 화면 퀵 액션 처리 — 화면 어디에 있든 대상 화면으로 바로 이동한다.
    private func consumeQuickAction() {
        guard let action = quickActionCenter.pending else { return }
        quickActionCenter.pending = nil
        switch action {
        case .membershipCard:
            showMembershipCard = true
        case .ledger:
            showMembershipCard = false
            path = NavigationPath()
            path.append(AppDestination.ledger)
        case .studyTimer:
            showMembershipCard = false
            path = NavigationPath()
            path.append(AppDestination.studyTimer)
        }
    }

    private func loadStore(_ operation: () async throws -> Void) async {
        do { try await operation() } catch { Logger.store.error("Store 초기 로딩 실패: \(error.localizedDescription)") }
    }
}
