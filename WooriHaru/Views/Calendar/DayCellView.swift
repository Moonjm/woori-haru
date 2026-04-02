import SwiftUI

/// DayCellView에 전달할 사전 계산된 표시 데이터
struct DayCellDisplayData: Equatable {
    let holidayLabels: [String]
    let eventEmojis: [String]
    let togetherRows: [[String]]
    let myEmojis: [String]
    let partnerEmojis: [String]

    var hasTogether: Bool { !togetherRows.isEmpty }
    var maxIndividualCount: Int { max(myEmojis.count, partnerEmojis.count) }
    var needsDivider: Bool { hasTogether && maxIndividualCount > 0 }

    init(records: [DailyRecord], partnerRecords: [DailyRecord],
         holidays: [String], pairEvents: [PairEvent],
         birthdays: [(emoji: String, label: String)]) {
        // 공휴일: 괄호 제거
        self.holidayLabels = holidays.prefix(2).map {
            $0.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression)
        }

        // 기념일 + 생일
        self.eventEmojis = pairEvents.map(\.emoji) + birthdays.map(\.emoji)

        // 같이 한 것
        let togetherEmojis = records.filter(\.together).map { $0.category.emoji }
            + partnerRecords.filter(\.together).map { $0.category.emoji }
        self.togetherRows = stride(from: 0, to: togetherEmojis.count, by: 3).map {
            Array(togetherEmojis[$0..<min($0 + 3, togetherEmojis.count)])
        }

        // 개별 기록
        self.myEmojis = records.filter { !$0.together }.map { $0.category.emoji }
        self.partnerEmojis = partnerRecords.filter { !$0.together }.map { $0.category.emoji }
    }
}

struct DayCellView: View {
    let date: Date
    let displayData: DayCellDisplayData
    let overeatLevel: OvereatLevel?
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
                ForEach(displayData.holidayLabels, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(Color.red500)
                        .cornerRadius(2)
                }

                // 기념일 + 생일 이모지
                if !displayData.eventEmojis.isEmpty {
                    emojiRow(displayData.eventEmojis, size: 11)
                }

                // 같이 한 것 (together) — 3개씩 줄바꿈
                if displayData.hasTogether {
                    VStack(spacing: 1) {
                        ForEach(Array(displayData.togetherRows.enumerated()), id: \.offset) { _, chunk in
                            emojiRow(chunk, size: 11)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(Color.blue50)
                    .cornerRadius(2)
                }

                // 같이/개별 구분 점선
                if displayData.needsDivider {
                    DottedHLine()
                        .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.slate400)
                        .frame(height: 1)
                        .padding(.vertical, 1)
                }

                // 개별 기록: 내 것(왼쪽) | 점선 | 파트너(오른쪽)
                let maxCount = displayData.maxIndividualCount
                if maxCount > 0 {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 1) {
                            ForEach(0..<maxCount, id: \.self) { i in
                                if i < displayData.myEmojis.count {
                                    EmojiIconView(emoji: displayData.myEmojis[i], size: 11)
                                } else {
                                    Text(" ").font(.system(size: 11))
                                }
                            }
                        }
                        if !displayData.myEmojis.isEmpty && !displayData.partnerEmojis.isEmpty {
                            let lineHeight = CGFloat(maxCount) * 12 + CGFloat(maxCount - 1) * 1
                            DottedVLine()
                                .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.slate400)
                                .frame(width: 1, height: lineHeight)
                                .padding(.horizontal, 2)
                        }
                        VStack(spacing: 1) {
                            ForEach(0..<maxCount, id: \.self) { i in
                                if i < displayData.partnerEmojis.count {
                                    EmojiIconView(emoji: displayData.partnerEmojis[i], size: 11)
                                        .opacity(0.7)
                                } else {
                                    Text(" ").font(.system(size: 11))
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .background(.white)
        .contentShape(Rectangle())
        .onTapGesture { if isCurrentMonth { onTap() } }
    }

    @ViewBuilder
    private var dateNumber: some View {
        let isToday = date.isToday && isCurrentMonth
        Text("\(date.day)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isToday ? .white : dateColor)
            .frame(width: 20, height: 20)
            .background {
                if isToday {
                    Circle().fill(Color.slate700)
                }
            }
    }

    private var dateColor: Color {
        if !isCurrentMonth { return Color.slate400.opacity(0.5) }
        if date.isSunday || !displayData.holidayLabels.isEmpty { return Color.red500 }
        if date.isSaturday { return Color.blue500 }
        return .primary
    }

    @ViewBuilder
    private var overeatIndicator: some View {
        if let level = overeatLevel, level != .none {
            if level == .extreme {
                RainbowPigView()
            } else {
                Text("🐷")
                    .font(.system(size: 10))
                    .frame(width: 20, height: 20)
                    .background {
                        Circle()
                            .fill(overeatColor(level).opacity(0.15))
                        Circle()
                            .strokeBorder(overeatColor(level), lineWidth: 1.5)
                    }
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

    @ViewBuilder
    private func emojiRow(_ emojis: [String], size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(emojis.prefix(4).enumerated()), id: \.offset) { _, emoji in
                EmojiIconView(emoji: emoji.trimmingCharacters(in: .whitespacesAndNewlines), size: size)
            }
        }
    }
}

// MARK: - Rainbow Pig

private struct RainbowPigView: View {
    @State private var rotation: Double = 0

    private static let rainbowColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .red
    ]

    var body: some View {
        Text("🐷")
            .font(.system(size: 10))
            .frame(width: 20, height: 20)
            .background {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: Self.rainbowColors,
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        )
                    )
                    .opacity(0.2)
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: Self.rainbowColors,
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: 1.5
                    )
            }
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Dotted Lines

private struct DottedVLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

private struct DottedHLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
