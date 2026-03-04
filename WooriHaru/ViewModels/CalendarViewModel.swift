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
        let id: String      // "yyyy-MM-dd"
        let date: Date
        let day: Int
        let isCurrentMonth: Bool
    }
}

// MARK: - CalendarViewModel

@MainActor
@Observable
final class CalendarViewModel {

    // MARK: - Published State

    var months: [MonthData] = []
    var records: [String: [DailyRecord]] = [:]
    var partnerRecords: [String: [DailyRecord]] = [:]
    var overeats: [String: OvereatLevel] = [:]
    var holidays: [String: [String]] = [:]
    var pairEvents: [String: [PairEvent]] = [:]
    var birthdayMap: [String: [(emoji: String, label: String)]] = [:]
    var currentMonthLabel: String = ""
    var isDrawerOpen: Bool = false
    var isPaired: Bool = false
    var pairInfo: PairInfo?
    var pickerTargetYear: Int = Calendar.current.component(.year, from: Date())
    var pickerTargetMonth: Int = Calendar.current.component(.month, from: Date())

    // MARK: - Private

    private let recordService = RecordService()
    private let holidayService = HolidayService()
    private let pairService = PairService()
    private let pairEventService = PairEventService()
    private let calendar = Calendar.current
    private var isLoadingEarlier = false
    private var isLoadingLater = false
    private var loadedMonthIds: Set<String> = []

    // Track loaded year ranges to avoid duplicate holiday fetches
    private var loadedHolidayYears: Set<Int> = []

    // MARK: - Initial Load

    /// Loads the current month +/- 2 months (5 months total) and fetches data for each.
    func initialLoad() async {
        // 페어 상태 확인
        do {
            pairInfo = try await pairService.getStatus()
            isPaired = pairInfo?.status == .connected
        } catch {
            isPaired = false
        }

        let today = Date()
        let currentStart = today.startOfMonth()

        var monthList: [MonthData] = []
        for offset in -2...2 {
            let date = currentStart.addingMonths(offset)
            let data = buildMonthData(date)
            monthList.append(data)
            loadedMonthIds.insert(data.id)
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
        guard !isLoadingEarlier, let earliest = months.first else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }

        var newMonths: [MonthData] = []
        for offset in stride(from: -3, through: -1, by: 1) {
            let date = earliest.startDate.addingMonths(offset)
            let data = buildMonthData(date)
            guard !loadedMonthIds.contains(data.id) else { continue }
            newMonths.append(data)
        }
        guard !newMonths.isEmpty else { return }

        for m in newMonths { loadedMonthIds.insert(m.id) }
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
        guard !isLoadingLater, let latest = months.last else { return }
        isLoadingLater = true
        defer { isLoadingLater = false }

        var newMonths: [MonthData] = []
        for offset in 1...3 {
            let date = latest.startDate.addingMonths(offset)
            let data = buildMonthData(date)
            guard !loadedMonthIds.contains(data.id) else { continue }
            newMonths.append(data)
        }
        guard !newMonths.isEmpty else { return }

        for m in newMonths { loadedMonthIds.insert(m.id) }
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
        pickerTargetYear = year
        pickerTargetMonth = month
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
        loadedMonthIds.removeAll()
        var monthList: [MonthData] = []
        for offset in -2...2 {
            let date = targetStart.addingMonths(offset)
            let data = buildMonthData(date)
            monthList.append(data)
            loadedMonthIds.insert(data.id)
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

    /// Reloads data for the month containing the given date.
    /// Data clearing is handled by loadMonthData itself.
    func refreshMonth(containing date: Date) async {
        let yearMonth = date.startOfMonth().yearMonth
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

        // 이전 월 날짜 (leading)
        for i in (0..<leadingEmpties).reversed() {
            let prevDate = calendar.date(byAdding: .day, value: -(i + 1), to: startOfMonth)!
            cells.append(.init(id: "\(id)-prev-\(prevDate.dateString)", date: prevDate, day: prevDate.day, isCurrentMonth: false))
        }

        // 현재 월 날짜
        for day in 1...daysInMonth {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            cells.append(.init(id: dayDate.dateString, date: dayDate, day: day, isCurrentMonth: true))
        }

        // 다음 월 날짜 (trailing) - 항상 42칸(6주) 고정
        let trailingCount = 42 - cells.count
        if trailingCount > 0 {
            let lastDay = calendar.date(byAdding: .day, value: daysInMonth - 1, to: startOfMonth)!
            for i in 1...trailingCount {
                let nextDate = calendar.date(byAdding: .day, value: i, to: lastDay)!
                cells.append(.init(id: "\(id)-next-\(nextDate.dateString)", date: nextDate, day: nextDate.day, isCurrentMonth: false))
            }
        }

        return MonthData(
            id: id,
            year: year,
            month: month,
            startDate: startOfMonth,
            cells: cells
        )
    }

    /// 생일 맵 구축 (CalendarView에서 authVM.user 전달)
    func updateBirthdays(user: User?, pairInfo: PairInfo?) {
        birthdayMap.removeAll()

        let years = loadedMonthIds.compactMap { Int($0.prefix(4)) }
        let yearRange = Set(years)

        // 내 생일
        if let birthDate = user?.birthDate, birthDate.count >= 10 {
            let mmdd = String(birthDate.suffix(5))
            let genderEmoji = user?.gender == .male ? "👨" : user?.gender == .female ? "👩" : ""
            for year in yearRange {
                let key = "\(year)-\(mmdd)"
                birthdayMap[key, default: []].append((emoji: "🎂\(genderEmoji)", label: "내 생일"))
            }
        }

        // 파트너 생일
        if let birthDate = pairInfo?.partnerBirthDate, birthDate.count >= 10 {
            let mmdd = String(birthDate.suffix(5))
            let name = pairInfo?.partnerName ?? "파트너"
            let genderEmoji = pairInfo?.partnerGender == .male ? "👨" : pairInfo?.partnerGender == .female ? "👩" : ""
            for year in yearRange {
                let key = "\(year)-\(mmdd)"
                birthdayMap[key, default: []].append((emoji: "🎂\(genderEmoji)", label: "\(name) 생일"))
            }
        }
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

        // Fetch records (clear first to prevent duplication on reload)
        do {
            let fetchedRecords = try await recordService.fetchRecords(from: fromStr, to: toStr)
            for dayOffset in 0..<daysInMonth {
                if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                    records[dayDate.dateString] = []
                }
            }
            for record in fetchedRecords {
                records[record.date, default: []].append(record)
            }
        } catch {
            print("[CalendarVM] Failed to fetch records for \(monthData.id): \(error.localizedDescription)")
        }

        // Fetch overeats (clear first to prevent stale data)
        do {
            let fetchedOvereats = try await recordService.fetchOvereats(from: fromStr, to: toStr)
            for dayOffset in 0..<daysInMonth {
                if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                    overeats.removeValue(forKey: dayDate.dateString)
                }
            }
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

        // Fetch partner records (only when paired)
        if isPaired {
            do {
                let partnerRecs = try await pairService.fetchPartnerRecords(from: fromStr, to: toStr)
                for dayOffset in 0..<daysInMonth {
                    if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                        partnerRecords[dayDate.dateString] = []
                    }
                }
                for record in partnerRecs {
                    partnerRecords[record.date, default: []].append(record)
                }
            } catch {
                print("[CalendarVM] Failed to fetch partner records: \(error.localizedDescription)")
            }

            do {
                let events = try await pairEventService.fetchEvents(from: fromStr, to: toStr)
                for event in events {
                    pairEvents[event.eventDate, default: []].append(event)
                }
                // recurring 이벤트: 현재 연도의 MM-DD에도 추가
                for event in events where event.recurring {
                    let mmdd = String(event.eventDate.suffix(5))
                    let thisYearDate = "\(monthData.year)-\(mmdd)"
                    if thisYearDate != event.eventDate {
                        pairEvents[thisYearDate, default: []].append(event)
                    }
                }
            } catch {
                print("[CalendarVM] Failed to fetch pair events: \(error.localizedDescription)")
            }
        }
    }
}
