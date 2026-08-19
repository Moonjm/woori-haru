import SwiftUI

/// 지금 배터리와 지금 상태 — **화면에서 유일한 진한 패널이다.**
///
/// 이 자리는 3단계까지 `BatteryHealthCard`(열화)의 것이었다. 4단계에서 「현재 상태를 열화보다
/// 위로」 순서가 바뀌면서 강조도 함께 옮겨 왔다 — **눈이 먼저 가라고 만든 패널이 맨 아래에 있으면
/// 강조가 순서와 어긋난다.** 링도 같은 이유로 여기 하나뿐이다. 잔존율 92%와 잔량 72%가 같은
/// 모양으로 나란히 놓이면 무엇이 무엇인지 안 갈린다.
struct BatteryNowCard: View {
    let status: VehicleStatus
    /// `stateSince`로부터 흐른 분. 화면이 1분마다 다시 계산해 넘긴다.
    let minutesInState: Int?

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 96

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                stateLine.padding(.bottom, 10)
                row("사용 가능", status.usableBatteryLevel.map { "\($0)%" } ?? ChargeFormat.placeholder)
                row("위치", status.locationName ?? ChargeFormat.placeholder)
            }
            Spacer(minLength: 0)
        }
        .batteryPanelBackground()
        .accessibilityElement(children: .combine)
        // `.combine`은 자식을 묶을 뿐 그 결과를 읽지 않는다 — 라벨을 얹으면 통째로 대체되므로
        // 화면에 보이는 값을 순서대로 모두 이어 붙인다.
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - 링

    /// 잔량 링. Swift Charts를 들이지 않는 저장소 관례대로 `Circle().trim`으로 그린다.
    /// 열화 링에서 물려받은 어휘 그대로다 — 96pt, 선 굵기 9.
    private var ring: some View {
        ZStack {
            Circle().stroke(VehicleTheme.trackFill, lineWidth: 9)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // **화면에서 빛나는 것은 이것 하나뿐이다.** 후광 색은 링 색을 따라간다 —
                // 잔량 20% 미만이면 링이 빨강이 되는데 거기 초록 후광이 지면 색이
                // 서로를 부정한다.
                .shadow(color: ringColor.opacity(0.55), radius: 12)
            VStack(spacing: 1) {
                Text(status.batteryLevel.map { "\($0)%" } ?? ChargeFormat.placeholder)
                    .font(.title2)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(VehicleFormat.distance(status.ratedRangeKm))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
            .padding(.horizontal, 10)
        }
        .frame(width: ringSize, height: ringSize)
        .animation(.snappy, value: ratio)
    }

    private var ratio: CGFloat {
        guard let level = status.batteryLevel else { return 0 }
        return min(1, max(0, CGFloat(level) / 100))
    }

    /// 50% 이상 민트, 20~50% 노랑, 20% 미만 빨강. **문구는 붙이지 않는다** — 색만 바뀐다.
    /// 판정은 `BatteryBand`, 색은 `VehicleTheme`. 둘 다 여기서 하지 않는다.
    private var ringColor: Color {
        VehicleTheme.color(for: BatteryBand.of(status.batteryLevel))
    }

    // MARK: - 상태

    /// `state`는 3단계까지 기준 시각 줄에 작은 글씨로만 붙어 있었다. 여기서 제 자리를 갖는다.
    private var stateLine: some View {
        HStack(spacing: 6) {
            Circle()
                // **상태를 색으로 말하지 않는다.** 민트는 이 테마에서 「좋음」이라, 오프라인 옆에
                // 켜지면 거짓말이 된다. 상태는 옆 글자가 말하고 점은 자리만 잡는다.
                .fill(VehicleTheme.textSecondary)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(VehicleFormat.stateLabel(status.state))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textPrimary)
                if let minutesInState {
                    Text(VehicleFormat.elapsed(minutes: minutesInState))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["배터리 \(status.batteryLevel.map { "\($0)퍼센트" } ?? "값 없음")"]
        parts.append(status.ratedRangeKm == nil
            ? "주행가능 값 없음"
            : "주행가능 \(VehicleFormat.distance(status.ratedRangeKm))")
        parts.append(status.state == nil ? "상태 값 없음" : VehicleFormat.stateLabel(status.state))
        if let minutesInState { parts.append(VehicleFormat.elapsed(minutes: minutesInState)) }
        parts.append("사용 가능 \(status.usableBatteryLevel.map { "\($0)퍼센트" } ?? "값 없음")")
        parts.append("위치 \(status.locationName ?? "값 없음")")
        return parts.joined(separator: ", ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
    }
}

/// 값이 없거나 못 받았을 때 **같은 자리·같은 색**으로 서는 패널.
/// 첫 화면의 주인공이 사라지면 화면이 무너져 보인다 — 자리가 바뀌어도 같은 이유다.
struct BatteryNowPlaceholderCard: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(VehicleTheme.textTertiary)
                // 장식 아이콘이다 — VoiceOver가 원문 심벌 이름을 읽지 않도록 숨긴다.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 제목·설명만 묶는다. 버튼까지 묶으면 눌러도 반응 없는 문구 조각으로 삼켜진다.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title). \(message)")
                if let retry {
                    Button("다시 시도", action: retry)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.accentBright)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VehicleTheme.accent.opacity(0.18), in: Capsule())
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

extension View {
    /// 히어로 패널 배경. **더 이상 「진한 판」이 아니다** — 배경이 검정이 되면서
    /// 어두운 판은 특별할 수 없게 됐다. 다른 카드와 같은 면을 쓰고, 강조는 링이 맡는다.
    ///
    /// `BatteryNowCard`와 `BatteryNowPlaceholderCard`가 같은 자리에 번갈아 서는 같은
    /// 패널이라, 스타일이 갈라지면 화면 상태가 바뀔 때 색이 미묘하게 달라져 보인다.
    fileprivate func batteryPanelBackground() -> some View {
        modifier(BatteryPanelBackground())
    }
}

private struct BatteryPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VehicleTheme.cardFill, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(VehicleTheme.cardStroke, lineWidth: 1)
            )
    }
}

#Preview("지금") {
    VStack(spacing: 12) {
        BatteryNowCard(status: VehicleStatus(
            asOf: "2026-08-19T12:00:00", state: "offline", stateSince: "2026-08-19T08:48:00",
            batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: 385, estRangeKm: 370,
            odometerKm: 107_258, insideTempC: 28, outsideTempC: 31, climateOn: false,
            locationName: "집", tpmsBar: nil), minutesInState: 192)
        BatteryNowCard(status: VehicleStatus(
            asOf: "2026-08-19T12:00:00", state: "online", stateSince: "2026-08-19T11:55:00",
            batteryLevel: 14, usableBatteryLevel: 12, ratedRangeKm: 74, estRangeKm: 70,
            odometerKm: 107_258, insideTempC: 28, outsideTempC: 31, climateOn: true,
            locationName: nil, tpmsBar: nil), minutesInState: 5)
        BatteryNowPlaceholderCard(icon: "car",
                                  title: "아직 기록이 없어요",
                                  message: "차가 한 번 깨어나면 값이 쌓여요")
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
