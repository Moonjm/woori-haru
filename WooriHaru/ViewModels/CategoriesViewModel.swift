import Foundation
import Observation

@MainActor
@Observable
final class CategoriesViewModel {
    var categories: [Category] = []
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

    private let categoryService = CategoryService()

    func loadCategories() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            categories = try await categoryService.fetchCategories()
            categories.sort { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
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
            try await categoryService.createCategory(CategoryRequest(emoji: newEmoji, name: newName, isActive: newIsActive))
            newEmoji = ""
            newName = ""
            newIsActive = true
            successMessage = "새 카테고리를 추가했어요."
            await loadCategories()
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
            try await categoryService.updateCategory(id: id, CategoryRequest(emoji: editEmoji, name: editName, isActive: editIsActive))
            editingId = nil
            successMessage = "카테고리를 저장했어요."
            await loadCategories()
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
            try await categoryService.deleteCategory(id: category.id)
            successMessage = "삭제가 완료됐어요."
            await loadCategories()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리 삭제에 실패했습니다."
        }
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)

        guard let sourceIndex = source.first else { return }
        let movedIndex = sourceIndex < destination ? destination - 1 : destination
        let moved = categories[movedIndex]
        let beforeId: Int? = (movedIndex + 1 < categories.count) ? categories[movedIndex + 1].id : nil

        Task {
            do {
                try await categoryService.reorderCategory(ReorderCategoryRequest(targetId: moved.id, beforeId: beforeId))
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
