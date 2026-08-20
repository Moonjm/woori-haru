import SwiftUI

/// 월별 막대 한 줄. **카드가 아니라 막대만 그린다** — 제목·콜아웃·`GlassCard`는 부르는 쪽이 얹는다.
/// 원형이 카드까지 그리면 카드 구성이 조금씩 다른 일곱 자리에서 전부 예외가 생긴다.
///
/// **탭은 콜아웃만 바꾼다**(`onSelect`). 화면을 옮기거나 달을 바꾸지 않는다 —
/// `VehicleTrendChart`가 세운 규칙이고, 차트가 열넷으로 늘어도 같아야 읽을 수 있다.
struct MonthlyBarChart: View {
    let points: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var barHeight: CGFloat = 72

    var body: some View {
        let maxValue = ChartScale.maxValue(points)
        HStack(alignment: .bottom, spacing: ChartScale.slotSpacing(count: points.count)) {
            // **id는 offset이 아니라 점의 정체성이다** — offset으로 두면 데이터가 바뀔 때
            // SwiftUI가 엉뚱한 슬롯을 같은 뷰로 재사용해 탭·값이 옆으로 미끄러진다.
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                bar(point, index: index, maxValue: maxValue)
            }
        }
        .frame(height: barHeight + 24)
    }

    private func bar(_ point: ChartPoint, index: Int, maxValue: Decimal) -> some View {
        let isSelected = point.id == selectedID
        let ratio = ChartScale.ratio(point.value, max: maxValue)
        return VStack(spacing: 5) {
            Spacer(minLength: 0)
            // 기록이 없는 달도 자리를 지킨다 — 건너뛰면 계절 비교가 어긋난다.
            // 그 자리는 트랙 색이라 「0을 기록한 달」과 갈린다.
            RoundedRectangle(cornerRadius: 4)
                .fill(point.value == nil
                      ? AnyShapeStyle(VehicleTheme.trackFill)
                      : AnyShapeStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted))
                .frame(height: max(3, ratio * barHeight))
            // **감추지 않고 빈 글자로 둔다.** 라벨 뷰 자체를 없애면 남은 라벨들이
            // `HStack`에서 다시 채워져 자기 막대에서 옆으로 밀린다 — 자리는 지키고 글자만 지운다.
            Text(MonthLabel.shows(index: index, count: points.count) ? point.label : "")
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(point.id) }
    }
}

#Preview("월별 막대") {
    let values: [Decimal?] = [nil, 32700, 41200, 0, 38400, 52300, 47100, 39900, 44300, 51800, 36200, 42900]
    let points = values.enumerated().map { index, value in
        ChartPoint(id: String(format: "2026-%02d", index + 1), label: "\(index + 1)", value: value)
    }
    return VStack(spacing: 12) {
        MonthlyBarChart(points: points, selectedID: "2026-06") { _ in }
        // 값이 전부 0인 기간 — 0으로 나누지 않는지 본다.
        MonthlyBarChart(points: points.map { ChartPoint(id: $0.id, label: $0.label, value: 0) },
                        selectedID: nil) { _ in }
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
