import Foundation

@MainActor
struct CategoryService {
    private let api = APIClient.shared

    func fetchCategories(active: Bool? = nil) async throws -> [Category] {
        var query: [String: String] = [:]
        if let active { query["active"] = String(active) }
        let response: DataResponse<[Category]> = try await api.get("/categories", query: query)
        return response.data ?? []
    }

    func createCategory(_ request: CategoryRequest) async throws {
        try await api.postVoid("/categories", body: request)
    }

    func updateCategory(id: Int, _ request: CategoryRequest) async throws {
        try await api.putVoid("/categories/\(id)", body: request)
    }

    func deleteCategory(id: Int) async throws {
        try await api.deleteVoid("/categories/\(id)")
    }

    func reorderCategory(_ request: ReorderCategoryRequest) async throws {
        try await api.putVoid("/categories/order", body: request)
    }
}
