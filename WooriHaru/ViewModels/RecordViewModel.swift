import Foundation
import Observation

@MainActor
@Observable
final class RecordViewModel {
    // MARK: - State

    var selectedDate: Date = .now
    var records: [DailyRecord] = []
    var overeatLevel: OvereatLevel = .none
    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Form State

    var selectedCategoryId: Int?
    var memo: String = ""
    var editingRecord: DailyRecord?

    // MARK: - Computed

    var dateString: String {
        selectedDate.dateString
    }

    // MARK: - Services

    private let recordService = RecordService()
    private let categoryService = CategoryService()

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        errorMessage = nil

        let date = dateString

        do {
            async let fetchedRecords = recordService.fetchRecords(date: date)
            async let fetchedCategories = categoryService.fetchCategories(active: true)
            async let fetchedOvereats = recordService.fetchOvereats(from: date, to: date)

            let (loadedRecords, loadedCategories, loadedOvereats) = try await (
                fetchedRecords,
                fetchedCategories,
                fetchedOvereats
            )

            records = loadedRecords
            categories = loadedCategories
            overeatLevel = loadedOvereats.first?.overeatLevel ?? .none
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "데이터를 불러오지 못했습니다."
        }

        isLoading = false
    }

    // MARK: - Record CRUD

    func createRecord() async {
        guard let categoryId = selectedCategoryId else { return }

        errorMessage = nil

        let request = DailyRecordRequest(
            date: dateString,
            categoryId: categoryId,
            memo: memo.isEmpty ? nil : memo,
            together: false
        )

        do {
            try await recordService.createRecord(request)
            resetForm()
            await loadData()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "기록 생성에 실패했습니다."
        }
    }

    func updateRecord() async {
        guard let record = editingRecord,
              let categoryId = selectedCategoryId else { return }

        errorMessage = nil

        let request = DailyRecordRequest(
            date: dateString,
            categoryId: categoryId,
            memo: memo.isEmpty ? nil : memo,
            together: false
        )

        do {
            try await recordService.updateRecord(id: record.id, request)
            resetForm()
            await loadData()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "기록 수정에 실패했습니다."
        }
    }

    func deleteRecord(_ record: DailyRecord) async {
        errorMessage = nil

        do {
            try await recordService.deleteRecord(id: record.id)
            await loadData()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "기록 삭제에 실패했습니다."
        }
    }

    // MARK: - Overeat

    func updateOvereat(_ level: OvereatLevel) async {
        errorMessage = nil

        let request = UpdateOvereatRequest(
            date: dateString,
            overeatLevel: level
        )

        do {
            try await recordService.updateOvereat(request)
            overeatLevel = level
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "과식 레벨 변경에 실패했습니다."
        }
    }

    // MARK: - Form Helpers

    func startEditing(_ record: DailyRecord) {
        editingRecord = record
        selectedCategoryId = record.category.id
        memo = record.memo ?? ""
    }

    func resetForm() {
        editingRecord = nil
        selectedCategoryId = nil
        memo = ""
    }
}
