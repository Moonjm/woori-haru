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
    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?

    private let recordService = RecordService()
    private let categoryService = CategoryService()
    private var allRecords: [DailyRecord] = []

    func loadInitial() async {
        do {
            categories = try await categoryService.fetchCategories()
        } catch {
            print("[SearchVM] Failed to load categories: \(error.localizedDescription)")
        }
        await search()
    }

    func search() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let (fromStr, toStr) = dateRange(year: selectedYear, month: selectedMonth)

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

    private func dateRange(year: Int, month: Int) -> (String, String) {
        if month == 0 { return ("\(year)-01-01", "\(year)-12-31") }
        let from = String(format: "%04d-%02d-01", year, month)
        let cal = Calendar.current
        let comps = DateComponents(year: year, month: month)
        let startDate = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: startDate)!
        let to = String(format: "%04d-%02d-%02d", year, month, range.count)
        return (from, to)
    }
}
