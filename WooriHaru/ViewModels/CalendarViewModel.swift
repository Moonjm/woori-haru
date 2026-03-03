import Foundation
import Observation

// MARK: - MonthData

struct MonthData: Identifiable {
    let id: String          // "yyyy-MM"
    let year: Int
    let month: Int
    let startDate: Date
    var cells: [DayCell]

    struct DayCell: Identifiable {
        let id: String      // "yyyy-MM-dd" or "empty-N"
        let date: Date?
        let day: Int?
    }
}

// MARK: - CalendarViewModel

@MainActor
@Observable
final class CalendarViewModel {

    // MARK: - Published State

    var months: [MonthData] = []
    var records: [String: [DailyRecord]] = [:]
    var overeats: [String: OvereatLevel] = [:]
    var holidays: [String: [String]] = [:]
    var currentMonthLabel: String = ""
    var isDrawerOpen: Bool = false

    // MARK: - Private

    private let recordService = RecordService()
    private let holidayService = HolidayService()
    private let calendar = Calendar.current

    // Track loaded year ranges to avoid duplicate holiday fetches
    private var loadedHolidayYears: Set<Int> = []

    // MARK: - Initial Load

    /// Loads the current month +/- 2 months (5 months total) and fetches data for each.
    func initialLoad() async {
        let today = Date()
        let currentStart = today.startOfMonth()

        var monthList: [MonthData] = []
        for offset in -2...2 {
            let date = currentStart.addingMonths(offset)
            monthList.append(buildMonthData(date))
        }
        months = monthList
        currentMonthLabel = currentStart.monthDisplayText

        // Fetch data for all loaded months concurrently
        await withTaskGroup(of: Void.self) { group in
            for month in monthList {
                group.addTask { [self] in
                    await self.loadMonthData(month)
                }
            }
        }
    }

    // MARK: - Infinite Scroll

    /// Prepends 3 months when the user scrolls toward earlier months.
    func loadEarlierMonths() async {
        guard let earliest = months.first else { return }
        var newMonths: [MonthData] = []
        for offset in stride(from: -3, through: -1, by: 1) {
            let date = earliest.startDate.addingMonths(offset)
            newMonths.append(buildMonthData(date))
        }
        months.insert(contentsOf: newMonths, at: 0)

        await withTaskGroup(of: Void.self) { group in
            for month in newMonths {
                group.addTask { [self] in
                    await self.loadMonthData(month)
                }
            }
        }
    }

    /// Appends 3 months when the user scrolls toward later months.
    func loadLaterMonths() async {
        guard let latest = months.last else { return }
        var newMonths: [MonthData] = []
        for offset in 1...3 {
            let date = latest.startDate.addingMonths(offset)
            newMonths.append(buildMonthData(date))
        }
        months.append(contentsOf: newMonths)

        await withTaskGroup(of: Void.self) { group in
            for month in newMonths {
                group.addTask { [self] in
                    await self.loadMonthData(month)
                }
            }
        }
    }

    // MARK: - Navigation

    /// Jumps to a specific month, loading it (and surrounding months) if needed.
    func scrollToMonth(year: Int, month: Int) async {
        let targetId = String(format: "%04d-%02d", year, month)

        // If the month is already loaded, just update the label
        if months.contains(where: { $0.id == targetId }) {
            let comps = DateComponents(year: year, month: month)
            if let date = calendar.date(from: comps) {
                currentMonthLabel = date.monthDisplayText
            }
            return
        }

        // Otherwise, reload around the target month
        let comps = DateComponents(year: year, month: month)
        guard let targetDate = calendar.date(from: comps) else { return }

        let targetStart = targetDate.startOfMonth()
        var monthList: [MonthData] = []
        for offset in -2...2 {
            let date = targetStart.addingMonths(offset)
            monthList.append(buildMonthData(date))
        }
        months = monthList
        currentMonthLabel = targetStart.monthDisplayText

        await withTaskGroup(of: Void.self) { group in
            for m in monthList {
                group.addTask { [self] in
                    await self.loadMonthData(m)
                }
            }
        }
    }

    // MARK: - Refresh

    /// Clears cached data for the month containing the given date and reloads it.
    func refreshMonth(containing date: Date) async {
        let monthStart = date.startOfMonth()
        let yearMonth = monthStart.yearMonth

        // Clear cached data for every day in this month
        let daysCount = monthStart.daysInMonth()
        for dayOffset in 0..<daysCount {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: monthStart) {
                let key = dayDate.dateString
                records.removeValue(forKey: key)
                overeats.removeValue(forKey: key)
            }
        }

        // Reload data for this month
        if let monthData = months.first(where: { $0.id == yearMonth }) {
            await loadMonthData(monthData)
        }
    }

    // MARK: - Private Helpers

    /// Builds the grid of DayCells for a given month start date.
    /// Generates leading empty cells (for weekday alignment), day cells, and trailing empty cells
    /// to fill a complete 6-row x 7-column grid (42 cells).
    private func buildMonthData(_ startOfMonth: Date) -> MonthData {
        let year = startOfMonth.year
        let month = startOfMonth.month
        let id = startOfMonth.yearMonth

        // Weekday of the first day (1 = Sunday, 7 = Saturday)
        let firstWeekday = startOfMonth.weekday
        let leadingEmpties = firstWeekday - 1
        let daysInMonth = startOfMonth.daysInMonth()

        var cells: [MonthData.DayCell] = []

        // Leading empty cells
        for i in 0..<leadingEmpties {
            cells.append(.init(id: "\(id)-empty-\(i)", date: nil, day: nil))
        }

        // Day cells
        for day in 1...daysInMonth {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            cells.append(.init(id: dayDate.dateString, date: dayDate, day: day))
        }

        // Trailing empty cells to complete the grid (total 42 cells = 6 rows)
        let totalCells = 42
        let trailing = totalCells - cells.count
        for i in 0..<trailing {
            cells.append(.init(id: "\(id)-trail-\(i)", date: nil, day: nil))
        }

        return MonthData(
            id: id,
            year: year,
            month: month,
            startDate: startOfMonth,
            cells: cells
        )
    }

    /// Fetches records, overeats, and holidays for a given month from the services.
    /// Errors are handled gracefully -- failures are logged and skipped.
    private func loadMonthData(_ monthData: MonthData) async {
        let startDate = monthData.startDate
        let daysInMonth = startDate.daysInMonth()
        guard let endDate = calendar.date(byAdding: .day, value: daysInMonth - 1, to: startDate) else { return }

        let fromStr = startDate.dateString
        let toStr = endDate.dateString
        let yearStr = String(monthData.year)

        // Fetch records
        do {
            let fetchedRecords = try await recordService.fetchRecords(from: fromStr, to: toStr)
            for record in fetchedRecords {
                records[record.date, default: []].append(record)
            }
        } catch {
            print("[CalendarVM] Failed to fetch records for \(monthData.id): \(error.localizedDescription)")
        }

        // Fetch overeats
        do {
            let fetchedOvereats = try await recordService.fetchOvereats(from: fromStr, to: toStr)
            for item in fetchedOvereats {
                overeats[item.date] = item.overeatLevel
            }
        } catch {
            print("[CalendarVM] Failed to fetch overeats for \(monthData.id): \(error.localizedDescription)")
        }

        // Fetch holidays (only if not already loaded for this year)
        if !loadedHolidayYears.contains(monthData.year) {
            loadedHolidayYears.insert(monthData.year)
            do {
                let fetchedHolidays = try await holidayService.fetchHolidays(year: yearStr)
                for (date, names) in fetchedHolidays {
                    holidays[date] = names
                }
            } catch {
                // Remove from loaded set so it can be retried later
                loadedHolidayYears.remove(monthData.year)
                print("[CalendarVM] Failed to fetch holidays for \(yearStr): \(error.localizedDescription)")
            }
        }
    }
}
