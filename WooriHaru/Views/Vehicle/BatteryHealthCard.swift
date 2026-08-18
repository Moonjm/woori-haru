import SwiftUI

/// 배터리 건강 — **화면에서 유일한 진한 패널이다.**
///
/// 앱 전체를 다크로 뒤집지 않는다. 지금 유리 토큰은 밝은 배경을 전제로 만들어졌고,
/// 우리하루의 다른 미니앱과 결도 어긋난다. 대신 화면에서 가장 중요한 값 하나만 어둡게 깔아
/// 눈이 먼저 가게 한다.
///
/// **경고 문구를 넣지 않는다** — 열화는 고장이 아니다. 잔존율이 낮아지면 링 색만 바뀐다.
struct BatteryHealthCard: View {
    let remainingPercent: Decimal?
    let degradationPercent: Decimal?
    let fullRangeKm: Decimal?
    let capacityKwh: Decimal?
    let rangeLostKm: Decimal?

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 96

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text("배터리 건강")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 10)
                row("주행가능", VehicleFormat.againstBaseline(
                    fullRangeKm, baseline: VehicleBaseline.newRangeKm, unit: "km", fraction: 0))
                row("용량", VehicleFormat.againstBaseline(
                    capacityKwh, baseline: VehicleBaseline.newCapacityKwh, unit: "kWh", fraction: 1))
                row("줄어든 거리", VehicleFormat.distance(rangeLostKm))
            }
            Spacer(minLength: 0)
        }
        .batteryPanelBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("배터리 건강 잔존 \(VehicleFormat.percent(remainingPercent)), 열화 \(VehicleFormat.percent(degradationPercent))")
    }

    // MARK: - 링

    /// 잔존율 링. Swift Charts를 들이지 않는 저장소 관례대로 `Circle().trim`으로 그린다.
    ///
    /// **100%를 넘는 달은 링이 한 바퀴에서 멈추지만 숫자는 그대로 낸다** — 원은 한 바퀴가
    /// 끝이라 넘는 만큼을 그릴 자리가 없다. 숫자까지 자르면 냉간·재보정으로 튄 값이 사라진다.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, ratio))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(VehicleFormat.percent(remainingPercent))
                    .font(.title2)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("열화 \(VehicleFormat.percent(degradationPercent))")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
        }
        .frame(width: ringSize, height: ringSize)
        .animation(.snappy, value: ratio)
    }

    private var ratio: CGFloat {
        guard let remainingPercent else { return 0 }
        return CGFloat(truncating: (remainingPercent / 100) as NSDecimalNumber)
    }

    /// 90% 이상 초록, 80~90% 노랑, 80% 미만 주황. **문구는 붙이지 않는다.**
    private var ringColor: Color {
        guard let remainingPercent else { return Color.slate500 }
        if remainingPercent >= 90 { return .green300 }
        if remainingPercent >= 80 { return .orange300 }
        return .orange500
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
    }
}

/// 표본이 없거나 못 받았을 때 **같은 자리·같은 색**으로 서는 패널.
/// 자리를 비우지 않는다 — 첫 화면의 주인공이 사라지면 화면이 무너져 보인다.
struct BatteryHealthPlaceholderCard: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
                // 장식 아이콘이다 — VoiceOver가 "bolt badge clock" 같은 원문 심벌 이름을
                // 따로 읽지 않도록 숨긴다. 의미는 아래 결합된 문구가 담는다.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 제목·설명만 한 정거장으로 묶는다. 재시도 버튼은 밖에 남겨 둔다 —
                // 여기까지 묶으면 버튼이 눌러도 반응 없는 문구 조각으로 삼켜진다.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title). \(message)")
                if let retry {
                    Button("다시 시도", action: retry)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .batteryPanelBackground()
    }
}

// MARK: - 공용 패널 배경

private extension View {
    /// 진한 패널 배경(그라디언트 + 모서리 + 그림자). `BatteryHealthCard`와
    /// `BatteryHealthPlaceholderCard`가 같은 자리에 번갈아 서는 같은 패널이라,
    /// 스타일이 갈라지면 화면 상태가 바뀔 때 색이 미묘하게 달라져 보인다.
    func batteryPanelBackground() -> some View {
        modifier(BatteryPanelBackground())
    }
}

private struct BatteryPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.navy800, Color.navy900],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .shadow(color: Color.navy900.opacity(0.35), radius: 14, y: 8)
    }
}

#Preview("건강") {
    VStack(spacing: 12) {
        BatteryHealthCard(remainingPercent: Decimal(string: "92.4"), degradationPercent: 8,
                          fullRangeKm: Decimal(string: "525.3"), capacityKwh: Decimal(string: "71.6"),
                          rangeLostKm: 43)
        BatteryHealthCard(remainingPercent: Decimal(string: "78.1"), degradationPercent: 22,
                          fullRangeKm: 444, capacityKwh: nil, rangeLostKm: 124)
        BatteryHealthPlaceholderCard(icon: "bolt.badge.clock",
                                     title: "아직 잴 만한 충전이 없어요",
                                     message: "80% 이상 충전하면 값이 쌓여요")
    }
    .padding(16)
    .background(Color.slate50)
}
