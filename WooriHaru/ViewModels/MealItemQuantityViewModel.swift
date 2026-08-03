import Foundation

/// 저장된 끼니 항목의 **수량만** 고친다.
///
/// **g 전용이다** — `MealItem`에 1인분 정보(`servingSizeG`·`servingSizeKnown`)가 없다.
/// 「인분」을 쓰는 검색 상세 시트와 다른 점이 그것뿐이라 헷갈리기 쉬운데, 여기서 인분을
/// 흉내 내려면 없는 값을 지어내야 한다.
@MainActor
@Observable
final class MealItemQuantityViewModel {
    let item: MealItem
    /// 직접 입력도 되므로 문자열로 들고 있는다.
    var gramText: String

    private let original: MealItemRequest

    init(item: MealItem, original: MealItemRequest) {
        self.item = item
        self.original = original
        self.gramText = item.quantityG.trimmedText
    }

    /// 지금 보낼 수량. **`> 0`만으로는 부족하다** — `inf`도 `1e300`도 그 검사를 통과하고,
    /// 그 값으로 만든 열량이 `kcalText`의 `Int(...)`에서 트랩을 걸어 **앱이 그 자리에서
    /// 죽는다**(검색 상세 시트에서 실제로 겪어 고친 자리다). `isFinite`만 넣으면 `1e300`이
    /// 그대로 남는다.
    var quantityG: Double? {
        guard let value = Double(gramText),
              value.isFinite,
              value > 0,
              value <= DietInputLimits.maxQuantityG else { return nil }
        return value
    }

    /// 지금 수량으로 보낼 항목. **원본에서 새로 만든다** — 이미 만들어 둔 것을 고쳐 쓰면
    /// 조작할 때마다 환산 오차가 쌓인다.
    var edited: MealItemRequest? {
        quantityG.map { NutritionMath.rescaled(original, to: $0) }
    }

    /// **값이 그대로면 저장하지 않는다** — 저장 한 번에 LLM 호출 한 번이 나가므로, 열었다
    /// 그냥 닫는 사용자가 매번 비용을 내면 안 된다.
    var canSave: Bool {
        guard let quantityG else { return false }
        return quantityG != original.quantityG
    }

    func increase() { setGram((quantityG ?? 0) + GramStepper.step) }
    func decrease() { setGram((quantityG ?? GramStepper.minimum) - GramStepper.step) }
    func selectQuick(_ gram: Double) { setGram(gram) }

    private func setGram(_ value: Double) {
        gramText = max(GramStepper.minimum, value).trimmedText
    }

    var kcalText: String { "\(Int((edited?.kcal ?? 0).rounded()))kcal" }

    /// 6줄이다 — 포화지방·트랜스지방·콜레스테롤은 서버가 끼니에 저장하지 않는다.
    ///
    /// **`isEstimated`는 전부 기본값(false)이다** — 저장된 항목의 출처를 되짚을 방법이
    /// 서버에도 없다. 「원본 값」이 아니라 「모른다」는 뜻이다.
    var nutrientRows: [NutrientRow] {
        guard let edited else { return [] }
        return [
            NutrientRow(name: "탄수화물", valueText: formattedGram(edited.carbsG), isSub: false),
            NutrientRow(name: "당류", valueText: formattedGram(edited.sugarG), isSub: true),
            NutrientRow(name: "단백질", valueText: formattedGram(edited.proteinG), isSub: false),
            NutrientRow(name: "지방", valueText: formattedGram(edited.fatG), isSub: false),
            NutrientRow(name: "나트륨", valueText: "\(Int(edited.sodiumMg.rounded()).formatted())mg", isSub: false),
            NutrientRow(name: "식이섬유", valueText: formattedGram(edited.fiberG), isSub: false)
        ]
    }

    /// 환산 결과는 `30.000000000000004`처럼 나올 수 있다 — 소수 첫째 자리에서 끊는다.
    private func formattedGram(_ value: Double) -> String {
        "\(((value * 10).rounded() / 10).trimmedText)g"
    }
}
