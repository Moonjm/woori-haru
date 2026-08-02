import SwiftUI

/// 목표 대비 탄단지 막대.
struct MacroBar: View {
    let name: String
    let intakeG: Double
    let targetG: Int
    /// 값에 붙일 단위. **나트륨만 mg다** — 고정으로 "g"를 붙이면 `2000g`처럼 천 배 틀린
    /// 값을 보여 준다. 막대 비율은 두 값이 같은 단위이기만 하면 되므로 단위와 무관하다.
    var unit: String = "g"
    var tint: Color = .blue500

    /// 목표가 0이면 0으로 나누지 않는다.
    static func ratio(intakeG: Double, targetG: Int) -> Double {
        guard targetG > 0 else { return 0 }
        return intakeG / Double(targetG)
    }

    /// 막대 길이는 1을 넘지 않는다. 비율 자체(`ratio`)는 자르지 않는다.
    static func fill(intakeG: Double, targetG: Int) -> Double {
        min(1.0, ratio(intakeG: intakeG, targetG: targetG))
    }

    /// 단위를 붙이는 자리를 한 곳으로 모은다 — 여기가 뷰 안에 묻혀 있어 나트륨이 오래
    /// `2000g`으로 그려졌다.
    static func valueText(intakeG: Double, targetG: Int, unit: String) -> String {
        "\(Int(intakeG.rounded()))\(unit) / \(targetG)\(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                Text(Self.valueText(intakeG: intakeG, targetG: targetG, unit: unit))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.slate700)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.slate200)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * Self.fill(intakeG: intakeG, targetG: targetG))
                }
            }
            .frame(height: 6)
        }
    }
}
