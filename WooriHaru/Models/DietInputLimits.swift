import Foundation

/// 사용자가 손으로 넣는 숫자의 상한.
///
/// **`isFinite`만으로는 부족하다.** `1e300`은 유한하지만, 그 값으로 만든 열량이 화면에서
/// `Int(...)`로 변환될 때 **트랩이 걸려 앱이 그 자리에서 죽는다**(`Int(Double)`은 `Int.max`를
/// 넘으면 크래시다). 무한대만 막으면 이 자리가 그대로 남는다.
///
/// 실제 식사에서 닿을 수 없는 값으로 넉넉히 잡는다 — **정상 입력을 막는 것보다 크래시를 막는
/// 것이 목적이라** 상한을 조이지 않는다.
enum DietInputLimits {
    /// 100kg. 한 끼 항목 하나가 이 값을 넘을 일은 없다.
    static let maxQuantityG: Double = 100_000
    /// 영양소 한 칸의 상한. 100,000kcal·100,000mg — 어느 쪽도 실제로는 닿지 않는다.
    static let maxNutrientValue: Double = 100_000
}
