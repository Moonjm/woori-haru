import Foundation
import Observation

@MainActor
@Observable
final class RecordViewModel {
    // MARK: - State

    var selectedDate: Date = .now
    var records: [DailyRecord] = []
    var partnerRecords: [DailyRecord] = []
    var overeatLevel: OvereatLevel = .none
    var isLoading = false
    var isSaving = false
    var errorMessage: String?

    // MARK: - Form State

    var selectedCategoryId: Int?
    var memo: String = ""
    var together: Bool = false
    var editingRecord: DailyRecord?

    // MARK: - Stores (set from View)

    private(set) var pairStore: PairStore!
    private(set) var categoryStore: CategoryStore!

    func configure(pairStore: PairStore, categoryStore: CategoryStore) {
        self.pairStore = pairStore
        self.categoryStore = categoryStore
    }

    // MARK: - Computed

    var dateString: String {
        selectedDate.dateString
    }

    // MARK: - Services

    private let recordService = RecordService()
    private let pairService = PairService()

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        records = []
        partnerRecords = []
        overeatLevel = .none

        let date = dateString

        do {
            async let fetchedRecords = recordService.fetchRecords(date: date)
            async let fetchedOvereats = recordService.fetchOvereats(from: date, to: date)

            let (loadedRecords, loadedOvereats) = try await (
                fetchedRecords,
                fetchedOvereats
            )

            records = loadedRecords
            overeatLevel = loadedOvereats.first?.overeatLevel ?? .none

            // 파트너 기록
            if pairStore.isPaired {
                do {
                    partnerRecords = try await pairService.fetchPartnerRecords(date: date)
                } catch {
                    partnerRecords = []
                }
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "데이터를 불러오지 못했습니다."
        }
    }

    /// records만 다시 불러오기 (생성/수정/삭제 후 사용)
    private func reloadRecords() async {
        do {
            records = try await recordService.fetchRecords(date: dateString)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "기록을 불러오지 못했습니다."
        }
    }

    // MARK: - Record CRUD

    @discardableResult
    func createRecord() async -> Bool {
        guard let categoryId = selectedCategoryId, !isSaving else { return false }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let request = DailyRecordRequest(
            date: dateString,
            categoryId: categoryId,
            memo: memo.isEmpty ? nil : memo,
            together: together
        )

        do {
            try await recordService.createRecord(request)
            resetForm()
            await reloadRecords()
            return true
        } catch let error as APIError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = "기록 생성에 실패했습니다."
            return false
        }
    }

    @discardableResult
    func updateRecord() async -> Bool {
        guard let record = editingRecord,
              let categoryId = selectedCategoryId,
              !isSaving else { return false }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let request = DailyRecordRequest(
            date: dateString,
            categoryId: categoryId,
            memo: memo.isEmpty ? nil : memo,
            together: together
        )

        do {
            try await recordService.updateRecord(id: record.id, request)
            resetForm()
            await reloadRecords()
            return true
        } catch let error as APIError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = "기록 수정에 실패했습니다."
            return false
        }
    }

    func deleteRecord(_ record: DailyRecord) async {
        errorMessage = nil

        do {
            try await recordService.deleteRecord(id: record.id)
            await reloadRecords()
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
        together = record.together
    }

    func resetForm() {
        editingRecord = nil
        selectedCategoryId = nil
        memo = ""
        together = false
    }

    func prepareForNewDate() {
        resetForm()
        records = []
        partnerRecords = []
        overeatLevel = .none
        errorMessage = nil
    }
}
