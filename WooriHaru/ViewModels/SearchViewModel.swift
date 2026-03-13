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

    var categoryStore: CategoryStore!

    private let recordService = RecordService()
    private var allRecords: [DailyRecord] = []

    func loadInitial() async {
        await search()
    }

    func search() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let (fromStr, toStr) = Date.monthRange(year: selectedYear, month: selectedMonth)

        do {
            allRecords = try await recordService.fetchRecords(from: fromStr, to: toStr)
            applyFilters()
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
