import SwiftUI

struct StorageItemRow: View {
    let item: StorageItem
    let sectionId: Int
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                InitialIconView(name: item.name, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.slate700)

                    expirySubtext
                }

                Spacer()

                HStack(spacing: 10) {
                    quantityStepper
                    expiryBadge
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expiry Subtext

    @ViewBuilder
    private var expirySubtext: some View {
        let days = StorageViewModel.daysUntilExpiry(item.expiryDate)
        if let days {
            if days < 0 {
                Text("소비기한 \(-days)일 지남")
                    .font(.caption2)
                    .foregroundStyle(Color.red500)
            } else if days <= 3 {
                Text("소비기한 \(days)일 남음")
                    .font(.caption2)
                    .foregroundStyle(Color.orange500)
            } else {
                Text("여유 있음")
                    .font(.caption2)
                    .foregroundStyle(Color.green600)
            }
        } else {
            Text("기한 없음")
                .font(.caption2)
                .foregroundStyle(Color.slate400)
        }
    }

    // MARK: - Quantity Stepper

    private var quantityStepper: some View {
        HStack(spacing: 6) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.purple500)
                    .frame(width: 24, height: 24)
                    .background(Color.purple500.opacity(0.08))
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)

            Text("\(item.quantity)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.slate700)
                .frame(minWidth: 18)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.purple500)
                    .frame(width: 24, height: 24)
                    .background(Color.purple500.opacity(0.08))
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Expiry Badge

    private var expiryBadge: some View {
        let days = StorageViewModel.daysUntilExpiry(item.expiryDate)
        return Group {
            if let days {
                Text(badgeText(days))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeBackground(days))
                    .foregroundStyle(badgeColor(days))
                    .cornerRadius(6)
            }
        }
    }

    private func badgeText(_ days: Int) -> String {
        if days < 0 { return "D+\(-days)" }
        if days == 0 { return "D-Day" }
        return "D-\(days)"
    }

    private func badgeColor(_ days: Int) -> Color {
        if days < 0 { return Color.red600 }
        if days <= 3 { return Color.orange700 }
        return Color.green600
    }

    private func badgeBackground(_ days: Int) -> Color {
        if days < 0 { return Color.red500.opacity(0.1) }
        if days <= 3 { return Color.orange500.opacity(0.1) }
        return Color.green600.opacity(0.1)
    }
}
