import SwiftUI

struct StudySessionLogView: View {
    @State private var vm = StudySessionLogViewModel()
    @State private var hasScrolledToToday = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 과거 로딩 트리거
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await vm.loadPastIfNeeded() }
                        }

                    ForEach(Array(vm.dayEntries.enumerated()), id: \.element.id) { index, entry in
                        // 월 헤더: 해당 월의 첫 번째 날이거나 이전 항목과 월이 다를 때
                        if isFirstOfMonth(index: index, entry: entry) {
                            monthHeader(entry.date)
                        }

                        dayRow(entry)
                            .id(entry.id)
                    }

                    // 미래 로딩 트리거
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await vm.loadFutureIfNeeded() }
                        }
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
            }
        }
        .navigationTitle("공부 기록")
        .navigationBarTitleDisplayMode(.inline)
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Month Header

    private func monthHeader(_ date: Date) -> some View {
        HStack {
            Text(monthYearText(date))
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
            // 왼쪽: 날짜 + 요일
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

            // 오른쪽: 세션 블록들
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

    // MARK: - Session Block (구글 캘린더 스타일)

    private func sessionBlock(_ session: StudySession) -> some View {
        HStack(spacing: 0) {
            // 왼쪽 컬러 바
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Spacer()

            // 소요 시간
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

    private func monthYearText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

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

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return String(format: "%d시간 %d분", h, m) }
        if m > 0 { return String(format: "%d분", m) }
        return "1분 미만"
    }

    private func scrollToToday(proxy: ScrollViewProxy) {
        if let index = vm.todayEntryIndex() {
            let id = vm.dayEntries[index].id
            proxy.scrollTo(id, anchor: .center)
            hasScrolledToToday = true
        }
    }
}
