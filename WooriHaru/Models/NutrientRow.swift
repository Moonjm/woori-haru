import Foundation

/// 상세 표의 영양소 한 줄. **두 시트가 같은 표를 그린다** — 검색 상세(`FoodDetailSheet`)와
/// 끼니 항목 수량 수정(`MealItemQuantitySheet`). 어느 한 뷰모델의 소유가 아니라 표시용
/// 모델이라 밖에 둔다.
struct NutrientRow: Identifiable, Equatable {
    let name: String
    let valueText: String
    /// 탄수화물 아래 당류처럼 한 단계 들여쓰는 줄
    let isSub: Bool
    /// 서버가 잔여 열량에서 계산해 채운 값. **틀렸다는 뜻이 아니라 출처가 다르다는 뜻이다.**
    ///
    /// **기본값이 `false`인 것은 「원본 값」이 아니라 「모른다」는 뜻이다** — 서버가 출처를
    /// 기록하는 것은 탄수화물·지방 둘뿐이고, 저장된 항목에는 그마저 없다.
    let isEstimated: Bool

    var id: String { name }

    init(name: String, valueText: String, isSub: Bool, isEstimated: Bool = false) {
        self.name = name
        self.valueText = valueText
        self.isSub = isSub
        self.isEstimated = isEstimated
    }
}
