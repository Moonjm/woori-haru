import Foundation
import Testing
@testable import WooriHaru

@Suite("통계 응답 디코딩")
struct InsightsModelsTests {
    /// 서버가 실제로 내는 모양이다. 필드를 줄이면 「우리가 아는 모양」만 테스트하게 된다.
    private static let json = """
    {
      "months": 12,
      "monthly": [{
        "yearMonth": "2026-08",
        "distanceKm": 780.4, "driveCount": 41, "drivingMin": 1120,
        "energyAddedKwh": 152.8, "energyUsedKwh": 161.0, "cost": 32700, "chargeCount": 7,
        "chargingMin": 640, "ratedRangeUsedKm": 812.1,
        "idleMin": 42800, "parkDrainRatedKm": 18.4, "parkDrainSamples": 34
      }, {
        "yearMonth": "2026-07",
        "distanceKm": null, "driveCount": null, "drivingMin": null,
        "energyAddedKwh": null, "energyUsedKwh": null, "cost": null, "chargeCount": null,
        "chargingMin": null, "ratedRangeUsedKm": null,
        "idleMin": 44640, "parkDrainRatedKm": 0.0, "parkDrainSamples": 0
      }],
      "efficiencyKwhPerKm": 0.168,
      "temperatureBuckets": [{"fromC": null, "toC": 0, "driveCount": 88,
                              "distanceKm": 910.0, "ratedRangeUsedKm": 1180.4}],
      "driveTimes": [{"weekday": 0, "hour": 8, "count": 12}],
      "distanceBuckets": [{"fromKm": 0, "toKm": 5, "driveCount": 120, "distanceKm": 380.2}],
      "places": [{"name": "집", "driveCount": 302, "distanceKm": 4120.8}],
      "maxSpeedKmh": 138,
      "totalDistanceKm": 107258.4,
      "recordedMonths": 59,
      "weekday": [{"weekday": 1, "driveCount": 38, "distanceKm": 612.0,
                   "drivingMin": 940, "occurrences": 52, "idleMin": 61200}],
      "chargeTimes": [{"weekday": 1, "hour": 23, "count": 4}],
      "speedBuckets": [{"fromKmh": 120, "toKmh": null, "driveCount": 3}],
      "speedEnergyBuckets": [{"fromKmh": 0, "toKmh": 20,
                              "distanceKm": 302.1, "ratedRangeUsedKm": 410.8}],
      "chargeStartLevels": [{"fromPct": 0, "toPct": 10, "count": 3}],
      "chargeEndLevels": [{"fromPct": 90, "toPct": 100, "count": 41}],
      "chargers": [{"name": "집", "chargeCount": 210, "energyAddedKwh": 4820.1,
                    "cost": 612000, "costMissingCount": 4}],
      "regions": {"cities": 34, "states": 8, "countries": 1},
      "records": {
        "longestDistance": {"driveId": 4821, "startedAt": "2025-09-13T07:12:00", "distanceKm": 412.8},
        "longestDuration": null,
        "bestEfficiency": {"driveId": 5002, "startedAt": "2026-05-02T14:20:00",
                           "distanceKm": 88.2, "ratedRangeUsedKm": 71.0}
      }
    }
    """

    /// **`APIClient`가 평범한 `JSONDecoder()`를 쓴다** — 날짜 전략이 없다.
    /// 그래서 모든 시각 필드가 `String`이고 파싱은 뷰가 필요할 때 한다.
    private func decoded() throws -> InsightsResponse {
        try JSONDecoder().decode(InsightsResponse.self, from: Data(Self.json.utf8))
    }

    @Test func 기록_없는_달은_0이_아니라_nil로_온다() throws {
        let month = try #require(try decoded().monthly.last)
        #expect(month.distanceKm == nil)
        #expect(month.driveCount == nil)
        // 셋만 예외다 — 기록이 없어도 값이 온다.
        #expect(month.idleMin == 44640)
        #expect(month.parkDrainSamples == 0)
    }

    @Test func 역대_기록은_셋이_따로_비어_올_수_있다() throws {
        let records = try decoded().records
        #expect(records.longestDistance != nil)
        #expect(records.longestDuration == nil)
        #expect(records.bestEfficiency != nil)
    }

    @Test func 전_기간_값_셋은_늘_온다() throws {
        let response = try decoded()
        #expect(response.totalDistanceKm == 107258.4)
        #expect(response.recordedMonths == 59)
        #expect(response.regions.countries == 1)
    }

    /// **한 응답 안에서 규약이 둘이다** — 섞으면 차트가 하루씩 밀린다.
    @Test func 요일_규약이_배열마다_다르다() throws {
        let response = try decoded()
        // driveTimes는 0 = 일요일
        #expect(DriveFormat.weekdayLabel(response.driveTimes[0].weekday) == "일")
        // weekday는 1 = 월요일
        #expect(DriveFormat.isoWeekdayLabel(response.weekday[0].weekday) == "월")
    }

    @Test func ISO_요일_라벨은_범위_밖에서_빈값을_낸다() {
        #expect(DriveFormat.isoWeekdayLabel(0) == ChargeFormat.placeholder)
        #expect(DriveFormat.isoWeekdayLabel(7) == "일")
        #expect(DriveFormat.isoWeekdayLabel(8) == ChargeFormat.placeholder)
    }
}
