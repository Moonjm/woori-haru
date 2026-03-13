import Foundation
import Observation

@MainActor
@Observable
final class CategoryStore {
    private(set) var categories: [Category] = []
    private let service = CategoryService()

    var activeCategories: [Category] { categories.filter(\.isActive) }

    func load() async throws {
        categories = try await service.fetchCategories()
        categories.sort { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
    }

    func create(_ request: CategoryRequest) async throws {
        try await service.createCategory(request)
        try await load()
    }

    func update(id: Int, _ request: CategoryRequest) async throws {
        try await service.updateCategory(id: id, request)
        try await load()
    }

    func delete(id: Int) async throws {
        try await service.deleteCategory(id: id)
        try await load()
    }

    func reorder(targetId: Int, beforeId: Int?) async throws {
        try await service.reorderCategory(ReorderCategoryRequest(targetId: targetId, beforeId: beforeId))
    }

    func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }
}
