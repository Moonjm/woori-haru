import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleStatusViewModelTests {
    private nonisolated static func status(asOf: String?) -> VehicleStatus {
        VehicleStatus(
            asOf: asOf, state: "asleep", stateSince: "2026-08-13T09:30:00",
            batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: Decimal(string: "312.4"),
            estRangeKm: nil, odometerKm: Decimal(string: "41203.8"),
            insideTempC: Decimal(string: "31.5"), outsideTempC: Decimal(string: "33.0"),
            climateOn: false, locationName: "집",
            tpmsBar: VehicleStatus.TpmsBar(fl: Decimal(string: "2.9"), fr: Decimal(string: "2.9"),
                                           rl: Decimal(string: "2.8"), rr: nil)
        )
    }

    /// 앱은 KST로 읽는다. 테스트도 같은 시간대에서 비교한다.
    private nonisolated static func kst(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: hour, minute: minute))!
    }

    private func makeViewModel(mock: MockAPIClient, now: Date) -> VehicleStatusViewModel {
        VehicleStatusViewModel(service: VehicleService(api: mock), now: { now })
    }

    @Test func 기준_시각이_몇_분_전인지_센다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(data: Self.status(asOf: "2026-08-13T10:02:00")))
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(viewModel.minutesAgo == 240)
        #expect(viewModel.isStale)
        #expect(viewModel.hasRecord)
    }

    @Test func 방금_받은_값은_오래되지_않았다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(data: Self.status(asOf: "2026-08-13T13:50:00")))
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(viewModel.minutesAgo == 12)
        #expect(!viewModel.isStale)
    }

    /// 기록이 아예 없는 것과 못 받은 것은 다르다.
    @Test func 기록이_없으면_에러가_아니다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(data: Self.status(asOf: nil)))
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(!viewModel.hasRecord)
        #expect(viewModel.minutesAgo == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/status")
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.status == nil)
    }
}
