import Foundation
import Observation

/// 충전 내역 목록(월 단위) 뷰모델. 가계부 내역 목록과 같은 월 이동 규칙을 따른다.
@MainActor
@Observable
final class ChargeListViewModel {

    // MARK: - State

    var month: LedgerYearMonth
    private(set) var items: [ChargeItem] = []
    /// 서버 SQL 집계 — 목록을 더해 만들지 않는다.
    private(set) var summary: ChargeSummary = .empty
    private(set) var isLoading = false
    var errorMessage: String?

    // MARK: - 의존성

    private let service: ChargeService
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        service: ChargeService = ChargeService(),
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

    /// 하루 단위로 묶은 섹션 (최신 날짜 먼저). 충전 시작 시각 기준이다.
    struct DaySection: Identifiable {
        let id: Date
        let date: Date
        let items: [ChargeItem]
    }

    var sections: [DaySection] {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.startDate) }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(id: day, date: day, items: grouped[day]!.sorted { $0.startDate > $1.startDate })
        }
    }

    /// 금액이 아직 안 들어간 건수 — 이 화면에 오는 이유가 그것이라 눈에 띄게 센다.
    var missingCostCount: Int { items.filter { $0.cost == nil }.count }

    /// 오늘이 속한 달인지 — 미래 달 이동 차단·버튼 비활성 표시에 쓴다.
    var isAtCurrentMonth: Bool { month >= currentMonth }

    private var currentMonth: LedgerYearMonth {
        let components = calendar.dateComponents([.year, .month], from: now())
        return LedgerYearMonth(year: components.year ?? 2026, month: components.month ?? 1)
    }

    // MARK: - 로드

    /// 마지막으로 로드에 성공한 달 — 다른 달을 요청하면 이전 데이터를 즉시 비우기 위한 기준.
    private var loadedMonth: LedgerYearMonth?
    /// 진행 중 reload의 세대 번호 — 겹친 요청 중 최신 것만 결과를 반영한다.
    private var reloadGeneration = 0

    func load() async {
        await reload()
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let requested = month
        // 다른 달을 불러오는 동안 이전 달 목록이 새 달의 것처럼 보이지 않게 즉시 비운다.
        if requested != loadedMonth {
            items = []
            summary = .empty
            isLoading = true
        }
        defer {
            if generation == reloadGeneration { isLoading = false }
        }
        do {
            let response = try await service.fetchCharges(yearMonth: requested.apiValue)
            guard generation == reloadGeneration else { return } // 밀려난 응답은 폐기
            items = response.items
            summary = response.summary
            loadedMonth = requested
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration else { return }
            // 같은 달 새로고침 실패면 보고 있던 목록은 두고 에러만 알린다.
            // **빈 목록으로 눙치지 않는다** — 「충전한 적 없음」과 구분되지 않는다.
            if requested != loadedMonth {
                items = []
                summary = .empty
                loadedMonth = nil
            }
            errorMessage = "충전 내역을 불러오지 못했습니다."
        }
    }

    func shiftMonth(_ delta: Int) async {
        let next = month.adding(months: delta)
        // 미래 달 충전 기록은 있을 수 없으니 오늘이 속한 달까지만 이동한다.
        guard next <= currentMonth else { return }
        month = next
        await reload()
    }

    /// 연월 피커로 미래 달을 골라도 오늘이 속한 달로 되돌린다.
    func selectMonth(year: Int, month selected: Int) async {
        month = min(LedgerYearMonth(year: year, month: selected), currentMonth)
        await reload()
    }

    func goToCurrentMonth() async {
        month = currentMonth
        await reload()
    }
}
