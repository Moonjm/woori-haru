import SwiftUI

/// 앱 공용 Liquid Glass 카드. 기존 흰 카드(RoundedRectangle.fill(.white).stroke) 대체용.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = GlassTokens.cardCornerRadius
    var padding: CGFloat = GlassTokens.cardPadding
    var alignment: Alignment = .leading
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            // 카드처럼 생긴 것은 어디를 눌러도 눌려야 한다. 이게 없으면 `NavigationLink`
            // 안에서 글씨·아이콘 픽셀만 탭에 닿고 그 사이 여백은 통과한다.
            // **모서리를 유리 모양과 맞춘다** — `.rect`로 두면 보이지 않는 귀퉁이가 눌린다.
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
