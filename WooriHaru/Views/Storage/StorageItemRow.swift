import SwiftUI

struct StorageItemRow: View {
    let item: StorageItem
    let sectionId: Int
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                InitialIconView(name: item.name, size: 32)

                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.slate700)

                Spacer()

                quantityStepper

                expiryBadge
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var quantityStepper: some View {
        HStack(spacing: 6) {
            Button(action: onDecrement) {
                Image(systemName: "minus.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate400)
            }
            .buttonStyle(.plain)

            Text("\(item.quantity)")
                .font(.subheadline)
                .monospacedDigit()
                .frame(minWidth: 20)

            Button(action: onIncrement) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate400)
            }
            .buttonStyle(.plain)
        }
    }

    private var expiryBadge: some View {
        let days = StorageViewModel.daysUntilExpiry(item.expiryDate)
        return Group {
            if let days {
                Text(expiryText(days))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(expiryColor(days).opacity(0.15))
                    .foregroundStyle(expiryColor(days))
                    .cornerRadius(4)
            } else {
                Text("기한 없음")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private func expiryText(_ days: Int) -> String {
        if days < 0 { return "D+\(-days)" }
        if days == 0 { return "D-Day" }
        return "D-\(days)"
    }

    private func expiryColor(_ days: Int) -> Color {
        if days < 0 { return Color.red600 }
        if days <= 3 { return Color.red500 }
        if days <= 7 { return Color.orange500 }
        return Color.green600
    }
}
