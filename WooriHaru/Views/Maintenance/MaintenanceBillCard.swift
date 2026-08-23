import SwiftUI

/// 목록의 한 달. 청구액을 앞세우고, **바로 앞 달이 목록에 있을 때만** 증감을 붙인다
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

                HStack(spacing: 8) {
                    if let delta {
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
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
