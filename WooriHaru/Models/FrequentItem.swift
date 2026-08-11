import Foundation

/// 내가 실제로 저장했던 항목. **응답 한 건이 그대로 `MealItemRequest`가 되므로 앱이 다시
/// 계산하지 않는다** — 수량과 영양소가 딸려 온다.
struct FrequentItem: Codable, Hashable, Identifiable {
    let foodName: String
    let foodCode: String?
    let quantityG: Double
    let kcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
    let source: NutritionSource
    /// 기간 내 먹은 횟수
    let count: Int
    /// "yyyy-MM-dd"
    let lastEatenOn: String

    /// 서버가 코드 없는 항목을 정규화한 이름으로 묶으므로 코드가 없으면 이름이 키다.
    var id: String { foodCode ?? foodName }

    var countText: String { "\(count)회" }
}
