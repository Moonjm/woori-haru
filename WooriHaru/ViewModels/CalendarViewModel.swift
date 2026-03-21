import Foundation
import Observation

// MARK: - MonthData

struct MonthData: Identifiable {
    let id: String          // "yyyy-MM"
    let year: Int
    let month: Int
    let startDate: Date
    var cells: [DayCell]

    // Per-month display data (관찰 격리)
    var records: [String: [DailyRecord]] = [:]
    var partnerRecords: [String: [DailyRecord]] = [:]
    var overeats: [String: OvereatLevel] = [:]
    var holidays: [String: [String]] = [:]
    var pairEvents: [String: [PairEvent]] = [:]
    var birthdayMap: [String: [(emoji: String, label: String)]] = [:]

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
    var currentMonthLabel: String = ""
    var isDrawerOpen: Bool = false
    var pickerTargetYear: Int = Calendar.current.component(.year, from: Date())
    var pickerTargetMonth: Int = Calendar.current.component(.month, from: Date())

    // MARK: - Private

    private let recordService = RecordService()
    private let holidayService = HolidayService()
    private let pairService = PairService()  // fetchPartnerRecords용
    private let pairEventService = PairEventService()
    private let calendar = Calendar.current
    private(set) var pairStore: PairStore!

    func configure(pairStore: PairStore) {
        self.pairStore = pairStore
    }

    private var isLoadingLater = false
    private var loadedMonthIds: Set<String> = []

    // Track which months have had their API data fetched
    private var dataLoadedMonths: Set<String> = []

    // Track loaded year ranges to avoid duplicate holiday fetches
    private var loadedHolidayYears: Set<Int> = []

    // MARK: - Initial Load

    /// 전체 범위(-36...+36)의 MonthData를 빌드하고,
    /// API 데이터는 현재 월 ±2 만 초기 로드한다.
    func initialLoad() async {
        let today = Date()
        let currentStart = today.startOfMonth()

        loadedMonthIds.removeAll()
        dataLoadedMonths.removeAll()

        var monthList: [MonthData] = []
        for offset in -36...36 {
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
                toLoad.append(m)
            }
        }
        guard !toLoad.isEmpty else { return }

        // 로드 시작 전에 마킹 (중복 호출 방지)
        let loadingIds = Set(toLoad.map(\.id))
        dataLoadedMonths.formUnion(loadingIds)

        await withTaskGroup(of: String?.self) { group in
            for month in toLoad {
                group.addTask { [self] in
                    do {
                        try await self.loadMonthData(month)
                        return nil // 성공
                    } catch {
                        return month.id // 실패한 id 반환
                    }
                }
            }
            for await failedId in group {
                if let failedId {
                    dataLoadedMonths.remove(failedId)
                }
            }
        }
        updateBirthdays(user: cachedUser, pairInfo: pairStore.pairInfo)
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

    /// months 배열을 해당 월 중심으로 재빌드 (동기). 이미 범위 안이면 false 반환.
    @discardableResult
    func rebuildMonthsIfNeeded(year: Int, month: Int) -> Bool {
        pickerTargetYear = year
        pickerTargetMonth = month
        let targetId = String(format: "%04d-%02d", year, month)

        // 이미 빌드된 범위 안에 있으면 라벨만 갱신
        if months.contains(where: { $0.id == targetId }) {
            let comps = DateComponents(year: year, month: month)
            if let date = calendar.date(from: comps) {
                currentMonthLabel = date.monthDisplayText
            }
            return false
        }

        // 범위 밖이면 해당 월 중심으로 재빌드
        let comps = DateComponents(year: year, month: month)
        guard let targetDate = calendar.date(from: comps) else { return false }

        let targetStart = targetDate.startOfMonth()
        loadedMonthIds.removeAll()
        dataLoadedMonths.removeAll()
        loadedHolidayYears.removeAll()

        var monthList: [MonthData] = []
        for offset in -36...36 {
            let date = targetStart.addingMonths(offset)
            let data = buildMonthData(date)
            monthList.append(data)
            loadedMonthIds.insert(data.id)
        }
        months = monthList
        currentMonthLabel = targetStart.monthDisplayText
        return true
    }

    /// Jumps to a specific month, extending the range if needed.
    func scrollToMonth(year: Int, month: Int) async {
        rebuildMonthsIfNeeded(year: year, month: month)
        let targetId = String(format: "%04d-%02d", year, month)
        await ensureDataLoaded(around: targetId)
        updateBirthdays(user: cachedUser, pairInfo: pairStore.pairInfo)
    }

    // MARK: - Refresh

    /// Reloads data for the month containing the given date.
    func refreshMonth(containing date: Date) async {
        let yearMonth = date.startOfMonth().yearMonth
        dataLoadedMonths.remove(yearMonth)
        if let monthData = months.first(where: { $0.id == yearMonth }) {
            do {
                try await loadMonthData(monthData)
                dataLoadedMonths.insert(yearMonth)
            } catch {
                // 실패 시 캐시에 추가하지 않아 재시도 가능
                print("[CalendarVM] Failed to refresh \(yearMonth): \(error.localizedDescription)")
            }
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

        // 다음 월 날짜 (trailing) - 마지막 주만 채움 (7의 배수)
        let remainder = cells.count % 7
        if remainder > 0 {
            let trailingCount = 7 - remainder
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

    /// 특정 날짜의 공휴일 이름 조회 (RecordSheetView용)
    func holidayNames(for date: Date) -> [String] {
        let monthId = date.startOfMonth().yearMonth
        guard let month = months.first(where: { $0.id == monthId }) else { return [] }
        return month.holidays[date.dateString] ?? []
    }

    /// 생일 맵 구축 — 각 MonthData에 직접 저장
    func updateBirthdays(user: User?, pairInfo: PairInfo?) {
        cachedUser = user

        // 기존 birthdayMap 클리어
        for i in months.indices where !months[i].birthdayMap.isEmpty {
            months[i].birthdayMap.removeAll()
        }

        let yearRange = Set(months.map(\.year))

        if let birthDateStr = user?.birthDate, let birthDate = Date.from(birthDateStr) {
            let mmdd = String(format: "%02d-%02d", birthDate.month, birthDate.day)
            let genderEmoji = user?.gender == .male ? "👨" : user?.gender == .female ? "👩" : ""
            for year in yearRange {
                let dateKey = "\(year)-\(mmdd)"
                let monthId = String(dateKey.prefix(7))
                if let idx = months.firstIndex(where: { $0.id == monthId }) {
                    months[idx].birthdayMap[dateKey, default: []].append((emoji: "🎂\(genderEmoji)", label: "내 생일"))
                }
            }
        }

        if let birthDateStr = pairInfo?.partnerBirthDate, let birthDate = Date.from(birthDateStr) {
            let mmdd = String(format: "%02d-%02d", birthDate.month, birthDate.day)
            let name = pairInfo?.partnerName ?? "파트너"
            let genderEmoji = pairInfo?.partnerGender == .male ? "👨" : pairInfo?.partnerGender == .female ? "👩" : ""
            for year in yearRange {
                let dateKey = "\(year)-\(mmdd)"
                let monthId = String(dateKey.prefix(7))
                if let idx = months.firstIndex(where: { $0.id == monthId }) {
                    months[idx].birthdayMap[dateKey, default: []].append((emoji: "🎂\(genderEmoji)", label: "\(name) 생일"))
                }
            }
        }
    }

    /// Fetches records, overeats, and holidays for a given month from the services.
    /// records 조회 실패 시 throw하여 재시도 가능하게 함.
    private func loadMonthData(_ monthData: MonthData) async throws {
        let startDate = monthData.startDate
        let daysInMonth = startDate.daysInMonth()
        guard let endDate = calendar.date(byAdding: .day, value: daysInMonth - 1, to: startDate) else { return }

        let fromStr = startDate.dateString
        let toStr = endDate.dateString
        let yearStr = String(monthData.year)

        // records는 핵심 데이터 — 실패 시 throw
        let fetchedRecords = try await recordService.fetchRecords(from: fromStr, to: toStr)
        var recordBatch: [String: [DailyRecord]] = [:]
        for dayOffset in 0..<daysInMonth {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                recordBatch[dayDate.dateString] = []
            }
        }
        for record in fetchedRecords {
            recordBatch[record.date, default: []].append(record)
        }

        var overeatBatch: [String: OvereatLevel] = [:]
        do {
            let fetchedOvereats = try await recordService.fetchOvereats(from: fromStr, to: toStr)
            for item in fetchedOvereats {
                overeatBatch[item.date] = item.overeatLevel
            }
        } catch {
            print("[CalendarVM] Failed to fetch overeats for \(monthData.id): \(error.localizedDescription)")
        }

        if !loadedHolidayYears.contains(monthData.year) {
            loadedHolidayYears.insert(monthData.year)
            do {
                let fetchedHolidays = try await holidayService.fetchHolidays(year: yearStr)
                for (date, names) in fetchedHolidays {
                    let hMonthId = String(date.prefix(7))
                    if let hIdx = months.firstIndex(where: { $0.id == hMonthId }) {
                        months[hIdx].holidays[date] = names
                    }
                }
            } catch {
                loadedHolidayYears.remove(monthData.year)
                print("[CalendarVM] Failed to fetch holidays for \(yearStr): \(error.localizedDescription)")
            }
        }

        var partnerBatch: [String: [DailyRecord]] = [:]
        var eventBatch: [String: [PairEvent]] = [:]

        if pairStore.isPaired {
            do {
                let partnerRecs = try await pairService.fetchPartnerRecords(from: fromStr, to: toStr)
                let groupedPartner = Dictionary(grouping: partnerRecs, by: \.date)
                for dayOffset in 0..<daysInMonth {
                    if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                        partnerBatch[dayDate.dateString] = groupedPartner[dayDate.dateString] ?? []
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
                        eventBatch[dayDate.dateString] = groupedEvents[dayDate.dateString] ?? []
                    }
                }
                for event in events where event.recurring {
                    let mmdd = String(event.eventDate.suffix(5))
                    let thisYearDate = "\(monthData.year)-\(mmdd)"
                    if thisYearDate != event.eventDate {
                        eventBatch[thisYearDate, default: []].append(event)
                    }
                }
            } catch {
                print("[CalendarVM] Failed to fetch pair events: \(error.localizedDescription)")
            }
        }

        // 모든 데이터를 한번에 적용 — months[idx] 갱신 최소화
        guard let idx = months.firstIndex(where: { $0.id == monthData.id }) else { return }
        months[idx].records = recordBatch
        months[idx].overeats = overeatBatch
        months[idx].partnerRecords = partnerBatch
        months[idx].pairEvents = eventBatch
    }
}
