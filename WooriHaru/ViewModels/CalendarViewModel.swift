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
    private var isLoadingLater = false
    private var loadedMonthIds: Set<String> = []

    // Track which months have had their API data fetched
    private var dataLoadedMonths: Set<String> = []

    // Track loaded year ranges to avoid duplicate holiday fetches
    private var loadedHolidayYears: Set<Int> = []

    // MARK: - Initial Load

    /// 전체 범위(-120...+120)의 MonthData를 빌드하고,
    /// API 데이터는 현재 월 ±2 만 초기 로드한다.
    func initialLoad() async {
        do {
            pairInfo = try await pairService.getStatus()
            isPaired = pairInfo?.status == .connected
        } catch {
            isPaired = false
        }

        let today = Date()
        let currentStart = today.startOfMonth()

        loadedMonthIds.removeAll()
        dataLoadedMonths.removeAll()

        var monthList: [MonthData] = []
        for offset in -120...120 {
            let date = currentStart.addingMonths(offset)
            let data = buildMonthData(date)
            monthList.append(data)
            loadedMonthIds.insert(data.id)
        }
        months = monthList
        currentMonthLabel = currentStart.monthDisplayText

        // API 데이터는 현재 월 ±2 만 로드
        await ensureDataLoaded(around: currentStart.yearMonth)
    }

    // MARK: - Lazy Data Loading

    /// 현재 스크롤 위치 기준 ±2 월의 API 데이터를 lazy 로드
    func ensureDataLoaded(around monthId: String) async {
        guard let idx = months.firstIndex(where: { $0.id == monthId }) else { return }
        let start = max(0, idx - 2)
        let end = min(months.count - 1, idx + 2)

        var toLoad: [MonthData] = []
        for i in start...end {
            let m = months[i]
            if !dataLoadedMonths.contains(m.id) {
                dataLoadedMonths.insert(m.id)
                toLoad.append(m)
            }
        }
        guard !toLoad.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for month in toLoad {
                group.addTask { [self] in
                    await self.loadMonthData(month)
                }
            }
        }
        updateBirthdays(user: cachedUser, pairInfo: pairInfo)
    }

    // MARK: - Infinite Scroll (Forward Append Only)

    /// Appends 12 months when the user scrolls toward later months.
    func loadLaterMonths() async {
        guard !isLoadingLater, let latest = months.last else { return }
        isLoadingLater = true
        defer { isLoadingLater = false }

        var newMonths: [MonthData] = []
        for offset in 1...12 {
            let date = latest.startDate.addingMonths(offset)
            let data = buildMonthData(date)
            guard !loadedMonthIds.contains(data.id) else { continue }
            newMonths.append(data)
            loadedMonthIds.insert(data.id)
        }
        guard !newMonths.isEmpty else { return }
        months.append(contentsOf: newMonths)
    }

    // MARK: - Navigation

    /// Jumps to a specific month, extending the range if needed.
    func scrollToMonth(year: Int, month: Int) async {
        pickerTargetYear = year
        pickerTargetMonth = month
        let targetId = String(format: "%04d-%02d", year, month)

        // 이미 빌드된 범위 안에 있으면 라벨만 갱신
        if months.contains(where: { $0.id == targetId }) {
            let comps = DateComponents(year: year, month: month)
            if let date = calendar.date(from: comps) {
                currentMonthLabel = date.monthDisplayText
            }
            // 해당 월 근처 API 데이터 로드
            await ensureDataLoaded(around: targetId)
            return
        }

        // 범위 밖이면 해당 월 중심으로 재빌드
        let comps = DateComponents(year: year, month: month)
        guard let targetDate = calendar.date(from: comps) else { return }

        let targetStart = targetDate.startOfMonth()
        loadedMonthIds.removeAll()
        dataLoadedMonths.removeAll()
        loadedHolidayYears.removeAll()

        var monthList: [MonthData] = []
        for offset in -120...120 {
            let date = targetStart.addingMonths(offset)
            let data = buildMonthData(date)
            monthList.append(data)
            loadedMonthIds.insert(data.id)
        }
        months = monthList
        currentMonthLabel = targetStart.monthDisplayText

        await ensureDataLoaded(around: targetId)
        updateBirthdays(user: cachedUser, pairInfo: pairInfo)
    }

    // MARK: - Refresh

    /// Reloads data for the month containing the given date.
    func refreshMonth(containing date: Date) async {
        let yearMonth = date.startOfMonth().yearMonth
        dataLoadedMonths.remove(yearMonth)
        if let monthData = months.first(where: { $0.id == yearMonth }) {
            await loadMonthData(monthData)
            dataLoadedMonths.insert(yearMonth)
        }
    }

    // MARK: - Private Helpers

    /// Builds the grid of DayCells for a given month start date.
    private func buildMonthData(_ startOfMonth: Date) -> MonthData {
        let year = startOfMonth.year
        let month = startOfMonth.month
        let id = startOfMonth.yearMonth

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

    private var cachedUser: User?

    /// 생일 맵 구축
    func updateBirthdays(user: User?, pairInfo: PairInfo?) {
        cachedUser = user
        birthdayMap.removeAll()

        let years = loadedMonthIds.compactMap { Int($0.prefix(4)) }
        let yearRange = Set(years)

        if let birthDateStr = user?.birthDate, let birthDate = Date.from(birthDateStr) {
            let mmdd = String(format: "%02d-%02d", birthDate.month, birthDate.day)
            let genderEmoji = user?.gender == .male ? "👨" : user?.gender == .female ? "👩" : ""
            for year in yearRange {
                let key = "\(year)-\(mmdd)"
                birthdayMap[key, default: []].append((emoji: "🎂\(genderEmoji)", label: "내 생일"))
            }
        }

        if let birthDateStr = pairInfo?.partnerBirthDate, let birthDate = Date.from(birthDateStr) {
            let mmdd = String(format: "%02d-%02d", birthDate.month, birthDate.day)
            let name = pairInfo?.partnerName ?? "파트너"
            let genderEmoji = pairInfo?.partnerGender == .male ? "👨" : pairInfo?.partnerGender == .female ? "👩" : ""
            for year in yearRange {
                let key = "\(year)-\(mmdd)"
                birthdayMap[key, default: []].append((emoji: "🎂\(genderEmoji)", label: "\(name) 생일"))
            }
        }
    }

    /// Fetches records, overeats, and holidays for a given month from the services.
    private func loadMonthData(_ monthData: MonthData) async {
        let startDate = monthData.startDate
        let daysInMonth = startDate.daysInMonth()
        guard let endDate = calendar.date(byAdding: .day, value: daysInMonth - 1, to: startDate) else { return }

        let fromStr = startDate.dateString
        let toStr = endDate.dateString
        let yearStr = String(monthData.year)

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

        if !loadedHolidayYears.contains(monthData.year) {
            loadedHolidayYears.insert(monthData.year)
            do {
                let fetchedHolidays = try await holidayService.fetchHolidays(year: yearStr)
                for (date, names) in fetchedHolidays {
                    holidays[date] = names
                }
            } catch {
                loadedHolidayYears.remove(monthData.year)
                print("[CalendarVM] Failed to fetch holidays for \(yearStr): \(error.localizedDescription)")
            }
        }

        if isPaired {
            do {
                let partnerRecs = try await pairService.fetchPartnerRecords(from: fromStr, to: toStr)
                let groupedPartner = Dictionary(grouping: partnerRecs, by: \.date)
                for dayOffset in 0..<daysInMonth {
                    if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                        partnerRecords[dayDate.dateString] = groupedPartner[dayDate.dateString] ?? []
                    }
                }
            } catch {
                print("[CalendarVM] Failed to fetch partner records: \(error.localizedDescription)")
            }

            do {
                let events = try await pairEventService.fetchEvents(from: fromStr, to: toStr)
                let groupedEvents = Dictionary(grouping: events, by: \.eventDate)
                for dayOffset in 0..<daysInMonth {
                    if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                        pairEvents[dayDate.dateString] = groupedEvents[dayDate.dateString] ?? []
                    }
                }
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
