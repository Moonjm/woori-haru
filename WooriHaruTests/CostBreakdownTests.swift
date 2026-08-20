import Foundation
import Testing
@testable import WooriHaru

struct CostBreakdownTests {
    private func period(_ ym: String, km: Decimal?, kwh: Decimal?, cost: Decimal?) -> VehiclePeriod {
        VehiclePeriod(yearMonth: ym, distanceKm: km, drivingMin: nil, driveCount: nil,
                      energyAddedKwh: kwh, energyUsedKwh: nil, cost: cost, chargeCount: nil)
    }

    /// 누적합은 기록이 없는 달을 건너뛰고 직전 누적을 이어 간다 —
    /// **그 달을 nil로 두면 선이 끊긴다.** 누적은 안 탄 달에도 값이 있다.
    @Test func 누적합은_기록이_없는_달을_건너뛴다() {
        #expect(VehicleMath.runningTotals([100, nil, 50]) == [100, nil, 150])
        #expect(VehicleMath.runningTotals([nil, 40]) == [nil, 40])
        #expect(VehicleMath.runningTotals([]) == [])
        // 0은 「안 탔다」라 누적이 그대로 이어진다.
        #expect(VehicleMath.runningTotals([100, 0, 50]) == [100, 100, 150])
    }

    /// 세 효과의 합이 총 증감과 정확히 같아야 한다 — 어긋나면 화면이
    /// 「▲18,400원인데 항을 더하면 17,900원」이라고 말하게 된다.
    @Test func 세_효과의_합이_총_증감과_같다() throws {
        let prev = period("2026-07", km: 620, kwh: 115, cost: 22770)
        let curr = period("2026-08", km: 780, kwh: 153, cost: 32700)
        let result = VehicleMath.costBreakdown(current: curr, previous: prev)
        let breakdown = try #require(result)

        // total은 두 달 비용의 차다. **기대값을 먼저 let에 담는다** —
        // #expect 안에 인라인 산술로 두면 양쪽 표시값이 같은데도 판정이 어긋난다
        // (Decimal 상등 문제가 아님을 다섯 경로로 확인했다).
        let expectedTotal: Decimal = 32700 - 22770
        #expect(breakdown.total == expectedTotal)
        let sum = breakdown.distance + breakdown.efficiency + breakdown.unitPrice
        // Decimal 나눗셈 오차를 감안해 1원 안쪽이면 같다고 본다.
        #expect(abs(sum - breakdown.total) < 1)
    }

    /// 재료가 하나라도 없거나 0이면 분해하지 않는다 — 0으로 나누는 길과
    /// 「기록 없는 달과 견줬다」는 두 함정을 여기서 막는다.
    @Test func 재료가_없으면_분해하지_않는다() {
        let ok = period("2026-08", km: 780, kwh: 153, cost: 32700)
        let noPrevCost = period("2026-07", km: 620, kwh: 115, cost: nil)
        let zeroKwh    = period("2026-07", km: 620, kwh: 0, cost: 22770)
        let noDistance = period("2026-07", km: nil, kwh: 115, cost: 22770)

        #expect(VehicleMath.costBreakdown(current: ok, previous: noPrevCost) == nil)
        #expect(VehicleMath.costBreakdown(current: ok, previous: zeroKwh) == nil)
        #expect(VehicleMath.costBreakdown(current: ok, previous: noDistance) == nil)
        #expect(VehicleMath.costBreakdown(current: noPrevCost, previous: ok) == nil)
    }

    /// 아무것도 안 바뀌면 세 효과가 전부 0이다.
    @Test func 같은_달이면_효과가_전부_0이다() throws {
        let p = period("2026-08", km: 780, kwh: 153, cost: 32700)
        let breakdown = try #require(VehicleMath.costBreakdown(current: p, previous: p))
        #expect(breakdown.total == 0)
        #expect(breakdown.distance == 0)
        #expect(breakdown.efficiency == 0)
        #expect(breakdown.unitPrice == 0)
    }

    /// `wonPerAddedKwh`의 분모는 반드시 `energyAddedKwh`(차에 들어간 양)다 —
    /// 값이 하나라도 없거나 분모가 0이면 나누지 않고 nil을 낸다.
    @Test func 단가는_충전량으로만_나눈다() {
        #expect(VehicleMath.wonPerAddedKwh(cost: 32700, energyAddedKwh: 153) == 32700 / Decimal(153))
        #expect(VehicleMath.wonPerAddedKwh(cost: nil, energyAddedKwh: 153) == nil)
        #expect(VehicleMath.wonPerAddedKwh(cost: 32700, energyAddedKwh: nil) == nil)
        #expect(VehicleMath.wonPerAddedKwh(cost: 32700, energyAddedKwh: 0) == nil)
    }
}
