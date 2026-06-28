import SwiftUI

/// 앱 공용 Liquid Glass 카드. 기존 흰 카드(RoundedRectangle.fill(.white).stroke) 대체용.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = GlassTokens.cardCornerRadius
    var padding: CGFloat = GlassTokens.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
