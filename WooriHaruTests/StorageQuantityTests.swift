import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct StorageQuantityTests {
    struct TimeoutError: Error {}

    private func makeSUT(itemQuantity: Int = 2) -> (vm: StorageViewModel, mock: MockAPIClient) {
        let mock = MockAPIClient()
        let vm = StorageViewModel(service: StorageService(api: mock))
        vm.storages = [
            Storage(id: 1, name: "냉장고", sortOrder: 0, storageType: "FRIDGE", sections: [
                StorageSection(id: 10, name: "칸", sortOrder: 0, items: [
                    StorageItem(
                        id: 100, name: "우유", quantity: itemQuantity,
                        expiryDate: nil, category: nil, createdBy: 1, createdAt: "2026-01-01"
                    ),
                ]),
            ]),
        ]
        vm.selectedStorageId = 1
        return (vm, mock)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw TimeoutError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func 증가는_네트워크_응답_전에_즉시_반영() {
        let (vm, _) = makeSUT()
        let item = vm.storages[0].sections[0].items[0]
        vm.updateItemQuantity(item, sectionId: 10, delta: 1)
        #expect(vm.storages[0].sections[0].items[0].quantity == 3)
    }

    @Test func 연타는_스냅샷이_아닌_현재_상태에서_누적() {
        let (vm, _) = makeSUT()
        // 세 호출 모두 quantity 2 스냅샷의 같은 item을 넘긴다 — 실제 연타와 동일
        let item = vm.storages[0].sections[0].items[0]
        vm.updateItemQuantity(item, sectionId: 10, delta: 1)
        vm.updateItemQuantity(item, sectionId: 10, delta: 1)
        vm.updateItemQuantity(item, sectionId: 10, delta: -1)
        #expect(vm.storages[0].sections[0].items[0].quantity == 3)  // 2+1+1-1
    }

    @Test func 수량은_0_이하로_내려가지_않음() {
        let (vm, _) = makeSUT(itemQuantity: 1)
        let item = vm.storages[0].sections[0].items[0]
        vm.updateItemQuantity(item, sectionId: 10, delta: -1)
        #expect(vm.storages[0].sections[0].items[0].quantity == 1)
    }

    @Test func 서버에는_최종_수량이_전송됨() async throws {
        let (vm, mock) = makeSUT()
        let item = vm.storages[0].sections[0].items[0]
        vm.updateItemQuantity(item, sectionId: 10, delta: 1)

        try await waitUntil { mock.putVoidCalls.contains { $0.path == "/storages/1/items/100" } }
        let body = mock.putVoidCalls.last?.body as? ItemRequest
        #expect(body?.quantity == 3)
        #expect(body?.sectionId == 10)
    }

    @Test func 실패하면_서버_상태로_롤백() async throws {
        let (vm, mock) = makeSUT()
        // 서버 상태(수량 2) 스냅샷 — 롤백 시 loadStorages()가 이 값을 다시 받는다
        mock.stubGet("/storages", result: DataResponse<[Storage]>(data: vm.storages))
        mock.setPutVoidError(MockAPIClient.MockAPIError.forced)

        let item = vm.storages[0].sections[0].items[0]
        vm.updateItemQuantity(item, sectionId: 10, delta: 1)
        #expect(vm.storages[0].sections[0].items[0].quantity == 3)  // 낙관적 반영

        try await waitUntil { vm.errorMessage != nil }
        #expect(vm.storages[0].sections[0].items[0].quantity == 2)  // 롤백 완료
    }
}
