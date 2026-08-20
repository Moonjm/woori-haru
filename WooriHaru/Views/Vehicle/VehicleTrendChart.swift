import SwiftUI

/// 12개월 충전 금액 추이 — 손으로 그린 막대(가계부 통계와 같은 방식, Swift Charts를 들이지 않는다).
///
/// 전비가 아니라 **금액**을 그린다. 계절에 따라 달라지는 것을 보려는 자리이지만, 정작 손에 잡히는
/// 것은 그 달에 얼마 썼느냐다 — 여름 에어컨·겨울 히터는 금액에도 그대로 나타난다.
///
/// **막대 탭은 콜아웃만 바꾼다.** 달을 옮기는 수단은 이미 셋(스와이프·화살표·피커)이다.
struct VehicleTrendChart: View {
    let trend: [VehiclePeriod]
    let selectedKey: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxValue = trend.compactMap(\.cost).max() ?? 0
        let selected = trend.first { $0.yearMonth == selectedKey }
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("월별 충전 금액")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)

                if let selected {
                    HStack(spacing: 6) {
                        Text("\(selected.monthNumber)월")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(VehicleTheme.accent)
                        // ChargeFormat.cost는 건별 금액용이라 nil을 「미입력」으로 읽는다 —
                        // 여기는 그 달의 합계 자리라 기록 없는 달과 구분해야 한다.
                        Text(ChargeFormat.summaryTotal(selected.cost, count: selected.chargeCount ?? 0, loaded: true))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text(VehicleFormat.distance(selected.distanceKm))
                            .font(.caption2)
                            .foregroundStyle(VehicleTheme.textSecondary)
                        Text(ChargeFormat.energy(selected.energyAddedKwh))
                            .font(.caption2)
                            .foregroundStyle(VehicleTheme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .animation(.snappy, value: selected.yearMonth)
                }

                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(trend) { period in
                        bar(period, maxValue: maxValue)
                    }
                }
                .frame(height: 96)
            }
        }
    }

    private func bar(_ period: VehiclePeriod, maxValue: Decimal) -> some View {
        let isSelected = period.yearMonth == selectedKey
        let ratio: CGFloat = {
            guard let value = period.cost, maxValue > 0 else { return 0 }
            return CGFloat(truncating: (value / maxValue) as NSDecimalNumber)
        }()
        return VStack(spacing: 5) {
            Spacer(minLength: 0)
            // 기록이 없는 달도 자리를 지킨다 — 건너뛰면 계절 비교가 어긋난다.
            RoundedRectangle(cornerRadius: 4)
                .fill(period.cost == nil
                      ? AnyShapeStyle(VehicleTheme.trackFill)
                      : AnyShapeStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted))
                .frame(height: max(3, ratio * 72))
            Text("\(period.monthNumber)")
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(period.yearMonth) }
    }
}
