import SwiftUI

/// 화면 배경 레이어. glass 요소가 비쳐 보이도록 은은한 그라데이션을 깐다.
struct GlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.slate50, Color.blue50],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// 화면 루트 배경으로 GlassBackground를 깐다.
    func glassScreenBackground() -> some View {
        background { GlassBackground() }
    }
}
