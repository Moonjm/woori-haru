import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedMonth: Int = 0  // 0 = 전체
    var selectedCategoryId: Int?  // nil = 전체
    var keyword: String = ""
    var results: [DailyRecord] = []
    var isLoading = false
    var errorMessage: String?

    private(set) var categoryStore: CategoryStore!

    func configure(categoryStore: CategoryStore) {
        self.categoryStore = categoryStore
    }

    private let recordService = RecordService()
    private var allRecords: [DailyRecord] = []
    private var searchTask: Task<Void, Never>?

    func loadInitial() async {
        await search()
    }

    func reloadSearch() {
        searchTask?.cancel()
        searchTask = Task { await search() }
    }

    func search() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let (fromStr, toStr) = Date.monthRange(year: selectedYear, month: selectedMonth)

        do {
            let fetched = try await recordService.fetchRecords(from: fromStr, to: toStr)
            try Task.checkCancellation()
            allRecords = fetched
            applyFilters()
        } catch is CancellationError {
            // 새 검색 요청으로 취소됨 — 무시
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "검색에 실패했습니다."
        }
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

        results = filtered.sorted { $0.date < $1.date }
    }

}
