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

    private static func krwExpenseTotal(_ list: [LedgerEntry]) -> Decimal {
        var sum = Decimal.zero
        for entry in list where entry.type == .expense && entry.currency.uppercased() == "KRW" {
            sum += entry.amount
        }
        return sum
    }

    // MARK: - 로드

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await reload()
    }

    func reload() async {
        let requested = month
        do {
            let list = try await ledgerService.fetchEntries(yearMonth: requested.apiValue)
            guard requested == month else { return } // 응답 도착 전에 월이 바뀌었으면 폐기
            entries = list
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard requested == month else { return }
            // 이전 월 결과가 현재 월의 데이터처럼 보이지 않게 비운다.
            entries = []
            errorMessage = "내역을 불러오지 못했습니다."
        }
    }

    func shiftMonth(_ delta: Int) async {
        month = month.adding(months: delta)
        await reload()
    }
}
