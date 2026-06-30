import SwiftUI

extension View {
    /// 주요 CTA: Liquid Glass prominent + 앱 액센트 틴트.
    func appGlassProminentButton() -> some View {
        buttonStyle(.glassProminent).tint(GlassTokens.accentTint)
    }

    /// 보조 액션: Liquid Glass.
    func appGlassButton() -> some View {
        buttonStyle(.glass)
    }

    /// 글래스 카드 위 입력칸 공용 스타일: 반투명 프로스티드 필 + 가는 테두리.
    func glassInputField(cornerRadius: CGFloat = 8) -> some View {
        background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.slate200, lineWidth: 1)
            }
    }
}
