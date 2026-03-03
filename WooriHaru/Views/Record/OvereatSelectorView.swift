import SwiftUI

struct OvereatSelectorView: View {
    let currentLevel: OvereatLevel
    let onSelect: (OvereatLevel) -> Void

    private let levels: [(OvereatLevel, String)] = [
        (.none, "없음"), (.mild, "소"), (.moderate, "중"), (.severe, "대"), (.extreme, "대대")
    ]

    var body: some View {
        HStack {
            Text("\u{1F437} 과식")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.slate600)

            Spacer()

            HStack(spacing: 4) {
                ForEach(levels, id: \.0) { level, label in
                    Button(action: { onSelect(level) }) {
                        Text(label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(buttonBackground(level))
                            .foregroundStyle(buttonForeground(level))
                            .clipShape(Capsule())
                            .overlay {
                                if currentLevel == level && level != .none {
                                    Capsule().stroke(buttonBorder(level), lineWidth: 1)
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.slate50)
                .stroke(Color.slate200, lineWidth: 1)
        }
    }

    private func buttonBackground(_ level: OvereatLevel) -> Color {
        guard currentLevel == level else { return .white }
        switch level {
        case .none: return .white
        case .mild: return Color.green100
        case .moderate: return Color.orange200
        case .severe: return Color.red.opacity(0.15)
        case .extreme: return Color.purple200
        }
    }

    private func buttonForeground(_ level: OvereatLevel) -> Color {
        guard currentLevel == level else { return Color.slate400 }
        switch level {
        case .none: return Color.slate500
        case .mild: return Color.green700
        case .moderate: return Color.orange700
        case .severe: return Color.red500
        case .extreme: return Color.purple800
        }
    }

    private func buttonBorder(_ level: OvereatLevel) -> Color {
        switch level {
        case .none: return Color.slate200
        case .mild: return Color.green300
        case .moderate: return Color.orange300
        case .severe: return Color.red400
        case .extreme: return Color.purple400
        }
    }
}
