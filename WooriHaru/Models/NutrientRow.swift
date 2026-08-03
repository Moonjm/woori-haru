import Foundation

/// 상세 표의 영양소 한 줄. **두 시트가 같은 표를 그린다** — 검색 상세(`FoodDetailSheet`)와
/// 끼니 항목 수량 수정(`MealItemQuantitySheet`). 어느 한 뷰모델의 소유가 아니라 표시용
/// 모델이라 밖에 둔다.
struct NutrientRow: Identifiable, Equatable {
    let name: String
    let valueText: String
    /// 탄수화물 아래 당류처럼 한 단계 들여쓰는 줄
    let isSub: Bool

    var id: String { name }
}
