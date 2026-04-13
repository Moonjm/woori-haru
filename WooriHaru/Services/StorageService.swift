import Foundation

struct StorageService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    // MARK: - Storage

    func fetchStorages() async throws -> [Storage] {
        let response: DataResponse<[Storage]> = try await api.get("/storages")
        return response.data ?? []
    }

    func createStorage(name: String, storageType: String?) async throws {
        try await api.postVoid("/storages", body: StorageCreateRequest(name: name, storageType: storageType))
    }

    func updateStorage(id: Int, name: String, storageType: String?) async throws {
        try await api.putVoid("/storages/\(id)", body: StorageUpdateRequest(name: name, storageType: storageType))
    }

    func deleteStorage(id: Int) async throws {
        try await api.deleteVoid("/storages/\(id)")
    }

    func reorderStorages(targetId: Int, beforeId: Int?) async throws {
        try await api.putVoid("/storages/order", body: OrderRequest(targetId: targetId, beforeId: beforeId))
    }

    // MARK: - Section

    func createSection(storageId: Int, name: String) async throws {
        try await api.postVoid("/storages/\(storageId)/sections", body: SectionCreateRequest(name: name))
    }

    func updateSection(storageId: Int, sectionId: Int, name: String) async throws {
        try await api.putVoid("/storages/\(storageId)/sections/\(sectionId)", body: SectionUpdateRequest(name: name))
    }

    func deleteSection(storageId: Int, sectionId: Int) async throws {
        try await api.deleteVoid("/storages/\(storageId)/sections/\(sectionId)")
    }

    func reorderSections(storageId: Int, targetId: Int, beforeId: Int?) async throws {
        try await api.putVoid("/storages/\(storageId)/sections/order", body: OrderRequest(targetId: targetId, beforeId: beforeId))
    }

    // MARK: - Item

    func createItem(storageId: Int, request: ItemRequest) async throws {
        try await api.postVoid("/storages/\(storageId)/items", body: request)
    }

    func updateItem(storageId: Int, itemId: Int, request: ItemRequest) async throws {
        try await api.putVoid("/storages/\(storageId)/items/\(itemId)", body: request)
    }

    func deleteItem(storageId: Int, itemId: Int) async throws {
        try await api.deleteVoid("/storages/\(storageId)/items/\(itemId)")
    }
}
