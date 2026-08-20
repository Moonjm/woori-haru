import SwiftUI

/// 월별 선 하나. **y축이 0에서 시작한다** — 누적값과 추세를 그리는 자리라 0이 뜻을 갖는다.
/// 0에서 시작하지 않아야 하는 차트(열화 추세)는 `DegradationTrendChart`가 따로 그린다.
///
/// **기록이 없는 달에서 선을 끊는다.** 이어 버리면 없는 달을 지나간 선이 「그 달에도 이만큼」으로
/// 읽힌다. 끊긴 자리는 x 간격으로만 남는다.
struct MonthlyLineChart: View {
    let points: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var height: CGFloat = 110

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                plot(in: proxy.size)
            }
            .frame(height: height)

            HStack(spacing: ChartScale.slotSpacing) {
                ForEach(points) { point in
                    let isSelected = point.id == selectedID
                    Text(point.label)
                        .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                        .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 연속한 점들의 묶음. 기록이 없는 달에서 갈린다.
    private var segments: [[(index: Int, value: Decimal)]] {
        var result: [[(index: Int, value: Decimal)]] = []
        var current: [(index: Int, value: Decimal)] = []
        for (index, point) in points.enumerated() {
            if let value = point.value {
                current.append((index, value))
            } else if !current.isEmpty {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func plot(in size: CGSize) -> some View {
        let maxValue = ChartScale.maxValue(points)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                // 점이 하나뿐인 구간은 선이 안 되므로 점만 남는다(아래 ForEach가 그린다).
                Path { path in
                    for (order, item) in segment.enumerated() {
                        let point = position(index: item.index, value: item.value,
                                             maxValue: maxValue, in: size)
                        if order == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(VehicleTheme.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(points) { point in
                if let value = point.value {
                    let isSelected = point.id == selectedID
                    Circle()
                        .fill(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                        .frame(width: isSelected ? 9 : 5, height: isSelected ? 9 : 5)
                        .position(position(index: points.firstIndex(of: point) ?? 0,
                                           value: value, maxValue: maxValue, in: size))
                }
            }
        }
        .contentShape(.rect)
        // **그리는 식과 같은 식으로 받는다**(`ChartScale.slotIndex`) — 예전처럼
        // 끝맞춤(`width / (count - 1)`)으로 받으면 가까운 점 대신 옆 점이 잡혔다.
        .onTapGesture { location in
            guard !points.isEmpty else { return }
            let index = ChartScale.slotIndex(atX: location.x, count: points.count, width: size.width)
            onSelect(points[index].id)
        }
    }

    private func position(index: Int, value: Decimal, maxValue: Decimal, in size: CGSize) -> CGPoint {
        let x = ChartScale.slotCenterX(index: index, count: points.count, width: size.width)
        let ratio = ChartScale.ratio(value, max: maxValue)
        return CGPoint(x: x, y: size.height * (1 - ratio))
    }
}

#Preview("월별 선") {
    let values: [Decimal?] = [820, 910, nil, 1040, 980, 1120, 1310, 1180, 1240, 1090, 1350, 1280]
    let points = values.enumerated().map { index, value in
        ChartPoint(id: String(format: "2026-%02d", index + 1), label: "\(index + 1)", value: value)
    }
    return VStack(spacing: 12) {
        MonthlyLineChart(points: points, selectedID: "2026-07") { _ in }
        // 점이 하나뿐 — 가운데에 찍히는지 본다.
        MonthlyLineChart(points: [points[3]], selectedID: nil) { _ in }
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
