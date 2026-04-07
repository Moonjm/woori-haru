import SwiftUI

struct StorageItemCell: View {
    let item: StorageItem
    let sectionId: Int
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    categoryIcon
                        .frame(maxWidth: .infinity)

                    expiryBadge
                }

                Text(item.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate700)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Button(action: onDecrement) {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.purple500)
                            .frame(width: 20, height: 20)
                            .background(Color.purple500.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Text("\(item.quantity)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.slate700)
                        .frame(minWidth: 14)

                    Button(action: onIncrement) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.purple500)
                            .frame(width: 20, height: 20)
                            .background(Color.purple500.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(Color.purple50)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Icon

    private var categoryIcon: some View {
        let cat = item.category.flatMap { ItemCategory(rawValue: $0) }
        return Group {
            if let cat {
                Text(cat.emoji)
                    .font(.system(size: 30))
            } else {
                Text(String(item.name.prefix(1)))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.purple400)
            }
        }
    }

    // MARK: - Expiry Badge

    private var expiryBadge: some View {
        let days = StorageViewModel.daysUntilExpiry(item.expiryDate)
        return Group {
            if let days {
                Text(badgeText(days))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(badgeBackground(days))
                    .foregroundStyle(badgeColor(days))
                    .cornerRadius(4)
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
        if days < 0 { return Color.red500.opacity(0.12) }
        if days <= 3 { return Color.orange500.opacity(0.12) }
        return Color.green600.opacity(0.1)
    }
}
