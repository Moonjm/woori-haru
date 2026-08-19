import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct ChargeTotalsViewModelTests {

    /// 실측(2026-08-19) 그대로다.
    private nonisolated static func totals() -> ChargeTotalsResponse {
        ChargeTotalsResponse(
            chargeCount: 474,
            energyAddedKwh: Decimal(string: "17442.0"),
            energyUsedKwh: Decimal(string: "18197.2"),
            cost: 3644562, costMissingCount: 35,
            costMissingEnergyUsedKwh: Decimal(string: "977.0"),
            firstChargedAt: "2021-09-03",
            fast: ChargeTotalsBreakdown(
                chargeCount: 39, energyAddedKwh: Decimal(string: "1358.4"),
                energyUsedKwh: Decimal(string: "1320.2"), cost: 140479,
                costMissingCount: 22, costMissingEnergyUsedKwh: Decimal(string: "833.9")),
            slow: ChargeTotalsBreakdown(
                chargeCount: 431, energyAddedKwh: Decimal(string: "16083.6"),
                energyUsedKwh: Decimal(string: "16877.1"), cost: 3493723,
                costMissingCount: 10, costMissingEnergyUsedKwh: Decimal(string: "143.1")))
    }

    private func makeViewModel(_ mock: MockAPIClient) -> ChargeTotalsViewModel {
        ChargeTotalsViewModel(service: ChargeService(api: mock))
    }

    private func stub(_ mock: MockAPIClient, _ t: ChargeTotalsResponse?) {
        mock.stubGet("/tesla/charges/totals", result: DataResponse<ChargeTotalsResponse>(data: t))
    }

    @Test func 급속과_완속_단가를_각자_낸다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(VehicleFormat.wonPerKwh(viewModel.fastWonPerKwh) == "₩289/kWh")
        #expect(VehicleFormat.wonPerKwh(viewModel.slowWonPerKwh) == "₩209/kWh")
        #expect(viewModel.hasTotals)
    }

    /// 탭을 오갈 때마다 전 기간 집계를 다시 부르지 않는다. **오류가 남아 있으면 재시도한다** —
    /// 1·2단계 뷰모델과 같은 규칙이다.
    @Test func 다시_열어도_한_번만_부른다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.load()

        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/totals" }.count == 1)
    }

    @Test func 오류가_남아_있으면_다시_들어올_때_재시도한다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/totals")
        await viewModel.reload()
        await viewModel.load()

        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/totals" }.count == 3)
    }

    /// **있던 값을 새로고침 실패로 지우지 않는다.**
    @Test func 새로고침이_실패해도_있던_값은_남는다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/totals")
        await viewModel.reload()

        #expect(viewModel.hasTotals)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/totals")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.hasTotals)
        #expect(viewModel.errorMessage != nil)
    }
}
