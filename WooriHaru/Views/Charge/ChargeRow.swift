import SwiftUI

/// 한 줄 충전 — 장소 + 시각·소요시간 + 충전량·배터리 + 금액.
struct ChargeRow: View {
    let item: ChargeItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.locationName ?? "장소 없음")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate900)
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
                .foregroundStyle(Color.slate400)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ChargeFormat.cost(item.cost))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    // 금액이 빈 건은 회색으로 죽이지 않고 따로 표시한다 — 채우러 오는 화면이다.
                    .foregroundStyle(item.cost == nil ? Color.orange700 : Color.slate900)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(ChargeFormat.energy(item.energyAddedKwh))
                    Text(ChargeFormat.batteryRange(item.startBatteryLevel, item.endBatteryLevel))
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.slate400)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}
