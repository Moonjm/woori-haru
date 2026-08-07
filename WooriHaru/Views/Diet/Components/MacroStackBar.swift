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

    /// 칸 사이 간격.
    static let spacing: CGFloat = 2
    /// 이 폭보다 좁은 칸에는 숫자를 넣지 않는다. **자리는 그대로 둔다** — 억지로 넣으면
    /// 줄어들다 못해 이웃 칸을 침범하고, 어느 숫자가 어느 칸인지가 오히려 흐려진다.
    static let minimumLabelWidth: CGFloat = 26

    /// 글자 크기를 키우면 막대와 숫자 줄이 함께 커져야 한다. **고정 높이로 두면 손쉬운
    /// 사용 설정에서 퍼센트가 잘린다.**
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 8
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 26

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

    /// 칸마다의 폭. **합이 100이 아닐 수 있어(반올림) 합으로 나눈다.** 합이 0이면 빈 배열이다 —
    /// 그릴 것이 없다.
    ///
    /// `available`은 간격을 뺀 폭이다(`availableWidth(in:count:)`).
    static func widths(_ macros: [MacroBasis], in available: CGFloat) -> [CGFloat] {
        let total = macros.reduce(0) { $0 + max(0, $1.percent) }
        guard total > 0 else { return [] }
        return macros.map { available * CGFloat(max(0, $0.percent) / total) }
    }

    /// 간격을 뺀, 칸들이 나눠 가질 폭.
    static func availableWidth(in totalWidth: CGFloat, count: Int) -> CGFloat {
        max(0, totalWidth - spacing * CGFloat(max(0, count - 1)))
    }

    var body: some View {
        if !Self.widths(macros, in: 1).isEmpty {
            GeometryReader { geometry in
                let widths = Self.widths(
                    macros,
                    in: Self.availableWidth(in: geometry.size.width, count: macros.count)
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Self.spacing) {
                        ForEach(Array(macros.enumerated()), id: \.element.id) { index, macro in
                            Capsule()
                                .fill(Self.tint(for: macro.name))
                                .frame(width: widths[index], height: barHeight)
                        }
                    }

                    HStack(spacing: Self.spacing) {
                        ForEach(Array(macros.enumerated()), id: \.element.id) { index, macro in
                            label(macro, width: widths[index])
                        }
                    }
                }
            }
            .frame(height: rowHeight)
            // 칸이 좁아 숫자를 뺀 경우에도 읽을 수 있어야 한다.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    /// 좁은 칸에서는 자리만 지키고 숫자를 뺀다.
    @ViewBuilder
    private func label(_ macro: MacroBasis, width: CGFloat) -> some View {
        if width >= Self.minimumLabelWidth {
            Text("\(Int(macro.percent.rounded()))%")
                .font(.caption2)
                .foregroundStyle(Color.slate500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: width)
        } else {
            Color.clear.frame(width: width, height: 0)
        }
    }

    private var accessibilityText: String {
        macros
            .map { "\($0.name) \(Int($0.percent.rounded()))퍼센트" }
            .joined(separator: ", ")
    }
}
