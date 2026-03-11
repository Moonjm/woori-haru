import SwiftUI

struct DayEntry: Identifiable {
    let id: String // "yyyy-MM-dd"
    let date: Date
    let sessions: [StudySession]
}

@MainActor
@Observable
final class StudySessionLogViewModel {
    var dayEntries: [DayEntry] = []
    var isLoadingPast = false
    var isLoadingFuture = false
    var errorMessage: String?

    private let service = StudyService()
    private var loadedMonths: Set<String> = [] // "yyyy-MM"

    // MARK: - Initial Load

    func loadInitial() async {
        let today = Date()
        let prevMonth = today.addingMonths(-1)

        await loadMonth(prevMonth)
        await loadMonth(today)
    }

    // MARK: - Load More

    func loadPastIfNeeded() async {
        guard !isLoadingPast else { return }
        guard let earliest = dayEntries.first?.date else { return }
        let prevMonth = earliest.addingMonths(-1)
        let key = prevMonth.yearMonth
        guard !loadedMonths.contains(key) else { return }

        isLoadingPast = true
        defer { isLoadingPast = false }
        await loadMonth(prevMonth)
    }

    func loadFutureIfNeeded() async {
        guard !isLoadingFuture else { return }
        guard let latest = dayEntries.last?.date else { return }
        let nextMonth = latest.addingMonths(1)
        let key = nextMonth.yearMonth
        guard !loadedMonths.contains(key) else { return }

        isLoadingFuture = true
        defer { isLoadingFuture = false }
        await loadMonth(nextMonth)
    }

    // MARK: - Private

    private func loadMonth(_ date: Date) async {
        let key = date.yearMonth
        guard !loadedMonths.contains(key) else { return }
        loadedMonths.insert(key)

        let (from, to) = Date.monthRange(year: date.year, month: date.month)
        do {
            let sessions = try await service.fetchSessions(from: from, to: to)
            var grouped: [String: [StudySession]] = [:]
            for session in sessions {
                for key in sessionDateKeys(session) {
                    grouped[key, default: []].append(session)
                }
            }
            let days = generateDays(for: date, sessions: grouped)
            mergeDays(days)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 세션이 속하는 날짜 키 목록 반환 (자정을 넘기면 양일 모두 포함)
    private func sessionDateKeys(_ session: StudySession) -> [String] {
        guard let start = Date.fromISO(session.startedAt) else {
            return [String(session.startedAt.prefix(10))]
        }
        let startKey = start.dateString
        guard let endStr = session.endedAt,
              let end = Date.fromISO(endStr) else {
            return [startKey]
        }
        let endKey = end.dateString
        if startKey == endKey {
            return [startKey]
        }
        // 자정을 넘긴 경우 양일 포함
        var keys = [startKey]
        let cal = Calendar.current
        var cursor = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: start))!
        while cursor.dateString <= endKey {
            keys.append(cursor.dateString)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return keys
    }

    private func generateDays(for monthDate: Date, sessions: [String: [StudySession]]) -> [DayEntry] {
        let cal = Calendar.current
        let start = monthDate.startOfMonth()
        let daysCount = monthDate.daysInMonth()

        return (0..<daysCount).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = date.dateString
            return DayEntry(id: key, date: date, sessions: sessions[key] ?? [])
        }
    }

    private func mergeDays(_ newDays: [DayEntry]) {
        var entriesById = Dictionary(uniqueKeysWithValues: dayEntries.map { ($0.id, $0) })
        for day in newDays {
            entriesById[day.id] = day
        }
        dayEntries = entriesById.values.sorted { $0.date < $1.date }
    }

    func todayEntryIndex() -> Int? {
        let todayKey = Date().dateString
        return dayEntries.firstIndex { $0.id == todayKey }
    }

    func entryId(for date: Date) -> String {
        date.dateString
    }

    /// 특정 날짜로 이동 시 해당 월 데이터가 없으면 로드
    func ensureMonthLoaded(for date: Date) async {
        let key = date.yearMonth
        if !loadedMonths.contains(key) {
            await loadMonth(date)
        }
    }

    var currentVisibleDate: Date = Date()
}
