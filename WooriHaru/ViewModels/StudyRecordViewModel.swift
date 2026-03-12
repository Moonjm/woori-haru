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
    var selectedDate: Date?
    var isLoading = false
    var errorMessage: String?

    var pauseTypes: [PauseType] = []

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
        let grandTotal = max(totals.reduce(0) { $0 + $1.seconds }, 1)
        return totals.map { item in
            SubjectStudyRecord(
                id: item.id, name: item.name,
                totalSeconds: item.seconds,
                ratio: Double(item.seconds) / Double(grandTotal)
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
        pauseTypes.first(where: { $0.value == value })?.label ?? value
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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let (from, to) = Date.monthRange(year: currentYear, month: currentMonth)
        do {
            let sessions = try await service.fetchSessions(from: from, to: to)
            dailyRecords = buildDailyRecords(sessions: sessions)
            if pauseTypes.isEmpty {
                pauseTypes = try await service.fetchPauseTypes()
            }
        } catch is CancellationError {
            // 화면 이탈 시 Task 취소 — 무시
        } catch {
            errorMessage = error.localizedDescription
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
        selectedDate = nil
        Task { await loadMonth() }
    }

    func goToNextMonth() {
        if currentMonth == 12 {
            currentYear += 1
            currentMonth = 1
        } else {
            currentMonth += 1
        }
        dailyRecords = []
        selectedDate = nil
        Task { await loadMonth() }
    }

    func goToToday() {
        let today = Date()
        currentYear = today.year
        currentMonth = today.month
        dailyRecords = []
        selectedDate = nil
        Task { await loadMonth() }
    }

    // MARK: - Private

    private func buildDailyRecords(sessions: [StudySession]) -> [DailyStudyRecord] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: DateComponents(year: currentYear, month: currentMonth)) else { return [] }
        let daysCount = monthStart.daysInMonth()

        // 세션을 날짜별로 그룹화
        var grouped: [String: [StudySession]] = [:]
        for session in sessions {
            for key in sessionDateKeys(session) {
                grouped[key, default: []].append(session)
            }
        }

        return (0..<daysCount).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: monthStart) else { return nil }
            let key = date.dateString
            let daySessions = grouped[key] ?? []
            let totalSeconds = computeDayTotal(sessions: daySessions, date: date)
            let pauseSeconds = computeDayPause(sessions: daySessions, date: date)
            return DailyStudyRecord(id: key, date: date, totalSeconds: totalSeconds, pauseSeconds: pauseSeconds, sessions: daySessions)
        }
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
