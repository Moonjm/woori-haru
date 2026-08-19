import Foundation
import Testing
@testable import WooriHaru

struct DriveInsightsMathTests {

    // MARK: - 전비

    /// `drives`에는 kWh가 없다. **주행가능거리 소모량으로 환산한다** —
    /// 소비 kWh = 소모 rated km × `cars.efficiency`, 전비 = 실주행 km ÷ 소비 kWh.
    /// 실측값(2026-08-17 최근 12개월 영하 버킷)으로 검산한다.
    @Test func 주행가능거리_소모로_전비를_환산한다() {
        let value = VehicleMath.kmPerKwh(
            distanceKm: Decimal(string: "2424.8")!,
            ratedRangeUsedKm: Decimal(string: "2939.2")!,
            efficiencyKwhPerKm: Decimal(string: "0.1367")!
        )
        // 2424.8 ÷ (2939.2 × 0.1367) = 2424.8 ÷ 401.788… = 6.03…
        #expect(VehicleFormat.efficiency(value) == "6.0km/kWh")
    }

    /// 온화한 구간이 더 멀리 간다 — 이 카드가 답하려는 질문이 그것이다.
    @Test func 온도대마다_전비가_다르다() {
        let cold = VehicleMath.kmPerKwh(distanceKm: Decimal(string: "2424.8")!,
                                        ratedRangeUsedKm: Decimal(string: "2939.2")!,
                                        efficiencyKwhPerKm: Decimal(string: "0.1367")!)!
        let mild = VehicleMath.kmPerKwh(distanceKm: Decimal(string: "5990.4")!,
                                        ratedRangeUsedKm: Decimal(string: "5723.9")!,
                                        efficiencyKwhPerKm: Decimal(string: "0.1367")!)!
        #expect(mild > cold)
    }

    /// 분모가 없거나 0이면 계산하지 않는다 — 0으로 내면 「1kWh로 0km 갔다」가 된다.
    /// `efficiency`가 nil인 것은 TeslaMate가 아직 못 채운 경우다.
    @Test func 분모가_없으면_전비도_없다() {
        let eff = Decimal(string: "0.1367")!
        #expect(VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 0, efficiencyKwhPerKm: eff) == nil)
        #expect(VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 120, efficiencyKwhPerKm: nil) == nil)
        #expect(VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 120, efficiencyKwhPerKm: 0) == nil)
        // 빈 버킷은 0으로 오는 것이 사실이다. 그래도 전비는 낼 수 없다.
        #expect(VehicleMath.kmPerKwh(distanceKm: 0, ratedRangeUsedKm: 0, efficiencyKwhPerKm: eff) == nil)
    }

    // MARK: - 라벨

    /// 하한/상한이 없으면 nil이다. 경계는 `fromC` 포함, `toC` 미만이다.
    @Test func 온도_버킷_이름을_경계에서_짓는다() {
        #expect(TemperatureBucket.stub(from: nil, to: 0).label == "영하")
        #expect(TemperatureBucket.stub(from: 0, to: 10).label == "0~10℃")
        #expect(TemperatureBucket.stub(from: 10, to: 20).label == "10~20℃")
        #expect(TemperatureBucket.stub(from: 30, to: nil).label == "30℃ 이상")
    }

    @Test func 거리_버킷_이름을_경계에서_짓는다() {
        #expect(DistanceBucket.stub(from: 0, to: 5).label == "0~5km")
        #expect(DistanceBucket.stub(from: 50, to: 100).label == "50~100km")
        #expect(DistanceBucket.stub(from: 100, to: nil).label == "100km 이상")
    }

    /// **0이 일요일이다**(PostgreSQL `dow` 그대로). 여기서 어긋나면 히트맵 전체가 하루씩 밀린다.
    @Test func 요일은_0이_일요일이다() {
        #expect(DriveFormat.weekdayLabel(0) == "일")
        #expect(DriveFormat.weekdayLabel(1) == "월")
        #expect(DriveFormat.weekdayLabel(6) == "토")
        // 범위 밖은 「—」다. 상류가 늘었다는 사실이 0으로 숨으면 안 된다.
        #expect(DriveFormat.weekdayLabel(7) == ChargeFormat.placeholder)
    }

    @Test func 시각은_두_자리로_적는다() {
        #expect(DriveFormat.hourLabel(0) == "0시")
        #expect(DriveFormat.hourLabel(17) == "17시")
    }

    // MARK: - 기간

    @Test func 기간은_두_가지다() {
        #expect(DrivePeriod.allCases.map(\.rawValue) == [3, 12])
        #expect(DrivePeriod.threeMonths.label == "최근 3개월")
        #expect(DrivePeriod.twelveMonths.label == "최근 12개월")
    }

    // MARK: - 디코딩

    /// 서버가 주는 그대로 읽는다. **버킷 다섯 칸은 늘 오고 빈 칸은 0이다**(nil이 아니다).
    /// `driveTimes`만 0인 칸이 빠져 성기게 온다.
    @Test func 응답을_디코딩한다() throws {
        let json = """
        { "months": 12,
          "efficiencyKwhPerKm": 0.1367,
          "temperatureBuckets": [
            { "fromC": null, "toC": 0, "driveCount": 82, "distanceKm": 2424.8, "ratedRangeUsedKm": 2939.2 },
            { "fromC": 30, "toC": null, "driveCount": 0, "distanceKm": 0, "ratedRangeUsedKm": 0 }
          ],
          "driveTimes": [ { "weekday": 1, "hour": 8, "count": 43 } ],
          "distanceBuckets": [ { "fromKm": 100, "toKm": null, "driveCount": 3, "distanceKm": 412.0 } ],
          "places": [] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DriveInsightsResponse.self, from: json)

        #expect(decoded.months == 12)
        #expect(decoded.temperatureBuckets[0].label == "영하")
        #expect(decoded.temperatureBuckets[1].driveCount == 0)
        #expect(decoded.driveTimes[0].weekday == 1)
        #expect(decoded.distanceBuckets[0].toKm == nil)
        #expect(decoded.places.isEmpty)
    }

    /// TeslaMate가 `cars.efficiency`를 아직 못 채운 경우다. 화면은 전비 카드를 감춘다.
    @Test func 효율_계수가_없을_수_있다() throws {
        let json = """
        { "months": 3, "efficiencyKwhPerKm": null, "temperatureBuckets": [],
          "driveTimes": [], "distanceBuckets": [], "places": [] }
        """.data(using: .utf8)!

        #expect(try JSONDecoder().decode(DriveInsightsResponse.self, from: json).efficiencyKwhPerKm == nil)
    }
}

// 테스트 전용 생성 도우미 — 라벨만 보는 자리에서 숫자 넷을 매번 적지 않게 한다.
extension TemperatureBucket {
    static func stub(from: Int?, to: Int?) -> TemperatureBucket {
        TemperatureBucket(fromC: from, toC: to, driveCount: 0, distanceKm: 0, ratedRangeUsedKm: 0)
    }
}

extension DistanceBucket {
    static func stub(from: Int, to: Int?) -> DistanceBucket {
        DistanceBucket(fromKm: from, toKm: to, driveCount: 0, distanceKm: 0)
    }
}
