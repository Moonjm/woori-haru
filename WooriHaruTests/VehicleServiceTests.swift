import Foundation
import Testing
@testable import WooriHaru

struct VehicleServiceTests {
    static func period(_ yearMonth: String) -> VehiclePeriod {
        VehiclePeriod(
            yearMonth: yearMonth, distanceKm: 842, drivingMin: 1043, driveCount: 61,
            energyAddedKwh: 186, energyUsedKwh: 201, cost: 52300, chargeCount: 5
        )
    }

    @Test func 요약은_연월을_붙여_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/summary", result: DataResponse<VehicleSummaryResponse>(
            data: VehicleSummaryResponse(
                month: Self.period("2026-08"), previous: Self.period("2026-07"),
                trend: [Self.period("2026-08")], charges: []
            )
        ))
        let service = VehicleService(api: mock)

        let summary = try await service.fetchSummary(yearMonth: "2026-08")

        #expect(summary.month.yearMonth == "2026-08")
        #expect(mock.getCalls.map(\.path) == ["/tesla/summary"])
        #expect(mock.getCalls.first?.query == ["yearMonth": "2026-08"])
    }

    @Test func 상태는_파라미터_없이_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(
            data: VehicleStatus(
                asOf: "2026-08-13T14:02:00", state: "asleep", stateSince: nil,
                batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: 312, estRangeKm: nil,
                odometerKm: 41203, insideTempC: nil, outsideTempC: nil, climateOn: false,
                locationName: "집", tpmsBar: nil
            )
        ))
        let service = VehicleService(api: mock)

        let status = try await service.fetchStatus()

        #expect(status.batteryLevel == 72)
        #expect(mock.getCalls.first?.query == [:])
    }

    @Test func 미등록은_limit을_붙여_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: 37, items: [])
        ))
        let service = VehicleService(api: mock)

        let response = try await service.fetchMissingCost(limit: 50)

        #expect(response.totalCount == 37)
        #expect(mock.getCalls.first?.query == ["limit": "50"])
    }

    /// 파라미터가 없다. 전 기간이 오고, 몇 개월을 그릴지는 앱이 정한다.
    @Test func 배터리_건강은_파라미터_없이_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/battery-health", result: DataResponse<BatteryHealthResponse>(
            data: BatteryHealthResponse(samples: [
                BatteryHealthSample(yearMonth: "2026-07", fullRangeKm: Decimal(string: "527.1")!,
                                    capacityKwh: nil, sampleCount: 1, capacitySampleCount: 0),
                BatteryHealthSample(yearMonth: "2026-08", fullRangeKm: Decimal(string: "525.3")!,
                                    capacityKwh: Decimal(string: "71.6")!,
                                    sampleCount: 3, capacitySampleCount: 1),
            ])
        ))
        let service = VehicleService(api: mock)

        let health = try await service.fetchBatteryHealth()

        #expect(health.samples.count == 2)
        #expect(mock.getCalls.map(\.path) == ["/tesla/battery-health"])
        #expect(mock.getCalls.first?.query == [:])
    }

    /// 표본이 하나도 없는 것은 에러가 아니다 — 「아직 잴 만한 충전이 없다」다.
    @Test func 표본이_없어도_에러가_아니다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/battery-health", result: DataResponse<BatteryHealthResponse>(
            data: BatteryHealthResponse(samples: [])
        ))
        let service = VehicleService(api: mock)

        #expect(try await service.fetchBatteryHealth().samples.isEmpty)
    }

    /// 기간은 쿼리로 간다. 서버가 받는 범위는 1~60이고 화면은 3·12만 쓴다.
    @Test func 주행_인사이트는_개월수를_붙여_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/drive-insights", result: DataResponse<DriveInsightsResponse>(
            data: DriveInsightsResponse(
                months: 12, efficiencyKwhPerKm: Decimal(string: "0.1367"),
                temperatureBuckets: [], driveTimes: [], distanceBuckets: [], places: [],
                maxSpeedKmh: 138,
                totalDistanceKm: Decimal(string: "107257.8"),
                recordedMonths: 60
            )
        ))
        let service = VehicleService(api: mock)

        let insights = try await service.fetchDriveInsights(months: 12)

        #expect(insights.months == 12)
        #expect(mock.getCalls.map(\.path) == ["/tesla/drive-insights"])
        #expect(mock.getCalls.first?.query == ["months": "12"])
    }

    /// 그 기간에 주행이 없는 것은 에러가 아니다 — 「이 기간에 주행 기록이 없어요」다.
    @Test func 주행이_없어도_에러가_아니다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/drive-insights", result: DataResponse<DriveInsightsResponse>(
            data: DriveInsightsResponse(
                months: 3, efficiencyKwhPerKm: nil,
                temperatureBuckets: [], driveTimes: [], distanceBuckets: [], places: [],
                maxSpeedKmh: 138,
                totalDistanceKm: Decimal(string: "107257.8"),
                recordedMonths: 60
            )
        ))
        let service = VehicleService(api: mock)

        let insights = try await service.fetchDriveInsights(months: 3)

        #expect(insights.distanceBuckets.isEmpty)
        #expect(insights.efficiencyKwhPerKm == nil)
    }

    /// 서버가 200에 빈 본문을 주면 화면이 빈 달로 착각하지 않게 에러로 끊는다.
    @Test func 본문이_비면_에러다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/summary", result: DataResponse<VehicleSummaryResponse>(data: nil))
        let service = VehicleService(api: mock)

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchSummary(yearMonth: "2026-08")
        }
    }
}
