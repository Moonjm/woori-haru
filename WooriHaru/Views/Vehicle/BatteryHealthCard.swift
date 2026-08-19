import SwiftUI

/// 배터리 건강 — 잔존율과 열화, 그리고 그것을 이루는 세 값.
///
/// **3단계까지 이 카드가 진한 패널과 링을 갖고 있었다.** 4단계에서 「현재 상태를 열화보다 위로」
/// 순서가 바뀌면서 그 둘을 `BatteryNowCard`에 넘기고 밝은 카드로 내려왔다 — 링이 둘이면
/// 잔존율 92%와 잔량 72%가 안 갈리고, 눈이 먼저 가라고 만든 패널이 맨 아래에 있으면
/// 강조가 순서와 어긋난다.
///
/// **경고 문구를 넣지 않는다** — 열화는 고장이 아니다. 잔존율이 낮아지면 숫자 색만 바뀐다.
struct BatteryHealthCard: View {
    let remainingPercent: Decimal?
    let degradationPercent: Decimal?
    let fullRangeKm: Decimal?
    let capacityKwh: Decimal?
    let rangeLostKm: Decimal?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("배터리 건강")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    Text("열화 \(VehicleFormat.percent(degradationPercent))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.slate400)
                }
                .padding(.bottom, 10)

                // 잔존율만 색을 갖는다. 링이 하던 일이 숫자로 옮겨 온 것이다.
                HStack(alignment: .firstTextBaseline) {
                    Text("잔존율")
                        .font(.caption2)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    Text(VehicleFormat.percent(remainingPercent))
                        .font(.title3)
                        .fontWeight(.heavy)
                        .monospacedDigit()
                        .foregroundStyle(remainingColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.vertical, 4)

                row("주행가능", VehicleFormat.againstBaseline(
                    fullRangeKm, baseline: VehicleBaseline.newRangeKm, unit: "km", fraction: 0))
                row("용량", VehicleFormat.againstBaseline(
                    capacityKwh, baseline: VehicleBaseline.newCapacityKwh, unit: "kWh", fraction: 1))
                row("줄어든 거리", VehicleFormat.distance(rangeLostKm))
            }
        }
        .accessibilityElement(children: .combine)
        // `.combine`은 자식을 묶을 뿐 그 결과를 읽지 않는다 — 라벨을 얹으면 통째로 대체되므로
        // 화면에 보이는 순서대로 값을 모두 이어 붙인다.
        .accessibilityLabel(
            "배터리 건강 잔존 \(VehicleFormat.percent(remainingPercent)), 열화 \(VehicleFormat.percent(degradationPercent)), " +
            "주행가능 \(VehicleFormat.againstBaseline(fullRangeKm, baseline: VehicleBaseline.newRangeKm, unit: "km", fraction: 0)), " +
            "용량 \(VehicleFormat.againstBaseline(capacityKwh, baseline: VehicleBaseline.newCapacityKwh, unit: "kWh", fraction: 1)), " +
            "줄어든 거리 \(VehicleFormat.distance(rangeLostKm))"
        )
    }

    /// 90% 이상 초록, 80~90% 주황, 80% 미만 진한 주황. 판정은 `HealthBand`가 한다 —
    /// **반올림한 값으로 갈라야** 옆에 찍히는 숫자와 색이 어긋나지 않는다.
    private var remainingColor: Color {
        switch HealthBand.of(remainingPercent) {
        case .good: Color.green600
        case .fair: Color.orange500
        case .low: Color.orange700
        case nil: Color.slate500
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
    }
}

/// 표본이 없거나 못 받았을 때 **같은 자리**에 서는 카드.
struct BatteryHealthPlaceholderCard: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.slate400)
                    // 장식 아이콘이다 — VoiceOver가 원문 심벌 이름을 읽지 않도록 숨긴다.
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.slate900)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 제목·설명만 묶는다. 버튼까지 묶으면 눌러도 반응 없는 문구 조각으로 삼켜진다.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(title). \(message)")
                    if let retry {
                        Button("다시 시도", action: retry)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue600, in: Capsule())
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
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
