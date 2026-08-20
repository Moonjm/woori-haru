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
                row(("더 탔다", "덜 탔다", "거리는 그대로"), breakdown.distance,
                    detail: "\(VehicleFormat.distance(previous.distanceKm)) → \(VehicleFormat.distance(current.distanceKm))")
                row(("전비가 나빠졌다", "전비가 좋아졌다", "전비는 그대로"), breakdown.efficiency,
                    detail: "\(VehicleFormat.efficiency(previous.efficiency)) → \(VehicleFormat.efficiency(current.efficiency))")
                row(("단가가 올랐다", "단가가 내렸다", "단가는 그대로"), breakdown.unitPrice,
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
        let display = signedDisplay(breakdown.total)
        return HStack(alignment: .firstTextBaseline) {
            Text("충전비가 달라진 이유")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textSecondary)
            Spacer(minLength: 8)
            Text(display.text)
                .font(.caption)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(display.color)
        }
    }

    /// 라벨 세 짝(증가일 때/감소일 때/변화 없을 때) 가운데 하나를 골라 줄을 그린다.
    ///
    /// **라벨·부호·색을 전부 같은 반올림값 하나에서 뽑는다** — 따로 판정하면
    /// 반 원 미만에서 부호는 「+」인데 라벨은 「덜 탔다」, 색은 초록인 줄이 나온다.
    private func row(_ labels: (up: String, down: String, flat: String), _ value: Decimal, detail: String) -> some View {
        let rounded = VehicleMath.rounded(value)
        let label = rounded > 0 ? labels.up : (rounded < 0 ? labels.down : labels.flat)
        let display = signedDisplay(value)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(display.text)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(display.color)
        }
    }

    /// 부호 있는 금액 문자열과 그 색을 **같은 반올림값**에서 함께 뽑는다.
    /// 이 카드에서 「+9,200」과 「9,200」은 다른 뜻이라 부호를 반드시 붙인다.
    private func signedDisplay(_ value: Decimal) -> (text: String, color: Color) {
        let rounded = VehicleMath.rounded(value)
        let sign = rounded >= 0 ? "+" : "−"
        let color: Color = rounded >= 0 ? VehicleTheme.danger : VehicleTheme.accent
        return (sign + VehicleFormat.won(abs(rounded)), color)
    }

    /// 나눗셈은 뷰가 아니라 `VehicleMath`에서 한다 — `VehicleMath.wonPerAddedKwh` 참조.
    private func unitPriceText(_ period: VehiclePeriod) -> String {
        guard let price = VehicleMath.wonPerAddedKwh(cost: period.cost, energyAddedKwh: period.energyAddedKwh)
        else { return "—" }
        return ChargeFormat.unitPrice(price)
    }
}
