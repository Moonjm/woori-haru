import Foundation
import Observation

@MainActor
@Observable
final class CategoriesViewModel {
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    // Create form
    var newEmoji: String = ""
    var newName: String = ""
    var newIsActive: Bool = true

    // Edit form
    var editingId: Int?
    var editEmoji: String = ""
    var editName: String = ""
    var editIsActive: Bool = true

    private(set) var categoryStore: CategoryStore!

    func configure(categoryStore: CategoryStore) {
        self.categoryStore = categoryStore
    }

    func loadCategories() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await categoryStore.load()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리를 불러오지 못했습니다."
        }
    }

    func createCategory() async {
        guard !newEmoji.isEmpty, !newName.isEmpty else {
            errorMessage = "이모지와 이름을 입력해주세요."
            return
        }
        errorMessage = nil
        successMessage = nil
        do {
            try await categoryStore.create(CategoryRequest(emoji: newEmoji, name: newName, isActive: newIsActive))
            newEmoji = ""
            newName = ""
            newIsActive = true
            successMessage = "새 카테고리를 추가했어요."
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리 생성에 실패했습니다."
        }
    }

    func updateCategory() async {
        guard let id = editingId, !editEmoji.isEmpty, !editName.isEmpty else { return }
        errorMessage = nil
        successMessage = nil
        do {
            try await categoryStore.update(id: id, CategoryRequest(emoji: editEmoji, name: editName, isActive: editIsActive))
            editingId = nil
            successMessage = "카테고리를 저장했어요."
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리 수정에 실패했습니다."
        }
    }

    func deleteCategory(_ category: Category) async {
        errorMessage = nil
        successMessage = nil
        do {
            try await categoryStore.delete(id: category.id)
            successMessage = "삭제가 완료됐어요."
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리 삭제에 실패했습니다."
        }
    }

    func syncCategoryOrder(movedId: Int) {
        guard let movedIndex = categoryStore.categories.firstIndex(where: { $0.id == movedId }) else { return }
        let beforeId: Int? = (movedIndex + 1 < categoryStore.categories.count) ? categoryStore.categories[movedIndex + 1].id : nil
        Task {
            do {
                try await categoryStore.reorder(targetId: movedId, beforeId: beforeId)
            } catch {
                errorMessage = "카테고리 순서 변경에 실패했습니다."
                await loadCategories()
            }
        }
    }

    func startEditing(_ category: Category) {
        editingId = category.id
        editEmoji = category.emoji
        editName = category.name
        editIsActive = category.isActive
    }

    func cancelEditing() {
        editingId = nil
    }
}
