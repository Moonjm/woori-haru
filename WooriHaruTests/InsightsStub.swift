import Foundation
@testable import WooriHaru

/// 통계 응답 스텁 한 벌. **열한 태스크가 같은 것을 쓴다** — 태스크마다 만들면 필드를
/// 하나 더할 때 열한 군데를 고치게 된다.
enum InsightsStub {
    /// `monthlyCount`개월치를 만든다. 노브는 **각각 하나의 경계**를 연다.
    /// - `emptyLastMonth`: 마지막 달이 기록 없는 달(값은 nil, `parkDrainSamples`는 0)
    /// - `emptyPlaces`: `places`·`chargers`가 빈 배열, `regions`가 전부 0
    /// - `emptyRecords`: `records` 셋 다 nil
    static func response(months: Int = 12,
                         monthlyCount: Int = 12,
                         emptyLastMonth: Bool = false,
                         emptyPlaces: Bool = false,
                         emptyRecords: Bool = false) -> InsightsResponse {
        let monthly = (0..<monthlyCount).map { index -> InsightsMonth in
            let isEmpty = emptyLastMonth && index == monthlyCount - 1
            // 2026-08에서 거슬러 올라간다. 자릿수를 두 자리로 맞춘다.
            let month = 8 - (monthlyCount - 1 - index)
            let yearMonth = String(format: "2026-%02d", max(1, month))
            return InsightsMonth(
                yearMonth: yearMonth,
                distanceKm: isEmpty ? nil : 780,
                driveCount: isEmpty ? nil : 41,
                drivingMin: isEmpty ? nil : 1120,
                energyAddedKwh: isEmpty ? nil : 153,
                energyUsedKwh: isEmpty ? nil : 161,
                cost: isEmpty ? nil : 32700,
                chargeCount: isEmpty ? nil : 7,
                chargingMin: isEmpty ? nil : 640,
                ratedRangeUsedKm: isEmpty ? nil : 812,
                // 셋은 기록이 없어도 온다.
                idleMin: isEmpty ? 44640 : 42800,
                parkDrainRatedKm: isEmpty ? 0 : Decimal(string: "18.4")!,
                parkDrainSamples: isEmpty ? 0 : 34)
        }
        // **1 = 월요일**(ISO)로 일곱 개. 순서가 곧 월~일이다.
        let weekday = (1...7).map { day in
            InsightsWeekday(weekday: day, driveCount: 38, distanceKm: 612,
                            drivingMin: 940, occurrences: 52, idleMin: 61200)
        }
        return InsightsResponse(
            months: months, monthly: monthly,
            efficiencyKwhPerKm: Decimal(string: "0.168")!,
            temperatureBuckets: [],
            // **0 = 일요일**. `weekday` 배열과 규약이 다르다.
            driveTimes: [DriveTime(weekday: 0, hour: 8, count: 12)],
            distanceBuckets: [],
            places: emptyPlaces ? [] : [
                DrivePlace(name: "집", driveCount: 302, distanceKm: 4120),
                DrivePlace(name: "회사", driveCount: 151, distanceKm: 2010)],
            maxSpeedKmh: 138, totalDistanceKm: 107258, recordedMonths: 59,
            weekday: weekday,
            chargeTimes: [DriveTime(weekday: 0, hour: 23, count: 4)],
            speedBuckets: [SpeedBucket(fromKmh: 120, toKmh: nil, driveCount: 3)],
            speedEnergyBuckets: [SpeedEnergyBucket(fromKmh: 0, toKmh: 20,
                                                    distanceKm: 302, ratedRangeUsedKm: 410)],
            chargeStartLevels: [ChargeLevelBucket(fromPct: 0, toPct: 10, count: 3)],
            chargeEndLevels: [ChargeLevelBucket(fromPct: 80, toPct: 90, count: 12),
                              ChargeLevelBucket(fromPct: 90, toPct: 100, count: 41)],
            chargers: emptyPlaces ? [] : [
                Charger(name: "집", chargeCount: 210, energyAddedKwh: 4820,
                        cost: 612000, costMissingCount: 4)],
            regions: Regions(cities: emptyPlaces ? 0 : 34,
                             states: emptyPlaces ? 0 : 8,
                             countries: emptyPlaces ? 0 : 1),
            // **`longestDuration`만 nil이다** — 셋이 따로 빌 수 있음을 기본 스텁이 드러낸다.
            records: emptyRecords
                ? InsightsRecords(longestDistance: nil, longestDuration: nil, bestEfficiency: nil)
                : InsightsRecords(
                    longestDistance: DistanceRecord(driveId: 4821,
                                                    startedAt: "2025-09-13T07:12:00",
                                                    distanceKm: 412),
                    longestDuration: nil,
                    bestEfficiency: EfficiencyRecord(driveId: 5002,
                                                     startedAt: "2026-05-02T14:20:00",
                                                     distanceKm: 88, ratedRangeUsedKm: 71)))
    }

    /// `months`마다 다른 응답을 물릴 수 있다 — 기간 칩 테스트가 그것을 본다.
    static func stub(_ mock: MockAPIClient, _ response: InsightsResponse) {
        mock.stubGet("/tesla/insights", result: DataResponse<InsightsResponse>(data: response))
    }
}
