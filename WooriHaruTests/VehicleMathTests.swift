import Foundation
import Testing
@testable import WooriHaru

struct VehicleMathTests {
    /// 분모가 없거나 0이면 계산하지 않는다 — 0으로 내면 「0원에 탔다」가 된다.
    @Test func 주행이_없으면_km당_비용도_전비도_없다() {
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: nil) == nil)
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: 0) == nil)
        #expect(VehicleMath.costPerKm(cost: nil, distanceKm: 842) == nil)
        // 전비는 충전량으로 나눈다 — 충전이 없으면 낼 수 없다.
        #expect(VehicleMath.kmPerKwh(energyAddedKwh: 0, distanceKm: 842) == nil)
        #expect(VehicleMath.kmPerKwh(energyAddedKwh: nil, distanceKm: 842) == nil)
        #expect(VehicleMath.kmPerKwh(energyAddedKwh: 186, distanceKm: nil) == nil)
    }

    /// 전비 단위는 km/kWh다 — 국내 제원표와 같아야 자기 차 숫자와 견줄 수 있다.
    @Test func km당_비용과_전비를_계산한다() {
        let costPerKm = VehicleMath.costPerKm(cost: 52300, distanceKm: Decimal(string: "842.3"))
        #expect(VehicleFormat.costPerKm(costPerKm) == "₩62/km")

        let efficiency = VehicleMath.kmPerKwh(
            energyAddedKwh: Decimal(string: "186.4"), distanceKm: Decimal(string: "842.3")
        )
        #expect(VehicleFormat.efficiency(efficiency) == "4.5km/kWh")
    }

    /// 지난달이 비면 증감을 내지 않는다 — 0에서 늘었다고 말할 수 없다.
    @Test func 지난달이_비면_증감이_없다() {
        #expect(VehicleMath.deltaPercent(current: 62, previous: nil) == nil)
        #expect(VehicleMath.deltaPercent(current: 62, previous: 0) == nil)
        #expect(VehicleMath.deltaPercent(current: 62, previous: 50) == 24)
        #expect(VehicleMath.deltaPercent(current: 40, previous: 50) == -20)
    }

    @Test func bar를_psi로_바꾼다() {
        #expect(VehicleFormat.pressurePsi(Decimal(string: "2.9")) == "42psi")
        #expect(VehicleFormat.pressurePsi(Decimal(string: "2.5")) == "36psi")
        #expect(VehicleFormat.pressurePsi(nil) == "—")
    }

    /// 제안값은 직전 저장 단가 × 이 건의 사용 전력이다. 첫 건은 직전 단가가 없어 제안이 없다.
    @Test func 제안값은_직전_단가에서_나온다() {
        #expect(VehicleMath.suggestedCost(unitPrice: nil, energyUsedKwh: Decimal(string: "51.8")) == nil)
        #expect(VehicleMath.suggestedCost(unitPrice: 272, energyUsedKwh: nil) == nil)
        #expect(VehicleMath.suggestedCost(unitPrice: 272, energyUsedKwh: Decimal(string: "51.8")) == 14090)
    }

    @Test func 기준_시각을_상대로_읽는다() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(-30), now: now) == 0)
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(-4 * 3600), now: now) == 240)
        // 시계가 어긋나 미래 시각이 와도 음수를 내지 않는다.
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(120), now: now) == 0)

        #expect(VehicleFormat.relative(minutes: 0) == "방금")
        #expect(VehicleFormat.relative(minutes: 45) == "45분 전")
        #expect(VehicleFormat.relative(minutes: 240) == "4시간 전")
        #expect(VehicleFormat.relative(minutes: 2880) == "2일 전")

        #expect(VehicleFormat.elapsed(minutes: 0) == "방금")
        #expect(VehicleFormat.elapsed(minutes: 45) == "45분째")
        #expect(VehicleFormat.elapsed(minutes: 240) == "4시간째")
        #expect(VehicleFormat.elapsed(minutes: 2880) == "2일째")
    }

    /// 서버가 주는 `asOf`는 KST 벽시계 값이다. **기기 시간대로 읽으면 안 된다** —
    /// 이 값만은 「지금」과 빼서 경과 시간을 내므로, 한국 밖에서는 시차만큼 어긋나
    /// 늘 「방금 기준」이 되거나 멀쩡한 값이 오래된 것으로 표시된다.
    @Test func 기준_시각은_기기_시간대와_무관하게_KST로_읽는다() {
        let status = VehicleStatus(
            asOf: "2026-08-13T14:02:00", state: nil, stateSince: nil,
            batteryLevel: nil, usableBatteryLevel: nil, ratedRangeKm: nil, estRangeKm: nil,
            odometerKm: nil, insideTempC: nil, outsideTempC: nil, climateOn: nil,
            locationName: nil, tpmsBar: nil
        )
        // 2026-08-13 14:02 KST = 05:02 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let expected = utc.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 5, minute: 2))!

        #expect(status.asOfDate == expected)
        #expect(VehicleFormat.parseKST("2026-08-13T14:02:00.500") == expected.addingTimeInterval(0.5))
        #expect(VehicleFormat.parseKST("14:02") == nil)
    }

    /// 모르는 상태 문자열은 원문 그대로 낸다 — 상류가 값을 늘렸다는 사실이 숨으면 안 된다.
    @Test func 모르는_상태는_원문을_낸다() {
        #expect(VehicleFormat.stateLabel("asleep") == "잠자는 중")
        #expect(VehicleFormat.stateLabel("driving") == "주행 중")
        #expect(VehicleFormat.stateLabel("hibernating") == "hibernating")
        #expect(VehicleFormat.stateLabel(nil) == "—")
    }

    @Test func 거리를_읽기_좋게_쓴다() {
        #expect(VehicleFormat.distance(Decimal(string: "842.3")) == "842km")
        #expect(VehicleFormat.odometer(Decimal(string: "41203.8")) == "41,204km")
        #expect(VehicleFormat.distance(nil) == "—")
    }
}
