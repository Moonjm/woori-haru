import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var selectedYear: Int = 0  // 0 = 전체 기간 (기본값)
    var selectedMonth: Int = 0  // 0 = 전체
    var selectedCategoryId: Int?  // nil = 전체
    var keyword: String = ""
    var results: [DailyRecord] = []
    var isLoading = false
    var errorMessage: String?

    private(set) var categoryStore: CategoryStore!
    private(set) var pairStore: PairStore!

    func configure(categoryStore: CategoryStore, pairStore: PairStore) {
        self.categoryStore = categoryStore
        self.pairStore = pairStore
    }

    private let recordService = RecordService()
    private let pairService = PairService()
    private var allRecords: [DailyRecord] = []
    private var searchTask: Task<Void, Never>?

    /// 전체 기간 검색의 시작 연도 (기록 도입 이전이라도 안전하게 포함)
    private let earliestRecordYear = 2018

    func loadInitial() {
        reloadSearch()
    }

    func reloadSearch() {
        searchTask?.cancel()
        searchTask = Task { await search() }
    }

    func search() async {
        isLoading = true
        errorMessage = nil

        let (fromStr, toStr) = dateRange()

        do {
            let mine = try await recordService.fetchRecords(from: fromStr, to: toStr)
            try Task.checkCancellation()

            var combined = mine
            // 페어 연결 시 파트너가 등록한 "함께 기록"도 검색 대상에 포함
            if pairStore.isPaired {
                let partner = try? await pairService.fetchPartnerRecords(from: fromStr, to: toStr)
                try Task.checkCancellation()  // 파트너 fetch가 취소되면 stale 결과 덮어쓰기 방지
                if let partner {
                    combined += partner.filter(\.together)
                }
            }

            allRecords = combined
            applyFilters()
            isLoading = false
        } catch is CancellationError {
            // 새 검색 요청으로 취소됨 — isLoading은 새 Task가 관리
        } catch let error as APIError {
            errorMessage = error.errorDescription
            isLoading = false
        } catch {
            errorMessage = "검색에 실패했습니다."
            isLoading = false
        }
    }

    /// 검색할 날짜 범위. selectedYear == 0이면 전체 기간(earliestRecordYear ~ 내년)
    private func dateRange() -> (from: String, to: String) {
        if selectedYear == 0 {
            let currentYear = Calendar.current.component(.year, from: Date())
            return ("\(earliestRecordYear)-01-01", "\(currentYear + 1)-12-31")
        }
        return Date.monthRange(year: selectedYear, month: selectedMonth)
    }

    func applyFilters() {
        var filtered = allRecords

        if let catId = selectedCategoryId {
            filtered = filtered.filter { $0.category.id == catId }
        }

        if !keyword.isEmpty {
            let lowered = keyword.lowercased()
            filtered = filtered.filter { ($0.memo ?? "").lowercased().contains(lowered) }
        }

        results = filtered.sorted { $0.date > $1.date }
    }

}
