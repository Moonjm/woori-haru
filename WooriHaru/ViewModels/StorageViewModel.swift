import Foundation
import Observation

@MainActor
@Observable
final class StorageViewModel {
    // MARK: - State

    var storages: [Storage] = []
    var selectedStorageIndex: Int = 0
    var isLoading = false
    var errorMessage: String?

    // MARK: - Sheet State

    var showAddStorageSheet = false
    var showAddItemSheet = false
    var editingItem: StorageItem?
    var editingSectionId: Int?

    // MARK: - Storage Form

    var storageFormName: String = ""
    var storageFormType: StorageType = .fridge

    // MARK: - Section Form

    var newSectionName: String = ""
    var editingSectionForRename: StorageSection?
    var sectionRenameName: String = ""

    // MARK: - Item Form

    var itemFormName: String = ""
    var itemFormQuantity: Int = 1
    var itemFormExpiryDate: Date? = nil
    var itemFormCategory: ItemCategory = .other
    var itemFormSectionId: Int?

    private let service = StorageService()

    // MARK: - Computed

    var selectedStorage: Storage? {
        guard storages.indices.contains(selectedStorageIndex) else { return nil }
        return storages[selectedStorageIndex]
    }

    var expiringItems: [(item: StorageItem, sectionName: String)] {
        guard let storage = selectedStorage else { return [] }
        let today = Self.dateString(from: Date())
        let threeDaysLater = Self.dateString(from: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date())
        return storage.sections.flatMap { section in
            section.items.compactMap { item in
                guard let expiry = item.expiryDate, expiry <= threeDaysLater, expiry >= today else { return nil }
                return (item: item, sectionName: section.name)
            }
        }
    }

    var expiringItemCount: Int { expiringItems.count }

    // MARK: - Load

    func loadStorages() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            storages = try await service.fetchStorages()
            if selectedStorageIndex >= storages.count {
                selectedStorageIndex = max(0, storages.count - 1)
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "보관함을 불러오지 못했습니다."
        }
    }

    // MARK: - Storage CRUD

    func createStorage() async {
        let name = storageFormName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await service.createStorage(name: name, storageType: storageFormType.rawValue)
            storageFormName = ""
            showAddStorageSheet = false
            await loadStorages()
            selectedStorageIndex = storages.count - 1
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "보관함 생성에 실패했습니다."
        }
    }

    func updateStorage(name: String, storageType: String?) async {
        guard let storage = selectedStorage, !name.isEmpty else { return }
        do {
            try await service.updateStorage(id: storage.id, name: name, storageType: storageType)
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "보관함 이름 수정에 실패했습니다."
        }
    }

    func deleteStorage() async {
        guard let storage = selectedStorage else { return }
        do {
            try await service.deleteStorage(id: storage.id)
            selectedStorageIndex = 0
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "보관함 삭제에 실패했습니다."
        }
    }

    // MARK: - Section CRUD

    func createSection() async {
        guard let storage = selectedStorage else { return }
        let name = newSectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await service.createSection(storageId: storage.id, name: name)
            newSectionName = ""
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "구역 추가에 실패했습니다."
        }
    }

    func updateSectionName() async {
        guard let storage = selectedStorage, let section = editingSectionForRename else { return }
        let name = sectionRenameName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await service.updateSection(storageId: storage.id, sectionId: section.id, name: name)
            editingSectionForRename = nil
            sectionRenameName = ""
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "구역 이름 수정에 실패했습니다."
        }
    }

    func deleteSection(_ sectionId: Int) async {
        guard let storage = selectedStorage else { return }
        do {
            try await service.deleteSection(storageId: storage.id, sectionId: sectionId)
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "구역 삭제에 실패했습니다."
        }
    }

    // MARK: - Reorder (local + API)

    func moveSectionLocally(fromId: Int, toId: Int) {
        guard fromId != toId,
              storages.indices.contains(selectedStorageIndex) else { return }
        let sections = storages[selectedStorageIndex].sections
        guard let fromIndex = sections.firstIndex(where: { $0.id == fromId }),
              let toIndex = sections.firstIndex(where: { $0.id == toId }) else { return }
        storages[selectedStorageIndex].sections.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
    }

    func commitSectionOrder(targetId: Int) async {
        guard let storage = selectedStorage else { return }
        let sections = storage.sections
        guard let targetIndex = sections.firstIndex(where: { $0.id == targetId }) else { return }
        let beforeId = targetIndex + 1 < sections.count ? sections[targetIndex + 1].id : nil
        do {
            try await service.reorderSections(storageId: storage.id, targetId: targetId, beforeId: beforeId)
        } catch {
            errorMessage = "구역 순서 변경에 실패했습니다."
            await loadStorages()
        }
    }

    func moveStorageLocally(fromId: Int, toId: Int) {
        guard fromId != toId else { return }
        guard let fromIndex = storages.firstIndex(where: { $0.id == fromId }),
              let toIndex = storages.firstIndex(where: { $0.id == toId }) else { return }
        let selectedId = selectedStorage?.id
        storages.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
        if let selectedId, let newIndex = storages.firstIndex(where: { $0.id == selectedId }) {
            selectedStorageIndex = newIndex
        }
    }

    func commitStorageOrder(targetId: Int) async {
        guard let targetIndex = storages.firstIndex(where: { $0.id == targetId }) else { return }
        let beforeId = targetIndex + 1 < storages.count ? storages[targetIndex + 1].id : nil
        do {
            try await service.reorderStorages(targetId: targetId, beforeId: beforeId)
        } catch {
            errorMessage = "보관함 순서 변경에 실패했습니다."
            await loadStorages()
        }
    }

    // MARK: - Item CRUD

    func prepareAddItem(sectionId: Int) {
        editingItem = nil
        editingSectionId = nil
        itemFormName = ""
        itemFormQuantity = 1
        itemFormExpiryDate = nil
        itemFormCategory = .other
        itemFormSectionId = sectionId
        showAddItemSheet = true
    }

    func prepareEditItem(_ item: StorageItem, sectionId: Int) {
        editingItem = item
        editingSectionId = sectionId
        itemFormName = item.name
        itemFormQuantity = item.quantity
        itemFormExpiryDate = item.expiryDate.flatMap { Self.date(from: $0) }
        itemFormCategory = item.category.flatMap { ItemCategory(rawValue: $0) } ?? .other
        itemFormSectionId = sectionId
        showAddItemSheet = true
    }

    func saveItem() async {
        guard let storage = selectedStorage, let sectionId = itemFormSectionId else { return }
        let name = itemFormName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let request = ItemRequest(
            name: name,
            quantity: itemFormQuantity,
            expiryDate: itemFormExpiryDate.map { Self.dateString(from: $0) },
            category: itemFormCategory.rawValue,
            sectionId: sectionId
        )
        do {
            if let editing = editingItem {
                try await service.updateItem(storageId: storage.id, itemId: editing.id, request: request)
            } else {
                try await service.createItem(storageId: storage.id, request: request)
            }
            showAddItemSheet = false
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "품목 저장에 실패했습니다."
        }
    }

    func updateItemQuantity(_ item: StorageItem, sectionId: Int, delta: Int) async {
        guard let storage = selectedStorage else { return }
        let newQuantity = item.quantity + delta
        if newQuantity <= 0 { return }
        let request = ItemRequest(
            name: item.name,
            quantity: newQuantity,
            expiryDate: item.expiryDate,
            category: item.category,
            sectionId: sectionId
        )
        do {
            try await service.updateItem(storageId: storage.id, itemId: item.id, request: request)
            await loadStorages()
        } catch {
            errorMessage = "수량 변경에 실패했습니다."
        }
    }

    func deleteItem(_ itemId: Int) async {
        guard let storage = selectedStorage else { return }
        do {
            try await service.deleteItem(storageId: storage.id, itemId: itemId)
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "품목 삭제에 실패했습니다."
        }
    }

    // MARK: - Date Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        dateFormatter.date(from: string)
    }

    static func daysUntilExpiry(_ expiryDate: String?) -> Int? {
        guard let expiry = expiryDate, let date = date(from: expiry) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day
    }
}
