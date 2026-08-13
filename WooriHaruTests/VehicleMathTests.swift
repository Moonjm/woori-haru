import Foundation
import Testing
@testable import WooriHaru

struct VehicleMathTests {
    /// 분모가 없거나 0이면 계산하지 않는다 — 0으로 내면 「0원에 탔다」가 된다.
    @Test func 주행이_없으면_km당_비용도_전비도_없다() {
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: nil) == nil)
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: 0) == nil)
        #expect(VehicleMath.costPerKm(cost: nil, distanceKm: 842) == nil)
        #expect(VehicleMath.consumptionKwhPer100km(energyAddedKwh: 186, distanceKm: 0) == nil)
    }

    @Test func km당_비용과_전비를_계산한다() {
        let costPerKm = VehicleMath.costPerKm(cost: 52300, distanceKm: Decimal(string: "842.3"))
        #expect(VehicleFormat.costPerKm(costPerKm) == "₩62/km")

        let consumption = VehicleMath.consumptionKwhPer100km(
            energyAddedKwh: Decimal(string: "186.4"), distanceKm: Decimal(string: "842.3")
        )
        #expect(VehicleFormat.consumption(consumption) == "22.1kWh/100km")
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
        #expect(VehicleFormat.pressureBar(nil) == "—")
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
