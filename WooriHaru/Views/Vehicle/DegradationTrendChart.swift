import SwiftUI

/// 열화 추이 — 월별 만충 환산 주행거리. 손으로 그린 선이다(Swift Charts를 들이지 않는 관례).
///
/// **y축을 0에서 시작하지 않는다.** 0부터 그리면 몇 %의 변화가 선 굵기에 묻힌다. 대신
/// 신차 기준선 568km를 점선으로 함께 그려, 무엇과 견주는 값인지 화면 안에 남긴다.
///
/// **점 탭은 콜아웃만 바꾼다.** 점 하나는 손가락보다 작아 개별 히트 영역을 두지 않고,
/// 차트 전체가 탭을 받아 x가 가장 가까운 달을 고른다.
struct DegradationTrendChart: View {
    /// **빠진 달에서 갈린 선분들.** 한 배열 안은 연속한 달이다.
    let segments: [[BatteryHealthSample]]
    let selectedKey: String?
    let onSelect: (String) -> Void

    private static let chartHeight: CGFloat = 120

    private var samples: [BatteryHealthSample] { segments.flatMap { $0 } }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("열화 추이")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                callout

                GeometryReader { proxy in
                    plot(in: proxy.size)
                }
                .frame(height: Self.chartHeight)

                footer
            }
        }
    }

    // MARK: - 콜아웃

    private var selected: BatteryHealthSample? {
        samples.first { $0.yearMonth == selectedKey } ?? samples.last
    }

    @ViewBuilder private var callout: some View {
        if let selected {
            let remaining = VehicleMath.remainingPercent(
                current: selected.fullRangeKm, baseline: VehicleBaseline.newRangeKm)
            HStack(spacing: 6) {
                Text(selected.shortLabel)
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(Color.blue600)
                Text(VehicleFormat.distance(selected.fullRangeKm))
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text("잔존 \(VehicleFormat.percent(remaining))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.slate500)
                // 표본 수는 그 달 값이 얼마나 단단한지다 — 한 건짜리 달은 튈 수 있다.
                Text("표본 \(selected.sampleCount)건")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.slate400)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .animation(.snappy, value: selected.yearMonth)
        }
    }

    // MARK: - 그리기

    private func plot(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // 신차 기준선. 점선이라 표본 선과 헷갈리지 않는다.
            Path { path in
                let y = baselineY(in: size)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(Color.slate300, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Path { path in
                    for (index, sample) in segment.enumerated() {
                        let point = position(sample, in: size)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Color.blue500, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(samples) { sample in
                let isSelected = sample.yearMonth == selected?.yearMonth
                Circle()
                    .fill(isSelected ? Color.blue600 : Color.blue300)
                    .frame(width: isSelected ? 9 : 5, height: isSelected ? 9 : 5)
                    .position(position(sample, in: size))
            }
        }
        .contentShape(.rect)
        .onTapGesture { location in
            guard let nearest = nearest(to: location, in: size) else { return }
            onSelect(nearest.yearMonth)
        }
    }

    /// y축 범위 — 표본과 신차 기준선을 모두 담고 위아래로 조금 띄운다.
    /// **0에서 시작하지 않으므로 기준선이 범위 안에 반드시 들어가야 한다** —
    /// 빠지면 점선이 차트 밖으로 나가 비교 대상이 화면에서 사라진다.
    private var domain: (low: Decimal, high: Decimal) {
        let values = samples.map(\.fullRangeKm) + [VehicleBaseline.newRangeKm]
        let low = values.min() ?? 0
        let high = values.max() ?? VehicleBaseline.newRangeKm
        let padding = max(5, (high - low) / 10)
        return (low - padding, high + padding)
    }

    /// x는 **달 번호에 비례한다.** 배열 순서로 놓으면 표본이 빠진 구간이 좁아져,
    /// 선을 끊어 둔 뜻이 사라진다.
    private func position(_ sample: BatteryHealthSample, in size: CGSize) -> CGPoint {
        let ordinals = samples.map(\.monthOrdinal)
        let first = ordinals.min() ?? 0
        let span = (ordinals.max() ?? first) - first
        // 표본이 한 달치뿐이면 왼쪽 끝에 붙는 대신 가운데에 찍는다.
        let x = span == 0 ? size.width / 2
                          : size.width * CGFloat(sample.monthOrdinal - first) / CGFloat(span)
        return CGPoint(x: x, y: y(for: sample.fullRangeKm, in: size))
    }

    private func baselineY(in size: CGSize) -> CGFloat {
        y(for: VehicleBaseline.newRangeKm, in: size)
    }

    private func y(for value: Decimal, in size: CGSize) -> CGFloat {
        let (low, high) = domain
        let span = max(1, high - low)
        let ratio = CGFloat(truncating: ((value - low) / span) as NSDecimalNumber)
        return size.height * (1 - ratio)
    }

    private func nearest(to location: CGPoint, in size: CGSize) -> BatteryHealthSample? {
        samples.min {
            abs(position($0, in: size).x - location.x) < abs(position($1, in: size).x - location.x)
        }
    }

    // MARK: - 아래 줄

    private var footer: some View {
        HStack(spacing: 8) {
            Text("┈ 신차 \(VehicleFormat.distance(VehicleBaseline.newRangeKm))")
                .foregroundStyle(Color.slate400)
            Spacer(minLength: 0)
            if samples.count > 1, let first = samples.first, let last = samples.last {
                Text("\(first.shortLabel) → \(last.shortLabel)")
                    .foregroundStyle(Color.slate400)
            } else {
                // 점 하나로는 추이가 아니다. 그 사실을 화면이 말해 준다.
                Text("값이 쌓이면 추이가 보여요")
                    .foregroundStyle(Color.slate500)
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
    }
}

#Preview("추이") {
    let ranges = ["556.0", "552.4", "548.1", "544.0", "541.2", "536.8",
                  "534.0", "530.5", "528.0", "527.1", "525.3"]
    let all = ranges.enumerated().map { index, value in
        BatteryHealthSample(yearMonth: String(format: "2025-%02d", index + 1),
                            fullRangeKm: Decimal(string: value)!, capacityKwh: nil,
                            sampleCount: index % 3 + 1, capacitySampleCount: 0)
    }
    return VStack(spacing: 12) {
        // 연속한 달
        DegradationTrendChart(segments: [all], selectedKey: nil) { _ in }
        // 가운데가 빠져 선이 갈린 경우
        DegradationTrendChart(segments: [Array(all.prefix(4)), Array(all.suffix(5))],
                              selectedKey: nil) { _ in }
        // 표본이 한 달치뿐
        DegradationTrendChart(segments: [[all[10]]], selectedKey: nil) { _ in }
    }
    .padding(16)
    .background(Color.slate50)
}
