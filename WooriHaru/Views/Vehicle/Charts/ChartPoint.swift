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

    // MARK: - 슬롯 기하

    /// 막대·라벨 사이 간격. **HStack과 x 계산이 같은 값을 봐야 한다** —
    /// 두 곳에 따로 적으면 선의 점이 자기 막대에서 조용히 미끄러진다.
    static let slotSpacing: CGFloat = 5

    /// 슬롯 하나의 폭. 간격 `count - 1`개를 뺀 나머지를 `count`로 나눈다.
    private static func slotWidth(count: Int, width: CGFloat) -> CGFloat {
        (width - slotSpacing * CGFloat(count - 1)) / CGFloat(count)
    }

    /// 슬롯 `index`의 중심 x. `count == 1`이면 가운데다.
    ///
    /// 막대는 `HStack(spacing:)`이 자리를 잡아 주지만 선·점은 좌표를 직접 찍는다 —
    /// 그 좌표가 이 식에서 나와야 선의 점이 자기 막대 위에 선다.
    static func slotCenterX(index: Int, count: Int, width: CGFloat) -> CGFloat {
        // 점이 하나뿐이면 왼쪽 끝에 붙는 대신 가운데에 찍는다.
        guard count > 1 else { return width / 2 }
        let slot = slotWidth(count: count, width: width)
        // 간격만으로 폭이 다 차면(카드가 아직 폭을 못 받은 첫 프레임, 점이 아주 많은 경우)
        // 슬롯이 음수가 된다 — 음수 x로 흩뿌리지 않고 가운데에 모은다.
        guard slot > 0 else { return width / 2 }
        return CGFloat(index) * (slot + slotSpacing) + slot / 2
    }

    /// x를 슬롯 인덱스로 되돌린다. **`slotCenterX`의 역이어야 한다** —
    /// 그리는 식과 탭을 받는 식이 다르면 가까운 점 대신 옆 점이 잡힌다.
    static func slotIndex(atX x: CGFloat, count: Int, width: CGFloat) -> Int {
        guard count > 1 else { return 0 }
        let slot = slotWidth(count: count, width: width)
        // `slotCenterX`와 같은 갈림길을 탄다 — 슬롯이 음수면 그쪽은 전부 가운데에
        // 모이므로 여기서 나눠 봐야 범위 밖 인덱스만 나온다.
        guard slot > 0 else { return 0 }
        let raw = Int(((x - slot / 2) / (slot + slotSpacing)).rounded())
        // 양 끝 바깥을 눌러도 맨 앞·맨 뒤 슬롯이 받는다.
        return min(count - 1, max(0, raw))
    }
}
