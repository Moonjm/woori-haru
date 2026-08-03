import Foundation

/// 상세 시트 — 수량·단위를 조절하고 담기 전에 영양소를 미리 본다.
///
/// **출처마다 환산 함수가 다르다.** 검색 결과는 100g당 값에서 계산하고
/// (`NutritionMath.item(from:quantityG:)`), 자주 드셨어요는 저장된 절대값을 비례 환산한다
/// (`NutritionMath.rescaled`). 그래서 수량이 바뀔 때마다 **출처에서 새로 만든다** — 이미
/// 만들어 둔 항목을 고쳐 쓰면 조작할 때마다 환산 오차가 쌓인다.
@MainActor
@Observable
final class FoodDetailViewModel {
    enum Unit: String, CaseIterable, Identifiable {
        case serving, gram

        var id: String { rawValue }
        var label: String {
            switch self {
            case .serving: "1인분"
            case .gram: "g"
            }
        }
    }

    struct NutrientRow: Identifiable, Equatable {
        let name: String
        let valueText: String
        /// 탄수화물 아래 당류처럼 한 단계 들여쓰는 줄
        let isSub: Bool

        var id: String { name }
    }

    /// g 모드 빠른 선택. **1인분을 모르는 항목은 지금 반드시 타이핑해야 하는데** 검색 결과의
    /// 상당수가 여기 해당한다(원재료 전부·가공식품 31%·음식 21%). 칩 셋이 그 타이핑을 없앤다.
    static let quickGrams: [Double] = [50, 100, 200]

    /// 인분 스테퍼 한 칸과 하한. 「반 그릇」이 실제로 가장 흔한 조정이다.
    static let servingStep: Double = 0.5
    static let minimumServings: Double = 0.5
    /// g 스테퍼 한 칸과 하한. **0으로 내려가면 영양소가 전부 0으로 굳는다.**
    ///
    /// 10g씩은 100g을 맞추는 데 열 번을 눌러야 해서 실제로는 타이핑하게 된다. 25g은 빠른
    /// 선택 칩(50·100·200)과 같은 격자라 칩으로 대강 맞추고 스테퍼로 다듬는 흐름이 된다.
    /// **더 잘게 넣고 싶으면 직접 타이핑할 수 있다** — 스테퍼 하한이 입력까지 막지는 않는다.
    static let gramStep: Double = 25
    static let minimumGram: Double = 25

    let source: FoodPickSource
    private(set) var unit: Unit
    private(set) var servings: Double = 1
    /// g 모드 수량. 직접 입력도 되므로 문자열로 들고 있는다.
    var gramText: String

    /// 「일일목표 N%」의 분모. 프로필이 없으면 nil이고 배지를 감춘다.
    private let targetKcal: Int?

    init(source: FoodPickSource, targetKcal: Int? = nil) {
        self.source = source
        self.targetKcal = targetKcal

        switch source {
        case let .food(food) where food.servingSizeKnown:
            unit = .serving
            gramText = food.servingSizeG.trimmedText
        case .food:
            // 1인분을 모르면 g 모드로 고정하고 수량을 비운다 — 서버가 채운 200g은
            // 그럴듯해 보여서 사용자가 고치지 않는다.
            unit = .gram
            gramText = ""
        case let .frequent(item):
            // 저장된 절대값뿐이라 1인분 개념이 없다. 지난번 수량으로 채운다.
            unit = .gram
            gramText = item.quantityG.trimmedText
        }
    }

    // MARK: - 단위

    /// 1인분 크기를 아는 항목만 단위를 고를 수 있다.
    var servingSizeG: Double? {
        guard case let .food(food) = source, food.servingSizeKnown else { return nil }
        return food.servingSizeG
    }

    /// **1인분을 모르면 단위 선택 자체를 감춘다.**
    var showsUnitPicker: Bool { servingSizeG != nil }

    /// **g 모드에서만 보인다** — 1인분을 아는 항목의 화면을 어지럽히지 않는다.
    var showsQuickGramChips: Bool { unit == .gram }

    /// 「1인분 = 250g」
    var servingSizeText: String? {
        servingSizeG.map { "1인분 = \($0.trimmedText)g" }
    }

    var servingSizeUnknownHint: String? {
        guard case let .food(food) = source, !food.servingSizeKnown else { return nil }
        return "1인분 정보 없음 — 드신 양을 넣어 주세요"
    }

    /// 「1.5인분」
    var servingsText: String { "\(servings.trimmedText)인분" }

    // MARK: - 수량

    /// 지금 담길 수량. 비어 있거나 0 이하면 nil이고 「추가하기」가 눌리지 않는다.
    var quantityG: Double? {
        switch unit {
        case .serving:
            guard let servingSizeG else { return nil }
            let quantity = servingSizeG * servings
            return quantity > 0 ? quantity : nil
        case .gram:
            // **`> 0`만으로는 부족하다.** `Double("inf")`도 `Double("1e309")`도 이 검사를
            // 통과하고, 그 값으로 만든 열량이 `kcalText`의 `Int(...)`에서 트랩을 걸어
            // **앱이 그 자리에서 죽는다.** 무한대만 막아도 `1e300`이 그대로 남는다.
            guard let quantity = Double(gramText),
                  quantity.isFinite,
                  quantity > 0,
                  quantity <= DietInputLimits.maxQuantityG else { return nil }
            return quantity
        }
    }

    func increaseServings() { servings += Self.servingStep }

    /// **0.5 아래로 내려가지 않는다** — 0이 되면 영양소가 전부 0으로 굳는다.
    func decreaseServings() {
        servings = max(Self.minimumServings, servings - Self.servingStep)
    }

    func increaseGram() { setGram((currentGram ?? 0) + Self.gramStep) }
    func decreaseGram() { setGram((currentGram ?? Self.minimumGram) - Self.gramStep) }
    func selectQuickGram(_ gram: Double) { setGram(gram) }

    private var currentGram: Double? { Double(gramText) }

    private func setGram(_ value: Double) {
        gramText = max(Self.minimumGram, value).trimmedText
    }

    /// 단위를 바꾼다. **숫자가 튀지 않게 지금 수량을 옮겨 담는다.** g에서 인분으로 갈 때는
    /// 가장 가까운 0.5 배수로 맞춘다 — 1인분 크기를 아는 항목에서만 가능하다.
    func setUnit(_ newUnit: Unit) {
        guard newUnit != unit, let servingSizeG else { return }
        switch newUnit {
        case .gram:
            gramText = (servingSizeG * servings).trimmedText
        case .serving:
            let gram = currentGram ?? servingSizeG
            servings = max(Self.minimumServings, ((gram / servingSizeG) * 2).rounded() / 2)
        }
        unit = newUnit
    }

    // MARK: - 담을 항목

    /// 지금 수량으로 담을 항목. **출처에 맞는 환산 함수를 쓴다.**
    var item: MealItemRequest? {
        guard let quantityG else { return nil }
        switch source {
        case let .food(food):
            return NutritionMath.item(from: food, quantityG: quantityG)
        case let .frequent(frequent):
            return NutritionMath.rescaled(NutritionMath.request(from: frequent), to: quantityG)
        }
    }

    var canAdd: Bool { item != nil }

    var kcalText: String { "\(Int((item?.kcal ?? 0).rounded()))kcal" }

    /// **프로필이 없으면 감춘다** — 목표가 없으면 비율에 의미가 없다.
    var dailyGoalPercentText: String? {
        guard let targetKcal, targetKcal > 0, let item else { return nil }
        return "일일목표 \(Int((item.kcal / Double(targetKcal) * 100).rounded()))%"
    }

    /// 참고 화면에 없는 **식이섬유**가 우리에게는 있어 한 줄이 더 붙는다.
    ///
    /// 포화지방·트랜스지방·콜레스테롤은 **검색 결과에만 있다** — `MealItemRequest`에 없고
    /// `Food`에 100g당으로만 있어서 `item`이 아니라 출처에서 직접 환산한다. 자주 드셨어요는
    /// 저장된 항목이라 값이 없고, **0으로 그리면 「없음」이 아니라 「진짜 0」으로 읽히므로**
    /// 줄 자체를 감춘다.
    var nutrientRows: [NutrientRow] {
        guard let item else { return [] }
        return [
            NutrientRow(name: "탄수화물", valueText: formattedGram(item.carbsG), isSub: false),
            NutrientRow(name: "당류", valueText: formattedGram(item.sugarG), isSub: true),
            NutrientRow(name: "단백질", valueText: formattedGram(item.proteinG), isSub: false),
            NutrientRow(name: "지방", valueText: formattedGram(item.fatG), isSub: false)
        ] + fatDetailRows + [
            NutrientRow(name: "나트륨", valueText: "\(Int(item.sodiumMg.rounded()).formatted())mg", isSub: false),
            NutrientRow(name: "식이섬유", valueText: formattedGram(item.fiberG), isSub: false)
        ]
    }

    /// 지방 아래 들여쓰는 두 줄과 콜레스테롤. 검색 결과에서만 나온다.
    ///
    /// **서버가 값 없는 칸을 0.0으로 채워 보내므로 「진짜 0」과 구분되지 않는다.** 검색
    /// 결과에서는 그대로 0으로 보여 준다 — 원본이 그렇게 왔다는 뜻이고, 그 이상은 알 수 없다.
    private var fatDetailRows: [NutrientRow] {
        guard case let .food(food) = source, let quantityG else { return [] }
        let cholesterol = NutritionMath.scale(per100g: food.cholesterolMgPer100g, quantityG: quantityG)
        return [
            NutrientRow(
                name: "포화지방",
                valueText: formattedGram(NutritionMath.scale(per100g: food.saturatedFatPer100g, quantityG: quantityG)),
                isSub: true
            ),
            NutrientRow(
                name: "트랜스지방",
                valueText: formattedGram(NutritionMath.scale(per100g: food.transFatPer100g, quantityG: quantityG)),
                isSub: true
            ),
            NutrientRow(
                name: "콜레스테롤",
                valueText: "\(Int(cholesterol.rounded()).formatted())mg",
                isSub: false
            )
        ]
    }

    /// 환산 결과는 `30.000000000000004`처럼 나올 수 있다 — 소수 첫째 자리에서 끊고
    /// 정수면 소수점을 뗀다(`Double.trimmedText`는 끊어 주지 않는다).
    private func formattedGram(_ value: Double) -> String {
        "\(((value * 10).rounded() / 10).trimmedText)g"
    }
}
