import SwiftUI

struct CalendarView: View {
    @Binding var navPath: NavigationPath
    @State private var calendarVM = CalendarViewModel()
    @State private var recordVM = RecordViewModel()
    @State private var showSheet = false
    @State private var showPicker = false
    @State private var initialScrollDone = false
    @State private var scrolledMonthId: String? = CalendarView.makeTodayMonthId()
    @State private var suppressEdgeLoadingCount = 0
    @Environment(AuthViewModel.self) private var authVM

    private let todayMonthId: String = CalendarView.makeTodayMonthId()

    private static func makeTodayMonthId() -> String {
        let today = Date()
        return String(format: "%04d-%02d", today.year, today.month)
    }

    private var isViewingToday: Bool {
        scrolledMonthId == todayMonthId
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
                                            records: calendarVM.records,
                                            partnerRecords: calendarVM.partnerRecords,
                                            overeats: calendarVM.overeats,
                                            holidays: calendarVM.holidays,
                                            pairEvents: calendarVM.pairEvents,
                                            birthdayMap: calendarVM.birthdayMap,
                                            onSelectDate: { date in
                                                recordVM.selectedDate = date
                                                recordVM.holidayNames = calendarVM.holidays[date.dateString] ?? []
                                                showSheet = true
                                            }
                                        )
                                    }
                                    .id(monthData.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                        .scrollPosition(id: $scrolledMonthId, anchor: .top)
                        .onChange(of: scrolledMonthId) { _, id in
                            guard let id else { return }
                            if let month = calendarVM.months.first(where: { $0.id == id }) {
                                calendarVM.currentMonthLabel = month.startDate.monthDisplayText
                                calendarVM.pickerTargetYear = month.year
                                calendarVM.pickerTargetMonth = month.month
                            }
                            guard initialScrollDone, suppressEdgeLoadingCount == 0 else { return }
                            // Lazy load API data for nearby months
                            Task { await calendarVM.ensureDataLoaded(around: id) }
                            // Forward infinite scroll (append only)
                            if let idx = calendarVM.months.firstIndex(where: { $0.id == id }) {
                                if idx >= calendarVM.months.count - 3 {
                                    Task { await calendarVM.loadLaterMonths() }
                                }
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if !isViewingToday && !showPicker && initialScrollDone {
                                Button {
                                    Task {
                                        suppressEdgeLoadingCount += 1
                                        defer { suppressEdgeLoadingCount -= 1 }
                                        let today = Date()
                                        let targetId = String(format: "%04d-%02d", today.year, today.month)
                                        if calendarVM.months.contains(where: { $0.id == targetId }) {
                                            var tx = Transaction()
                                            tx.animation = nil
                                            withTransaction(tx) {
                                                scrolledMonthId = targetId
                                            }
                                            calendarVM.currentMonthLabel = today.monthDisplayText
                                            calendarVM.pickerTargetYear = today.year
                                            calendarVM.pickerTargetMonth = today.month
                                        } else {
                                            await calendarVM.scrollToMonth(year: today.year, month: today.month)
                                            var tx = Transaction()
                                            tx.animation = nil
                                            withTransaction(tx) {
                                                scrolledMonthId = targetId
                                            }
                                        }
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
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: isViewingToday)
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
                                    scrolledMonthId = target
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

            if calendarVM.isDrawerOpen {
                SideDrawerView(isOpen: $calendarVM.isDrawerOpen, navPath: $navPath)
                    .transition(.move(edge: .leading))
            }
        }
        .onChange(of: showPicker) { _, show in
            // 피커 닫힐 때 API 데이터 보장
            if !show {
                let target = String(format: "%04d-%02d", calendarVM.pickerTargetYear, calendarVM.pickerTargetMonth)
                Task { await calendarVM.ensureDataLoaded(around: target) }
            }
        }
        .sheet(isPresented: $showSheet) {
            RecordSheetView(viewModel: recordVM, onChanged: {
                Task { await calendarVM.refreshMonth(containing: recordVM.selectedDate) }
            })
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.visible)
            .onAppear {
                recordVM.isPaired = calendarVM.isPaired
                recordVM.partnerName = calendarVM.pairInfo?.partnerName ?? "파트너"
            }
        }
        .task {
            await calendarVM.initialLoad()
            calendarVM.updateBirthdays(user: authVM.user, pairInfo: calendarVM.pairInfo)

            // scrolledMonthId는 이미 todayMonthId로 초기화됨
            // 레이아웃이 안정화될 시간을 확보한 뒤 표시
            try? await Task.sleep(for: .milliseconds(50))
            initialScrollDone = true
        }
    }
}
