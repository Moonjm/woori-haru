import SwiftUI

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

    private let todayMonthId: String = CalendarView.makeTodayMonthId()
    private static let sheetHeightRatio: CGFloat = 0.7
    private static let sheetAnimationDuration: Double = 0.25

    private static func makeTodayMonthId() -> String {
        let today = Date()
        return String(format: "%04d-%02d", today.year, today.month)
    }

    private var isViewingToday: Bool {
        scrolledMonthId == todayMonthId
    }

    private func dismissSheet() {
        withAnimation(.easeInOut(duration: Self.sheetAnimationDuration)) {
            showSheet = false
        }
        recordVM.resetForm()
    }

    private func updateVisibleMonth(using frames: [VisibleMonthFrame]) {
        let visibleFrame = frames
            .filter { $0.maxY > 0 }
            .min { lhs, rhs in
                abs(lhs.minY) < abs(rhs.minY)
            }

        guard let visibleFrame, scrolledMonthId != visibleFrame.id else { return }

        scrolledMonthId = visibleFrame.id

        if let month = calendarVM.months.first(where: { $0.id == visibleFrame.id }) {
            calendarVM.currentMonthLabel = month.startDate.monthDisplayText
            calendarVM.pickerTargetYear = month.year
            calendarVM.pickerTargetMonth = month.month
        }

        guard initialScrollDone, suppressEdgeLoadingCount == 0 else { return }

        dataLoadTask?.cancel()
        dataLoadTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
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
                    isPickerOpen: showPicker,
                    onMenuTap: { withAnimation { calendarVM.isDrawerOpen = true } },
                    onMonthTap: { showPicker.toggle() },
                    onSearchTap: { navPath.append(AppDestination.search) }
                )

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        WeekdayHeaderView()

                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(calendarVM.months) { monthData in
                                        VStack(spacing: 0) {
                                            Text(verbatim: "\(monthData.year)년 \(monthData.month)월")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundStyle(Color.slate400)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 6)
                                                .background(.white.opacity(0.95))
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
                            .onPreferenceChange(VisibleMonthFrameKey.self, perform: updateVisibleMonth)
                            .onAppear { scrollProxy = proxy }
                        }
                        .overlay(alignment: .bottom) {
                            if !isViewingToday && !showPicker && initialScrollDone {
                                Button {
                                    Task {
                                        suppressEdgeLoadingCount += 1
                                        defer { suppressEdgeLoadingCount -= 1 }
                                        let today = Date()
                                        let targetId = String(format: "%04d-%02d", today.year, today.month)
                                        if !calendarVM.months.contains(where: { $0.id == targetId }) {
                                            await calendarVM.scrollToMonth(year: today.year, month: today.month)
                                        }
                                        scrollProxy?.scrollTo(targetId, anchor: .top)
                                        scrolledMonthId = targetId
                                        calendarVM.currentMonthLabel = today.monthDisplayText
                                        calendarVM.pickerTargetYear = today.year
                                        calendarVM.pickerTargetMonth = today.month
                                        await Task.yield()
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

                    // Picker overlay
                    if showPicker {
                        VStack(spacing: 0) {
                            YearMonthPickerView(
                                isPresented: $showPicker,
                                initialYear: calendarVM.pickerTargetYear,
                                initialMonth: calendarVM.pickerTargetMonth,
                                onSelect: { year, month in
                                    calendarVM.pickerTargetYear = year
                                    calendarVM.pickerTargetMonth = month
                                    // 즉시 스크롤 (네트워크 없이)
                                    let target = String(format: "%04d-%02d", year, month)
                                    suppressEdgeLoadingCount += 1
                                    scrollProxy?.scrollTo(target, anchor: .top)
                                    suppressEdgeLoadingCount -= 1
                                }
                            )

                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showPicker = false }
                        }
                        .transaction { $0.animation = nil }
                    }
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
                            onChanged: {
                                Task { await calendarVM.refreshMonth(containing: recordVM.selectedDate) }
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
        .onChange(of: showPicker) { _, show in
            // 피커 닫힐 때 API 데이터 보장
            if !show {
                let target = String(format: "%04d-%02d", calendarVM.pickerTargetYear, calendarVM.pickerTargetMonth)
                Task { await calendarVM.ensureDataLoaded(around: target) }
            }
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
    }
}
