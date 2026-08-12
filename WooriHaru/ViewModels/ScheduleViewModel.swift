import Foundation
import os

/// 배차 근무를 월 단위로 보여준다. **조회 전용이다** — 여기서 고치지 않는다.
///
/// 서버 조회가 월 단위(`GET /dispatch/shifts?yearMonth=`)라 화면 단위도 한 달로 맞춘다.
/// 기본 달력처럼 세로로 이어 붙이면 화면 단위와 조회 단위가 어긋나 조회가 흩어진다.
@MainActor
@Observable
final class ScheduleViewModel {
    /// 칸 하나에 그릴 근무 표시. 순번이 없으면 색만 칠한다.
    /// **아빠는 `slot`, 엄마는 `slotCode`다.** 역할마다 쓰는 필드가 다르다.
    struct Badge: Equatable {
        let role: DispatchRole
        let slot: Int?
        let slotCode: String?
    }

    private let service: DispatchServing
    private let holidayService: HolidayService
    private let calendar: Calendar

    /// 시계. `refreshToday()`가 이것으로 `today`를 다시 읽는다.
    private let now: @Sendable () -> Date

    /// 화면이 「오늘」로 여기는 날. **관찰되는 저장 프로퍼티여야 한다.**
    ///
    /// 시계를 그때그때 읽는 계산 프로퍼티로 두면 SwiftUI가 의존성을 걸 대상이 없다 —
    /// 시간이 흐르는 것만으로는 저장 프로퍼티가 하나도 안 바뀌므로 화면을 다시 그리지
    /// 않고, 말일 자정을 넘겨도 「오늘」 버튼이 잠긴 채로 굳는다. 버튼이 잠기면 탭이
    /// `goToToday()`에 닿지도 못해, 정작 필요한 순간에 못 쓰게 된다.
    ///
    /// 날짜가 바뀌면 화면이 `refreshToday()`를 불러 여기를 갱신한다.
    private(set) var today: Date

    private(set) var yearMonth: String
    private(set) var cells: [MonthData.DayCell] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var startOfMonth: Date
    private var badgesByDate: [String: [Badge]] = [:]

    /// 날짜별 원본. **편집 시트가 휴무와 미등록을 갈라야 해서 필요하다** — `badgesByDate`는
    /// 근무일만 담으므로 「휴무로 저장됨」과 「저장된 적 없음」이 둘 다 빈 값으로 보인다.
    private var daysByDate: [String: [DispatchShiftDay]] = [:]

    /// 아빠와 엄마가 **둘 다 확정 휴무**인 날. 부모님이 함께 시간을 낼 수 있는 날이라
    /// 이 달력을 여는 실제 이유에 가깝다.
    private var bothOffDates: Set<String> = []

    /// 받아 둔 공휴일을 연 단위로 들고 있는다. **달을 옮겨도 남는다.**
    /// 화면 상태 안에만 두고 「이미 받았다」는 표시를 바깥에 따로 두면 둘이 어긋나
    /// 공휴일이 통째로 사라진다 — 기본 달력에서 실제로 그렇게 됐다(#70).
    private var holidaysByYear: [Int: [String: [String]]] = [:]

    /// 달을 옮길 때마다 올린다. 늦게 온 이전 달 응답이 새 달 화면을 채우지 못하게 막는다.
    private var generation = 0

    init(
        service: DispatchServing = DispatchService(),
        holidayService: HolidayService = HolidayService(),
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .dispatchGregorian
    ) {
        self.service = service
        self.holidayService = holidayService
        self.calendar = calendar
        self.now = now
        let today = now()
        self.today = today
        let start = Self.startOfMonth(for: today, calendar: calendar)
        self.startOfMonth = start
        self.yearMonth = Self.yearMonthString(for: start, calendar: calendar)
        self.cells = MonthGridBuilder.cells(for: start, calendar: calendar)
    }

    var monthLabel: String {
        "\(calendar.component(.year, from: startOfMonth))년 \(calendar.component(.month, from: startOfMonth))월"
    }

    var pickerYear: Int { calendar.component(.year, from: startOfMonth) }
    var pickerMonth: Int { calendar.component(.month, from: startOfMonth) }

    /// 이번 달을 보고 있는가. 「오늘」 버튼을 잠그는 데 쓴다.
    var isViewingCurrentMonth: Bool {
        startOfMonth == Self.startOfMonth(for: today, calendar: calendar)
    }

    /// 그 날짜가 오늘인가. **칸이 스스로 `Date.isToday`로 판단하지 않고 여기서 받아 간다.**
    ///
    /// 두 가지가 걸려 있다. 하나는 날이 바뀌었을 때 — 칸 안에서 시계를 읽으면 입력값이
    /// 그대로라 SwiftUI가 칸을 다시 그리지 않아 어제가 계속 굵게 남는다. 다른 하나는
    /// 기기 달력 — `Date.isToday`는 `Calendar.current`를 쓰므로, 기기가 비그레고리력이면
    /// 같은 화면의 다른 값들(주입 달력으로 계산한 것)과 어긋난다.
    func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: today)
    }

    /// 날이 바뀌었다. 화면이 날짜 변경 알림을 받아 부른다.
    func refreshToday() {
        today = now()
    }

    func badges(on dateString: String) -> [Badge] {
        badgesByDate[dateString] ?? []
    }

    /// 두 사람이 **둘 다 쉬는** 날인가. **미등록은 여기 들어오지 않는다** — 아빠 배차표를
    /// 아직 안 올린 달은 값이 없을 뿐인데, 그것을 휴무로 세면 한 달 내내 「둘 다 쉬는 날」이
    /// 된다. 서버가 아빠의 휴무도 레코드로 내려주므로 없는 것과 쉬는 것이 갈린다.
    func isBothOff(on dateString: String) -> Bool {
        bothOffDates.contains(dateString)
    }

    /// 편집 시트에 넘길 그날의 원본. 휴무도 들어 있고, 미등록이면 비어 있다.
    func shiftDays(on dateString: String) -> [DispatchShiftDay] {
        daysByDate[dateString] ?? []
    }

    /// 하루 편집의 저장 결과를 화면에 반영한다. **그 날짜만 갈아 끼운다.**
    ///
    /// 달 전체를 다시 조회하지 않는다 — 칸 하나를 고치자고 한 달치를 다시 받는 왕복이고,
    /// 그 사이 화면이 잠깐 비었다 채워진다. 서버가 204를 주는 근거도 같다: 두 역할이 한
    /// 트랜잭션이라 성공했으면 보낸 것이 전부 들어갔고, 안 보낸 역할은 안 바뀐다.
    ///
    /// **「둘 다 휴무」도 같이 다시 센다.** 밴드만 갈면, 두 사람이 함께 쉬게 된 날의 초록
    /// 배경이 달을 옮겼다 돌아올 때까지 따라오지 않는다.
    func apply(_ days: [DispatchShiftDay], on dateString: String) {
        daysByDate[dateString] = days

        let badges = Self.group(days)[dateString] ?? []
        if badges.isEmpty {
            badgesByDate.removeValue(forKey: dateString)
        } else {
            badgesByDate[dateString] = badges
        }

        if Self.datesBothOff(days).contains(dateString) {
            bothOffDates.insert(dateString)
        } else {
            bothOffDates.remove(dateString)
        }
    }

    func holidayNames(on dateString: String) -> [String] {
        holidaysByYear[calendar.component(.year, from: startOfMonth)]?[dateString] ?? []
    }

    func load() async {
        let token = generation
        isLoading = true
        errorMessage = nil

        do {
            let days = try await service.findShifts(yearMonth: yearMonth)
            // 조회 중에 달이 바뀌었다. 이 결과는 지금 보이는 달의 것이 아니다.
            guard token == generation else { return }
            badgesByDate = Self.group(days)
            bothOffDates = Self.datesBothOff(days)
            daysByDate = Dictionary(grouping: days, by: \.date)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            // 서버 메시지가 이미 사용자용 한국어다. 봉투 JSON째 보여주지 않는다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
        guard token == generation else { return }
        isLoading = false

        // **공휴일은 근무를 그린 뒤에 채운다.** 부가 정보를 먼저 기다리면, 공휴일 쪽이
        // 느리기만 해도 근무 조회가 시작조차 못 해 화면이 빈 채로 남는다. 실패는 캐시하지
        // 않으므로 달을 옮길 때마다 그 지연이 되풀이된다.
        await loadHolidaysIfNeeded(year: calendar.component(.year, from: startOfMonth))
    }

    func move(by months: Int) async {
        guard let next = calendar.date(byAdding: .month, value: months, to: startOfMonth) else { return }
        await show(next)
    }

    /// 이번 달로 돌아간다. **이미 이번 달이면 아무것도 하지 않는다** — 같은 달을 다시
    /// 조회하는 값 없는 왕복이고, 그 사이 화면이 흐려졌다 돌아와 눌린 것처럼만 보인다.
    ///
    /// **누른 시점의 날짜로 먼저 맞춘다.** 날짜 변경 알림이 늦거나 오지 않은 경우에도
    /// 「오늘」이 어제로 가지 않게 한다.
    func goToToday() async {
        refreshToday()
        guard !isViewingCurrentMonth else { return }
        await show(today)
    }

    func jump(year: Int, month: Int) async {
        guard let next = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return }
        await show(next)
    }

    /// `2026-09` 문자열로 그 달을 띄운다. 저장을 마치고 돌아올 때 **저장한 달**을 보여주는
    /// 자리다 — 배차표는 다음 달치를 등록하는 것이 정상이라, 보고 있던 달로 돌아오면
    /// 방금 넣은 것이 화면에 없다.
    func show(yearMonth: String) async {
        // 형식이 어긋나면 아무것도 하지 않는다. 보고 있던 달을 유지하는 편이,
        // 엉뚱한 달로 튀는 것보다 낫다.
        guard let parsed = Self.parseYearMonth(yearMonth) else { return }
        await jump(year: parsed.year, month: parsed.month)
    }

    private func show(_ start: Date) async {
        generation += 1
        startOfMonth = Self.startOfMonth(for: start, calendar: calendar)
        yearMonth = Self.yearMonthString(for: startOfMonth, calendar: calendar)
        cells = MonthGridBuilder.cells(for: startOfMonth, calendar: calendar)
        // 이전 달 값을 지운다. 남겨 두면 조회가 끝나기 전까지 이전 달 근무가 새 달에 보인다.
        badgesByDate = [:]
        bothOffDates = []
        daysByDate = [:]
        await load()
    }

    /// **실패해도 조용히 넘어간다.** 근무가 주 정보고 공휴일은 부가다.
    private func loadHolidaysIfNeeded(year: Int) async {
        guard holidaysByYear[year] == nil else { return }
        do {
            holidaysByYear[year] = try await holidayService.fetchHolidays(year: String(year))
        } catch {
            Logger.calendar.error("공휴일 조회 실패: \(year) \(error.localizedDescription)")
        }
    }

    /// 날짜별로 모으고 **역할 순서를 고정한다.** 응답 순서대로 그리면 날마다 위아래가 바뀐다.
    ///
    /// **연월로 다시 거르지 않는다.** `findShifts(yearMonth:)`는 그 달의 날짜만 돌려주는
    /// 계약이다 — 여기서 또 거르면 서버가 실제로 무엇을 보냈는지 조용히 감추고, 서버가
    /// 계약을 어겨도 화면이 티 내지 않는다. 늦게 온 이전 달 응답을 막는 일은 `load()`의
    /// `generation` 토큰이 한다.
    private static func group(_ days: [DispatchShiftDay]) -> [String: [Badge]] {
        var result: [String: [Badge]] = [:]
        for day in days where day.working {
            result[day.date, default: []].append(Badge(role: day.role, slot: day.slot, slotCode: day.slotCode))
        }
        return result.mapValues { badges in
            badges.sorted { roleRank($0.role) < roleRank($1.role) }
        }
    }

    /// 두 사람이 **둘 다 쉬는** 날짜들.
    ///
    /// **레코드가 있고 그것이 휴무여야 한다.** 없는 것과 쉬는 것은 다르다 — 아빠 배차표를
    /// 아직 안 올린 달은 아빠 레코드가 통째로 없는데, 그것을 휴무로 세면 그 달 전체가
    /// 「둘 다 쉬는 날」이 되어 달력이 그럴듯한 거짓말을 한다.
    private static func datesBothOff(_ days: [DispatchShiftDay]) -> Set<String> {
        var offRolesByDate: [String: Set<DispatchRole>] = [:]
        for day in days where !day.working {
            offRolesByDate[day.date, default: []].insert(day.role)
        }
        return Set(offRolesByDate.filter { $0.value == [.father, .mother] }.keys)
    }

    /// 엄마를 먼저 그린다(화면에서 위). 역할별 순위를 매겨 비교해야 엄격 약순서를 지킨다 —
    /// `lhs.role == .mother`처럼 한쪽만 보고 비교하면 `엄마, 엄마`처럼 자기 자신과
    /// 견줄 때도 참이 나와 정렬 결과가 정의되지 않는다.
    private static func roleRank(_ role: DispatchRole) -> Int {
        switch role {
        case .mother: return 0
        case .father: return 1
        }
    }

    /// `Date.startOfMonth()`(Date+Extensions)는 `Calendar.current`를 쓴다. 기기 달력이
    /// 불교력이면 연도가 어긋나므로(`DispatchModels.swift`의 `Calendar.dispatchGregorian`
    /// 참고) 주입받은 `calendar`로 직접 계산한다.
    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps)!
    }

    /// `Date.yearMonth`(Date+Extensions)와 같은 이유로 여기서 직접 만든다 — 서버로
    /// 나가는 값이라 `Calendar.current`를 타면 안 된다.
    private static func yearMonthString(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year!, comps.month!)
    }

    /// `DispatchReviewViewModel.isValidYearMonth`와 같은 형식(`^\d{4}-(0[1-9]|1[0-2])$`)만
    /// 받는다 — 검수 화면이 이미 그 형식으로만 저장을 허용하므로, 여기서 어긋난 값이
    /// 온다면 호출자 쪽 문제다. 그래도 크래시 대신 조용히 실패한다.
    private static func parseYearMonth(_ value: String) -> (year: Int, month: Int)? {
        guard value.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: "-")
        guard let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        return (year, month)
    }
}
