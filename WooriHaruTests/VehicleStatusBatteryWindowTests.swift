import Foundation
import Testing
@testable import WooriHaru

// MARK: - 뷰모델(병렬·독립 로딩)

@MainActor
struct VehicleStatusViewModelBatteryWindowTests {
    private nonisolated static func status() -> VehicleStatus {
        VehicleStatus(
            asOf: "2026-08-18T13:00:00", state: "asleep", stateSince: nil,
            batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: 312, estRangeKm: nil,
            odometerKm: 41203, insideTempC: nil, outsideTempC: nil, climateOn: false,
            locationName: "집", tpmsBar: nil)
    }

    private nonisolated static func window() -> BatteryWindowResponse {
        BatteryWindowResponse(
            hours: 48, from: "2026-08-18T13:00:00", to: "2026-08-20T13:00:00",
            samples: [BatterySample(at: "2026-08-18T13:00:00", batteryLevel: 62, usableBatteryLevel: nil)],
            charges: [], parkDrain: ParkDrain(ratedKm: 4.2, hours: 96.4, samples: 6))
    }

    /// 둘 다 성공하면 둘 다 값이 채워진다 — 개요 로딩과 함께 병렬로 받는다.
    @Test func 상태와_배터리_추이를_함께_받는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.status == Self.status())
        #expect(viewModel.batteryWindow == Self.window())
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.batteryWindowErrorMessage == nil)
    }

    /// **하나가 실패해도 다른 카드는 그린다** — 상태가 실패해도 배터리 추이는 받은 값을 지닌다.
    @Test func 상태가_실패해도_배터리_추이는_남는다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/status")
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.status == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.batteryWindow == Self.window())
        #expect(viewModel.batteryWindowErrorMessage == nil)
    }

    /// 반대 방향도 같다 — 배터리 추이가 실패해도 상태는 받은 값을 지닌다.
    @Test func 배터리_추이가_실패해도_상태는_남는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/battery-window")
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.status == Self.status())
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.batteryWindow == nil)
        #expect(viewModel.batteryWindowErrorMessage != nil)
    }

    /// 「최근 48시간」은 창이 계속 움직인다 — 캐시하지 않고 매번 서버를 부른다.
    @Test func 다시_부르면_매번_서버를_부른다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()
        await viewModel.reload()

        #expect(mock.getCalls.filter { $0.path == "/tesla/battery-window" }.count == 2)
    }
}
