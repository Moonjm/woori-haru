import SwiftUI

struct DayCellView: View {
    let date: Date
    let records: [DailyRecord]
    let partnerRecords: [DailyRecord]
    let overeatLevel: OvereatLevel?
    let holidays: [String]
    let pairEvents: [PairEvent]
    let birthdays: [(emoji: String, label: String)]
    let isCurrentMonth: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                dateNumber
                if isCurrentMonth { overeatIndicator }
                Spacer()
            }

            if isCurrentMonth {
                // 공휴일
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

                // 기념일 + 생일 이모지
                let eventEmojis = pairEvents.map(\.emoji) + birthdays.map(\.emoji)
                if !eventEmojis.isEmpty {
                    Text(eventEmojis.joined())
                        .font(.system(size: 10))
                        .lineLimit(1)
                }

                // 같이 한 것 (together)
                let togetherEmojis = records.filter(\.together).map { $0.category.emoji }
                    + partnerRecords.filter(\.together).map { $0.category.emoji }
                if !togetherEmojis.isEmpty {
                    Text(togetherEmojis.joined())
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(Color.blue50)
                        .cornerRadius(2)
                }

                // 개별 기록: 내 것 + 파트너 (파트너는 opacity 낮게)
                let myEmojis = records.filter { !$0.together }.map { $0.category.emoji }
                let partnerEmojis = partnerRecords.filter { !$0.together }.map { $0.category.emoji }
                if !myEmojis.isEmpty || !partnerEmojis.isEmpty {
                    HStack(spacing: 1) {
                        if !myEmojis.isEmpty {
                            Text(myEmojis.joined())
                                .font(.system(size: 10))
                        }
                        if !partnerEmojis.isEmpty {
                            Text(partnerEmojis.joined())
                                .font(.system(size: 10))
                                .opacity(0.7)
                        }
                    }
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(2)
        .background(.white)
        .opacity(isCurrentMonth ? 1.0 : 0.3)
        .contentShape(Rectangle())
        .onTapGesture { if isCurrentMonth { onTap() } }
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
