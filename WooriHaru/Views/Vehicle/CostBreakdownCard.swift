import SwiftUI

/// 「이번 달 충전비, 왜 달라졌을까」 — 지난달 대비 증감을 거리·전비·단가 셋으로 쪼갠다.
///
/// **지표 줄의 `지난달보다 ▲ 12%`가 답하지 않던 것을 답한다.** 12%가 어디서 왔는지
/// 말하지 않으면 그 숫자로 할 수 있는 일이 없다.
///
/// 세 항의 합은 총 증감과 정확히 같다(`VehicleMath.costBreakdown` 참조).
/// 재료가 하나라도 없으면 부르는 쪽이 카드째 감춘다.
struct CostBreakdownCard: View {
    let breakdown: CostBreakdown
    let current: VehiclePeriod
    let previous: VehiclePeriod

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                row("더 탔다", breakdown.distance,
                    detail: "\(VehicleFormat.distance(previous.distanceKm)) → \(VehicleFormat.distance(current.distanceKm))")
                row("전비가 달라졌다", breakdown.efficiency,
                    detail: "\(VehicleFormat.efficiency(previous.efficiency)) → \(VehicleFormat.efficiency(current.efficiency))")
                row("단가가 달라졌다", breakdown.unitPrice,
                    detail: "\(unitPriceText(previous)) → \(unitPriceText(current))")

                // 여기 단가는 충전량(차에 들어간 양) 기준이다 — 누적 카드의 단가는
                // 벽에서 뽑아쓴 양이 분모라 값이 다르다. 그 차이를 화면에 남긴다.
                Text("단가는 충전량 1kWh당 금액이에요.")
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("충전비가 달라진 이유")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textSecondary)
            Spacer(minLength: 8)
            Text(signedWon(breakdown.total))
                .font(.caption)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(breakdown.total >= 0 ? VehicleTheme.danger : VehicleTheme.accent)
        }
    }

    private func row(_ label: String, _ value: Decimal, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(signedWon(value))
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(value >= 0 ? VehicleTheme.danger : VehicleTheme.accent)
        }
    }

    /// 부호를 반드시 붙인다 — 이 카드에서 「+9,200」과 「9,200」은 다른 뜻이다.
    private func signedWon(_ value: Decimal) -> String {
        let rounded = VehicleMath.rounded(value)
        let sign = rounded >= 0 ? "+" : "−"
        return sign + VehicleFormat.won(abs(rounded))
    }

    private func unitPriceText(_ period: VehiclePeriod) -> String {
        guard let cost = period.cost, let kwh = period.energyAddedKwh, kwh > 0 else { return "—" }
        return ChargeFormat.unitPrice(cost / kwh)
    }
}
