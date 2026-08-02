import Foundation

extension Double {
    /// 175.0 → "175", 68.5 → "68.5" — 소수점 이하가 0이면 정수로, 아니면 그대로 보여준다.
    /// 몸무게·키처럼 사용자가 직접 입력하고 다시 편집할 값을 텍스트 필드에 채울 때 쓴다.
    var trimmedText: String {
        self == rounded() ? String(Int(self)) : String(self)
    }
}
