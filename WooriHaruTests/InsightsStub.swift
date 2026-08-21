import Foundation
@testable import WooriHaru

/// 통계 응답 스텁 한 벌. **열한 태스크가 같은 것을 쓴다** — 태스크마다 만들면 필드를
/// 하나 더할 때 열한 군데를 고치게 된다.
enum InsightsStub {
    /// 기준 달(2026-08)의 절대 개월 수(연×12+월-1). `response(monthlyCount:)`가 여기서
    /// 거슬러 올라가 연·월을 다시 푼다 — `monthlyCount`가 60(전체 기간)까지 커질 수 있어
    /// `"2026-"` 접두어를 고정하면 해를 못 넘긴다.
    private static let baseTotalMonths = 2026 * 12 + (8 - 1)

    /// `monthlyCount`개월치를 만든다. 노브는 **각각 하나의 경계**를 연다.
    /// - `emptyLastMonth`: 마지막 달이 기록 없는 달(값은 nil, `parkDrainSamples`는 0)
    /// - `emptyPlaces`: `places`·`chargers`가 빈 배열, `regions`가 전부 0
    /// - `emptyRecords`: `records` 셋 다 nil
    /// - `emptyWeekday`: `weekday` 배열의 화요일(2) 칸이 「그 요일에 한 번도 안 탔다」다 —
    ///   `drivingMin`이 `Int?`인 이유(서버가 `?: 0` 없이 그대로 null을 낸다)를 재현한다.
    static func response(months: Int = 12,
                         monthlyCount: Int = 12,
                         emptyLastMonth: Bool = false,
                         emptyPlaces: Bool = false,
                         emptyRecords: Bool = false,
                         emptyWeekday: Bool = false) -> InsightsResponse {
        let monthly = (0..<monthlyCount).map { index -> InsightsMonth in
            let isEmpty = emptyLastMonth && index == monthlyCount - 1
            // 절대 개월 수로 뺀 뒤 다시 연·월로 푼다 — 60개월(전체 기간) 창이 5년을
            // 덮어서 해를 넘겨야 한다(실제 데이터 범위 2021-09~2026-08과 맞춘다).
            let offset = monthlyCount - 1 - index
            let totalMonths = baseTotalMonths - offset
            let year = totalMonths / 12
            let month = totalMonths % 12 + 1
            let yearMonth = String(format: "%04d-%02d", year, month)
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
        let weekday = (1...7).map { day -> InsightsWeekday in
            let isEmptyDay = emptyWeekday && day == 2
            return InsightsWeekday(
                weekday: day,
                driveCount: isEmptyDay ? 0 : 38,
                distanceKm: isEmptyDay ? 0 : 612,
                drivingMin: isEmptyDay ? nil : 940,
                occurrences: 52,
                idleMin: isEmptyDay ? 74880 : 61200)
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
