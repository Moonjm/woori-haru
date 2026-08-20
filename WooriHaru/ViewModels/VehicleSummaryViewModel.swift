import Foundation
import Observation

/// 충전 탭 — 월 단위 차량 집계와 그 달 충전 목록. 미등록 배지 수만 월과 무관하게 따로 받는다.
@MainActor
@Observable
final class VehicleSummaryViewModel {

    // MARK: - State

    var month: LedgerYearMonth
    private(set) var summary: VehicleSummaryResponse?
    /// 전체 기간 미등록 건수. 배지와 등록 화면 진입점에 쓴다.
    private(set) var missingCostCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    // MARK: - 의존성

    private let service: VehicleService
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        service: VehicleService = VehicleService(),
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.service = service
        self.now = now
        self.calendar = calendar
        let components = calendar.dateComponents([.year, .month], from: now())
        self.month = LedgerYearMonth(year: components.year ?? 2026, month: components.month ?? 1)
    }

    // MARK: - 파생 값

    struct DaySection: Identifiable {
        let id: Date
        let date: Date
        let items: [ChargeItem]
    }

    var sections: [DaySection] {
        let grouped = Dictionary(grouping: summary?.charges ?? []) { calendar.startOfDay(for: $0.startDate) }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(id: day, date: day, items: grouped[day]!.sorted { $0.startDate > $1.startDate })
        }
    }

    /// 보고 있는 달의 응답을 실제로 받았는지. 로딩·실패의 빈 값을 「0km 탔다」로 그리지 않기 위한 구분이다.
    var isMonthLoaded: Bool { loadedMonth == month }

    var isAtCurrentMonth: Bool { month >= currentMonth }

    private var currentMonth: LedgerYearMonth {
        let components = calendar.dateComponents([.year, .month], from: now())
        return LedgerYearMonth(year: components.year ?? 2026, month: components.month ?? 1)
    }

    // MARK: - 로드

    private var loadedMonth: LedgerYearMonth?
    /// 겹친 요청 중 최신 것만 결과를 반영한다.
    private var reloadGeneration = 0

    func load() async {
        await reload()
        await refreshMissingCount()
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let requested = month
        if requested != loadedMonth {
            summary = nil
            isLoading = true
        }
        defer {
            if generation == reloadGeneration { isLoading = false }
        }
        do {
            let loaded = try await service.fetchSummary(yearMonth: requested.apiValue)
            guard generation == reloadGeneration else { return }
            summary = loaded
            loadedMonth = requested
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration else { return }
            if requested != loadedMonth {
                summary = nil
                loadedMonth = nil
            }
            errorMessage = "차량 요약을 불러오지 못했습니다."
        }
    }

    /// 배지 하나 때문에 화면을 죽이지 않는다 — 실패하면 조용히 0으로 둔다.
    func refreshMissingCount() async {
        do {
            missingCostCount = try await service.fetchMissingCost(limit: 1).totalCount
        } catch {
            return
        }
    }

    func shiftMonth(_ delta: Int) async {
        let next = month.adding(months: delta)
        guard next <= currentMonth else { return }
        month = next
        await reload()
    }

    func selectMonth(year: Int, month selected: Int) async {
        month = min(LedgerYearMonth(year: year, month: selected), currentMonth)
        await reload()
    }
}
