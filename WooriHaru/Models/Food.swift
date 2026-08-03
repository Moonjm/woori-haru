import Foundation

enum FoodDataset: String, Codable, Hashable {
    case dish = "DISH"
    case raw = "RAW"
    case processed = "PROCESSED"
    /// 서버가 새 데이터셋을 늘렸을 때 **검색 결과 전체가 날아가지 않게** 흡수하는 값.
    /// 배지는 달지 않는다 — 이름을 모르니 지어내지 않는다.
    ///
    /// **쿼리로 보내면 안 된다**(`DietService.searchFoods`) — 서버가 enum 변환에 실패해 400을 준다.
    case unknown

    /// **모르는 값을 던지지 않고 삼킨다.** `[Food]` 배열은 한 건만 실패해도 전체가 실패하므로,
    /// 서버가 `USER` 같은 값을 늘리는 날 검색 화면이 통째로 빈 목록이 된다.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodDataset(rawValue: raw) ?? .unknown
    }

    /// 목록에서 구분해 보여줄 배지 문구. 조리 음식은 기본값이라 배지를 달지 않는다.
    var badge: String? {
        switch self {
        case .dish: nil
        case .raw: "원재료"
        case .processed: "가공식품"
        case .unknown: nil
        }
    }
}

/// `GET /diet/foods` 결과. 값은 전부 **100g당**이라 담을 때 `NutritionMath`로 환산해야 한다.
struct Food: Codable, Hashable, Identifiable {
    let code: String
    let name: String
    /// 프랜차이즈·제조사. 없는 행이 더 많다(음식 68%, 원재료 100%).
    ///
    /// **식품명에 브랜드가 없다** — 도미노피자 318건이 전부
    /// `피자_뉴욕 오리진 피자 오리지널 (L)` 같은 이름이다. 이 값이 없으면 「도미노」로
    /// 검색해 나온 결과를 보고도 왜 나왔는지 알 수 없다.
    let maker: String?
    let dataset: FoodDataset
    let servingSizeG: Double
    /// **false면 `servingSizeG`(200g)는 서버가 채운 자리채움값이다** — 기본 수량으로 쓰면
    /// 달걀 한 개가 4배로 담긴다. 검색 결과 중 원재료 전부·가공식품 31%·음식 21%가 여기 걸린다.
    let servingSizeKnown: Bool
    let kcalPer100g: Double
    let carbsPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let sugarPer100g: Double
    let sodiumMgPer100g: Double
    let fiberPer100g: Double
    /// **상세 시트 표시 전용이다.** 서버가 끼니에 저장하지 않으므로 담은 뒤에는 사라진다 —
    /// 자주 드셨어요·사진 인식 항목에는 이 값이 없다. 값이 없는 칸은 서버가 0.0으로 채운다.
    let saturatedFatPer100g: Double
    let transFatPer100g: Double
    let cholesterolMgPer100g: Double

    /// 서버가 잔여 열량에서 계산해 채운 필드(`["carbs","fat"]`). 비었으면 전부 원본 값이다.
    ///
    /// 프랜차이즈 영양성분표는 어린이 기호식품 의무표시 항목(열량·단백질·나트륨·당류·
    /// 포화지방)만 싣는다. 탄수화물·총지방이 아예 없어서 서버가 같은 분류의 음식에서
    /// 탄:지 비율을 빌려 채운다.
    ///
    /// **옵셔널이다** — non-optional로 받으면 서버 배포 전에 앱이 나가는 순간 검색 결과
    /// 배열 전체가 디코딩에 실패한다. 빈 배열과 nil을 화면에서 구분하지 않는다(둘 다
    /// 「추정 없음」이다).
    let estimatedFields: [String]?

    /// 코드는 데이터셋 안에서만 유일하다.
    ///
    /// **알려진 한계:** `.unknown`끼리는 `"unknown-"`을 공유한다. 서버가 데이터셋을 둘 이상
    /// 늘리고 그 둘에 같은 `code`가 있어야 겹치므로, 그때 가서 원본 문자열을 들고 있으면 된다.
    var id: String { "\(dataset.rawValue)-\(code)" }
}
