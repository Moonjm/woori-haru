import SwiftUI

/// 비율 도넛. **조각이 셋을 넘으면 조각마다 이름을 붙일 것** — 각도만으로는 크기를 못 견준다.
/// 이 카드가 답하는 건 「대략 어떤 모양인가」라 이름으로 충분하다 — 정확한 비교가 필요한
/// 도넛이 생기면 그때는 값도 함께 적어야 한다.
///
/// 가운데를 비우고 그 자리에 총계를 적는 것은 부르는 쪽이 `overlay`로 얹는다.
struct DonutChart: View {
    struct Slice: Identifiable, Equatable {
        let label: String
        let value: Decimal
        let color: Color
        var id: String { label }
    }

    let slices: [Slice]
    var lineWidth: CGFloat = 18
    var size: CGFloat = 96

    /// 조각 사이 간격(전체 각도에 대한 비율). 각도 비율로 고정해 조각 수·크기가 달라도
    /// 간격의 「느낌」이 같다. 급속/완속(조각 둘)에서도 시험해 봤다 — 두 조각 다 여전히
    /// 넉넉해서 이상해 보이지 않아, 조각 둘·다섯 구분 없이 컴포넌트 전체에 넣었다.
    private static let sliceGap: CGFloat = 0.012

    private var total: Decimal { slices.reduce(0) { $0 + $1.value } }

    var body: some View {
        ZStack {
            // 총합이 0이면 조각을 그리지 않고 트랙만 남긴다 — 0으로 나누는 길을 막는다.
            Circle()
                .strokeBorder(VehicleTheme.trackFill, lineWidth: lineWidth)

            if total > 0 {
                ForEach(Array(offsets.enumerated()), id: \.offset) { _, item in
                    // 양끝을 절반씩 당겨 옆 조각과의 경계에 어두운 틈을 낸다. 조각이 간격보다
                    // 작으면(0건 버킷 등) start가 end를 넘지 않게 막아 사라지기만 하고 안 터진다.
                    let start = min(item.start + Self.sliceGap / 2, item.end)
                    let end = max(item.end - Self.sliceGap / 2, start)
                    Circle()
                        .trim(from: start, to: end)
                        .stroke(item.slice.color,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90)) // 12시에서 시작한다
                        .padding(lineWidth / 2)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var offsets: [(slice: Slice, start: CGFloat, end: CGFloat)] {
        var cursor: CGFloat = 0
        return slices.map { slice in
            let fraction = ChartScale.ratio(slice.value, max: total)
            let start = cursor
            cursor += fraction
            return (slice, start, min(1, cursor))
        }
    }
}

#Preview("도넛") {
    VStack(spacing: 16) {
        DonutChart(slices: [
            .init(label: "급속", value: 1840, color: VehicleTheme.accentBright),
            .init(label: "완속", value: 4620, color: VehicleTheme.accentMuted),
        ])
        // 총합 0 — 트랙만 남는지 본다.
        DonutChart(slices: [
            .init(label: "급속", value: 0, color: VehicleTheme.accentBright),
            .init(label: "완속", value: 0, color: VehicleTheme.accentMuted),
        ])
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
