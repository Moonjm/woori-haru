import CoreGraphics

/// 전체화면 사진 뷰어를 **아래로 끌어 닫는** 규칙.
///
/// **뷰 밖에 둔다.** SwiftUI 제스처 자체는 단위 테스트가 닿지 않지만, 임계값·속도·불투명도
/// 계산은 닿아야 한다 — 숫자 하나가 어긋나면 「가끔 안 닫힌다」로 나타나는데, 그것을 손으로만
/// 확인하면 매번 실기기를 띄워야 한다.
enum PhotoDragDismiss {
    /// 이만큼 내려가면 닫는다.
    static let threshold: CGFloat = 120
    /// 배경이 이 아래로는 안 옅어진다.
    ///
    /// **완전 투명까지 가면 안 된다** — `fullScreenCover` 뒤의 시스템 배경색이 드러나 라이트
    /// 모드에서 흰색이 튀어나온다.
    static let minimumBackgroundOpacity: Double = 0.55
    /// 이 속도보다 빠르게 아래로 튕기면 거리가 짧아도 닫는다.
    static let flickVelocity: CGFloat = 800

    /// **거리만 보면 휙 튕기는 동작이 빠진다** — 사용자는 그것도 닫히길 기대하므로,
    /// 안 닫히면 버그로 느낀다.
    ///
    /// **위로 끄는 것은 어느 쪽 기준으로도 닫지 않는다.** 부호를 잘못 보면 위로 끌 때 닫힌다.
    static func shouldDismiss(translationY: CGFloat, velocityY: CGFloat) -> Bool {
        guard translationY > 0 else { return false }
        return translationY >= threshold || velocityY >= flickVelocity
    }

    /// 끄는 만큼 옅어지되 하한에서 멈춘다.
    static func backgroundOpacity(translationY: CGFloat) -> Double {
        let progress = min(max(offsetY(translationY: translationY) / threshold, 0), 1)
        return 1 - (1 - minimumBackgroundOpacity) * Double(progress)
    }

    /// 화면에 반영할 세로 이동. **위로 끌면 0이다** — 따라오게 해 놓고 안 닫는 것이 가장 나쁘다.
    static func offsetY(translationY: CGFloat) -> CGFloat {
        max(0, translationY)
    }

    /// 끄는 동안 사진이 조금 작아진다. 1에서 0.9까지만 줄어든다 — 더 줄면 닫히기도 전에
    /// 사진이 사라지는 것처럼 보인다.
    static func imageScale(translationY: CGFloat) -> CGFloat {
        let progress = min(max(offsetY(translationY: translationY) / threshold, 0), 1)
        return 1 - 0.1 * progress
    }
}
