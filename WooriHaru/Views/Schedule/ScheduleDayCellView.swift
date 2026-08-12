import SwiftUI

/// 스케줄표의 한 칸. 날짜 → 공휴일 → 근무 밴드 순으로 쌓는다.
///
/// **근무일에만 밴드를 그린다.** 휴무와 미등록은 둘 다 밴드가 없다 — 아빠는 그 달 전체를
/// 한 번에 등록하므로 미등록이면 달 전체가 비어 한눈에 보이고, 엄마는 패턴이라 늘 채워진다.
struct ScheduleDayCellView: View {
    let date: Date
    let isCurrentMonth: Bool
    let holidayNames: [String]
    let badges: [ScheduleViewModel.Badge]

    static let cellHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("\(date.day)")
                    .font(.system(size: 13))
                    .fontWeight(date.isToday && isCurrentMonth ? .bold : .regular)
                    .foregroundStyle(dateColor)
                Spacer()
            }

            if isCurrentMonth {
                // 공휴일 — 기본 달력과 같은 모양이라 두 화면이 같은 것으로 읽힌다.
                ForEach(holidayNames.prefix(1), id: \.self) { name in
                    Text(name.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(Color.red500)
                        .cornerRadius(2)
                }

                ForEach(badges, id: \.role) { badge in
                    Text(badge.slot.map(String.init) ?? " ")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(badge.role == .father ? Color.blue500 : Color.purple400)
                        .foregroundStyle(.white)
                        .cornerRadius(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .frame(height: Self.cellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var dateColor: Color {
        guard isCurrentMonth else { return .slate300 }
        if !holidayNames.isEmpty || date.weekday == 1 { return .red500 }
        if date.weekday == 7 { return .blue500 }
        return .slate900
    }

    private var accessibilityDescription: String {
        var parts = ["\(date.month)월 \(date.day)일"]
        parts += holidayNames
        for badge in badges {
            let who = badge.role == .father ? "아빠" : "엄마"
            parts.append(badge.slot.map { "\(who) \($0)번 근무" } ?? "\(who) 근무")
        }
        return parts.joined(separator: ", ")
    }
}
