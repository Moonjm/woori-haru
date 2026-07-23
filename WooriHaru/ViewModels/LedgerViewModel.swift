import Foundation
import Observation

/// 내역 탭(월 목록) 뷰모델. 검색은 전용 화면(LedgerSearchView)이 따로 담당한다.
@MainActor
@Observable
final class LedgerViewModel {

    // MARK: - State

    var month = LedgerYearMonth.current()

    private(set) var entries: [LedgerEntry] = []
    private(set) var isLoading = false
    var errorMessage: String?

    // MARK: - Service

    private let ledgerService = LedgerService()

    // MARK: - 파생 값

    /// 하루 단위로 묶은 섹션 (최신 날짜 먼저)
    struct DaySection: Identifiable {
        let id: Date
        let date: Date
        let entries: [LedgerEntry]
        let krwTotal: Decimal
    }

    var sections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let items = grouped[day]!.sorted { $0.date > $1.date }
            return DaySection(id: day, date: day, entries: items, krwTotal: Self.krwExpenseTotal(items))
        }
    }

    /// 원화 지출 합계 (외화는 환산하지 않으므로 제외)
    var monthlyKRWTotal: Decimal { Self.krwExpenseTotal(entries) }

    /// 통화별 외화 지출 합계 (환산 없이 통화별로 그대로). 통화 오름차순.
    var foreignTotals: [(currency: String, amount: Decimal)] {
        var map: [String: Decimal] = [:]
        for entry in entries where entry.type == .expense && LedgerFormat.isForeign(entry.currency) {
            map[entry.currency.uppercased(), default: .zero] += entry.amount
        }
        return map.sorted { $0.key < $1.key }.map { (currency: $0.key, amount: $0.value) }
    }

    /// 외화 지출을 결제 시점 환율 메모 기준으로 원화 환산한 합계. 환율 메모가 없는 건은 제외.
    /// 환율 메모의 환산액은 절대값이므로 취소 보정(음수) 건은 부호를 입혀 합계를 줄인다.
    var foreignConvertedKRWTotal: Decimal {
        var sum = Decimal.zero
        for entry in entries where entry.type == .expense && LedgerFormat.isForeign(entry.currency) {
            guard let converted = entry.fxConvertedAmount else { continue }
            sum += entry.amount < 0 ? -abs(converted) : abs(converted)
        }
        return sum
    }

    private static func krwExpenseTotal(_ list: [LedgerEntry]) -> Decimal {
        var sum = Decimal.zero
        for entry in list where entry.type == .expense && entry.currency.uppercased() == "KRW" {
            sum += entry.amount
        }
        return sum
    }

    // MARK: - 로드

    /// 마지막으로 로드에 성공한 달 — 다른 달 요청 시 이전 데이터를 즉시 비우기 위한 기준.
    private var loadedMonth: LedgerYearMonth?
    /// 진행 중 reload의 세대 번호 — 같은 달끼리 겹쳐도(새로고침+저장 콜백) 최신 요청만
    /// 결과 반영과 로딩 해제를 담당하고, 밀려난 응답은 폐기된다.
    private var reloadGeneration = 0

    func load() async {
        await reload()
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let requested = month
        // 다른 달을 불러오는 동안 이전 달 데이터가 새 달의 것처럼 보이지 않게 즉시 비운다.
        // (같은 달 새로고침은 기존 목록을 유지한 채 갱신)
        if requested != loadedMonth {
            entries = []
            isLoading = true
        }
        defer {
            if generation == reloadGeneration { isLoading = false }
        }
        do {
            let list = try await ledgerService.fetchEntries(yearMonth: requested.apiValue)
            guard generation == reloadGeneration else { return } // 밀려난 응답은 폐기
            entries = list
            loadedMonth = requested
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration else { return }
            // 같은 달 새로고침 실패면 보고 있던 목록은 그대로 두고 에러만 알린다.
            if requested != loadedMonth {
                entries = []
                loadedMonth = nil // 화면이 빈 상태이므로 다음 reload는 로딩 표시부터 시작
            }
            errorMessage = "내역을 불러오지 못했습니다."
        }
    }

    /// 오늘이 속한 달인지 — 미래 달 이동 차단·버튼 비활성 표시에 쓴다.
    var isAtCurrentMonth: Bool { month >= LedgerYearMonth.current() }

    func shiftMonth(_ delta: Int) async {
        let next = month.adding(months: delta)
        // 미래 달 내역은 있을 수 없으니 오늘이 속한 달까지만 이동한다.
        guard next <= LedgerYearMonth.current() else { return }
        month = next
        await reload()
    }
}
