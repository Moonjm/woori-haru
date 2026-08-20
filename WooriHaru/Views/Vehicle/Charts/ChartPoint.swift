import SwiftUI

/// 차트 원형이 받는 한 점. **도메인 타입을 원형이 알지 않게 하는 경계다** —
/// 원형이 `VehiclePeriod`나 `TemperatureBucket`을 알면 그 원형은 한 곳에서만 쓰인다.
/// 각 카드가 자기 타입을 이 배열로 바꿔 넘긴다.
///
/// **`value`가 옵셔널인 것이 이 타입의 요점이다.** 「0은 안 탔다, nil은 기록이 없다」는
/// `VehiclePeriod`의 관례가 차트에서도 유지돼야 한다 — 기록이 없는 달을 건너뛰면
/// 계절 비교가 어긋나므로 자리는 지키되 막대를 안 그린다.
struct ChartPoint: Identifiable, Equatable {
    /// 고유 키. 월별 차트에서는 `yearMonth`("2026-08")다.
    let id: String
    /// x축에 적는 짧은 글자. 월별 차트에서는 달 번호("8")다.
    let label: String
    let value: Decimal?
}

/// 값 → 화면 비율. **원형 넷이 같은 규칙을 쓴다** — 규칙을 원형마다 두면
/// 한쪽만 고쳤을 때 나란히 놓인 차트 둘의 높이가 서로 다른 뜻을 갖는다.
enum ChartScale {
    /// 기록이 있는 점 중 최댓값. 하나도 없으면 0이다.
    static func maxValue(_ points: [ChartPoint]) -> Decimal {
        points.compactMap(\.value).max() ?? 0
    }

    /// 0…1. **분모가 0이면 나누지 않고, 음수는 0으로 자른다.**
    static func ratio(_ value: Decimal?, max: Decimal) -> CGFloat {
        guard let value, max > 0, value > 0 else { return 0 }
        return CGFloat(truncating: (value / max) as NSDecimalNumber)
    }
}
