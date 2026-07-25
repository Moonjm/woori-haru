import SwiftUI

// UIKit/KVO 기반 스크롤 잠금·모멘텀 중단 헬퍼는 CalendarScrollLock.swift에 격리되어 있다.

private struct VisibleMonthFrame: Equatable {
    let id: String
    let minY: CGFloat
    let maxY: CGFloat
}

private struct VisibleMonthFrameKey: PreferenceKey {
    static var defaultValue: [VisibleMonthFrame] = []

    static func reduce(value: inout [VisibleMonthFrame], nextValue: () -> [VisibleMonthFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct CalendarView: View {
    @Binding var navPath: NavigationPath
    @Environment(PairStore.self) private var pairStore
    @Environment(CategoryStore.self) private var categoryStore
    @State private var calendarVM = CalendarViewModel()
    @State private var recordVM = RecordViewModel()
    @State private var showSheet = false
    @State private var showPicker = false
    @State private var initialScrollDone = false
    @State private var scrolledMonthId: String? = CalendarView.makeTodayMonthId()
    @State private var suppressEdgeLoadingCount = 0
    @State private var scrollProxy: ScrollViewProxy?
    @Environment(AuthViewModel.self) private var authVM
    @State private var drawerDragOffset: CGFloat = 0
    @State private var isDraggingDrawer = false
    @State private var dataLoadTask: Task<Void, Never>?
    @State private var isScrolling = false
    @State private var scrollIdleTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?

    private let todayMonthId: String = CalendarView.makeTodayMonthId()
    private static let sheetHeightRatio: CGFloat = 0.7
    private static let sheetAnimationDuration: Double = 0.25
    private static let scrollIdleDelayMs: Int = 300
    private static let dataLoadDelayMs: Int = 200

    // LazyVStack의 contentSize drift 방지를 위해 월별 정확한 높이를 계산한다.
    // MonthGridView.cellHeightBase와 암묵적으로 커플링되어 있음 — 그쪽 값이 바뀌면 여기도 반영 필요.
    // @ScaledMetric로 Dynamic Type 대응: 접근성 사이즈에서도 실제 렌더 높이와 일치한다.
    @ScaledMetric(relativeTo: .caption) private var monthHeaderHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var monthCellHeight: CGFloat = MonthGridView.cellHeightBase

    private func monthTotalHeight(_ monthData: MonthData) -> CGFloat {
        let rows = monthData.cells.count / 7
        return monthHeaderHeight + CGFloat(rows) * monthCellHeight
    }

    private static func makeTodayMonthId() -> String {
        let today = Date()
        return String(format: "%04d-%02d", today.year, today.month)
    }

    private var isViewingToday: Bool {
        scrolledMonthId == todayMonthId
    }

    /// 모멘텀 스크롤 중단 후 목표로 이동
    private func forceScrollTo(_ targetId: String) async {
        // 현재 보이는 월로 먼저 스크롤하여 모멘텀 중단
        if let currentId = scrolledMonthId, currentId != targetId {
            scrollProxy?.scrollTo(currentId, anchor: .top)
            await Task.yield()
        }
        scrollProxy?.scrollTo(targetId, anchor: .top)
    }

    private func dismissSheet() {
        let anchorId = scrolledMonthId
        withAnimation(.easeInOut(duration: Self.sheetAnimationDuration)) {
            showSheet = false
        }
        recordVM.resetForm()

        dismissTask?.cancel()

        // 시트 dismiss 애니메이션 완료 후 스크롤 복원
        // (데이터 갱신은 onChanged에서 즉시 처리됨)
        // 50ms 여유: withAnimation 완료 후 레이아웃 안정화 마진
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(Self.sheetAnimationDuration) + .milliseconds(50))
            guard !Task.isCancelled else { return }
            if let anchorId, scrolledMonthId != anchorId {
                scrollProxy?.scrollTo(anchorId, anchor: .top)
            }
        }
    }

    private func updateVisibleMonth(using frames: [VisibleMonthFrame]) {
        // 시트 열린 동안엔 스크롤이 잠기므로 preference가 튈 수 있음 — 불필요한 월 플립/데이터 로드 방지
        guard !showSheet else { return }

        let visibleFrame = frames
            .filter { $0.maxY > 0 }
            .min { lhs, rhs in
                abs(lhs.minY) < abs(rhs.minY)
            }

        guard let visibleFrame, scrolledMonthId != visibleFrame.id else { return }

        isScrolling = true
        scrollIdleTask?.cancel()
        scrollIdleTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.scrollIdleDelayMs))
            guard !Task.isCancelled else { return }
            isScrolling = false
        }

        scrolledMonthId = visibleFrame.id

        if let month = calendarVM.months.first(where: { $0.id == visibleFrame.id }) {
            calendarVM.currentMonthLabel = month.startDate.monthDisplayText
            calendarVM.pickerTargetYear = month.year
            calendarVM.pickerTargetMonth = month.month
        }

        guard initialScrollDone, suppressEdgeLoadingCount == 0 else { return }

        dataLoadTask?.cancel()
        dataLoadTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.dataLoadDelayMs))
            guard !Task.isCancelled else { return }
            await calendarVM.ensureDataLoaded(around: visibleFrame.id)
            if let idx = calendarVM.months.firstIndex(where: { $0.id == visibleFrame.id }),
               idx >= calendarVM.months.count - 3 {
                await calendarVM.loadLaterMonths()
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                CalendarHeaderView(
                    monthLabel: calendarVM.currentMonthLabel,
                    onMenuTap: { withAnimation { calendarVM.isDrawerOpen = true } },
                    onMonthTap: { showPicker.toggle() },
                    onSearchTap: { navPath.append(AppDestination.search) }
                )

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        WeekdayHeaderView()

                        ScrollViewReader { proxy in
                            ScrollView {
                                // LazyVStack 바깥/ScrollView 내부에 배치 — 가상화로 deinit 되지 않고
                                // ScrollView와 생명주기를 공유하면서 UIScrollView ancestor walk도 성공한다.
                                LockScrollOffsetHelper(active: showSheet)
                                    .frame(width: 0, height: 0)
                                LazyVStack(spacing: 0) {
                                    ForEach(calendarVM.months) { monthData in
                                        VStack(spacing: 0) {
                                            Text(verbatim: "\(monthData.year)년 \(monthData.month)월")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundStyle(Color.slate400)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 16)
                                                .frame(height: monthHeaderHeight)
                                                .background(.white.opacity(0.5))
                                            MonthGridView(
                                                monthData: monthData,
                                                onSelectDate: { date in
                                                    recordVM.prepareForNewDate()
                                                    recordVM.selectedDate = date
                                                    withAnimation(.easeInOut(duration: Self.sheetAnimationDuration)) {
                                                        showSheet = true
                                                    }
                                                }
                                            )
                                        }
                                        // LazyVStack의 contentSize drift 방지 — 월별 정확한 높이를 명시해
                                        // 시트/키보드 레이아웃 패스 때 off-screen 셀 높이 재추정을 차단한다.
                                        .frame(height: monthTotalHeight(monthData))
                                        .background {
                                            GeometryReader { geo in
                                                Color.clear.preference(
                                                    key: VisibleMonthFrameKey.self,
                                                    value: [
                                                        VisibleMonthFrame(
                                                            id: monthData.id,
                                                            minY: geo.frame(in: .named("calendarScroll")).minY,
                                                            maxY: geo.frame(in: .named("calendarScroll")).maxY
                                                        )
                                                    ]
                                                )
                                            }
                                        }
                                        .id(monthData.id)
                                    }
                                }
                            }
                            .coordinateSpace(name: "calendarScroll")
                            .scrollDismissesKeyboard(.immediately)
                            .ignoresSafeArea(.keyboard)
                            .stopScroll(when: showPicker)
                            .onPreferenceChange(VisibleMonthFrameKey.self, perform: updateVisibleMonth)
                            .onAppear { scrollProxy = proxy }
                        }
                        .overlay(alignment: .bottom) {
                            if !isViewingToday && !showPicker && !isScrolling && initialScrollDone {
                                Button {
                                    Task {
                                        suppressEdgeLoadingCount += 1
                                        defer { suppressEdgeLoadingCount -= 1 }
                                        let today = Date()
                                        let targetId = String(format: "%04d-%02d", today.year, today.month)
                                        // 범위 밖이면 동기로 재빌드
                                        calendarVM.rebuildMonthsIfNeeded(year: today.year, month: today.month)
                                        // 모멘텀 스크롤 중단 후 즉시 이동
                                        await forceScrollTo(targetId)
                                        scrolledMonthId = targetId
                                        calendarVM.pickerTargetYear = today.year
                                        calendarVM.pickerTargetMonth = today.month
                                        // 데이터 로드는 백그라운드 (이전 요청 취소)
                                        dataLoadTask?.cancel()
                                        dataLoadTask = Task { await calendarVM.ensureDataLoaded(around: targetId) }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("오늘")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(Color.slate700)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(.white)
                                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                                    )
                                }
                                .padding(.bottom, 20)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .accessibilityLabel("오늘로 이동")
                                .animation(.easeInOut(duration: 0.2), value: isViewingToday)
                            }
                        }
                    }
                    .opacity(initialScrollDone ? 1 : 0)

                }
            }
            .ignoresSafeArea(.keyboard)
            .simultaneousGesture(
                calendarVM.isDrawerOpen ? nil :
                DragGesture()
                    .onChanged { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        if !isDraggingDrawer && horizontal > 15 && horizontal > vertical * 1.5 {
                            isDraggingDrawer = true
                        }
                        if isDraggingDrawer && value.translation.width > 0 {
                            drawerDragOffset = min(value.translation.width, SideDrawerView.width)
                        }
                    }
                    .onEnded { value in
                        if isDraggingDrawer,
                           value.translation.width > SideDrawerView.width * 0.35
                            || value.predictedEndTranslation.width > SideDrawerView.width * 0.5 {
                            withAnimation(.easeOut(duration: 0.25)) {
                                calendarVM.isDrawerOpen = true
                                drawerDragOffset = 0
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.25)) {
                                drawerDragOffset = 0
                            }
                        }
                        isDraggingDrawer = false
                    }
            )
            .scrollDisabled(isDraggingDrawer)

            SideDrawerView(
                isOpen: $calendarVM.isDrawerOpen,
                navPath: $navPath,
                dragOffset: drawerDragOffset
            )

            // Bottom sheet overlay
            if showSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { dismissSheet() }
                    .transition(.opacity)

                GeometryReader { geo in
                    VStack {
                        Spacer()
                        RecordSheetView(
                            viewModel: recordVM,
                            holidayNames: calendarVM.holidayNames(for: recordVM.selectedDate),
                            eventLabels: calendarVM.eventLabels(for: recordVM.selectedDate),
                            onChanged: {
                                Task {
                                    await calendarVM.refreshMonth(containing: recordVM.selectedDate)
                                }
                            },
                            onDismiss: { dismissSheet() }
                        )
                        .frame(height: geo.size.height * Self.sheetHeightRatio)
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .transition(.move(edge: .bottom))
            }
        }
        .glassScreenBackground()
        .sheet(isPresented: $showPicker) {
            MonthPickerSheet(
                initialYear: calendarVM.pickerTargetYear,
                initialMonth: calendarVM.pickerTargetMonth
            ) { year, month in
                let target = String(format: "%04d-%02d", year, month)
                calendarVM.rebuildMonthsIfNeeded(year: year, month: month)
                Task {
                    suppressEdgeLoadingCount += 1
                    defer { suppressEdgeLoadingCount -= 1 }
                    await forceScrollTo(target)
                    dataLoadTask?.cancel()
                    dataLoadTask = Task { await calendarVM.ensureDataLoaded(around: target) }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .task {
            calendarVM.configure(pairStore: pairStore)
            recordVM.configure(pairStore: pairStore, categoryStore: categoryStore)
            await calendarVM.initialLoad()
            calendarVM.updateBirthdays(user: authVM.user, pairInfo: pairStore.pairInfo)

            // months 배열 세팅 후 ScrollViewReader로 강제 스크롤
            try? await Task.sleep(for: .milliseconds(100))
            scrollProxy?.scrollTo(todayMonthId, anchor: .top)
            try? await Task.sleep(for: .milliseconds(50))
            initialScrollDone = true
        }
        .onDisappear {
            dataLoadTask?.cancel()
            scrollIdleTask?.cancel()
            dismissTask?.cancel()
        }
    }
}
