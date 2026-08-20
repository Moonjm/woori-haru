import SwiftUI

/// 막대 + 선 이중축. **두 축의 눈금을 화면에 적지 않는다** — 단위가 다른 두 계열을 겹치는
/// 자리라 눈금 둘을 다 적으면 카드가 숫자로 덮인다. 정확한 값은 콜아웃이 말한다.
///
/// `bars`와 `line`은 **같은 순서·같은 id**여야 한다. 부르는 쪽이 같은 배열에서 만든다.
struct MonthlyBarLineChart: View {
    let bars: [ChartPoint]
    let line: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var height: CGFloat = 96

    var body: some View {
        let barMax = ChartScale.maxValue(bars)
        let lineMax = ChartScale.maxValue(line)
        VStack(spacing: 5) {
            // **탭 폭을 GeometryReader에서 받는다.** 화면 폭(`UIScreen`)으로 나누면
            // 카드 안쪽 여백만큼 어긋나 오른쪽 끝 달이 안 잡힌다.
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(bars) { point in
                            let isSelected = point.id == selectedID
                            RoundedRectangle(cornerRadius: 4)
                                .fill(point.value == nil
                                      ? AnyShapeStyle(VehicleTheme.trackFill)
                                      : AnyShapeStyle(isSelected
                                                      ? VehicleTheme.accentBright : VehicleTheme.accentMuted))
                                .frame(height: max(3, ChartScale.ratio(point.value, max: barMax) * height))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: height, alignment: .bottom)

                    linePath(in: proxy.size, maxValue: lineMax)
                }
                .contentShape(.rect)
                .onTapGesture { location in
                    guard !bars.isEmpty else { return }
                    let slot = proxy.size.width / CGFloat(bars.count)
                    let index = min(bars.count - 1, max(0, Int(location.x / max(1, slot))))
                    onSelect(bars[index].id)
                }
            }
            .frame(height: height)

            HStack(spacing: 5) {
                ForEach(bars) { point in
                    let isSelected = point.id == selectedID
                    Text(point.label)
                        .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                        .foregroundStyle(isSelected
                                         ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 선은 **기록이 있는 점만 잇는다.** 막대와 달리 자리를 비워 두지 않고 건너뛴다 —
    /// 두 계열 중 하나만 빈 달이 있을 수 있는데, 선을 0으로 떨어뜨리면 없는 값이 있는 값이 된다.
    private func linePath(in size: CGSize, maxValue: Decimal) -> some View {
        Path { path in
            var started = false
            for (index, point) in line.enumerated() {
                guard let value = point.value else { started = false; continue }
                let x = line.count <= 1
                    ? size.width / 2
                    : size.width * CGFloat(index) / CGFloat(line.count - 1)
                let y = size.height * (1 - ChartScale.ratio(value, max: maxValue))
                let cgPoint = CGPoint(x: x, y: y)
                if started { path.addLine(to: cgPoint) } else { path.move(to: cgPoint); started = true }
            }
        }
        .stroke(VehicleTheme.warning,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

#Preview("이중축") {
    let kwh: [Decimal?] = [120, 142, nil, 165, 151, 138, 172, 160, 149, 155, 168, 158]
    let cost: [Decimal?] = [26000, 31000, nil, 35800, 32700, 29900, 38400, 34100, 32000, 33500, 36900, 34700]
    let bars = kwh.enumerated().map { i, v in
        ChartPoint(id: String(format: "2026-%02d", i + 1), label: "\(i + 1)", value: v)
    }
    let line = cost.enumerated().map { i, v in
        ChartPoint(id: String(format: "2026-%02d", i + 1), label: "\(i + 1)", value: v)
    }
    return MonthlyBarLineChart(bars: bars, line: line, selectedID: "2026-07") { _ in }
        .padding(16)
        .background(VehicleTheme.background)
        .environment(\.vehicleDark, true)
}
