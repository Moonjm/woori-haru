import Foundation

/// **100g당 값 → 수량 기준 환산을 여기 한 곳에 모은다.** 서버 `Food.nutritionFor`와 같은 식이며
/// (`per100g × quantityG / 100`, 반올림 없음), 다르면 저장된 수치가 조용히 틀린다.
///
/// 환산 대상은 **7개 전부**다 — 열량·탄단지에 더해 당류·나트륨·식이섬유까지. 넷만 채워 보내면
/// 서버가 나머지를 `0.0`으로 받아 말없이 저장하고, 증상은 「나트륨이 매일 기준 이하」로만 나타난다.
enum NutritionMath {
    static func scale(per100g: Double, quantityG: Double) -> Double {
        per100g * (quantityG / 100.0)
    }

    /// 식품DB 검색 결과를 수량만큼 담는다.
    static func item(from food: Food, quantityG: Double) -> MealItemRequest {
        MealItemRequest(
            foodName: food.name,
            foodCode: food.code,
            quantityG: quantityG,
            kcal: scale(per100g: food.kcalPer100g, quantityG: quantityG),
            carbsG: scale(per100g: food.carbsPer100g, quantityG: quantityG),
            proteinG: scale(per100g: food.proteinPer100g, quantityG: quantityG),
            fatG: scale(per100g: food.fatPer100g, quantityG: quantityG),
            sugarG: scale(per100g: food.sugarPer100g, quantityG: quantityG),
            sodiumMg: scale(per100g: food.sodiumMgPer100g, quantityG: quantityG),
            fiberG: scale(per100g: food.fiberPer100g, quantityG: quantityG),
            source: .dbMatched
        )
    }

    /// 확인 화면에서 수량을 고칠 때. 100g당 값이 남아 있지 않으므로 **현재 수량 대비 비례**로 옮긴다.
    /// 원래 수량이 0이면 비율을 만들 수 없어 수량만 바꾼다(0으로 나누지 않는다).
    static func rescaled(_ item: MealItemRequest, to quantityG: Double) -> MealItemRequest {
        guard item.quantityG > 0 else {
            var changed = item
            changed.quantityG = quantityG
            return changed
        }
        let ratio = quantityG / item.quantityG
        var changed = item
        changed.quantityG = quantityG
        changed.kcal = item.kcal * ratio
        changed.carbsG = item.carbsG * ratio
        changed.proteinG = item.proteinG * ratio
        changed.fatG = item.fatG * ratio
        changed.sugarG = item.sugarG * ratio
        changed.sodiumMg = item.sodiumMg * ratio
        changed.fiberG = item.fiberG * ratio
        return changed
    }

    /// 검색 결과를 담을 때 채워 줄 기본 수량. **`servingSizeKnown`이 false면 없다** —
    /// 서버가 채운 200g 자리채움값이라 그대로 넣으면 그럴듯하게 틀린 수치가 기록된다.
    static func defaultQuantity(for food: Food) -> Double? {
        food.servingSizeKnown ? food.servingSizeG : nil
    }

    /// 인식 결과를 확정 요청으로 옮긴다. **다시 계산하지 않는다** — 서버가 이미 환산한 값이다.
    static func request(from item: AnalyzedItem) -> MealItemRequest {
        MealItemRequest(
            foodName: item.foodName,
            foodCode: item.foodCode,
            quantityG: item.quantityG,
            kcal: item.kcal,
            carbsG: item.carbsG,
            proteinG: item.proteinG,
            fatG: item.fatG,
            sugarG: item.sugarG,
            sodiumMg: item.sodiumMg,
            fiberG: item.fiberG,
            source: item.source
        )
    }

    /// 자주 먹는 음식은 수량과 영양소가 딸려 오므로 **탭 한 번으로 그대로 담긴다.**
    static func request(from item: FrequentItem) -> MealItemRequest {
        MealItemRequest(
            foodName: item.foodName,
            foodCode: item.foodCode,
            quantityG: item.quantityG,
            kcal: item.kcal,
            carbsG: item.carbsG,
            proteinG: item.proteinG,
            fatG: item.fatG,
            sugarG: item.sugarG,
            sodiumMg: item.sodiumMg,
            fiberG: item.fiberG,
            source: item.source
        )
    }

    /// 직접 입력 — 식품DB에도 없고 포장지 영양성분표를 보고 넣는 최후 수단.
    /// **`foodCode`는 빈 문자열이 아니라 `nil`이고 `source`는 `.llmEstimated`다**(식품DB 값이 아니다).
    static func manualItem(
        name: String,
        quantityG: Double,
        kcal: Double,
        carbsG: Double,
        proteinG: Double,
        fatG: Double,
        sugarG: Double,
        sodiumMg: Double,
        fiberG: Double
    ) -> MealItemRequest {
        MealItemRequest(
            foodName: name,
            foodCode: nil,
            quantityG: quantityG,
            kcal: kcal,
            carbsG: carbsG,
            proteinG: proteinG,
            fatG: fatG,
            sugarG: sugarG,
            sodiumMg: sodiumMg,
            fiberG: fiberG,
            source: .llmEstimated
        )
    }
}
