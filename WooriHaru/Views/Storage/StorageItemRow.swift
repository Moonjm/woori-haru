import SwiftUI

struct StorageItemCell: View {
    let item: StorageItem
    let sectionId: Int
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // 이모지 아이콘 (컬러 배경)
                categoryIcon
                    .frame(width: 50, height: 50)
                    .background(iconBackground)
                    .cornerRadius(15)

                // 이름 + 수량
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.slate700)
                        .lineLimit(1)

                    Text("x\(item.quantity)")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }

                Spacer()

                // 유통기한 프로그레스바
                expiryIndicator

                // 수량 조절 버튼
                HStack(spacing: 2) {
                    Button(action: onDecrement) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.slate400)
                            .frame(width: 30, height: 30)
                            .background(Color.slate100)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)

                    Button(action: onIncrement) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.slate600)
                            .frame(width: 30, height: 30)
                            .background(Color.slate100)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Icon

    private var categoryIcon: some View {
        let cat = item.category.flatMap { ItemCategory(rawValue: $0) }
        return Group {
            if let cat {
                Text(cat.emoji)
                    .font(.system(size: 26))
            } else {
                Text(String(item.name.prefix(1)))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // 카테고리별 배경색 (파스텔 톤)
    private var iconBackground: Color {
        guard let catStr = item.category,
              let cat = ItemCategory(rawValue: catStr) else {
            return Color(red: 0.75, green: 0.70, blue: 0.85) // 기본 퍼플
        }
        switch cat.group {
        case .vegetable:  return Color(red: 0.88, green: 0.96, blue: 0.88) // 연초록
        case .fruit:      return Color(red: 1.0,  green: 0.93, blue: 0.88) // 연피치
        case .meat:       return Color(red: 1.0,  green: 0.90, blue: 0.90) // 연빨강
        case .egg:        return Color(red: 1.0,  green: 0.97, blue: 0.88) // 연노랑
        case .seafood:    return Color(red: 0.88, green: 0.94, blue: 1.0)  // 연파랑
        case .dairy:      return Color(red: 0.93, green: 0.95, blue: 1.0)  // 연라벤더
        case .grain:      return Color(red: 0.97, green: 0.95, blue: 0.88) // 연베이지
        case .kimchi:     return Color(red: 1.0,  green: 0.91, blue: 0.87) // 연주황
        case .beverage:   return Color(red: 0.88, green: 0.97, blue: 0.97) // 연민트
        case .snack:      return Color(red: 1.0,  green: 0.95, blue: 0.86) // 연골드
        case .bakery:     return Color(red: 0.98, green: 0.94, blue: 0.88) // 연브라운
        case .coffee:     return Color(red: 0.95, green: 0.92, blue: 0.88) // 연모카
        default:          return Color(red: 0.94, green: 0.94, blue: 0.96) // 연그레이
        }
    }

    // MARK: - Expiry Indicator (프로그레스바)

    private var expiryIndicator: some View {
        let days = StorageViewModel.daysUntilExpiry(item.expiryDate)
        return Group {
            if let days {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(expiryText(days))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(expiryColor(days))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.slate200)
                        .frame(width: 44, height: 5)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(expiryColor(days))
                                .frame(width: 44 * expiryProgress(days))
                        }
                }
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

    private func expiryProgress(_ days: Int) -> CGFloat {
        if days < 0 { return 1.0 }
        return max(0.15, min(1.0, CGFloat(7 - days) / 7.0))
    }
}
