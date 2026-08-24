import SwiftUI

/// 목록의 한 달. 부과액을 앞세우고, **바로 앞 달이 목록에 있을 때만** 증감을 붙인다
/// (`delta`가 nil인 경우다 — 판단은 `MaintenanceTrendMath`가 이미 했다).
struct MaintenanceBillCard: View {
    let bill: MaintenanceBill
    let delta: MaintenanceDelta?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(MaintenanceFormat.monthTitle(bill.yearMonth))
                        .font(.headline)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Spacer(minLength: 8)
                    if bill.discountTotal != 0 {
                        Text("할인 \(MaintenanceFormat.won(bill.discountTotal))")
                            .font(.caption2)
                            .foregroundStyle(VehicleTheme.textTertiary)
                    }
                }

                Text(MaintenanceFormat.won(bill.chargedAmount))
                    .font(.title2)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.accentBright)

                // **`delta`가 nil이면 이 줄 자체를 안 만든다.** 미납 배지가 있던 시절엔
                // 이 `HStack`이 늘 뭔가를 그렸지만, 지금은 `delta`가 없으면 `Spacer` 혼자
                // 남는다 — 그래도 `HStack`이 있는 한 `VStack(spacing: 10)`이 위아래에
                // 똑같이 10pt를 더해 아무 것도 없는 자리에 빈 줄만큼의 여백이 남는다.
                if let delta {
                    HStack(spacing: 8) {
                        // 오른 달은 경고색이다 — 「지난달보다 더 냈다」가 이 줄의 뜻이다.
                        let up = delta.amount > 0
                        Text(MaintenanceFormat.signedWon(delta.amount))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(up ? VehicleTheme.warning : VehicleTheme.accent)
                        if let ratio = delta.ratio {
                            Text(MaintenanceFormat.percent(ratio))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        Text("전월 대비")
                            .font(.caption2)
                            .foregroundStyle(VehicleTheme.textTertiary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
