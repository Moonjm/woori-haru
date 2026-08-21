import SwiftUI

/// 최근 48시간 배터리 추이 — `/tesla/battery-window`. 손으로 그린 선이다
/// (`DegradationTrendChart`와 같은 관례로, Swift Charts를 들이지 않는다).
///
/// y축을 0에서 시작하지 않는다. SOC 62%와 20%의 차이를 보여야 하는 자리라, 0부터
/// 그리면 변화가 선 굵기에 묻힌다. `MonthlyLineChart`(y축이 0에서 시작하는 것이 명시된
/// 원형)는 여기 쓰지 않는다.
struct BatteryWindowCard: View {
    let window: BatteryWindowResponse

    private static let chartHeight: CGFloat = 120

    private var windowStart: Date? { VehicleFormat.parseKST(window.from) }
    private var windowEnd: Date? { VehicleFormat.parseKST(window.to) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                callout

                if let start = windowStart, let end = windowEnd, end > start, !window.samples.isEmpty {
                    GeometryReader { proxy in
                        plot(in: proxy.size, from: start, span: end.timeIntervalSince(start))
                    }
                    .frame(height: Self.chartHeight)
                } else {
                    Text("최근 \(window.hours)시간 기록이 없어요")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                }

                footer
            }
        }
    }

    // MARK: - 머리글

    private var header: some View {
        HStack(spacing: 6) {
            Text("배터리 추이")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textSecondary)
            Spacer(minLength: 0)
            // 범위 칩. 아래 요약 줄이 「최근 7일」을 말하므로, 이 칩이 실제로 그리는
            // 구간(`hours`)을 밝혀 둬야 둘이 서로 다른 기간을 말한다는 것이 헷갈리지 않는다.
            Text("최근 \(window.hours)시간")
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textTertiary)
        }
    }

    @ViewBuilder private var callout: some View {
        if let latest = window.samples.last {
            HStack(spacing: 6) {
                Text("\(latest.batteryLevel)%")
                    .font(.title3)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.accent)
                if let usable = latest.usableBatteryLevel {
                    Text("사용 가능 \(usable)%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
    }

    // MARK: - 그리기

    private func plot(in size: CGSize, from start: Date, span: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            // 충전 구간을 선 아래 다른 색으로 깐다. 이미 범위 경계로 잘려서 온다 —
            // 앱이 다시 자르지 않는다.
            ForEach(Array(window.charges.enumerated()), id: \.offset) { _, segment in
                if let rect = chargeRect(segment, in: size, from: start, span: span) {
                    Rectangle()
                        .fill(VehicleTheme.accentGlow.opacity(0.22))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }

            // 주 계열 — `batteryLevel`. 절대 끊지 않는다. `usableBatteryLevel`과 달리
            // 거의 모든 표본에 값이 있다.
            Path { path in
                let points = socPoints(in: size, from: start, span: span)
                for (index, point) in points.enumerated() {
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(VehicleTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // 보조 계열 — `usableBatteryLevel`. 실측 3%만 채워져 있어 선으로 이으면
            // 거의 다 끊긴다 — 있을 때만 점을 찍는다.
            ForEach(window.samples.filter { $0.usableBatteryLevel != nil }) { sample in
                if let point = usablePosition(sample, in: size, from: start, span: span) {
                    Circle()
                        .fill(VehicleTheme.textSecondary)
                        .frame(width: 4, height: 4)
                        .position(point)
                }
            }
        }
    }

    /// SOC 선이 지날 점들. 시각을 못 읽는 표본은 건너뛴다 — 개별 `guard`로 걸러
    /// `move`·`addLine`이 어긋나지 않게 먼저 배열로 모은다.
    private func socPoints(in size: CGSize, from start: Date, span: TimeInterval) -> [CGPoint] {
        window.samples.compactMap { sample in
            guard let date = sample.date, let fraction = fraction(for: date, from: start, span: span) else {
                return nil
            }
            return CGPoint(x: size.width * fraction, y: y(for: Decimal(sample.batteryLevel), in: size))
        }
    }

    private func usablePosition(_ sample: BatterySample, in size: CGSize, from start: Date,
                                span: TimeInterval) -> CGPoint? {
        guard let usable = sample.usableBatteryLevel, let date = sample.date,
              let fraction = fraction(for: date, from: start, span: span) else { return nil }
        return CGPoint(x: size.width * fraction, y: y(for: Decimal(usable), in: size))
    }

    /// 충전 구간 하나를 채울 사각형. 시작·끝을 못 읽거나 뒤집혀 있으면 그리지 않는다.
    private func chargeRect(_ segment: TimeSegment, in size: CGSize, from start: Date,
                            span: TimeInterval) -> CGRect? {
        guard let segStart = VehicleFormat.parseKST(segment.from),
              let segEnd = VehicleFormat.parseKST(segment.to),
              let fxStart = fraction(for: segStart, from: start, span: span),
              let fxEnd = fraction(for: segEnd, from: start, span: span),
              fxEnd > fxStart else { return nil }
        let x0 = size.width * fxStart
        let x1 = size.width * fxEnd
        return CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
    }

    /// 시각을 범위 안의 비율로. 범위 밖은 자른다 — 서버가 이미 자르지만, 계약이
    /// 깨져도 화면이 무너지지 않게 한 번 더 막는다(`StateTimelineMath.clip`과 같은 이유).
    private func fraction(for date: Date, from start: Date, span: TimeInterval) -> CGFloat? {
        guard span > 0 else { return nil }
        let value = date.timeIntervalSince(start) / span
        return CGFloat(min(1, max(0, value)))
    }

    /// y축 범위 — 이번 창의 SOC·사용 가능 표본을 모두 담고 위아래로 조금 띄운다.
    /// 0이나 100으로 고정하지 않는다 — 그러면 20~62% 같은 좁은 구간이 화면 가운데
    /// 띠 하나로 뭉개진다. 다만 퍼센트 값이라 범위를 0...100 밖으로는 내보내지 않는다.
    private var domain: (low: Decimal, high: Decimal) {
        let levels = window.samples.map { Decimal($0.batteryLevel) }
            + window.samples.compactMap { sample in sample.usableBatteryLevel.map { Decimal($0) } }
        let low = levels.min() ?? 0
        let high = levels.max() ?? 100
        let padding = max(2, (high - low) / 10)
        return (max(0, low - padding), min(100, high + padding))
    }

    private func y(for value: Decimal, in size: CGSize) -> CGFloat {
        let (low, high) = domain
        let span = max(1, high - low)
        let ratio = CGFloat(truncating: ((value - low) / span) as NSDecimalNumber)
        return size.height * (1 - ratio)
    }

    // MARK: - 아래 줄

    /// 「최근 7일 대기 소모 0.04km/시간」. `hours`와 다른 기간(최근 7일)이라 문구에
    /// 박아 둔다 — 위 범위 칩과 다른 기간임을 숨기지 않는다.
    ///
    /// `VehicleMath.drainPerHour`가 표본이 없을 때 `nil`을 내므로 그 경우 줄 자체를
    /// 지운다 — 0km/시간은 「안 샜다」는 거짓말이다.
    @ViewBuilder private var footer: some View {
        if let drain = VehicleMath.drainPerHour(window.parkDrain) {
            Text("최근 7일 대기 소모 \(VehicleFormat.drainRate(drain))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textTertiary)
                .lineLimit(1)
        }
    }
}

#Preview("배터리 추이") {
    func iso(_ hoursAgo: Int) -> String {
        let date = Date(timeIntervalSinceNow: -Double(hoursAgo) * 3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
    let samples = stride(from: 48, through: 0, by: -1).map { hoursAgo -> BatterySample in
        let level = 62 - Int(Double(48 - hoursAgo) * 0.6)
        return BatterySample(at: iso(hoursAgo), batteryLevel: max(20, level),
                             usableBatteryLevel: hoursAgo % 11 == 0 ? max(19, level - 1) : nil)
    }
    let window = BatteryWindowResponse(
        hours: 48, from: iso(48), to: iso(0), samples: samples,
        charges: [TimeSegment(from: iso(30), to: iso(27))],
        parkDrain: ParkDrain(ratedKm: 4.2, hours: 96.4, samples: 6))
    let empty = BatteryWindowResponse(hours: 48, from: iso(48), to: iso(0), samples: [],
                                      charges: [], parkDrain: ParkDrain(ratedKm: 0, hours: 0, samples: 0))
    return VStack(spacing: 12) {
        BatteryWindowCard(window: window)
        BatteryWindowCard(window: empty)
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
