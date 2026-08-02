import Foundation

enum FoodDataset: String, Codable, Hashable {
    case dish = "DISH"
    case raw = "RAW"
    case processed = "PROCESSED"

    /// 목록에서 구분해 보여줄 배지 문구. 조리 음식은 기본값이라 배지를 달지 않는다.
    var badge: String? {
        switch self {
        case .dish: nil
        case .raw: "원재료"
        case .processed: "가공식품"
        }
    }
}

/// `GET /diet/foods` 결과. 값은 전부 **100g당**이라 담을 때 `NutritionMath`로 환산해야 한다.
struct Food: Codable, Hashable, Identifiable {
    let code: String
    let name: String
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

    /// 코드는 데이터셋 안에서만 유일하다.
    var id: String { "\(dataset.rawValue)-\(code)" }
}
