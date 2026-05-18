import SwiftUI

// MARK: - Supporting Types

struct DailyStudyRecord: Identifiable {
    let id: String // "yyyy-MM-dd"
    let date: Date
    let totalSeconds: Int
    let pauseSeconds: Int
    let sessions: [StudySession]

    var totalMinutes: Double { Double(totalSeconds) / 60.0 }
    var totalHours: Double { Double(totalSeconds) / 3600.0 }
}

struct WeeklyStudyRecord: Identifiable {
    let id: String // "yyyy-MM-dd" of Monday
    let weekStart: Date // Monday
    let weekEnd: Date   // Sunday
    let totalSeconds: Int
    let pauseSeconds: Int
    let dailyRecords: [DailyStudyRecord] // Monday..Sunday (7 entries)
}

struct SubjectStudyRecord: Identifiable {
    let id: Int
    let name: String
    let totalSeconds: Int
    let ratio: Double // 0.0 ~ 1.0
}

struct MonthlySummary {
    let totalSeconds: Int
    let studyDays: Int
    let averageSecondsPerStudyDay: Int
    let maxDaySeconds: Int
    let maxDayDate: Date?

    var totalFormatted: String { totalSeconds.durationText }
    var averageFormatted: String { averageSecondsPerStudyDay.durationText }
    var maxFormatted: String { maxDaySeconds.durationText }

    static let empty = MonthlySummary(
        totalSeconds: 0, studyDays: 0,
        averageSecondsPerStudyDay: 0, maxDaySeconds: 0, maxDayDate: nil
    )
}

// MARK: - ViewModel

@MainActor
@Observable
final class StudyRecordViewModel {
    var currentYear: Int = Date().year
    var currentMonth: Int = Date().month
    var dailyRecords: [DailyStudyRecord] = []
    var weeklyRecords: [WeeklyStudyRecord] = []
    var selectedDate: Date?
    var isLoading = false
    var errorMessage: String?
    private var loadTask: Task<Void, Never>?

    private static let mondayCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    private(set) var pauseTypeStore: PauseTypeStore!

    func configure(pauseTypeStore: PauseTypeStore) {
        self.pauseTypeStore = pauseTypeStore
    }

    private let service = StudyService()

    // MARK: - Month Label

    var monthLabel: String {
        String(format: "%d년 %d월", currentYear, currentMonth)
    }

    var isCurrentMonth: Bool {
        let today = Date()
        return currentYear == today.year && currentMonth == today.month
    }

    // MARK: - Monthly Summary

    var summary: MonthlySummary {
        guard !dailyRecords.isEmpty else { return .empty }
        let total = dailyRecords.reduce(0) { $0 + $1.totalSeconds }
        let studyDays = dailyRecords.filter { $0.totalSeconds > 0 }
        let avg = studyDays.isEmpty ? 0 : total / studyDays.count
        let maxDay = dailyRecords.max(by: { $0.totalSeconds < $1.totalSeconds })
        return MonthlySummary(
            totalSeconds: total,
            studyDays: studyDays.count,
            averageSecondsPerStudyDay: avg,
            maxDaySeconds: maxDay?.totalSeconds ?? 0,
            maxDayDate: maxDay?.date
        )
    }

    // MARK: - Heatmap

    /// 히트맵 색상 레벨 (0~4)
    func heatmapLevel(for seconds: Int) -> Int {
        let hours = Double(seconds) / 3600.0
        if hours < 0.01 { return 0 }
        if hours < 1 { return 1 }
        if hours < 3 { return 2 }
        if hours < 6 { return 3 }
        return 4
    }

    // MARK: - Subject Breakdown

    var subjectRecords: [SubjectStudyRecord] {
        let allSessions = dailyRecords.flatMap(\.sessions)
        let totals = aggregateBySubject(allSessions)
        let maxSeconds = max(totals.map(\.seconds).max() ?? 0, 1)
        return totals.map { item in
            SubjectStudyRecord(
                id: item.id, name: item.name,
                totalSeconds: item.seconds,
                ratio: Double(item.seconds) / Double(maxSeconds)
            )
        }
    }

    // MARK: - Daily Breakdown

    func subjectBreakdown(for record: DailyStudyRecord) -> [(name: String, seconds: Int)] {
        aggregateBySubject(record.sessions).map { ($0.name, $0.seconds) }
    }

    func pauseBreakdown(for record: DailyStudyRecord) -> [(label: String, seconds: Int)] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: record.date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        var byType: [String: Int] = [:]
        for session in record.sessions {
            for detail in clippedPauseDetails(session: session, rangeStart: dayStart, rangeEnd: dayEnd) {
                byType[detail.type, default: 0] += detail.seconds
            }
        }
        return byType.map { type, seconds in
            (label: pauseTypeLabel(type), seconds: seconds)
        }
        .sorted { $0.seconds > $1.seconds }
    }

    func pauseTypeLabel(_ value: String) -> String {
        pauseTypeStore.pauseTypes.first(where: { $0.value == value })?.label ?? value
    }

    private func aggregateBySubject(_ sessions: [StudySession]) -> [(id: Int, name: String, seconds: Int)] {
        var totals: [Int: (name: String, seconds: Int)] = [:]
        for session in sessions {
            let existing = totals[session.subject.id]
            totals[session.subject.id] = (
                name: session.subject.name,
                seconds: (existing?.seconds ?? 0) + session.totalSeconds
            )
        }
        return totals.map { (id: $0.key, name: $0.value.name, seconds: $0.value.seconds) }
            .sorted { $0.seconds > $1.seconds }
    }

    // MARK: - Load

    func loadMonth() async {
        isLoading = true

        let cal = Self.mondayCalendar
        guard let monthStart = cal.date(from: DateComponents(year: currentYear, month: currentMonth)),
              let monthEnd = cal.date(byAdding: .day, value: monthStart.daysInMonth() - 1, to: monthStart),
              let firstMonday = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start,
              let lastWeekMonday = cal.dateInterval(of: .weekOfYear, for: monthEnd)?.start,
              let lastSunday = cal.date(byAdding: .day, value: 6, to: lastWeekMonday) else {
            isLoading = false
            return
        }

        let from = firstMonday.dateString
        let to = lastSunday.dateString

        do {
            let sessions = try await service.fetchSessions(from: from, to: to)
            try Task.checkCancellation()
            let allDays = buildDailyRecords(sessions: sessions, from: firstMonday, to: lastSunday)
            dailyRecords = allDays.filter {
                $0.date.year == currentYear && $0.date.month == currentMonth
            }
            weeklyRecords = buildWeeklyRecords(
                allDays: allDays, firstMonday: firstMonday, monthEnd: monthEnd
            )
            try await pauseTypeStore.load()
            isLoading = false
        } catch is CancellationError {
            // 새 월 이동으로 취소됨 — isLoading은 새 Task가 관리
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// 날짜가 속한 주(월요일)의 id 반환. 히트맵 선택 시 자동 펼침에 사용.
    func weekId(for date: Date) -> String? {
        Self.mondayCalendar.dateInterval(of: .weekOfYear, for: date)?.start.dateString
    }

    /// 이전 로드를 취소하고 최근 N주 데이터를 다시 로드. 빠른 연속 갱신 race 방지용.
    func refreshRecentWeeks(count: Int = 5) {
        loadTask?.cancel()
        loadTask = Task { await loadRecentWeeks(count: count) }
    }

    /// 이번 주를 포함한 최근 `count` 주(월~일)의 데이터를 로드.
    /// 월별 화면이 아닌 타이머 화면처럼 롤링 윈도우가 필요할 때 사용.
    func loadRecentWeeks(count: Int = 5) async {
        isLoading = true

        let cal = Self.mondayCalendar
        let today = Date()
        guard let thisMonday = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let startMonday = cal.date(byAdding: .day, value: -(count - 1) * 7, to: thisMonday),
              let thisSunday = cal.date(byAdding: .day, value: 6, to: thisMonday) else {
            isLoading = false
            return
        }

        let from = startMonday.dateString
        let to = thisSunday.dateString

        do {
            let sessions = try await service.fetchSessions(from: from, to: to)
            try Task.checkCancellation()
            let allDays = buildDailyRecords(sessions: sessions, from: startMonday, to: thisSunday)
            dailyRecords = []
            weeklyRecords = buildWeeklyRecords(
                allDays: allDays, firstMonday: startMonday, monthEnd: thisSunday
            )
            try await pauseTypeStore.load()
            isLoading = false
        } catch is CancellationError {
            // 갱신으로 취소됨
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func goToPreviousMonth() {
        if currentMonth == 1 {
            currentYear -= 1
            currentMonth = 12
        } else {
            currentMonth -= 1
        }
        dailyRecords = []
        weeklyRecords = []
        selectedDate = nil
        loadTask?.cancel()
        loadTask = Task { await loadMonth() }
    }

    func goToNextMonth() {
        if currentMonth == 12 {
            currentYear += 1
            currentMonth = 1
        } else {
            currentMonth += 1
        }
        dailyRecords = []
        weeklyRecords = []
        selectedDate = nil
        loadTask?.cancel()
        loadTask = Task { await loadMonth() }
    }

    func goToToday() {
        let today = Date()
        currentYear = today.year
        currentMonth = today.month
        dailyRecords = []
        weeklyRecords = []
        selectedDate = nil
        loadTask?.cancel()
        loadTask = Task { await loadMonth() }
    }

    // MARK: - Private

    private func buildDailyRecords(sessions: [StudySession], from start: Date, to end: Date) -> [DailyStudyRecord] {
        let cal = Calendar.current

        // 세션을 날짜별로 그룹화
        var grouped: [String: [StudySession]] = [:]
        for session in sessions {
            for key in sessionDateKeys(session) {
                grouped[key, default: []].append(session)
            }
        }

        var records: [DailyStudyRecord] = []
        var cursor = cal.startOfDay(for: start)
        let lastDay = cal.startOfDay(for: end)
        while cursor <= lastDay {
            let key = cursor.dateString
            let daySessions = grouped[key] ?? []
            let totalSeconds = computeDayTotal(sessions: daySessions, date: cursor)
            let pauseSeconds = computeDayPause(sessions: daySessions, date: cursor)
            records.append(DailyStudyRecord(
                id: key, date: cursor,
                totalSeconds: totalSeconds, pauseSeconds: pauseSeconds,
                sessions: daySessions
            ))
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return records
    }

    private func buildWeeklyRecords(
        allDays: [DailyStudyRecord], firstMonday: Date, monthEnd: Date
    ) -> [WeeklyStudyRecord] {
        let cal = Calendar.current
        let lookup = Dictionary(uniqueKeysWithValues: allDays.map { ($0.id, $0) })

        var weeks: [WeeklyStudyRecord] = []
        var weekStart = cal.startOfDay(for: firstMonday)
        let monthEndDay = cal.startOfDay(for: monthEnd)

        while weekStart <= monthEndDay {
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
            var weekDays: [DailyStudyRecord] = []
            for offset in 0..<7 {
                let date = cal.date(byAdding: .day, value: offset, to: weekStart)!
                if let rec = lookup[date.dateString] {
                    weekDays.append(rec)
                } else {
                    weekDays.append(DailyStudyRecord(
                        id: date.dateString, date: date,
                        totalSeconds: 0, pauseSeconds: 0, sessions: []
                    ))
                }
            }
            let total = weekDays.reduce(0) { $0 + $1.totalSeconds }
            let pause = weekDays.reduce(0) { $0 + $1.pauseSeconds }
            weeks.append(WeeklyStudyRecord(
                id: weekStart.dateString,
                weekStart: weekStart, weekEnd: weekEnd,
                totalSeconds: total, pauseSeconds: pause,
                dailyRecords: weekDays
            ))
            weekStart = cal.date(byAdding: .day, value: 7, to: weekStart)!
        }
        return weeks
    }

    /// 세션의 해당 날짜 범위 내 실제 공부 시간 계산
    private func computeDayTotal(sessions: [StudySession], date: Date) -> Int {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        return sessions.reduce(0) { total, session in
            guard let start = Date.fromISO(session.startedAt) else { return total }
            let end = session.effectiveEndDate
            let clippedStart = max(start, dayStart)
            let clippedEnd = min(end, dayEnd)
            guard clippedStart < clippedEnd else { return total }

            let pausedSeconds = clippedPauseSeconds(session: session, rangeStart: clippedStart, rangeEnd: clippedEnd)
            return total + Int(clippedEnd.timeIntervalSince(clippedStart)) - pausedSeconds
        }
    }

    private func computeDayPause(sessions: [StudySession], date: Date) -> Int {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        return sessions.reduce(0) { total, session in
            guard Date.fromISO(session.startedAt) != nil else { return total }
            return total + clippedPauseSeconds(session: session, rangeStart: dayStart, rangeEnd: dayEnd)
        }
    }

    private func clippedPauseSeconds(session: StudySession, rangeStart: Date, rangeEnd: Date) -> Int {
        clippedPauseDetails(session: session, rangeStart: rangeStart, rangeEnd: rangeEnd)
            .reduce(0) { $0 + $1.seconds }
    }

    private func clippedPauseDetails(session: StudySession, rangeStart: Date, rangeEnd: Date) -> [(type: String, seconds: Int)] {
        let sessionEnd = session.effectiveEndDate
        return session.pauses.compactMap { pause in
            guard let ps = Date.fromISO(pause.pausedAt) else { return nil }
            let pe = pause.resumedAt.flatMap { Date.fromISO($0) } ?? sessionEnd
            let cps = max(ps, rangeStart)
            let cpe = min(pe, rangeEnd)
            guard cps < cpe else { return nil }
            return (type: pause.type ?? "REST", seconds: Int(cpe.timeIntervalSince(cps)))
        }
    }

    private func sessionDateKeys(_ session: StudySession) -> [String] {
        guard let start = Date.fromISO(session.startedAt) else {
            return [String(session.startedAt.prefix(10))]
        }
        let startKey = start.dateString
        guard let endStr = session.endedAt, let end = Date.fromISO(endStr) else {
            return [startKey]
        }
        let endKey = end.dateString
        if startKey == endKey { return [startKey] }
        var keys = [startKey]
        let cal = Calendar.current
        var cursor = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: start))!
        while cursor.dateString <= endKey {
            keys.append(cursor.dateString)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return keys
    }
}
