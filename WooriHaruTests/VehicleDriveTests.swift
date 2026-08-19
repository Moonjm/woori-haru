import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleDriveViewModelTests {

    /// 실측(2026-08-17 최근 12개월) 그대로다 — 온도 939건, 거리 959건.
    private nonisolated static func insights(
        months: Int = 12, efficiency: String? = "0.1367", places: [DrivePlace] = []
    ) -> DriveInsightsResponse {
        DriveInsightsResponse(
            months: months,
            efficiencyKwhPerKm: efficiency.flatMap { Decimal(string: $0) },
            temperatureBuckets: [
                TemperatureBucket(fromC: nil, toC: 0, driveCount: 82,
                                  distanceKm: Decimal(string: "2424.8")!,
                                  ratedRangeUsedKm: Decimal(string: "2939.2")!),
                TemperatureBucket(fromC: 0, toC: 10, driveCount: 229,
                                  distanceKm: Decimal(string: "6507.3")!,
                                  ratedRangeUsedKm: Decimal(string: "7097.1")!),
                TemperatureBucket(fromC: 10, toC: 20, driveCount: 244,
                                  distanceKm: Decimal(string: "5990.4")!,
                                  ratedRangeUsedKm: Decimal(string: "5723.9")!),
                TemperatureBucket(fromC: 20, toC: 30, driveCount: 266,
                                  distanceKm: Decimal(string: "5748.4")!,
                                  ratedRangeUsedKm: Decimal(string: "5798.5")!),
                TemperatureBucket(fromC: 30, toC: nil, driveCount: 118,
                                  distanceKm: Decimal(string: "2494.6")!,
                                  ratedRangeUsedKm: Decimal(string: "2551.5")!),
            ],
            driveTimes: [
                DriveTime(weekday: 1, hour: 8, count: 43),
                DriveTime(weekday: 2, hour: 17, count: 41),
                DriveTime(weekday: 0, hour: 14, count: 12),
            ],
            distanceBuckets: [
                DistanceBucket(fromKm: 0, toKm: 5, driveCount: 620, distanceKm: 1802),
                DistanceBucket(fromKm: 5, toKm: 20, driveCount: 210, distanceKm: 2400),
                DistanceBucket(fromKm: 20, toKm: 50, driveCount: 90, distanceKm: 2700),
                DistanceBucket(fromKm: 50, toKm: 100, driveCount: 36, distanceKm: 2500),
                DistanceBucket(fromKm: 100, toKm: nil, driveCount: 3, distanceKm: 412),
            ],
            places: places
        )
    }

    private nonisolated static func empty(months: Int = 3) -> DriveInsightsResponse {
        DriveInsightsResponse(
            months: months, efficiencyKwhPerKm: Decimal(string: "0.1367"),
            temperatureBuckets: [], driveTimes: [], distanceBuckets: [], places: []
        )
    }

    private func makeViewModel(_ mock: MockAPIClient) -> VehicleDriveViewModel {
        VehicleDriveViewModel(service: VehicleService(api: mock))
    }

    private func stub(_ mock: MockAPIClient, _ response: DriveInsightsResponse) {
        mock.stubGet("/tesla/drive-insights",
                     result: DataResponse<DriveInsightsResponse>(data: response))
    }

    /// 기본은 12개월이다.
    @Test func 기본_기간은_12개월이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.period == .twelveMonths)
        #expect(mock.getCalls.first?.query == ["months": "12"])
        #expect(viewModel.hasDrives)
    }

    /// 기간을 바꾸면 다시 받는다 — 네 카드가 같은 기간을 봐야 한다.
    @Test func 기간을_바꾸면_다시_받는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        await viewModel.select(.threeMonths)

        #expect(viewModel.period == .threeMonths)
        #expect(mock.getCalls.map { $0.query["months"] } == ["12", "3"])
    }

    /// 같은 기간을 다시 누르면 부르지 않는다.
    @Test func 같은_기간은_다시_부르지_않는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        await viewModel.select(.twelveMonths)

        #expect(mock.getCalls.count == 1)
    }

    /// 버킷별 전비를 앱이 낸다. 영하가 가장 나쁘고 10~20℃가 가장 좋다 — 실측 그대로다.
    @Test func 버킷마다_전비를_낸다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let rows = viewModel.temperatureRows
        #expect(rows.count == 5)
        #expect(rows[0].bucket.label == "영하")
        let cold = rows[0].kmPerKwh!
        let mild = rows[2].kmPerKwh!
        #expect(mild > cold)
        #expect(rows.allSatisfy { $0.kmPerKwh != nil })
    }

    /// **두 카드의 총합이 다르다.** 온도 쪽은 주행가능거리 소모가 0 이하인 주행을 뺀 뒤 센다.
    /// 한 곳에서 뽑아 「N건」으로 쓰면 어긋난다.
    @Test func 온도와_거리의_건수가_다르다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.temperatureDriveCount == 939)
        #expect(viewModel.distanceDriveCount == 959)
    }

    /// TeslaMate가 `cars.efficiency`를 아직 못 채운 경우다 — 전비 카드를 감춘다.
    /// 나머지 카드는 그대로 그린다.
    @Test func 효율_계수가_없으면_전비_카드를_감춘다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights(efficiency: nil))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.showsEfficiency)
        #expect(viewModel.hasDrives)
        #expect(viewModel.temperatureRows.allSatisfy { $0.kmPerKwh == nil })
    }

    /// **지오펜스가 하나도 없는 것이 이 차량의 기본 상태다.** 「가끔 비는 경우」가 아니다.
    @Test func 지오펜스가_없으면_자주_가는_곳을_감춘다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.showsPlaces)
    }

    @Test func 지오펜스가_있으면_자주_가는_곳을_낸다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights(places: [DrivePlace(name: "집", driveCount: 124, distanceKm: 812)]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.showsPlaces)
    }

    /// 히트맵은 성기게 온다 — 없는 칸은 0이다. `weekday` 0이 일요일이다.
    @Test func 히트맵의_없는_칸은_0이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.heatCount(weekday: 1, hour: 8) == 43)
        #expect(viewModel.heatCount(weekday: 0, hour: 14) == 12)
        #expect(viewModel.heatCount(weekday: 3, hour: 3) == 0)
        #expect(viewModel.maxHeatCount == 43)
    }

    /// 그 기간에 주행이 없는 것은 에러가 아니다. 카드마다 비우지 않고 화면 하나로 말한다.
    @Test func 주행이_없어도_에러가_아니다() async {
        let mock = MockAPIClient()
        stub(mock, Self.empty())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.hasDrives)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.maxHeatCount == 0)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/drive-insights")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.insights == nil)
    }

    /// **있던 값을 새로고침 실패로 지우지 않는다** — 1단계 건강 화면과 같은 규칙이다.
    @Test func 새로고침이_실패해도_있던_값은_남는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/drive-insights")
        await viewModel.reload()

        #expect(viewModel.hasDrives)
        #expect(viewModel.errorMessage != nil)
    }

    /// **지난번이 오류로 끝났으면 탭에 다시 들어와도 다시 받는다** — 그러지 않으면
    /// 빨간 배너가 영영 남는다. `VehicleHealthViewModel.load()`와 같은 규칙이다.
    @Test func 에러_상태에서_다시_들어오면_재시도한다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/drive-insights")
        await viewModel.reload()
        #expect(mock.getCalls.count == 2)

        await viewModel.load()

        #expect(mock.getCalls.count == 3)
    }

    /// **기간을 바꾸다 실패하면 옛 기간의 값을 남기지 않는다** — 칩은 3개월인데 화면이
    /// 12개월 값이면 거짓말이 된다. 새로고침 실패와 다르게 다뤄야 한다.
    @Test func 기간_변경이_실패하면_옛_기간_값을_지운다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/drive-insights")
        await viewModel.select(.threeMonths)

        #expect(viewModel.period == .threeMonths)
        #expect(viewModel.insights == nil)
        #expect(viewModel.errorMessage != nil)
    }
}
