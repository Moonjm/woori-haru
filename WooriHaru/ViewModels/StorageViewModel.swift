import Foundation
import Observation

@MainActor
@Observable
final class StorageViewModel {
    // MARK: - State

    var storages: [Storage] = []
    var selectedStorageId: Int? { didSet { updateExpiringItems() } }
    var isLoading = false
    var isMutating = false
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

    // 품목별 수량 업데이트 태스크 — 연타 시 이전 네트워크 요청을 취소해
    // 응답 순서 뒤바뀜으로 인한 서버 상태 어긋남을 방지한다.
    private var quantityTasks: [Int: Task<Void, Never>] = [:]

    // MARK: - Computed

    var selectedStorageIndex: Int? {
        guard let id = selectedStorageId else { return nil }
        return storages.firstIndex(where: { $0.id == id })
    }

    var selectedStorage: Storage? {
        guard let index = selectedStorageIndex else { return nil }
        return storages[index]
    }

    private(set) var expiringItems: [(item: StorageItem, sectionName: String)] = []

    var expiringItemCount: Int { expiringItems.count }

    // MARK: - Expiry Summary (cached)

    struct ExpirySummary {
        var total: Int = 0
        var expired: Int = 0
        var imminent: Int = 0
        var safe: Int = 0
    }

    private(set) var expirySummary = ExpirySummary()

    private func updateExpiringItems() {
        guard let storage = selectedStorage else {
            expiringItems = []
            expirySummary = ExpirySummary()
            return
        }
        let now = Calendar.current.startOfDay(for: Date())
        let threeDaysLater = Calendar.current.date(byAdding: .day, value: 3, to: now)!

        expiringItems = storage.sections.flatMap { section in
            section.items.compactMap { item in
                guard let expiryStr = item.expiryDate,
                      let expiryDate = Self.date(from: expiryStr),
                      expiryDate <= threeDaysLater else { return nil }
                return (item: item, sectionName: section.name)
            }
        }

        // Update expiry summary
        let allItems = storage.sections.flatMap(\.items)
        var summary = ExpirySummary(total: allItems.count)
        for item in allItems {
            guard let days = Self.daysUntilExpiry(item.expiryDate) else {
                summary.safe += 1
                continue
            }
            if days < 0 { summary.expired += 1 }
            else if days <= 3 { summary.imminent += 1 }
            else { summary.safe += 1 }
        }
        expirySummary = summary
    }

    // MARK: - Load

    func loadStorages() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            storages = try await service.fetchStorages()
            if let id = selectedStorageId, !storages.contains(where: { $0.id == id }) {
                selectedStorageId = storages.first?.id
            } else if selectedStorageId == nil {
                selectedStorageId = storages.first?.id
            }
            updateExpiringItems()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "보관함을 불러오지 못했습니다."
        }
    }

    // MARK: - Storage CRUD

    func createStorage() async {
        guard !isMutating else { return }
        let name = storageFormName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await service.createStorage(name: name, storageType: storageFormType.rawValue)
            storageFormName = ""
            showAddStorageSheet = false
            await loadStorages()
            selectedStorageId = storages.last?.id
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "보관함 생성에 실패했습니다."
        }
    }

    func updateStorage(name: String, storageType: String?) async {
        guard !isMutating, let storage = selectedStorage, !name.isEmpty else { return }
        isMutating = true
        defer { isMutating = false }
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
        guard !isMutating, let storage = selectedStorage else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await service.deleteStorage(id: storage.id)
            selectedStorageId = storages.first(where: { $0.id != storage.id })?.id
            await loadStorages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "보관함 삭제에 실패했습니다."
        }
    }

    // MARK: - Section CRUD

    func createSection() async {
        guard !isMutating, let storage = selectedStorage else { return }
        let name = newSectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isMutating = true
        defer { isMutating = false }
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
        guard !isMutating,
              let storage = selectedStorage,
              let section = editingSectionForRename else { return }
        let name = sectionRenameName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isMutating = true
        defer { isMutating = false }
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
        guard !isMutating, let storage = selectedStorage else { return }
        isMutating = true
        defer { isMutating = false }
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
              let idx = selectedStorageIndex else { return }
        let sections = storages[idx].sections
        guard let fromIndex = sections.firstIndex(where: { $0.id == fromId }),
              let toIndex = sections.firstIndex(where: { $0.id == toId }) else { return }
        storages[idx].sections.move(
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
        storages.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
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
        guard !isMutating,
              let storage = selectedStorage,
              let sectionId = itemFormSectionId else { return }
        let name = itemFormName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isMutating = true
        defer { isMutating = false }
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

    /// 수량 증감. 연타 시 이전 네트워크 요청은 취소하고 최신 상태만 서버에 반영.
    /// 파라미터 `item`의 quantity 스냅샷이 아닌 현재 storages 상태에서 읽어 누산 오류를 방지한다.
    func updateItemQuantity(_ item: StorageItem, sectionId: Int, delta: Int) {
        guard let storage = selectedStorage,
              let storageIdx = selectedStorageIndex,
              let sectionIdx = storages[storageIdx].sections.firstIndex(where: { $0.id == sectionId }),
              let itemIdx = storages[storageIdx].sections[sectionIdx].items.firstIndex(where: { $0.id == item.id })
        else { return }

        let current = storages[storageIdx].sections[sectionIdx].items[itemIdx]
        let newQuantity = current.quantity + delta
        guard newQuantity > 0 else { return }

        // 낙관적 로컬 업데이트 (MainActor 동기 — 연속 탭 시 값이 바르게 누적됨)
        storages[storageIdx].sections[sectionIdx].items[itemIdx].quantity = newQuantity
        updateExpiringItems()

        // 직전 태스크 취소 — 응답 순서 역전으로 서버 상태가 어긋나는 문제 방지
        quantityTasks[item.id]?.cancel()
        let storageId = storage.id
        let itemId = item.id
        let request = ItemRequest(
            name: current.name,
            quantity: newQuantity,
            expiryDate: current.expiryDate,
            category: current.category,
            sectionId: sectionId
        )
        quantityTasks[itemId] = Task { [weak self] in
            guard let self else { return }
            defer {
                // 외부에서 취소된 경우 맵은 이미 새 Task로 교체됐으므로 건드리지 않는다.
                // 정상 완료/비취소 에러 시에만 자기 엔트리를 제거.
                if !Task.isCancelled {
                    self.quantityTasks.removeValue(forKey: itemId)
                }
            }
            do {
                try await self.service.updateItem(storageId: storageId, itemId: itemId, request: request)
            } catch is CancellationError {
                // 더 새로운 요청이 시작됨 — 롤백/에러 표시 불필요
            } catch {
                // 실제 실패일 때만 롤백
                guard !Task.isCancelled else { return }
                await self.loadStorages()
                self.errorMessage = "수량 변경에 실패했습니다."
            }
        }
    }

    func deleteItem(_ itemId: Int) async {
        guard !isMutating, let storage = selectedStorage else { return }
        isMutating = true
        defer { isMutating = false }
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
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
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
