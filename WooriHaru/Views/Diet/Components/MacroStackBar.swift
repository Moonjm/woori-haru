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
    /// 숫자를 넣을 수 있는 최소 폭 — **기본 글자 크기 기준**이다. 실제 판정은 글자 크기에
    /// 따라 늘어난 `minimumLabelWidth`로 한다(`.caption2`가 커지면 「100%」도 같이 커진다).
    static let baseMinimumLabelWidth: CGFloat = 26

    /// 글자 크기를 키우면 막대와 숫자 줄이 함께 커져야 한다. **고정 높이로 두면 손쉬운
    /// 사용 설정에서 퍼센트가 잘린다.**
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 8
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 26
    /// **기준도 함께 커져야 한다.** 고정 26pt로 두면 접근성 크기에서 30pt짜리 칸이 검사를
    /// 통과해 놓고도 「100%」를 못 담아 다시 잘린다.
    @ScaledMetric(relativeTo: .caption2) private var minimumLabelWidth: CGFloat = MacroStackBar.baseMinimumLabelWidth

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

    /// 칸마다의 폭. **합이 100이 아닐 수 있어(반올림) 합으로 나눈다.** 그릴 것이 없으면
    /// 빈 배열이다.
    ///
    /// **성한 값만 내보낸다.** 결과가 그대로 `frame(width:)`로 들어가는데, 음수·무한대·NaN이
    /// 거기 닿으면 레이아웃이 정의되지 않는다. 서버 값이라 손댈 수 없으므로 여기서 막는다
    /// (`DietInputLimits`가 사용자 입력에 대해 같은 판단을 한다).
    ///
    /// `available`은 간격을 뺀 폭이다(`availableWidth(in:count:)`).
    static func widths(_ macros: [MacroBasis], in available: CGFloat) -> [CGFloat] {
        let safeAvailable = available.isFinite ? max(0, available) : 0
        // 음수·무한대·NaN은 0으로 본다 — 그 칸이 사라질 뿐 나머지 비율은 그대로다.
        let percents = macros.map { $0.percent.isFinite ? max(0, $0.percent) : 0 }
        let total = percents.reduce(0, +)
        guard total.isFinite, total > 0 else { return [] }
        return percents.map { safeAvailable * CGFloat($0 / total) }
    }

    /// 간격을 뺀, 칸들이 나눠 가질 폭.
    static func availableWidth(in totalWidth: CGFloat, count: Int) -> CGFloat {
        guard totalWidth.isFinite else { return 0 }
        return max(0, totalWidth - spacing * CGFloat(max(0, count - 1)))
    }

    /// 이 칸에 숫자를 넣을 수 있는가. **판정을 뷰 밖에 둔다** — 뷰 안에 있으면 테스트가 못 닿는다.
    static func showsLabel(width: CGFloat, minimum: CGFloat) -> Bool {
        width.isFinite && width >= minimum
    }

    /// 칸에 찍는 문구. **`Int(_:)`는 `Int.max`를 넘으면 트랩이라** 성한 값만 넘긴다.
    static func labelText(for percent: Double) -> String {
        guard percent.isFinite else { return "-" }
        return "\(Int(min(max(0, percent), 1000).rounded()))%"
    }

    /// 막대 전체를 한 문장으로 읽어 준다. **칸이 좁아 숫자를 뺀 경우에도 읽혀야 한다.**
    static func accessibilityText(_ macros: [MacroBasis]) -> String {
        macros
            .map { macro in
                // **`labelText`의 끝 글자를 떼어 쓰지 않는다** — 성하지 않은 값에서는 그것이
                // 「-」라 「탄수화물 퍼센트」처럼 숫자가 빠진 문장이 읽힌다.
                guard macro.percent.isFinite else { return "\(macro.name) 알 수 없음" }
                return "\(macro.name) \(Int(min(max(0, macro.percent), 1000).rounded()))퍼센트"
            }
            .joined(separator: ", ")
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
            // 칸이 좁아 숫자를 뺀 경우에도 읽을 수 있어야 한다 — 하나의 요소로 묶어 읽는다.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityText(macros))
        }
    }

    /// 좁은 칸에서는 자리만 지키고 숫자를 뺀다 — 억지로 넣으면 이웃 칸을 침범한다.
    @ViewBuilder
    private func label(_ macro: MacroBasis, width: CGFloat) -> some View {
        if Self.showsLabel(width: width, minimum: minimumLabelWidth) {
            Text(Self.labelText(for: macro.percent))
                .font(.caption2)
                .foregroundStyle(Color.slate500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: width)
        } else {
            Color.clear.frame(width: width, height: 0)
        }
    }
}
