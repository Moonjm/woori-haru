import SwiftUI

/// 곡선을 화면에 맞게 줄이는 계산. 뷰 밖에 두어 테스트가 닿게 한다.
enum ChargeCurveMath {
    /// 폰 차트 폭이 ~340pt라 이보다 많은 점은 어차피 픽셀에 겹친다.
    static let maxPoints = 150

    /// **버킷마다 최고점을 남긴다.** 균등 간격으로 솎으면 166kW 봉우리가 통째로 빠져
    /// 「최고 100kW였네」가 되는데, 곡선을 여는 이유가 바로 그 봉우리다.
    ///
    /// 골짜기를 잃는 대가는 받아들인다 — 충전 곡선에서 읽는 것은 「얼마나 들어갔나」이지
    /// 순간적인 흔들림이 아니다. **양 끝은 늘 남긴다** — 잘리면 소요 시간이 틀려 보인다.
    static func downsample(_ samples: [ChargeCurveSample], to limit: Int = maxPoints)
        -> [ChargeCurveSample] {
        guard samples.count > limit, limit > 2 else { return samples }
        let inner = limit - 2
        let body = samples.dropFirst().dropLast()
        let bucket = Double(body.count) / Double(inner)
        var picked: [ChargeCurveSample] = [samples[0]]
        for i in 0..<inner {
            let lo = body.startIndex + Int(Double(i) * bucket)
            let hi = min(body.startIndex + Int(Double(i + 1) * bucket), body.endIndex)
            guard lo < hi else { continue }
            // 이 버킷에서 가장 높은 점 하나. 전부 null이면 첫 점을 남긴다.
            let slice = body[lo..<hi]
            let best = slice.max { ($0.powerKw ?? -1) < ($1.powerKw ?? -1) }
            if let best { picked.append(best) }
        }
        picked.append(samples[samples.count - 1])
        return picked
    }

    /// 첫 샘플에서 뺀 경과 분. **서버는 KST 시각만 주고 경과 분을 내지 않는다.**
    ///
    /// `powerKw`가 null이거나 시각을 못 읽는 샘플은 **버린다** — 0으로 읽으면 곡선이
    /// 바닥까지 떨어졌다 올라온 것처럼 보인다. null은 「모른다」이지 「안 들어갔다」가 아니다.
    static func elapsedMinutes(_ samples: [ChargeCurveSample]) -> [(minutes: Double, powerKw: Int)] {
        let usable = samples.compactMap { s -> (Date, Int)? in
            guard let date = s.date, let kw = s.powerKw else { return nil }
            return (date, kw)
        }
        guard let first = usable.first?.0 else { return [] }
        return usable.map { (minutes: $0.0.timeIntervalSince(first) / 60, powerKw: $0.1) }
    }
}

/// 급속 충전 한 건의 kW 곡선. 손으로 그린다(Swift Charts를 들이지 않는 관례).
///
/// **x축은 경과 시간이다.** SoC 축이 테이퍼는 더 선명하지만, 곡선을 여는 이유가 대개
/// 「왜 오래 걸렸지」라 그 질문에 답하는 축이 시간이다 — 실측 사례로 어떤 세션은 앞 8분이
/// 63kW에 묶여 있었는데, SoC 축이면 그 구간이 왼쪽 끝에 짓눌려 사라진다.
struct ChargeCurveChart: View {
    let samples: [ChargeCurveSample]

    private static let height: CGFloat = 130

    /// (경과 분, kW) 쌍 하나. 다운샘플·경과분 계산은 아래서 딱 한 번만 돈다 —
    /// `body`·`header`·`peak`·`plot`·`duration`·`axis`가 나눠 쓴다.
    private typealias Point = (minutes: Double, powerKw: Int)

    var body: some View {
        let points: [Point] = ChargeCurveMath.elapsedMinutes(ChargeCurveMath.downsample(samples))
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header(points)
                if points.count < 2 {
                    // 점 하나로는 곡선이 아니다.
                    Text("이 충전엔 그릴 만한 곡선이 없어요")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                } else {
                    GeometryReader { proxy in plot(points, in: proxy.size) }
                        .frame(height: Self.height)
                    axis(points)
                }
            }
        }
    }

    private func peak(_ points: [Point]) -> Int { points.map(\.powerKw).max() ?? 0 }
    private func duration(_ points: [Point]) -> Double { points.last?.minutes ?? 0 }

    private func header(_ points: [Point]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("충전 곡선")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textSecondary)
            Spacer(minLength: 8)
            if points.count >= 2 {
                Text("최고 \(peak(points))kW")
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textPrimary)
            }
        }
    }

    private func plot(_ points: [Point], in size: CGSize) -> some View {
        let maxKw = max(1, peak(points))
        let span = max(1, duration(points))
        func at(_ p: Point) -> CGPoint {
            CGPoint(x: size.width * CGFloat(p.minutes / span),
                    y: size.height * (1 - CGFloat(Double(p.powerKw) / Double(maxKw))))
        }
        return ZStack(alignment: .topLeading) {
            // 채운 면 — 전력이 어떤 모양으로 들어갔는지 보여준다. 버킷마다 최고점을 남기므로
            // 넓이는 실제로 들어간 에너지보다 높게 보인다.
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height))
                for p in points { path.addLine(to: at(p)) }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [VehicleTheme.accent.opacity(0.45), VehicleTheme.accent.opacity(0.03)],
                                 startPoint: .top, endPoint: .bottom))
            Path { path in
                for (i, p) in points.enumerated() {
                    if i == 0 { path.move(to: at(p)) } else { path.addLine(to: at(p)) }
                }
            }
            .stroke(VehicleTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func axis(_ points: [Point]) -> some View {
        HStack {
            Text("0분")
            Spacer()
            Text("\(Int(duration(points).rounded()))분")
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(VehicleTheme.textTertiary)
    }
}

#Preview("곡선") {
    // 실측 세션 402의 모양 — 166kW로 시작해 33분간 66kW까지 테이퍼.
    let curve = (0...33).map { m -> ChargeCurveSample in
        let kw = Int(166.0 - Double(m) * 3.0)
        return ChargeCurveSample(at: String(format: "2025-09-10T13:%02d:00", m),
                                 powerKw: kw, batteryLevel: nil)
    }
    return VStack(spacing: 12) {
        ChargeCurveChart(samples: curve)
        ChargeCurveChart(samples: [])
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
