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
            }
            .onChange(of: vm.dayEntries.count) {
                if !hasScrolledToToday {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToToday(proxy: proxy)
                    }
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

            VStack(spacing: 0) {
                if entry.sessions.isEmpty {
                    Divider()
                        .padding(.top, 18)
                } else {
                    dayTimeline(entry.sessions, date: entry.date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Day Timeline

    private enum SegmentType {
        case study(subjectName: String)
        case rest
    }

    private struct TimelineSegment {
        let startDate: Date
        let endDate: Date
        let type: SegmentType

        var durationMinutes: Double {
            endDate.timeIntervalSince(startDate) / 60.0
        }

        var isStudy: Bool {
            if case .study = type { return true }
            return false
        }

        var label: String {
            switch type {
            case .study(let name): return name
            case .rest: return "휴식"
            }
        }
    }

    private func dayTimeline(_ sessions: [StudySession], date: Date) -> some View {
        let segments = buildDaySegments(sessions, date: date)
        let pointsPerMinute: CGFloat = 1.2

        return HStack(alignment: .top, spacing: 6) {
            // Time labels
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Text(Self.shortTimeFormatter.string(from: segment.startDate))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.slate400)
                        .frame(
                            height: max(CGFloat(segment.durationMinutes) * pointsPerMinute, 20),
                            alignment: .top
                        )
                }
                if let last = segments.last {
                    Text(Self.shortTimeFormatter.string(from: last.endDate))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.slate400)
                }
            }
            .frame(width: 40)

            // Blocks
            VStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let height = max(CGFloat(segment.durationMinutes) * pointsPerMinute, 20)
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(segment.isStudy ? Color.blue500 : Color.orange300)
                            .frame(width: 3)
                        Text(segment.label)
                            .font(.system(size: 11))
                            .foregroundStyle(segment.isStudy ? Color.blue700 : Color.orange700)
                            .padding(.leading, 6)
                        Spacer()
                    }
                    .frame(height: height)
                    .background(segment.isStudy ? Color.blue500.opacity(0.08) : Color.orange200.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }

    private func buildDaySegments(_ sessions: [StudySession], date: Date) -> [TimelineSegment] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = dayStart.addingTimeInterval(86400)

        // 시간 오름차순 정렬, 해당 날짜 범위로 클리핑
        let sorted = sessions
            .compactMap { session -> (session: StudySession, start: Date, end: Date)? in
                guard let start = Date.fromISO(session.startedAt) else { return nil }
                let end = session.endedAt.flatMap { Date.fromISO($0) } ?? Date()
                let clippedStart = max(start, dayStart)
                let clippedEnd = min(end, dayEnd)
                guard clippedStart < clippedEnd else { return nil }
                return (session, clippedStart, clippedEnd)
            }
            .sorted { $0.start < $1.start }

        var segments: [TimelineSegment] = []

        for item in sorted {
            // 세션 내부: 공부/휴식 구간 분리 (날짜 범위로 클리핑)
            let pauses = item.session.pauses
                .compactMap { pause -> (start: Date, end: Date)? in
                    guard let s = Date.fromISO(pause.pausedAt) else { return nil }
                    let e = pause.resumedAt.flatMap { Date.fromISO($0) } ?? item.end
                    let cs = max(s, item.start)
                    let ce = min(e, item.end)
                    guard cs < ce else { return nil }
                    return (cs, ce)
                }
                .sorted { $0.start < $1.start }

            var cursor = item.start
            for pause in pauses {
                if cursor < pause.start {
                    segments.append(TimelineSegment(
                        startDate: cursor, endDate: pause.start,
                        type: .study(subjectName: item.session.subject.name)
                    ))
                }
                segments.append(TimelineSegment(
                    startDate: pause.start, endDate: pause.end, type: .rest
                ))
                cursor = pause.end
            }
            if cursor < item.end {
                segments.append(TimelineSegment(
                    startDate: cursor, endDate: item.end,
                    type: .study(subjectName: item.session.subject.name)
                ))
            }
        }

        return segments
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

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
