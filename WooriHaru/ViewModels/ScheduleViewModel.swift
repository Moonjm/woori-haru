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
    struct Badge: Equatable {
        let role: DispatchRole
        let slot: Int?
    }

    private let service: DispatchServing
    private let holidayService: HolidayService
    private let calendar: Calendar

    private(set) var yearMonth: String
    private(set) var cells: [MonthData.DayCell] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var startOfMonth: Date
    private var badgesByDate: [String: [Badge]] = [:]

    /// 받아 둔 공휴일을 연 단위로 들고 있는다. **달을 옮겨도 남는다.**
    /// 화면 상태 안에만 두고 「이미 받았다」는 표시를 바깥에 따로 두면 둘이 어긋나
    /// 공휴일이 통째로 사라진다 — 기본 달력에서 실제로 그렇게 됐다(#70).
    private var holidaysByYear: [Int: [String: [String]]] = [:]

    /// 달을 옮길 때마다 올린다. 늦게 온 이전 달 응답이 새 달 화면을 채우지 못하게 막는다.
    private var generation = 0

    init(
        service: DispatchServing = DispatchService(),
        holidayService: HolidayService = HolidayService(),
        now: Date = Date(),
        calendar: Calendar = .dispatchGregorian
    ) {
        self.service = service
        self.holidayService = holidayService
        self.calendar = calendar
        let start = Self.startOfMonth(for: now, calendar: calendar)
        self.startOfMonth = start
        self.yearMonth = Self.yearMonthString(for: start, calendar: calendar)
        self.cells = MonthGridBuilder.cells(for: start, calendar: calendar)
    }

    var monthLabel: String {
        "\(calendar.component(.year, from: startOfMonth))년 \(calendar.component(.month, from: startOfMonth))월"
    }

    var pickerYear: Int { calendar.component(.year, from: startOfMonth) }
    var pickerMonth: Int { calendar.component(.month, from: startOfMonth) }

    func badges(on dateString: String) -> [Badge] {
        badgesByDate[dateString] ?? []
    }

    func holidayNames(on dateString: String) -> [String] {
        holidaysByYear[calendar.component(.year, from: startOfMonth)]?[dateString] ?? []
    }

    func load() async {
        let token = generation
        isLoading = true
        errorMessage = nil

        await loadHolidaysIfNeeded(year: calendar.component(.year, from: startOfMonth))

        do {
            let days = try await service.findShifts(yearMonth: yearMonth)
            // 조회 중에 달이 바뀌었다. 이 결과는 지금 보이는 달의 것이 아니다.
            guard token == generation else { return }
            badgesByDate = Self.group(days)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            // 서버 메시지가 이미 사용자용 한국어다. 봉투 JSON째 보여주지 않는다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
        guard token == generation else { return }
        isLoading = false
    }

    func move(by months: Int) async {
        guard let next = calendar.date(byAdding: .month, value: months, to: startOfMonth) else { return }
        await show(next)
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
            result[day.date, default: []].append(Badge(role: day.role, slot: day.slot))
        }
        return result.mapValues { badges in
            badges.sorted { roleRank($0.role) < roleRank($1.role) }
        }
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
