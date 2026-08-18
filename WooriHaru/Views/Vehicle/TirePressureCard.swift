import SwiftUI

/// 타이어 공기압 — 숫자 넷을 늘어놓는 대신 **차 도형 위 네 모서리**에 얹고,
/// 권장값에서 벗어난 바퀴만 색을 바꾼다. 값이 정상인지 사람이 판단하지 않게 하려는 것이다.
///
/// **psi만 낸다.** 서버는 TeslaMate 저장 단위인 bar로 주지만, 타이어에 넣을 때 쓰는 단위도
/// 차 문틀의 권장값도 psi다 — 두 단위를 함께 두면 읽을 때마다 어느 쪽인지 골라야 한다.
struct TirePressureCard: View {
    let tpms: VehicleStatus.TpmsBar?

    private struct Wheel {
        let name: String
        let bar: Decimal?
        var status: TireStatus { VehicleMath.tireStatus(bar: bar) }
    }

    private var wheels: [Wheel] {
        [Wheel(name: "앞 왼쪽", bar: tpms?.fl), Wheel(name: "앞 오른쪽", bar: tpms?.fr),
         Wheel(name: "뒤 왼쪽", bar: tpms?.rl), Wheel(name: "뒤 오른쪽", bar: tpms?.rr)]
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("타이어 공기압")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    Text("\(VehicleFormat.psiText(VehicleMath.averagePsi(tpms))) 평균")
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(Color.slate500)
                }

                diagram
                verdict
            }
        }
    }

    /// 차 도형을 가운데 두고 좌우에 바퀴를 놓는다 — 위에서 내려다본 배치라
    /// 화면의 왼쪽 위가 실제 앞 왼쪽 바퀴다.
    private var diagram: some View {
        HStack(spacing: 10) {
            VStack(spacing: 10) { wheel(wheels[0]); wheel(wheels[2]) }
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.slate100)
                .frame(width: 40)
                .overlay {
                    Image(systemName: "car.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.slate300)
                }
            VStack(spacing: 10) { wheel(wheels[1]); wheel(wheels[3]) }
        }
        .frame(height: 108)
    }

    private func wheel(_ wheel: Wheel) -> some View {
        VStack(spacing: 1) {
            Text(VehicleFormat.pressurePsi(wheel.bar))
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(wheel.status.foreground)
            Text(wheel.name)
                .font(.system(size: 9))
                .foregroundStyle(Color.slate400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(wheel.status.background, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(wheel.name) \(VehicleFormat.pressurePsi(wheel.bar)) \(wheel.status.spokenSuffix)")
    }

    /// 네 바퀴가 모두 정상이면 한 줄로 끝내고, 아니면 벗어난 바퀴 이름을 적는다.
    /// **값이 없는 바퀴는 경고가 아니라 「못 받았다」다.**
    @ViewBuilder private var verdict: some View {
        let abnormal = wheels.filter { $0.status.isAbnormal }
        let unknown = wheels.filter { $0.status == .unknown }
        if !abnormal.isEmpty {
            line("exclamationmark.triangle.fill",
                 "\(abnormal.map(\.name).joined(separator: "·")) 공기압을 확인해 주세요",
                 Color.orange700)
        } else if unknown.count == wheels.count {
            line("questionmark.circle", "아직 공기압 값을 받지 못했어요", Color.slate400)
        } else if !unknown.isEmpty {
            line("questionmark.circle",
                 "\(unknown.map(\.name).joined(separator: "·")) 값이 없어요",
                 Color.slate400)
        } else {
            line("checkmark.circle.fill", "네 바퀴 모두 정상", Color.green600)
        }
    }

    private func line(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(color)
    }
}

private extension TireStatus {
    var foreground: Color {
        switch self {
        case .normal: return .slate900
        case .low, .high: return .orange700
        case .unknown: return .slate400
        }
    }

    var background: Color {
        switch self {
        case .normal: return .slate100
        case .low, .high: return .orange100
        case .unknown: return .slate50
        }
    }

    var spokenSuffix: String {
        switch self {
        case .normal: return "정상"
        case .low: return "권장보다 낮음"
        case .high: return "권장보다 높음"
        case .unknown: return "값 없음"
        }
    }
}

#Preview("공기압") {
    VStack(spacing: 12) {
        TirePressureCard(tpms: VehicleStatus.TpmsBar(
            fl: Decimal(string: "2.90"), fr: Decimal(string: "2.83"),
            rl: Decimal(string: "2.97"), rr: Decimal(string: "2.90")))
        TirePressureCard(tpms: VehicleStatus.TpmsBar(
            fl: Decimal(string: "2.90"), fr: Decimal(string: "2.45"),
            rl: Decimal(string: "2.97"), rr: nil))
        TirePressureCard(tpms: nil)
    }
    .padding(16)
    .background(Color.slate50)
}
