import SwiftUI
import UIKit

// 달력 ScrollView의 UIKit 레벨 스크롤 제어 모음.
// SwiftUI가 제공하지 않는 두 가지를 UIScrollView에 직접 개입해 해결한다:
//  1) stopScroll(when:) — 모멘텀 스크롤 즉시 중단
//  2) LockScrollOffsetHelper — 시트/키보드로 인한 contentOffset 자동 조정 차단

// MARK: - UIView → UIScrollView 탐색 헬퍼

private extension UIView {
    /// superview 체인을 거슬러 올라가며 가장 가까운 UIScrollView를 찾는다.
    var ancestorScrollView: UIScrollView? {
        var current: UIView? = self
        while let v = current {
            if let sv = v as? UIScrollView { return sv }
            current = v.superview
        }
        return nil
    }
}

// MARK: - ScrollView 모멘텀 중단 헬퍼

private struct ScrollStopModifier: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        content
            .background(ScrollStopHelper(trigger: trigger))
    }
}

private struct ScrollStopHelper: UIViewRepresentable {
    let trigger: Bool

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard trigger else { return }
        if let sv = uiView.ancestorScrollView {
            sv.setContentOffset(sv.contentOffset, animated: false)
        }
    }
}

extension View {
    func stopScroll(when trigger: Bool) -> some View {
        modifier(ScrollStopModifier(trigger: trigger))
    }
}

// MARK: - ContentOffset 잠금 헬퍼
// 시트/키보드로 인한 UIScrollView의 contentOffset 자동 조정을 차단한다.
// `.ignoresSafeArea(.keyboard)`가 상위에서 contentInset 조정을 이미 억제한다는 전제 하에
// 잔여 offset 변경만 복원. 사용자 제스처(isDragging/isDecelerating) 중엔 간섭하지 않는다.
// ⚠️ 프로그램적 scrollTo(스크롤 프록시 포함)도 차단되니, active=true 동안 의도적 스크롤이
// 필요하면 먼저 deactivate 후 호출할 것.

struct LockScrollOffsetHelper: UIViewRepresentable {
    let active: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        context.coordinator.anchorView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.anchorView = uiView
        context.coordinator.setActive(active)
    }

    /// KVO 수명과 잠금 상태를 소유하는 코디네이터 — SwiftUI 뷰 갱신과 무관하게
    /// 관찰을 유지하고, 비활성화/해제 시점에 반드시 invalidate한다.
    final class Coordinator: NSObject {
        weak var anchorView: UIView?
        private weak var scrollView: UIScrollView?
        private var lockedOffset: CGPoint?
        private var offsetKVO: NSKeyValueObservation?
        private var isActive = false

        func setActive(_ active: Bool) {
            guard active != isActive else { return }
            isActive = active
            if active { lock() } else { unlock() }
        }

        private func lock() {
            // 활성화 시점에 anchor로부터 UIScrollView를 새로 찾는다
            // (초기 updateUIView 시점에는 view가 아직 window에 붙지 않았을 수 있음)
            if scrollView == nil {
                scrollView = anchorView?.ancestorScrollView
            }
            guard let sv = scrollView else { return }
            lockedOffset = sv.contentOffset
            offsetKVO = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, change in
                // 사용자 드래그/감속 중엔 간섭하지 않음
                guard let self, let locked = self.lockedOffset,
                      !sv.isDragging, !sv.isDecelerating,
                      let new = change.newValue,
                      abs(new.y - locked.y) > 0.5 || abs(new.x - locked.x) > 0.5 else { return }
                sv.setContentOffset(locked, animated: false)
            }
        }

        private func unlock() {
            offsetKVO?.invalidate()
            offsetKVO = nil
            lockedOffset = nil
        }

        deinit { unlock() }
    }
}
