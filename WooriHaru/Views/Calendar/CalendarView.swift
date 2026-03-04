import SwiftUI

struct CalendarView: View {
    @Binding var navPath: NavigationPath
    @State private var calendarVM = CalendarViewModel()
    @State private var recordVM = RecordViewModel()
    @State private var showSheet = false
    @State private var showPicker = false
    @State private var initialScrollDone = false
    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                CalendarHeaderView(
                    monthLabel: calendarVM.currentMonthLabel,
                    onMenuTap: { withAnimation { calendarVM.isDrawerOpen = true } },
                    onMonthTap: { showPicker.toggle() },
                    onSearchTap: { navPath.append(AppDestination.search) }
                )

                WeekdayHeaderView()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(calendarVM.months) { monthData in
                                Section {
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
                                            showSheet = true
                                        }
                                    )
                                } header: {
                                    Text(monthData.startDate.monthDisplayText)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.slate500)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(.white.opacity(0.9))
                                        .id(monthData.id)
                                }
                                .onAppear {
                                    calendarVM.currentMonthLabel = monthData.startDate.monthDisplayText
                                    // 끝에서 2번째 월이 보이면 추가 로드 (무한루프 방지)
                                    let count = calendarVM.months.count
                                    if count >= 2, monthData.id == calendarVM.months[count - 2].id {
                                        Task { await calendarVM.loadLaterMonths() }
                                    }
                                    if count >= 2, monthData.id == calendarVM.months[1].id {
                                        Task { await calendarVM.loadEarlierMonths() }
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: showPicker) { _, show in
                        if !show {
                            let target = String(format: "%04d-%02d", calendarVM.pickerTargetYear, calendarVM.pickerTargetMonth)
                            if calendarVM.months.contains(where: { $0.id == target }) {
                                withAnimation { proxy.scrollTo(target, anchor: .top) }
                            }
                        }
                    }
                    .onChange(of: calendarVM.months.count) {
                        if !initialScrollDone && !calendarVM.months.isEmpty {
                            initialScrollDone = true
                            let today = Date()
                            let todayMonth = String(format: "%04d-%02d", today.year, today.month)
                            proxy.scrollTo(todayMonth, anchor: .top)
                        }
                    }
                }
            }

            if calendarVM.isDrawerOpen {
                SideDrawerView(isOpen: $calendarVM.isDrawerOpen, navPath: $navPath)
                    .transition(.move(edge: .leading))
            }

            if showPicker {
                YearMonthPickerView(isPresented: $showPicker) { year, month in
                    Task {
                        await calendarVM.scrollToMonth(year: year, month: month)
                    }
                }
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
        }
    }
}
