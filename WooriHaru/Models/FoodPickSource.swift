import Foundation

/// 고를 수 있는 항목의 **두 출처**. 검색 결과(`Food`)는 100g당 값이고 자주 드셨어요
/// (`FrequentItem`)는 저장된 절대값이라 **환산 함수가 서로 다르다** —
/// 앞은 `NutritionMath.item(from:quantityG:)`, 뒤는 `NutritionMath.rescaled(_:to:)`.
/// 그래서 항목을 만드는 순간까지 어느 쪽인지 그대로 들고 다닌다.
enum FoodPickSource: Identifiable, Hashable {
    case food(Food)
    case frequent(FrequentItem)

    /// 검색 결과와 자주 드셨어요에 같은 식품이 있을 수 있으므로 접두어로 갈라 둔다.
    var id: String {
        switch self {
        case let .food(food): "food-\(food.id)"
        case let .frequent(item): "frequent-\(item.id)"
        }
    }

    var name: String {
        switch self {
        case let .food(food): food.name
        case let .frequent(item): item.foodName
        }
    }

    /// 조리 음식과 포장 제품이 섞여 나오므로 목록에서 구분해 보여준다. 자주 드셨어요에는
    /// `dataset`이 없다 — 저장된 항목이라 어느 데이터셋에서 왔는지 응답에 없다.
    var badge: String? {
        switch self {
        case let .food(food): food.dataset.badge
        case .frequent: nil
        }
    }

    /// 「도미노피자」. **검색 결과에만 있다** — 자주 드셨어요는 저장된 항목이라 브랜드가 없다.
    ///
    /// 식품명에 브랜드가 안 들어 있어서(`피자_뉴욕 오리진 피자 오리지널 (L)`) 이 값이 없으면
    /// 「도미노」로 검색해 나온 결과를 보고도 왜 나왔는지 알 수 없다.
    var brandText: String? {
        switch self {
        case let .food(food): food.maker
        case .frequent: nil
        }
    }

    /// 이 영양소가 추정으로 채워진 값인가. **검색 결과에만 있다** — 자주 드셨어요는 저장된
    /// 항목이라 출처를 모른다(`badge`·`brandText`와 같은 이유).
    ///
    /// `.frequent`의 `false`는 **「원본 값」이 아니라 「모른다」**는 뜻이다.
    func isEstimated(_ field: String) -> Bool {
        switch self {
        case let .food(food): food.estimatedFields?.contains(field) == true
        case .frequent: false
        }
    }

    /// 행 둘째 줄. 「1인분 (250g)」 · 「100g 기준」 · 「200g · 7회」
    var detailText: String {
        switch self {
        case let .food(food):
            food.servingSizeKnown ? "1인분 (\(food.servingSizeG.trimmedText)g)" : "100g 기준"
        case let .frequent(item):
            "\(item.quantityG.trimmedText)g · \(item.countText)"
        }
    }

    /// 행에 보이는 열량. **1인분을 모르면 100g 기준으로 낸다** — 서버가 채운 200g
    /// 자리채움값으로 계산한 열량을 먼저 보여주면 그럴듯하게 틀린 수치가 각인된다.
    var displayKcal: Double {
        switch self {
        case let .food(food):
            NutritionMath.scale(
                per100g: food.kcalPer100g,
                quantityG: food.servingSizeKnown ? food.servingSizeG : 100
            )
        case let .frequent(item):
            item.kcal
        }
    }

    var kcalText: String { "\(Int(displayKcal.rounded()))kcal" }

    /// ⊕가 그대로 담을 항목. **1인분을 모르는 검색 결과는 nil이다** — 채워 넣을 기본 수량이
    /// 없으므로 화면이 상세 시트를 열어야 한다. 200g은 1800g과 달리 그럴듯해 보여서
    /// 사용자가 고치지 않는다.
    var quickAddItem: MealItemRequest? {
        switch self {
        case let .food(food):
            guard let quantity = NutritionMath.defaultQuantity(for: food) else { return nil }
            return NutritionMath.item(from: food, quantityG: quantity)
        case let .frequent(item):
            return NutritionMath.request(from: item)
        }
    }

    var canQuickAdd: Bool { quickAddItem != nil }
}
