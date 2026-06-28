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
}
