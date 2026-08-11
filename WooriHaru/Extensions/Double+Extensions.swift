import Foundation

extension Double {
    /// 175.0 → "175", 68.5 → "68.5" — 소수점 이하가 0이면 정수로, 아니면 그대로 보여준다.
    /// 몸무게·키처럼 사용자가 직접 입력하고 다시 편집할 값을 텍스트 필드에 채울 때 쓴다.
    ///
    /// **`Int` 범위 밖에서는 정수로 바꾸지 않는다.** `Int(self)`는 `Int.max`를 넘으면 트랩이라
    /// 앱이 그 자리에서 죽는다 — `1e300`은 `rounded()`와 같아서 이 갈래를 그대로 탄다.
    /// 여기까지 오는 값은 붙여넣기로 들어온 터무니없는 입력뿐이라, 죽는 대신 원래 표기로 둔다.
    var trimmedText: String {
        guard isFinite, abs(self) < 1e18 else { return String(self) }
        return self == rounded() ? String(Int(self)) : String(self)
    }
}
