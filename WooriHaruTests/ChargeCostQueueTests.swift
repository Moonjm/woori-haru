import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct ChargeCostQueueViewModelTests {
    private nonisolated static func item(id: Int, energyUsedKwh: Decimal? = Decimal(string: "51.8")) -> ChargeItem {
        ChargeItem(
            id: id, startedAt: "2026-08-11T22:14:00", endedAt: "2026-08-12T02:31:00",
            durationMin: 257, locationName: "집", energyAddedKwh: Decimal(string: "48.2"),
            energyUsedKwh: energyUsedKwh, startBatteryLevel: 18, endBatteryLevel: 90, cost: nil
        )
    }

    private nonisolated static func stub(_ mock: MockAPIClient, items: [ChargeItem], totalCount: Int? = nil) {
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: totalCount ?? items.count, items: items)
        ))
    }

    private func makeViewModel(mock: MockAPIClient) -> ChargeCostQueueViewModel {
        ChargeCostQueueViewModel(
            vehicleService: VehicleService(api: mock),
            chargeService: ChargeService(api: mock)
        )
    }

    /// 첫 로드 전에는 아직 아무것도 확인하지 못했다 — 빈 큐를 「다 채웠다」로 보여주면 안 된다.
    @Test func 로드하기_전에는_끝난_것이_아니다() async {
        let mock = MockAPIClient()
        let viewModel = makeViewModel(mock: mock)

        #expect(!viewModel.isFinished)
    }

    @Test func 첫_건에는_제안값이_없다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.current?.id == 1)
        #expect(viewModel.suggestedCost == nil)
        #expect(viewModel.totalCount == 2)
    }

    /// 저장하면 다음 건으로 넘어가고, 그 단가가 다음 건의 제안값이 된다.
    @Test func 저장하면_다음_건과_제안값이_생긴다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(mock.putVoidCalls.map(\.path) == ["/tesla/charges/1/cost"])
        #expect(viewModel.current?.id == 2)
        #expect(viewModel.savedCount == 1)
        // 14100 ÷ 51.8 = 272.2… → × 51.8 ≈ 14100
        #expect(viewModel.suggestedCost == 14100)
    }

    /// 사용 전력이 없으면 제안할 근거가 없다 — 비워 둔다.
    @Test func 사용_전력이_없으면_제안하지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2, energyUsedKwh: nil)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.current?.id == 2)
        #expect(viewModel.suggestedCost == nil)
    }

    /// 건너뛰기는 서버를 부르지 않는다. 이번 큐에서만 빠지고 다음에 열면 다시 나온다.
    @Test func 건너뛰면_서버를_부르지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        viewModel.skip()

        #expect(viewModel.current?.id == 2)
        #expect(mock.putVoidCalls.isEmpty)
        #expect(viewModel.savedCount == 0)
    }

    @Test func 저장에_실패하면_그_자리에_남는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        mock.setPutVoidError(MockAPIClient.MockAPIError.forced)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.current?.id == 1)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.savedCount == 0)
    }

    /// 진행 중인 충전은 서버가 404로 막는다 — 그 사실을 그대로 알린다.
    @Test func 없는_충전은_안내가_다르다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1)])
        mock.setPutVoidError(APIError.serverError(statusCode: 404, message: "RESOURCE_NOT_FOUND"))
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.errorMessage?.contains("끝나지 않았거나") == true)
    }

    @Test func 마지막_건을_저장하면_끝난다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.isFinished)
        #expect(viewModel.current == nil)
    }
}
