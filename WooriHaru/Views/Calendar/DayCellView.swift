import SwiftUI

struct DayCellView: View {
    let date: Date
    let records: [DailyRecord]
    let overeatLevel: OvereatLevel?
    let holidays: [String]
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            // Date number + overeat indicator
            HStack(spacing: 2) {
                dateNumber
                overeatIndicator
                Spacer()
            }

            // Holiday labels (max 2)
            ForEach(holidays.prefix(2), id: \.self) { name in
                Text(name)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(Color.red500)
                    .cornerRadius(2)
            }

            // Record emojis
            let emojis = records.map { $0.category.emoji }
            if !emojis.isEmpty {
                Text(emojis.joined())
                    .font(.system(size: 12))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(2)
        .background(.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var dateNumber: some View {
        let isToday = date.isToday
        Text("\(date.day)")
            .font(.caption2)
            .fontWeight(isToday ? .bold : .regular)
            .foregroundStyle(isToday ? .white : dateColor)
            .padding(4)
            .background {
                if isToday {
                    Circle().fill(Color.slate900)
                }
            }
    }

    private var dateColor: Color {
        if date.isSunday || !holidays.isEmpty { return Color.red500 }
        if date.isSaturday { return Color.blue500 }
        return .primary
    }

    @ViewBuilder
    private var overeatIndicator: some View {
        if let level = overeatLevel, level != .none {
            Text("\u{1F437}")
                .font(.system(size: 10))
                .padding(2)
                .background {
                    Circle().fill(overeatColor(level).opacity(0.3))
                }
        }
    }

    private func overeatColor(_ level: OvereatLevel) -> Color {
        switch level {
        case .none: return .clear
        case .mild: return Color.green300
        case .moderate: return Color.orange300
        case .severe: return Color.red400
        case .extreme: return Color.purple400
        }
    }
}
