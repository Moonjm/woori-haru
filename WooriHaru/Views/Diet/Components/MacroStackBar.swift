import SwiftUI

/// 탄단지 **구성비** 스택 막대 — 「46% / 17% / 37%」.
///
/// **`MacroBar`와 다른 것이다.** 저쪽은 **목표 대비** 막대라 여기에 재사용하면
/// `2509kcal 중 80g`처럼 뜻이 맞지 않는 화면이 나온다. 이름이 비슷해 그러기 쉬워 따로 둔다.
///
/// **비율은 서버가 준 `percent`를 그대로 쓴다.** g에서 직접 계산하지 않는다 — 분모가
/// `totalKcal`이 아니라 매크로에서 역산한 값이라 순진하게 나누면 다른 숫자가 나온다
/// (`ScoreBasisCard`가 이미 같은 이유로 「앱은 계산하지 않는다」를 지킨다).
struct MacroStackBar: View {
    let macros: [MacroBasis]

    private let spacing: CGFloat = 2

    /// 카드의 g 표기(`탄 80g · 단 27g · 지 29g`)와 막대의 색을 맞추려고 밖에서도 쓴다 —
    /// 어느 칸이 무엇인지 알 길이 그 색뿐이다.
    static func tint(for name: String) -> Color {
        switch name {
        case "탄수화물": .blue500
        case "단백질": .green600
        case "지방": .orange400
        default: .slate400
        }
    }

    /// 합이 100이 아닐 수 있어(반올림) 합으로 나눈다. 0이면 그릴 것이 없다.
    private var total: Double {
        macros.reduce(0) { $0 + max(0, $1.percent) }
    }

    var body: some View {
        if total > 0 {
            GeometryReader { geometry in
                let available = max(0, geometry.size.width - spacing * CGFloat(max(0, macros.count - 1)))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: spacing) {
                        ForEach(macros) { macro in
                            Capsule()
                                .fill(Self.tint(for: macro.name))
                                .frame(width: width(macro, in: available), height: 8)
                        }
                    }

                    HStack(spacing: spacing) {
                        ForEach(macros) { macro in
                            Text("\(Int(macro.percent.rounded()))%")
                                .font(.caption2)
                                .foregroundStyle(Color.slate500)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width(macro, in: available))
                        }
                    }
                }
            }
            .frame(height: 26)
        }
    }

    private func width(_ macro: MacroBasis, in available: CGFloat) -> CGFloat {
        available * CGFloat(max(0, macro.percent) / total)
    }
}
