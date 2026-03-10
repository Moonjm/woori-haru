import SwiftUI

struct StudySessionLogView: View {
    @State private var vm = StudySessionLogViewModel()
    @State private var hasScrolledToToday = false
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var pendingScrollDate: Date?

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                if vm.dayEntries.isEmpty {
                    ProgressView()
                } else {
                    scrollContent(proxy: proxy)
                }
            }
            .background(Color.white)
            .task {
                await vm.loadInitial()
                scrollToToday(proxy: proxy)
            }
            .onChange(of: vm.dayEntries.count) {
                if !hasScrolledToToday {
                    scrollToToday(proxy: proxy)
                }
                if let date = pendingScrollDate {
                    let id = vm.entryId(for: date)
                    withAnimation {
                        proxy.scrollTo(id, anchor: .top)
                    }
                    pendingScrollDate = nil
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        selectedDate = vm.currentVisibleDate
                        showDatePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(Self.headerMonthFormatter.string(from: vm.currentVisibleDate))
                                .font(.headline)
                                .foregroundStyle(Color.slate900)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.slate400)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let todayKey = vm.entryId(for: Date())
                        withAnimation {
                            proxy.scrollTo(todayKey, anchor: .center)
                        }
                    } label: {
                        Text("오늘")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.blue500)
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .alert("오류", isPresented: .init(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - Scroll Content

    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 과거 로딩 트리거
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await vm.loadPastIfNeeded() }
                    }

                ForEach(Array(vm.dayEntries.enumerated()), id: \.element.id) { index, entry in
                    if isFirstOfMonth(index: index, entry: entry) {
                        monthHeader(entry.date)
                    }

                    dayRow(entry)
                        .id(entry.id)
                        .onAppear {
                            // 월이 바뀔 때만 헤더 업데이트
                            if entry.date.month != vm.currentVisibleDate.month
                                || entry.date.year != vm.currentVisibleDate.year {
                                vm.currentVisibleDate = entry.date
                            }
                        }
                }

                // 미래 로딩 트리거
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await vm.loadFutureIfNeeded() }
                    }
            }
        }
    }

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "날짜 선택",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .padding()
            .navigationTitle("날짜 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showDatePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이동") {
                        showDatePicker = false
                        pendingScrollDate = selectedDate
                        Task {
                            await vm.ensureMonthLoaded(for: selectedDate)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Month Header

    private func monthHeader(_ date: Date) -> some View {
        HStack {
            Text(Self.monthYearFormatter.string(from: date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Day Row

    private func dayRow(_ entry: DayEntry) -> some View {
        let isToday = entry.date.isToday
        let isSunday = entry.date.isSunday
        let isSaturday = entry.date.isSaturday

        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 2) {
                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color.blue500)
                            .frame(width: 36, height: 36)
                    }
                    Text("\(entry.date.day)")
                        .font(.system(size: 18, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(dayNumberColor(isToday: isToday, isSunday: isSunday, isSaturday: isSaturday))
                }
                .frame(height: 36)

                Text(weekdayShort(entry.date))
                    .font(.system(size: 11))
                    .foregroundStyle(dayLabelColor(isToday: isToday, isSunday: isSunday, isSaturday: isSaturday))
            }
            .frame(width: 48)
            .padding(.top, 2)

            VStack(spacing: 4) {
                if entry.sessions.isEmpty {
                    Divider()
                        .padding(.top, 18)
                } else {
                    ForEach(entry.sessions) { session in
                        sessionBlock(session)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Session Block

    private func sessionBlock(_ session: StudySession) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue500)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.subject.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.slate900)
                Text(sessionTimeRange(session))
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                if !session.pauses.isEmpty {
                    Text(pauseSummary(session.pauses))
                        .font(.caption2)
                        .foregroundStyle(Color.orange700)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Spacer()

            Text(formatDuration(session.totalSeconds))
                .font(.caption)
                .foregroundStyle(Color.slate400)
                .padding(.trailing, 10)
        }
        .background(Color.blue500.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func isFirstOfMonth(index: Int, entry: DayEntry) -> Bool {
        if index == 0 { return true }
        let prev = vm.dayEntries[index - 1]
        return entry.date.month != prev.date.month || entry.date.year != prev.date.year
    }

    private static let headerMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 yyyy"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f
    }()

    private func dayNumberColor(isToday: Bool, isSunday: Bool, isSaturday: Bool) -> Color {
        if isToday { return .white }
        if isSunday { return Color.red500 }
        if isSaturday { return Color.blue500 }
        return Color.slate900
    }

    private func dayLabelColor(isToday: Bool, isSunday: Bool, isSaturday: Bool) -> Color {
        if isToday { return Color.blue500 }
        if isSunday { return Color.red500 }
        if isSaturday { return Color.blue500 }
        return Color.slate400
    }

    private func weekdayShort(_ date: Date) -> String {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return symbols[date.weekday - 1]
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "a h:mm"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    private func sessionTimeRange(_ session: StudySession) -> String {
        let start = Date.fromISO(session.startedAt).map { Self.timeFormatter.string(from: $0) } ?? "??:??"
        let end = session.endedAt.flatMap { Date.fromISO($0) }.map { Self.timeFormatter.string(from: $0) } ?? "진행중"
        return "\(start) - \(end)"
    }

    private func pauseSummary(_ pauses: [StudyPause]) -> String {
        let count = pauses.count
        let totalPauseSeconds = pauses.reduce(0) { total, pause in
            guard let start = Date.fromISO(pause.pausedAt) else { return total }
            let end = pause.resumedAt.flatMap { Date.fromISO($0) } ?? Date()
            return total + Int(end.timeIntervalSince(start))
        }
        let m = totalPauseSeconds / 60
        if m > 0 {
            return "일시정지 \(count)회, \(m)분"
        }
        return "일시정지 \(count)회"
    }

    private func formatDuration(_ seconds: Int) -> String {
        seconds.durationText
    }

    private func scrollToToday(proxy: ScrollViewProxy) {
        if let index = vm.todayEntryIndex() {
            let id = vm.dayEntries[index].id
            proxy.scrollTo(id, anchor: .center)
            hasScrolledToToday = true
        }
    }
}
