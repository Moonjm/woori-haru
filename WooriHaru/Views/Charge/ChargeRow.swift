import SwiftUI

/// 한 줄 충전 — 장소 + 시각·소요시간 + 충전량·배터리 + 금액.
struct ChargeRow: View {
    let item: ChargeItem

    /// 시작→종료 SoC를 얇은 막대로. **완속·급속·짧은 보충이 목록에서 한눈에 갈린다** —
    /// 「63% → 80%」를 글자로 읽는 것과 폭으로 보는 것은 다르다.
    ///
    /// **둘 중 하나라도 없으면 그리지 않는다.** 한쪽만으로 그린 막대는 거짓말이다.
    @ViewBuilder private var batteryGauge: some View {
        if let start = item.startBatteryLevel, let end = item.endBatteryLevel, end > start {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(VehicleTheme.trackFill)
                    // 시작 지점까지는 옅게 — 「원래 들어 있던 만큼」이다.
                    Capsule()
                        .fill(VehicleTheme.textTertiary)
                        .frame(width: w * CGFloat(start) / 100)
                    // 이번에 채운 구간만 진하게.
                    Capsule()
                        .fill(VehicleTheme.accent)
                        .frame(width: w * CGFloat(end - start) / 100)
                        .offset(x: w * CGFloat(start) / 100)
                }
            }
            .frame(height: 4)
            .accessibilityLabel("배터리 \(start)%에서 \(end)%로")
            .padding(.top, 6)
            .padding(.bottom, 12)
            .padding(.horizontal, 16)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.locationName ?? "장소 없음")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(VehicleTheme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(LedgerFormat.time(item.startDate))
                        Text("·")
                        Text(ChargeFormat.duration(item.durationMin))
                        // 단가는 사용 전력이 있어야 낼 수 있다 — 없으면 자리도 만들지 않는다.
                        if let unit = item.costPerKwh {
                            Text("·")
                            Text(ChargeFormat.unitPrice(unit))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.textTertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ChargeFormat.cost(item.cost))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        // 금액이 빈 건은 회색으로 죽이지 않고 따로 표시한다 — 채우러 오는 화면이다.
                        .foregroundStyle(item.cost == nil ? VehicleTheme.warning : VehicleTheme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(ChargeFormat.energy(item.energyAddedKwh))
                        Text(ChargeFormat.batteryRange(item.startBatteryLevel, item.endBatteryLevel))
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textTertiary)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            batteryGauge
        }
        // 게이지까지가 한 행이라 보이는 만큼이 눌려야 한다 — Spacer의 빈 공간이 위임되지 않기 때문에 외곽 컨테이너에 정형이 필요하다.
        .contentShape(.rect)
    }
}
