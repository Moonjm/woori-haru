import SwiftUI
import UIKit

// MARK: - EmojiIconView

/// emoji 문자열이 "ico:" 접두사면 Asset Catalog의 SVG 아이콘을, 아니면 이모지 텍스트를 렌더링
struct EmojiIconView: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        if let iconName = emoji.iconName {
            if UIImage(named: iconName) != nil {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "questionmark.square")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(emoji)
                .font(.system(size: size))
        }
    }
}

// MARK: - String Extension

extension String {
    /// "ico:churros1" → "churros1", 일반 이모지 → nil
    var iconName: String? {
        hasPrefix("ico:") ? String(dropFirst(4)) : nil
    }

    /// 메뉴/라벨 표시용: "ico:churros1" → "[churros1]", 이모지 → 그대로
    var displayEmoji: String {
        if let name = iconName { return "[\(name)]" }
        return self
    }
}
