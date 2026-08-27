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
    case ledger
    case ledgerRecurring
    case ledgerApiKeys
    case ledgerInboundFailures
    case swimRecords
    case diet
    case schedule
    case dispatchUpload
    case vehicle
    case maintenance
    case visitorCar
    case visitorCarRegister
    case visitorCarBookings
    case visitorCarEntries
    case visitorCarSettings
}

struct ContentView: View {
    @Environment(PairStore.self) private var pairStore
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(SubjectStore.self) private var subjectStore
    @Environment(PauseTypeStore.self) private var pauseTypeStore
    @State private var path = NavigationPath()
    @State private var quickActionCenter = QuickActionCenter.shared
    @State private var showMembershipCard = false
    /// 배차표를 저장하고 돌아올 때 달력이 띄워야 할 달. 배차표는 다음 달치를 등록하는 게
    /// 정상이라, 보고 있던 달로 그냥 돌아오면 방금 저장한 게 화면에 없다.
    @State private var savedDispatchYearMonth: String?

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
                    case .ledger: LedgerView()
                    case .ledgerRecurring: LedgerRecurringView()
                    case .ledgerApiKeys: LedgerApiKeysView()
                    case .ledgerInboundFailures: LedgerInboundFailuresView()
                    case .swimRecords: SwimRecordListView()
                    case .diet: DietHomeView()
                    case .schedule: ScheduleView(navPath: $path, savedYearMonth: $savedDispatchYearMonth)
                    case .vehicle: VehicleView()
                    case .maintenance: MaintenanceView()
                    case .visitorCar: VisitorCarView(navPath: $path)
                    case .visitorCarRegister:
                        VisitorCarRegisterView {
                            // 홈으로 물러나면 `.task`가 다시 돌아 잔여시간을 새로 읽는다.
                        }
                    case .visitorCarBookings: VisitorCarBookingsView()
                    case .visitorCarEntries: VisitorCarEntriesView()
                    case .visitorCarSettings: Text("준비 중")
                    case .dispatchUpload:
                        DispatchUploadView(onSaved: { yearMonth in
                            savedDispatchYearMonth = yearMonth
                            // 검수 화면은 `navigationDestination(isPresented:)`로 떠서 `path`에
                            // 얹히지 않는다 — 업로드 화면을 `path`에서 빼면 검수 화면도 함께
                            // 사라져 달력까지 한 번에 물러난다.
                            if !path.isEmpty { path.removeLast() }
                        })
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
