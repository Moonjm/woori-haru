import SwiftUI

/// 화면 배경 레이어. glass 요소가 비쳐 보이도록 은은한 그라데이션을 깐다.
///
/// **차량 미니앱에서는 거의 검정에 아주 옅은 푸른 기를 깐다.** 위가 완전한 검정에 가깝고
/// 아래로 갈수록 남색 기가 돈다 — 단색으로 두면 화면이 평평해 보인다.
struct GlassBackground: View {
    @Environment(\.vehicleDark) private var vehicleDark

    var body: some View {
        LinearGradient(
            colors: vehicleDark
                ? [VehicleTheme.background, VehicleTheme.surfaceTint]
                : [Color.slate50, Color.blue50],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// 화면 루트 배경으로 GlassBackground를 깐다.
    ///
    /// **`vehicleDarkTheme()`보다 안쪽에 붙여야 한다** — 환경값은 바깥에서 안으로 흐른다.
    func glassScreenBackground() -> some View {
        background { GlassBackground() }
    }
}
