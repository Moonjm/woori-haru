import SwiftUI

/// 누적 스탯 2×2 타일 — 누적 주행 / 누적 충전 / 누적 충전비 / 급속·완속 단가.
///
/// **넷째 칸이 단가인 이유:** 원래 후보였던 「주유비 대비 절감액」은 유가·연비 상수를 앱에 박아야
/// 하는데 박는 순간부터 틀려지기 시작한다. 단가는 상수 없이 나오고 행동을 바꾸는 숫자다 —
/// 실측으로 급속이 완속보다 38% 비싸다.
struct ChargeTotalsCard: View {
    let totals: ChargeTotalsResponse?
    /// `/tesla/status`에서 온다 — **누적 주행거리는 이 응답에 없다.**
    let odometerKm: Decimal?

    private var fast: Decimal? {
        VehicleMath.wonPerKwh(cost: totals?.fast.cost,
                              energyUsedKwh: totals?.fast.energyUsedKwh,
                              costMissingEnergyUsedKwh: totals?.fast.costMissingEnergyUsedKwh)
    }

    private var slow: Decimal? {
        VehicleMath.wonPerKwh(cost: totals?.slow.cost,
                              energyUsedKwh: totals?.slow.energyUsedKwh,
                              costMissingEnergyUsedKwh: totals?.slow.costMissingEnergyUsedKwh)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("누적")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    if let since = totals?.firstChargedAt {
                        Text("\(since)부터")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.slate400)
                    }
                }
                HStack(spacing: 10) {
                    tile(VehicleFormat.odometer(odometerKm), "주행")
                    tile(ChargeFormat.energy(totals?.energyAddedKwh), "충전")
                }
                HStack(spacing: 10) {
                    tile(totals?.cost.map { LedgerFormat.amount($0, currency: "KRW") }
                         ?? ChargeFormat.placeholder, "충전비")
                    unitPriceTile
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
    }

    /// **표본 수를 함께 적는다.** 급속은 39건 중 22건이 미입력이라 17건에서만 나온 값이고,
    /// 「289원」만 크게 적으면 그 얇음이 숨는다.
    private var unitPriceTile: some View {
        VStack(spacing: 2) {
            row("급속", fast, totals?.fast.pricedCount)
            row("완속", slow, totals?.slow.pricedCount)
            Text("kWh당")
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: Decimal?, _ count: Int?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.slate500)
            Text(value.map { LedgerFormat.amount(VehicleMath.rounded($0), currency: "KRW") }
                 ?? ChargeFormat.placeholder)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
            if let count {
                Text("\(count)건")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Color.slate400)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

#Preview("누적") {
    let t = ChargeTotalsResponse(
        chargeCount: 474, energyAddedKwh: Decimal(string: "17442.0"),
        energyUsedKwh: Decimal(string: "18197.2"), cost: 3644562, costMissingCount: 35,
        costMissingEnergyUsedKwh: Decimal(string: "977.0"), firstChargedAt: "2021-09-03",
        fast: ChargeTotalsBreakdown(chargeCount: 39, energyAddedKwh: nil,
                                    energyUsedKwh: Decimal(string: "1320.2"), cost: 140479,
                                    costMissingCount: 22,
                                    costMissingEnergyUsedKwh: Decimal(string: "833.9")),
        slow: ChargeTotalsBreakdown(chargeCount: 431, energyAddedKwh: nil,
                                    energyUsedKwh: Decimal(string: "16877.1"), cost: 3493723,
                                    costMissingCount: 10,
                                    costMissingEnergyUsedKwh: Decimal(string: "143.1")))
    return VStack(spacing: 12) {
        ChargeTotalsCard(totals: t, odometerKm: Decimal(string: "41203.8"))
        // 아직 못 받았을 때 — 자리는 지키고 값만 「—」다.
        ChargeTotalsCard(totals: nil, odometerKm: nil)
    }
    .padding(16)
    .background(Color.slate50)
}
