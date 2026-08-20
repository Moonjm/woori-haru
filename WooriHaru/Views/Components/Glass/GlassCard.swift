import SwiftUI

/// 앱 공용 Liquid Glass 카드. 기존 흰 카드(RoundedRectangle.fill(.white).stroke) 대체용.
///
/// **차량 미니앱에서는 유리를 쓰지 않는다.** `\.vehicleDark`가 켜지면 `cardFill` + `cardStroke`로
/// 명시적으로 그린다 — Liquid Glass의 굴절은 뒤에 밝은 것이 있을 때만 드러나는 효과라,
/// 거의 검은 배경 위에서는 보이는 것 없이 색만 예측하기 어려워진다.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = GlassTokens.cardCornerRadius
    var padding: CGFloat = GlassTokens.cardPadding
    var alignment: Alignment = .leading
    @ViewBuilder var content: () -> Content

    @Environment(\.vehicleDark) private var vehicleDark

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .modifier(GlassCardSurface(cornerRadius: cornerRadius, dark: vehicleDark))
            // 카드처럼 생긴 것은 어디를 눌러도 눌려야 한다. 이게 없으면 `NavigationLink`
            // 안에서 글씨·아이콘 픽셀만 탭에 닿고 그 사이 여백은 통과한다.
            // **모서리를 유리 모양과 맞춘다** — `.rect`로 두면 보이지 않는 귀퉁이가 눌린다.
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// **밝은 갈래는 예전 코드 그대로다.** 42개 파일이 이 카드를 쓰고 있고,
/// 다크는 차량·충전 화면에서만 켜진다.
private struct GlassCardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let dark: Bool

    func body(content: Content) -> some View {
        if dark {
            content
                .background(VehicleTheme.cardFill, in: RoundedRectangle(cornerRadius: cornerRadius))
                // **테두리가 형태를 만든다.** 채움이 흰색 4%뿐이라 선이 없으면 배경과 안 갈린다.
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(VehicleTheme.cardStroke, lineWidth: 1)
                )
        } else {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
