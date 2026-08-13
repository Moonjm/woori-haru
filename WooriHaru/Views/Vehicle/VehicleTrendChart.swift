import SwiftUI

/// 12개월 전비 추이 — 손으로 그린 막대(가계부 통계와 같은 방식, Swift Charts를 들이지 않는다).
/// **막대 탭은 콜아웃만 바꾼다.** 달을 옮기는 수단은 이미 셋(스와이프·화살표·피커)이다.
struct VehicleTrendChart: View {
    let trend: [VehiclePeriod]
    let selectedKey: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxValue = trend.compactMap(\.consumption).max() ?? 0
        let selected = trend.first { $0.yearMonth == selectedKey }
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("전비 추이 (kWh/100km)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                if let selected {
                    HStack(spacing: 6) {
                        Text("\(selected.monthNumber)월")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(Color.blue600)
                        Text(VehicleFormat.consumption(selected.consumption))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text(VehicleFormat.distance(selected.distanceKm))
                            .font(.caption2)
                            .foregroundStyle(Color.slate500)
                        Text(ChargeFormat.cost(selected.cost))
                            .font(.caption2)
                            .foregroundStyle(Color.slate500)
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
            guard let value = period.consumption, maxValue > 0 else { return 0 }
            return CGFloat(truncating: (value / maxValue) as NSDecimalNumber)
        }()
        return VStack(spacing: 5) {
            Spacer(minLength: 0)
            // 기록이 없는 달도 자리를 지킨다 — 건너뛰면 계절 비교가 어긋난다.
            RoundedRectangle(cornerRadius: 4)
                .fill(period.consumption == nil
                      ? AnyShapeStyle(Color.slate200)
                      : AnyShapeStyle(isSelected ? Color.blue600 : Color.blue300))
                .frame(height: max(3, ratio * 72))
            Text("\(period.monthNumber)")
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? Color.blue600 : Color.slate400)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(period.yearMonth) }
    }
}
