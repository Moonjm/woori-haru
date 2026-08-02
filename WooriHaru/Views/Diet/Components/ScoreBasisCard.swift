import SwiftUI

/// 점수의 근거를 보여준다. **앱은 계산하지 않는다** — 서버가 준 `status`·`penalty`·`standard`를
/// 그대로 쓴다. 앱이 비율과 범위만 받아 직접 판정하면 감점 규칙이 두 곳에 생기고, 서버가
/// 기울기를 바꿨을 때 화면의 설명과 실제 점수가 어긋난다.
struct ScoreBasisCard: View {
    let title: String
    let score: Int?
    /// 끼니 근거(매크로 비율). 하루 카드에서는 nil이다.
    var basis: MealScoreBasis?
    /// 하루 점수에는 칼로리 항목과 매크로 g 목표가 붙는다. 끼니 카드에서는 nil이다.
    var dayBasis: DayScoreBasis?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Spacer()
                    Text(score.map { "\($0)점" } ?? "점수 없음")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.slate900)
                }

                Text(standardText)
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)

                if let calorie = dayBasis?.calorie {
                    calorieRow(calorie)
                    Divider()
                }

                ForEach(basis?.macros ?? []) { macro in
                    macroRow(macro)
                }

                ForEach(dayBasis?.macros ?? []) { macro in
                    MacroBar(name: macro.name, intakeG: macro.intakeG, targetG: macro.targetG)
                }
            }
        }
    }

    private var standardText: String {
        dayBasis?.standard ?? basis?.standard ?? ""
    }

    private func calorieRow(_ calorie: CalorieBasis) -> some View {
        HStack {
            Text("칼로리")
                .font(.caption)
                .foregroundStyle(Color.slate500)
            Spacer()
            Text("\(Int(calorie.intakeKcal.rounded()))kcal / \(calorie.targetKcal)kcal")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate700)
            Text("\(Int((calorie.ratio * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(Color.slate400)
        }
    }

    /// `status`와 `penalty`는 서버 값이다. 앱은 색과 문구만 고른다.
    private func macroRow(_ macro: MacroBasis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(macro.name)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                Text("\(Int(macro.percent.rounded()))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.slate700)
                Text("권장 \(macro.rangeMin)~\(macro.rangeMax)%")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }

            HStack(spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.slate200)
                        Capsule()
                            .fill(tint(for: macro.status))
                            .frame(width: geometry.size.width * min(1.0, macro.percent / 100.0))
                    }
                }
                .frame(height: 6)

                Text(statusText(macro))
                    .font(.caption2)
                    .foregroundStyle(tint(for: macro.status))
                    .frame(width: 76, alignment: .trailing)
            }
        }
    }

    private func tint(for status: MacroStatus) -> Color {
        switch status {
        case .inRange: .green600
        case .over: .orange400
        case .under: .blue400
        }
    }

    private func statusText(_ macro: MacroBasis) -> String {
        switch macro.status {
        case .inRange: "범위 안"
        case .over: "+\(Int((macro.percent - Double(macro.rangeMax)).rounded()))%p 초과"
        case .under: "-\(Int((Double(macro.rangeMin) - macro.percent).rounded()))%p 부족"
        }
    }
}
