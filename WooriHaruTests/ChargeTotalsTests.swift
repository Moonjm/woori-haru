import Foundation
import Testing
@testable import WooriHaru

struct ChargeTotalsTests {

    /// **미입력분 사용 전력을 분모에서 뺀다.** 안 빼면 낸 돈은 그대로인데 분모만 커져
    /// 단가가 낮게 나온다 — 실측(2026-08-18) 200.3 대 211.6원/kWh로 5.6% 어긋났다.
    @Test func 단가는_미입력분을_분모에서_뺀다() {
        let priced = VehicleMath.wonPerKwh(
            cost: 3644562,
            energyUsedKwh: Decimal(string: "18197.2")!,
            costMissingEnergyUsedKwh: Decimal(string: "977.0")!
        )
        // `won`으로 잰다 — 카드가 실제로 부르는 함수다. `wonPerKwh`는 접미사를 더할 뿐 이
        // 함수를 거친다.
        #expect(VehicleFormat.won(priced) == "₩212")

        // 빼지 않으면 이 값이 된다 — 회귀를 잡으려고 함께 못박는다.
        let naive = VehicleMath.wonPerKwh(
            cost: 3644562, energyUsedKwh: Decimal(string: "18197.2")!, costMissingEnergyUsedKwh: 0
        )
        #expect(VehicleFormat.won(naive) == "₩200")
        #expect(priced! > naive!)
    }

    /// 실측 그대로다 — 급속이 완속보다 38% 비싸다. 이 차이가 넷째 칸의 존재 이유다.
    @Test func 급속이_완속보다_비싸다() {
        let fast = VehicleMath.wonPerKwh(cost: 140479,
                                         energyUsedKwh: Decimal(string: "1320.2")!,
                                         costMissingEnergyUsedKwh: Decimal(string: "833.9")!)
        let slow = VehicleMath.wonPerKwh(cost: 3493723,
                                         energyUsedKwh: Decimal(string: "16877.1")!,
                                         costMissingEnergyUsedKwh: Decimal(string: "143.1")!)
        #expect(VehicleFormat.won(fast) == "₩289")
        #expect(VehicleFormat.won(slow) == "₩209")
        #expect(fast! > slow!)
    }

    /// 분모가 사라지는 경우들. **전부 미입력이면 단가를 낼 수 없다** — 0원이 아니다.
    @Test func 낼_수_없으면_단가도_없다() {
        #expect(VehicleMath.wonPerKwh(cost: nil, energyUsedKwh: 100, costMissingEnergyUsedKwh: 0) == nil)
        #expect(VehicleMath.wonPerKwh(cost: 1000, energyUsedKwh: nil, costMissingEnergyUsedKwh: 0) == nil)
        // 전부 미입력 — 분모가 0이 된다.
        #expect(VehicleMath.wonPerKwh(cost: 0, energyUsedKwh: 100, costMissingEnergyUsedKwh: 100) == nil)
        // 미입력분이 사용 전력보다 크게 오는 일은 없어야 하지만, 와도 죽지 않는다.
        #expect(VehicleMath.wonPerKwh(cost: 1000, energyUsedKwh: 100, costMissingEnergyUsedKwh: 120) == nil)
        #expect(VehicleFormat.wonPerKwh(nil) == ChargeFormat.placeholder)
    }

    /// 단가를 낸 표본이 몇 건인지 화면이 적어야 한다 — 급속은 39건 중 22건이 미입력이라
    /// **17건에서만 나온 값**이다. 「289원」만 크게 적으면 그 얇음이 숨는다.
    @Test func 단가를_낸_표본_수를_센다() {
        let fast = ChargeTotalsBreakdown(
            chargeCount: 39, energyAddedKwh: nil, energyUsedKwh: nil,
            cost: nil, costMissingCount: 22, costMissingEnergyUsedKwh: nil
        )
        #expect(fast.pricedCount == 17)
    }

    /// `fast + slow = 최상위` 불변식이 선다. 최상위 중복은 의도된 것이다 — 헤드라인과 내역이다.
    @Test func 급속과_완속을_더하면_최상위다() throws {
        let json = """
        { "chargeCount": 474, "energyAddedKwh": 17442.0, "energyUsedKwh": 18197.2,
          "cost": 3644562, "costMissingCount": 35, "costMissingEnergyUsedKwh": 977.0,
          "firstChargedAt": "2021-09-03",
          "fast": { "chargeCount": 42, "energyAddedKwh": 1358.4, "energyUsedKwh": 1329.0,
                    "cost": 143337, "costMissingCount": 24, "costMissingEnergyUsedKwh": 833.9 },
          "slow": { "chargeCount": 432, "energyAddedKwh": 16083.6, "energyUsedKwh": 16868.2,
                    "cost": 3501225, "costMissingCount": 11, "costMissingEnergyUsedKwh": 143.1 } }
        """.data(using: .utf8)!

        let t = try JSONDecoder().decode(ChargeTotalsResponse.self, from: json)

        #expect(t.fast.chargeCount + t.slow.chargeCount == t.chargeCount)
        #expect(t.fast.costMissingCount + t.slow.costMissingCount == t.costMissingCount)
        #expect(t.fast.cost! + t.slow.cost! == t.cost!)
        #expect(t.firstChargedAt == "2021-09-03")
    }

    /// 구버전 데이터에서 합이 nil일 수 있다. 0으로 읽지 않는다.
    @Test func 합이_비어도_디코딩된다() throws {
        let json = """
        { "chargeCount": 0, "energyAddedKwh": null, "energyUsedKwh": null,
          "cost": null, "costMissingCount": 0, "costMissingEnergyUsedKwh": null,
          "firstChargedAt": null,
          "fast": { "chargeCount": 0, "energyAddedKwh": null, "energyUsedKwh": null,
                    "cost": null, "costMissingCount": 0, "costMissingEnergyUsedKwh": null },
          "slow": { "chargeCount": 0, "energyAddedKwh": null, "energyUsedKwh": null,
                    "cost": null, "costMissingCount": 0, "costMissingEnergyUsedKwh": null } }
        """.data(using: .utf8)!

        let t = try JSONDecoder().decode(ChargeTotalsResponse.self, from: json)

        #expect(t.energyAddedKwh == nil)
        #expect(t.firstChargedAt == nil)
        #expect(t.fast.pricedCount == 0)
    }
}
