import SwiftUI

/// 스케줄표의 한 칸. 날짜 아래로 근무 밴드가 쌓인다.
///
/// **근무일에만 밴드를 그린다.** 휴무와 미등록은 둘 다 밴드가 없다 — 아빠는 그 달 전체를
/// 한 번에 등록하므로 미등록이면 달 전체가 비어 한눈에 보이고, 엄마는 패턴이라 늘 채워진다.
///
/// **공휴일은 이름을 쓰지 않고 날짜만 빨갛게 한다.** 이 화면은 누가 언제 일하는지를 보는
/// 자리라, 공휴일 이름표가 밴드와 자리를 다투면 정작 볼 것이 밀린다.
struct ScheduleDayCellView: View {
    let date: Date
    /// `MonthGridBuilder`가 주입 달력으로 이미 계산해 둔 값. `date.day`(기기 달력,
    /// `Date+Extensions`)를 다시 쓰면 기기 달력이 그레고리력이 아닐 때 밴드 위치(고정
    /// 포맷터 `dateString` 기준이라 맞다)와 숫자가 어긋난다.
    let day: Int
    let month: Int
    let isCurrentMonth: Bool
    /// **뷰모델이 판단해 넘겨준다.** 여기서 `date.isToday`로 직접 보면, 날이 바뀌어도
    /// 이 칸의 입력값은 그대로라 SwiftUI가 다시 그리지 않아 어제가 계속 굵게 남는다.
    let isToday: Bool
    let holidayNames: [String]
    let badges: [ScheduleViewModel.Badge]
    /// 아빠와 엄마가 둘 다 쉬는 날. **미등록은 여기 들어오지 않는다**(뷰모델이 가린다).
    let isBothOff: Bool

    static let cellHeight: CGFloat = 76

    /// 근무 밴드 한 줄의 높이. 역할마다 한 줄씩, 근무가 없어도 자리를 남긴다.
    private static let badgeRowHeight: CGFloat = 17

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("\(day)")
                    .font(.system(size: 13))
                    .fontWeight(isToday && isCurrentMonth ? .bold : .regular)
                    .foregroundStyle(dateColor)
                Spacer()
            }

            if isCurrentMonth {
                // **역할마다 자리가 고정이다.** 위가 엄마, 아래가 아빠. 근무가 없는 쪽은
                // 비워 두고 다른 쪽을 끌어올리지 않는다 — 올리면 같은 색이 날마다 다른
                // 줄에 놓여, 한 주를 훑을 때 누구 근무인지 색과 위치가 따로 논다.
                badgeRow(for: .mother)
                badgeRow(for: .father)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .frame(height: Self.cellHeight)
        // **둘 다 쉬는 날은 칸을 옅게 칠한다.** 밴드 자리를 뺏지 않아 정렬이 그대로고,
        // 한 달을 훑을 때 덩어리로 보인다. 그런 날은 밴드가 없어 색이 섞이지도 않는다.
        .background(isBothOff ? Color.green100 : .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// 아빠는 파랑, 엄마는 분홍. 순번이 있으면 숫자를, 없으면 색만 칠한다.
    @ViewBuilder
    private func badgeRow(for role: DispatchRole) -> some View {
        if let badge = badges.first(where: { $0.role == role }) {
            Text(badge.slot.map(String.init) ?? " ")
                .font(.system(size: 10))
                .fontWeight(.bold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.badgeRowHeight)
                .background(role == .father ? Color.blue500 : Color.pink500)
                .foregroundStyle(.white)
                .cornerRadius(2)
        } else {
            Color.clear.frame(height: Self.badgeRowHeight)
        }
    }

    private var dateColor: Color {
        guard isCurrentMonth else { return .slate300 }
        if !holidayNames.isEmpty || date.weekday == 1 { return .red500 }
        if date.weekday == 7 { return .blue500 }
        return .slate900
    }

    private var accessibilityDescription: String {
        var parts = ["\(month)월 \(day)일"]
        parts += holidayNames
        if isBothOff { parts.append("둘 다 휴무") }
        // 화면과 같은 순서로 읽는다 — 엄마가 위, 아빠가 아래다.
        for role in [DispatchRole.mother, .father] {
            guard let badge = badges.first(where: { $0.role == role }) else { continue }
            let who = role == .father ? "아빠" : "엄마"
            parts.append(badge.slot.map { "\(who) \($0)번 근무" } ?? "\(who) 근무")
        }
        return parts.joined(separator: ", ")
    }
}
