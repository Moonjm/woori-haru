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
        let nextMonth = today.addingMonths(1)

        await loadMonth(prevMonth)
        await loadMonth(today)
        await loadMonth(nextMonth)
    }

    // MARK: - Load More

    func loadPastIfNeeded() async {
        guard !isLoadingPast else { return }
        guard let earliest = dayEntries.first?.date else { return }
        let prevMonth = earliest.addingMonths(-1)
        let key = prevMonth.yearMonth
        guard !loadedMonths.contains(key) else { return }

        isLoadingPast = true
        await loadMonth(prevMonth)
        isLoadingPast = false
    }

    func loadFutureIfNeeded() async {
        guard !isLoadingFuture else { return }
        guard let latest = dayEntries.last?.date else { return }
        let nextMonth = latest.addingMonths(1)
        let key = nextMonth.yearMonth
        guard !loadedMonths.contains(key) else { return }

        isLoadingFuture = true
        await loadMonth(nextMonth)
        isLoadingFuture = false
    }

    // MARK: - Private

    private func loadMonth(_ date: Date) async {
        let key = date.yearMonth
        guard !loadedMonths.contains(key) else { return }
        loadedMonths.insert(key)

        let (from, to) = Date.monthRange(year: date.year, month: date.month)
        do {
            let sessions = try await service.fetchSessions(from: from, to: to)
            let grouped = Dictionary(grouping: sessions) { sessionDateKey($0) }
            let days = generateDays(for: date, sessions: grouped)
            mergeDays(days)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sessionDateKey(_ session: StudySession) -> String {
        guard let date = Date.fromISO(session.startedAt) else {
            return String(session.startedAt.prefix(10))
        }
        return date.dateString
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
        var all = dayEntries + newDays
        // 중복 제거 후 날짜 정렬
        var seen = Set<String>()
        all = all.filter { seen.insert($0.id).inserted }
        all.sort { $0.date < $1.date }
        dayEntries = all
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
