import SwiftUI

/// 온도별 전비 — 가로 막대. 1단계와 같이 손으로 그린다(Swift Charts를 들이지 않는 관례).
///
/// **막대 길이는 전비에 비례하고, 0에서 시작하지 않는다.** 6.0과 7.6은 26% 차이인데
/// 0부터 그리면 둘 다 긴 막대가 되어 차이가 안 보인다. 가장 낮은 버킷을 짧게 남기고
/// 나머지를 그 위에 얹는다.
struct TemperatureEfficiencyCard: View {
    let rows: [VehicleStatsViewModel.TemperatureRow]
    /// **거리 카드와 다른 수다** — 주행가능거리 소모가 0 이하인 주행이 여기선 빠진다.
    let driveCount: Int

    /// 막대가 아무리 짧아도 이만큼은 남긴다 — 0이면 라벨만 뜬 빈 줄로 보인다.
    private static let minimumRatio: CGFloat = 0.12

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header("온도별 전비", "\(driveCount)회 기준")
                ForEach(rows) { row in
                    bar(row)
                }
                Text("주행가능거리가 준 만큼으로 환산한 값이라 실제 충전량과는 조금 달라요.")
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private var maxValue: Decimal { rows.compactMap(\.kmPerKwh).max() ?? 0 }
    private var minValue: Decimal { rows.compactMap(\.kmPerKwh).min() ?? 0 }

    private func bar(_ row: VehicleStatsViewModel.TemperatureRow) -> some View {
        // 값이 없으면 비율도 없다(nil). 최소 폭(minimumRatio)을 값 없는 버킷에도 적용하면
        // 「—」 옆에 짧은 막대가 남아 「조금 탔다」로 읽힌다 — 그래서 최소 폭은 값이
        // 있는 행에만 건다.
        let ratio: CGFloat? = {
            guard let value = row.kmPerKwh else { return nil }
            guard maxValue > minValue else { return 1 }
            let span = maxValue - minValue
            let scaled = (value - minValue) / span
            let raw = CGFloat(truncating: scaled as NSDecimalNumber)
            return Self.minimumRatio + raw * (1 - Self.minimumRatio)
        }()
        // 가장 좋은 버킷을 진하게 — 「언제가 제일 멀리 가나」가 이 카드의 질문이다.
        let isBest = row.kmPerKwh != nil && row.kmPerKwh == maxValue
        return HStack(spacing: 8) {
            Text(row.bucket.label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
                .frame(width: 54, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(isBest ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                    // 값이 없는 행은 ratio가 nil이라 폭 0 — 막대 자체가 보이지 않는다.
                    .frame(width: ratio.map { max(3, proxy.size.width * $0) } ?? 0)
            }
            .frame(height: 14)
            Text(VehicleFormat.efficiency(row.kmPerKwh))
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
                .frame(width: 74, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.bucket.label) \(VehicleFormat.efficiency(row.kmPerKwh)), \(DriveFormat.count(row.bucket.driveCount))")
    }
}

/// 한 번에 얼마나 — 건수 분포. 지시선 라벨 도넛으로 그린다.
///
/// **범례가 없다.** 조각마다 바깥으로 지시선을 뻗어 구간 이름을 적는다 — 이 카드가
/// 답하는 건 「짧은 주행이 대부분인가」라는 대략의 모양이라 이름으로 충분하다(`DonutChart` doc).
/// 배치 계산(좌우 갈림·겹침 방지)은 `DonutLeaderLayout`이 순수 함수로 낸다.
///
/// **0인 버킷은 화면에서 빠진다** — 범례가 없으니 조각도 지시선도 안 남는다(각도 0).
/// 접근성 라벨에는 남긴다.
struct DistanceDistributionCard: View {
    let slices: [VehicleStatsViewModel.DistanceSlice]
    /// **전비 카드와 다른 수다.** 여기선 걸러 내는 주행이 없다.
    let driveCount: Int

    /// 새 색을 안 쓴다 — 강조색 하나를 다섯 단계 투명도로 나눠 조각을 가른다.
    private static let colors: [Color] = [
        VehicleTheme.accent,
        VehicleTheme.accent.opacity(0.75),
        VehicleTheme.accent.opacity(0.55),
        VehicleTheme.accent.opacity(0.38),
        VehicleTheme.accent.opacity(0.24),
    ]

    private static let donutSize: CGFloat = 128
    private static let chartHeight: CGFloat = 220
    private static let edgeRadius = donutSize / 2 + 3
    private static let bendX = donutSize / 2 + 22
    private static let labelX = donutSize / 2 + 32

    private func color(at index: Int) -> Color { Self.colors[index % Self.colors.count] }

    private var donutSlices: [DonutChart.Slice] {
        slices.enumerated().map { index, slice in
            DonutChart.Slice(label: slice.bucket.label,
                             value: Decimal(slice.bucket.driveCount),
                             color: color(at: index))
        }
    }

    /// 0건 버킷은 뺀다 — 각도가 0이라 지시선을 그릴 가장자리 점이 없다.
    private var visibleSlices: [(index: Int, slice: VehicleStatsViewModel.DistanceSlice)] {
        slices.enumerated().filter { $0.element.bucket.driveCount > 0 }
            .map { ($0.offset, $0.element) }
    }

    private struct LeaderItem: Identifiable {
        let label: String
        let color: Color
        let placement: DonutLeaderLayout.Placement
        var id: String { placement.id }
    }

    /// `DonutLeaderLayout.place`가 `visibleSlices`와 같은 개수·순서로 돌려주니 그대로 짝짓는다.
    private var leaderItems: [LeaderItem] {
        let leaderSlices = visibleSlices.map { _, slice in
            DonutLeaderLayout.Slice(label: slice.bucket.label,
                                     fraction: CGFloat(truncating: (slice.percent ?? 0) as NSDecimalNumber))
        }
        let placements = DonutLeaderLayout.place(leaderSlices, radius: Self.edgeRadius,
                                                  bendX: Self.bendX, labelX: Self.labelX)
        return zip(visibleSlices, placements).map { item, placement in
            LeaderItem(label: item.slice.bucket.label, color: color(at: item.index), placement: placement)
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("한 번에 얼마나")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)
                leaderDonut
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
            }
        }
    }

    private var leaderDonut: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                DonutChart(slices: donutSlices, size: Self.donutSize)
                    .position(center)
                    // 지시선이 각각을 말하니, 가운데는 전체를 말한다.
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(driveCount)")
                                .font(.subheadline)
                                .fontWeight(.heavy)
                                .monospacedDigit()
                                .foregroundStyle(VehicleTheme.textPrimary)
                            Text("회")
                                .font(.caption2)
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        .position(center)
                    }

                Path { path in
                    for item in leaderItems {
                        path.move(to: point(item.placement.edgePoint, from: center))
                        path.addLine(to: point(item.placement.bendPoint, from: center))
                        path.addLine(to: point(item.placement.labelPoint, from: center))
                    }
                }
                .stroke(VehicleTheme.textTertiary, lineWidth: 1)

                ForEach(leaderItems) { item in
                    leaderLabel(item.label, color: item.color, placement: item.placement, center: center)
                }
            }
        }
        .frame(height: Self.chartHeight)
    }

    private func point(_ offset: CGPoint, from center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }

    private func leaderLabel(_ label: String, color: Color, placement: DonutLeaderLayout.Placement,
                              center: CGPoint) -> some View {
        // **`overlay`가 `position`보다 먼저다.** 뒤에 붙이면 `position`이 가용 공간 전체로
        // 펼쳐진 뷰에 정렬돼, 라벨 다섯이 전부 카드 좌우 끝·세로 가운데로 몰린다.
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: placement.side == .right ? .leading : .trailing) {
                HStack(spacing: 4) {
                    if placement.side == .left {
                        Text(label).font(.caption2).foregroundStyle(VehicleTheme.textSecondary)
                        Circle().fill(color).frame(width: 6, height: 6)
                    } else {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(label).font(.caption2).foregroundStyle(VehicleTheme.textSecondary)
                    }
                }
                .fixedSize()
            }
            .position(point(placement.labelPoint, from: center))
    }

    /// 화면에는 이름만 남으니, 퍼센트·건수는 이 요약 하나로만 전해진다 — 0건 버킷도 담는다.
    private var accessibilitySummary: String {
        let rows = slices.map { slice in
            "\(slice.bucket.label) \(ChargeFormat.percent(slice.percent)), \(DriveFormat.count(slice.bucket.driveCount))"
        }
        return (["한 번에 얼마나, 총 \(DriveFormat.count(driveCount))"] + rows).joined(separator: ". ")
    }
}

/// 두 카드가 같은 머리 모양을 쓴다 — 제목 왼쪽, 모수 오른쪽.
/// **모수를 카드마다 따로 적는다.** 두 카드의 총합이 다르기 때문이다.
private func header(_ title: String, _ trailing: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(VehicleTheme.textSecondary)
        Spacer(minLength: 8)
        Text(trailing)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(VehicleTheme.textTertiary)
    }
}

#Preview("버킷 카드") {
    let buckets = [
        // **`Decimal`에 부동소수 리터럴을 쓰지 않는다** — Double을 거쳐 값이 틀어진다.
        TemperatureBucket(fromC: nil, toC: 0, driveCount: 82,
                          distanceKm: Decimal(string: "2424.8")!,
                          ratedRangeUsedKm: Decimal(string: "2939.2")!),
        TemperatureBucket(fromC: 0, toC: 10, driveCount: 229,
                          distanceKm: Decimal(string: "6507.3")!,
                          ratedRangeUsedKm: Decimal(string: "7097.1")!),
        TemperatureBucket(fromC: 10, toC: 20, driveCount: 244,
                          distanceKm: Decimal(string: "5990.4")!,
                          ratedRangeUsedKm: Decimal(string: "5723.9")!),
        TemperatureBucket(fromC: 20, toC: 30, driveCount: 266,
                          distanceKm: Decimal(string: "5748.4")!,
                          ratedRangeUsedKm: Decimal(string: "5798.5")!),
        TemperatureBucket(fromC: 30, toC: nil, driveCount: 0,
                          distanceKm: 0, ratedRangeUsedKm: 0),
    ]
    let efficiency = Decimal(string: "0.1367")!
    let rows = buckets.map { bucket in
        VehicleStatsViewModel.TemperatureRow(
            bucket: bucket,
            kmPerKwh: VehicleMath.kmPerKwh(distanceKm: bucket.distanceKm,
                                           ratedRangeUsedKm: bucket.ratedRangeUsedKm,
                                           efficiencyKwhPerKm: efficiency)
        )
    }
    let distanceBuckets = [
        DistanceBucket(fromKm: 0, toKm: 5, driveCount: 620, distanceKm: 1802),
        DistanceBucket(fromKm: 5, toKm: 20, driveCount: 210, distanceKm: 2400),
        DistanceBucket(fromKm: 20, toKm: 50, driveCount: 90, distanceKm: 2700),
        DistanceBucket(fromKm: 50, toKm: 100, driveCount: 36, distanceKm: 2500),
        DistanceBucket(fromKm: 100, toKm: nil, driveCount: 3, distanceKm: 412),
    ]
    let distanceTotal = distanceBuckets.reduce(0) { $0 + $1.driveCount }
    let distanceSlices = distanceBuckets.map { bucket in
        VehicleStatsViewModel.DistanceSlice(
            bucket: bucket,
            percent: VehicleMath.ratio(Decimal(bucket.driveCount), Decimal(distanceTotal)))
    }
    return ScrollView {
        VStack(spacing: 12) {
            TemperatureEfficiencyCard(rows: rows, driveCount: 939)
            DistanceDistributionCard(slices: distanceSlices, driveCount: distanceTotal)
        }
        .padding(16)
    }
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
