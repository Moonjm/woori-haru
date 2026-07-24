import Foundation
import Observation

/// 가계부 통계 탭 뷰모델 — 기간 선택 상태와 /entries/statistics 로드, 요약 파생 값을 담당한다.
/// 월별(최근 6개월 추이)·연별(12개월 추이)을 전환할 수 있고, 기간을 앞뒤로 이동할 수 있다.
@MainActor
@Observable
final class LedgerStatsViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case monthly = "월별"
        case yearly = "연별"
        var id: String { rawValue }
    }

    // MARK: - State

    var scope: Scope = .monthly
    var month = LedgerYearMonth.current()
    var year = LedgerYearMonth.current().year
    private(set) var stats: LedgerStatistics?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 차트에서 선택한 월 (yearMonth 문자열). 로드 시 기본값이 정해진다.
    var selectedMonth: String?
    /// 진행 중 로드의 세대 번호 — 기간을 오갔다 되돌아와도 최신 요청만 화면을 갱신한다.
    private var loadGeneration = 0

    private let ledgerService: LedgerService

    /// 기간 이동 하한 — 서버가 거부하는 범위 밖 연도를 요청하지 않게 막는다.
    static let minYear = 2000

    init(ledgerService: LedgerService = LedgerService()) {
        self.ledgerService = ledgerService
    }

    // MARK: - 기간 파생 값

    var periodTitle: String {
        scope == .monthly ? month.displayLong : "\(year)년"
    }

    var isAtCurrentPeriod: Bool {
        let current = LedgerYearMonth.current()
        return scope == .monthly ? month == current : year == current.year
    }

    var isAtMinPeriod: Bool {
        scope == .monthly
            ? month.year == Self.minYear && month.month == 1
            : year == Self.minYear
    }

    var summaryTitle: String {
        switch scope {
        case .monthly:
            let current = LedgerYearMonth.current()
            if month.year == current.year { return "\(month.month)월 지출" }
            return "\(month.year)년 \(month.month)월 지출"
        case .yearly:
            return "\(year)년 지출"
        }
    }

    // MARK: - 통계 파생 값

    /// 기준 기간 총 지출(원화 + 외화 환산) — 월별이면 추이 마지막(기준월), 연별이면 12개월 합.
    var currentTotal: Decimal {
        guard let stats else { return 0 }
        switch scope {
        case .monthly: return stats.monthlyTrend.last?.combinedTotal ?? 0
        case .yearly: return stats.monthlyTrend.reduce(Decimal.zero) { $0 + $1.combinedTotal }
        }
    }

    /// 직전 기간 총 지출 — 서버 값 우선, 구버전 응답이면 추이에서 지난달을 취한다.
    var previousTotal: Decimal {
        guard let stats else { return 0 }
        if let previous = stats.previousTotal { return previous }
        guard scope == .monthly, stats.monthlyTrend.count >= 2 else { return 0 }
        return stats.monthlyTrend[stats.monthlyTrend.count - 2].combinedTotal
    }

    var deltaPercent: Int? {
        let previous = previousTotal
        guard previous > 0 else { return nil }
        let ratio = ((currentTotal - previous) as NSDecimalNumber).doubleValue
            / (previous as NSDecimalNumber).doubleValue
        return Int((ratio * 100).rounded())
    }

    /// 추이에 외화 환산 지출이 있는지 — 범례 표시 여부.
    var hasFx: Bool {
        stats?.monthlyTrend.contains { ($0.fxKrwTotal ?? 0) != 0 } ?? false
    }

    /// 차트 콜아웃에 표시할 선택 키 — 탭 선택이 없으면 기본 선택을 따른다.
    var selectedTrendKey: String? {
        guard let stats else { return nil }
        return selectedMonth ?? Self.defaultSelectedMonth(stats, scope: scope)
    }

    /// 콜아웃 기본 선택 — 월별은 기준월, 연별은 지출이 있는 마지막 달.
    private static func defaultSelectedMonth(_ stats: LedgerStatistics, scope: Scope) -> String? {
        switch scope {
        case .monthly:
            return stats.yearMonth
        case .yearly:
            return (stats.monthlyTrend.last { $0.combinedTotal > 0 } ?? stats.monthlyTrend.last)?.yearMonth
        }
    }

    // MARK: - 기간 이동

    func shiftPeriod(_ delta: Int) {
        switch scope {
        case .monthly:
            let next = month.adding(months: delta)
            guard next.year >= Self.minYear else { return }
            month = next
        case .yearly:
            let next = year + delta
            guard next >= Self.minYear else { return }
            year = next
        }
        reloadForPeriodChange()
    }

    /// 현재 기간(이번 달/올해)으로 즉시 복귀한다.
    func resetToCurrentPeriod() {
        let current = LedgerYearMonth.current()
        switch scope {
        case .monthly: month = current
        case .yearly: year = current.year
        }
        reloadForPeriodChange()
    }

    func selectScope(_ newScope: Scope) {
        guard scope != newScope else { return }
        scope = newScope
        reloadForPeriodChange()
    }

    /// 월별 기간 선택 시트 확정 — 미래 달을 골라도 오늘이 속한 달까지로 되돌린다 (내역 탭과 동일).
    func selectMonthlyPeriod(year pickedYear: Int, month pickedMonth: Int) {
        month = min(LedgerYearMonth(year: pickedYear, month: pickedMonth), LedgerYearMonth.current())
        reloadForPeriodChange()
    }

    /// 연별 기간 선택 시트 확정.
    func selectYearlyPeriod(_ pickedYear: Int) {
        year = pickedYear
        reloadForPeriodChange()
    }

    // MARK: - 로드

    /// 기간이 바뀌면 이전 기간 데이터가 새 라벨 아래 보이지 않게 비우고 다시 불러온다.
    func reloadForPeriodChange() {
        // 새 load Task가 시작되기 전에 이전 요청의 응답이 도착해도 반영되지 않도록
        // 세대를 여기서 동기적으로 무효화한다.
        loadGeneration += 1
        stats = nil
        selectedMonth = nil
        errorMessage = nil
        Task { await load() }
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestScope = scope
        let requestMonth = month
        let requestYear = year
        isLoading = true
        // A→B→A처럼 같은 기간으로 되돌아와도 세대 번호가 다르므로 밀려난 응답은 폐기된다.
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let result: LedgerStatistics
            switch requestScope {
            case .monthly: result = try await ledgerService.fetchStatistics(yearMonth: requestMonth.apiValue)
            case .yearly: result = try await ledgerService.fetchStatistics(year: requestYear)
            }
            guard generation == loadGeneration else { return }
            stats = result
            selectedMonth = Self.defaultSelectedMonth(result, scope: requestScope)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = "통계를 불러오지 못했습니다."
        }
    }
}
