import Foundation
import Observation

@MainActor
@Observable
final class LedgerViewModel {

    // MARK: - State

    var month = LedgerYearMonth.current()
    var searchText = ""
    var isSearching = false

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

    var expenseCount: Int { entries.filter { $0.type == .expense }.count }

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

    /// 이 조회가 어떤 요청이었는지 식별한다. 응답 도착 시 현재 요청과 다르면(월 이동·검색으로
    /// 바뀌었으면) 오래된 응답이므로 버려 화면이 뒤바뀌지 않게 한다.
    private struct Request: Equatable {
        let yearMonth: String?
        let keyword: String?
    }

    private var currentRequest: Request {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if isSearching, !keyword.isEmpty {
            return Request(yearMonth: nil, keyword: keyword)
        }
        return Request(yearMonth: month.apiValue, keyword: nil)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await reload()
    }

    func reload() async {
        let request = currentRequest
        do {
            let list = try await ledgerService.fetchEntries(yearMonth: request.yearMonth, keyword: request.keyword)
            guard request == currentRequest else { return } // 사이에 월·검색이 바뀌었으면 폐기
            entries = list
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard request == currentRequest else { return }
            errorMessage = "내역을 불러오지 못했습니다."
        }
    }

    func shiftMonth(_ delta: Int) async {
        month = month.adding(months: delta)
        await reload()
    }
}
