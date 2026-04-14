import SwiftUI
import UIKit

// MARK: - UIView → UIScrollView 탐색 헬퍼

private extension UIView {
    /// superview 체인을 거슬러 올라가며 가장 가까운 UIScrollView를 찾는다.
    var ancestorScrollView: UIScrollView? {
        var current: UIView? = self
        while let v = current {
            if let sv = v as? UIScrollView { return sv }
            current = v.superview
        }
        return nil
    }
}

// MARK: - ScrollView 모멘텀 중단 헬퍼

private struct ScrollStopModifier: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        content
            .background(ScrollStopHelper(trigger: trigger))
    }
}

private struct ScrollStopHelper: UIViewRepresentable {
    let trigger: Bool

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard trigger else { return }
        if let sv = uiView.ancestorScrollView {
            sv.setContentOffset(sv.contentOffset, animated: false)
        }
    }
}

private extension View {
    func stopScroll(when trigger: Bool) -> some View {
        modifier(ScrollStopModifier(trigger: trigger))
    }
}

// MARK: - ContentOffset 잠금 헬퍼
// 시트/키보드로 인한 UIScrollView의 contentOffset 자동 조정을 차단한다.
// `.ignoresSafeArea(.keyboard)`가 상위에서 contentInset 조정을 이미 억제한다는 전제 하에
// 잔여 offset 변경만 복원. 사용자 제스처(isDragging/isDecelerating) 중엔 간섭하지 않는다.
// ⚠️ 프로그램적 scrollTo(스크롤 프록시 포함)도 차단되니, active=true 동안 의도적 스크롤이
// 필요하면 먼저 deactivate 후 호출할 것.

private struct LockScrollOffsetHelper: UIViewRepresentable {
    let active: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        context.coordinator.anchorView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.anchorView = uiView
        context.coordinator.setActive(active)
    }

    final class Coordinator: NSObject {
        weak var anchorView: UIView?
        private weak var scrollView: UIScrollView?
        private var lockedOffset: CGPoint?
        private var offsetKVO: NSKeyValueObservation?
        private var isActive = false

        func setActive(_ active: Bool) {
            guard active != isActive else { return }
            isActive = active
            if active { lock() } else { unlock() }
        }

        private func lock() {
            // 활성화 시점에 anchor로부터 UIScrollView를 새로 찾는다
            // (초기 updateUIView 시점에는 view가 아직 window에 붙지 않았을 수 있음)
            if scrollView == nil {
                scrollView = anchorView?.ancestorScrollView
            }
            guard let sv = scrollView else { return }
            lockedOffset = sv.contentOffset
            offsetKVO = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, change in
                // 사용자 드래그/감속 중엔 간섭하지 않음
                guard let self, let locked = self.lockedOffset,
                      !sv.isDragging, !sv.isDecelerating,
                      let new = change.newValue,
                      abs(new.y - locked.y) > 0.5 || abs(new.x - locked.x) > 0.5 else { return }
                sv.setContentOffset(locked, animated: false)
            }
        }

        private func unlock() {
            offsetKVO?.invalidate()
            offsetKVO = nil
            lockedOffset = nil
        }

        deinit { unlock() }
    }
}

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
                                    LockScrollOffsetHelper(active: showSheet)
                                        .frame(width: 0, height: 0)
                                    ForEach(calendarVM.months) { monthData in
                                        VStack(spacing: 0) {
                                            Text(verbatim: "\(monthData.year)년 \(monthData.month)월")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundStyle(Color.slate400)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 16)
                                                .frame(height: monthHeaderHeight)
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

                    // Picker overlay
                    if showPicker {
                        VStack(spacing: 0) {
                            YearMonthPickerView(
                                isPresented: $showPicker,
                                initialYear: calendarVM.pickerTargetYear,
                                initialMonth: calendarVM.pickerTargetMonth,
                                onSelect: { year, month in
                                    let target = String(format: "%04d-%02d", year, month)
                                    // 동기로 재빌드 (범위 밖이면) + 라벨 갱신
                                    calendarVM.rebuildMonthsIfNeeded(year: year, month: month)
                                    Task {
                                        suppressEdgeLoadingCount += 1
                                        defer { suppressEdgeLoadingCount -= 1 }
                                        // 모멘텀 스크롤 중단 후 즉시 이동
                                        await forceScrollTo(target)
                                        // 데이터 로드는 백그라운드 (이전 요청 취소)
                                        dataLoadTask?.cancel()
                                        dataLoadTask = Task { await calendarVM.ensureDataLoaded(around: target) }
                                    }
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
        .onDisappear {
            dataLoadTask?.cancel()
            scrollIdleTask?.cancel()
            dismissTask?.cancel()
        }
    }
}
