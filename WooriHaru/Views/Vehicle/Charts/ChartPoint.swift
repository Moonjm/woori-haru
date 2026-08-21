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
    ///
    /// **음수가 원리적으로 불가능한 나머지 스물다섯 장을 위한 가드다 — 고치지 않는다.**
    /// 거리·시간·건수·금액·비율은 전부 음수가 나올 수 없으니 이 가드가 곧 그 계약이다.
    /// 부호가 뜻을 갖는 화면(#21 「월별 대기 중 소모」)은 이 함수 대신 아래
    /// `divergingRatio`/`divergingBarHeight`를 쓴다 — 여기를 건드리면 스물다섯 장이
    /// 한꺼번에 회귀 위험을 진다.
    static func ratio(_ value: Decimal?, max: Decimal) -> CGFloat {
        guard let value, max > 0, value > 0 else { return 0 }
        return CGFloat(truncating: (value / max) as NSDecimalNumber)
    }

    // MARK: - 발산형(음수 보존)

    /// 절댓값 기준 최댓값. **발산형 막대 전용이다.** `maxValue`는 부호 그대로 `max()`를
    /// 써서 예를 들어 [-50, 10]이면 10을 고르는데, 발산형은 기준선에서 가장 멀리 뻗는
    /// 막대(여기서는 -50)가 위아래 스케일을 정해야 두 방향이 서로 비교된다.
    ///
    /// 값이 전부 0 이상인 나머지 스물다섯 장에서는 `abs(v) == v`이므로 이 함수의 결과가
    /// `maxValue`와 늘 같다 — 새 계산이 기존 카드를 조용히 바꾸지 않는다는 뜻이고,
    /// 그 사실 자체를 아래 테스트가 못박는다.
    static func maxAbsValue(_ points: [ChartPoint]) -> Decimal {
        points.compactMap(\.value).map { abs($0) }.max() ?? 0
    }

    /// 0…1, **부호는 버리고 크기만 낸다.** `ratio`와 달리 음수를 0으로 자르지 않고
    /// 절댓값을 쓴다 — 방향(위/아래)은 이 함수가 정하지 않고 `divergingBarHeight`가
    /// 부호를 다시 붙인다. 값이 0 이상일 때는 `abs(v) == v`라 `ratio`와 결과가 같다.
    static func divergingRatio(_ value: Decimal?, max: Decimal) -> CGFloat {
        guard let value, max > 0 else { return 0 }
        return CGFloat(truncating: (abs(value) / max) as NSDecimalNumber)
    }

    /// 발산형 막대의 **부호 있는** 픽셀 높이. 양수면 기준선 위로 뻗을 양(+), 음수면
    /// 기준선 아래로 뻗을 양(-)을 돌려준다 — 방향을 그리는 쪽의 `if/else`에 맡기지 않고
    /// 여기 한 곳의 계산으로 못박는다(그리는 쪽이 부호만 보고 위/아래 어느 절반에
    /// 그릴지 고르면 된다).
    ///
    /// 값이 있는데 크기가 0에 가까우면 부호는 지킨 채 최소 3pt를 보장한다 — 「거의
    /// 없다」와 「기록이 없다」를 갈라야 하는 이유는 `ratio`와 같다. 값이 nil이면 0이다
    /// (그 자리에 무엇을 그릴지는 그리는 쪽이 판단 — 이 저장소의 다른 월별 차트처럼
    /// 트랙 색 자리표시자를 쓴다).
    static func divergingBarHeight(_ value: Decimal?, maxAbs: Decimal, halfHeight: CGFloat) -> CGFloat {
        guard let value else { return 0 }
        let magnitude = max(3, divergingRatio(value, max: maxAbs) * halfHeight)
        return value < 0 ? -magnitude : magnitude
    }

    // MARK: - 슬롯 기하

    /// 막대·라벨 사이 간격. **HStack과 x 계산이 같은 값을 봐야 한다** —
    /// 두 곳에 따로 적으면 선의 점이 자기 막대에서 조용히 미끄러진다.
    ///
    /// **칸 수에 따라 좁아진다.** 12칸이면 5pt인데 60칸에서 그대로 두면 320pt 폭에서
    /// 간격만 295pt를 먹어 막대 폭이 음수가 된다.
    static func slotSpacing(count: Int) -> CGFloat {
        switch count {
        case ..<16: 5
        case ..<32: 3
        default: 1
        }
    }

    /// 슬롯 하나의 폭. 간격 `count - 1`개를 뺀 나머지를 `count`로 나눈다.
    private static func slotWidth(count: Int, width: CGFloat) -> CGFloat {
        (width - slotSpacing(count: count) * CGFloat(count - 1)) / CGFloat(count)
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
        return CGFloat(index) * (slot + slotSpacing(count: count)) + slot / 2
    }

    /// x를 슬롯 인덱스로 되돌린다. **`slotCenterX`의 역이어야 한다** —
    /// 그리는 식과 탭을 받는 식이 다르면 가까운 점 대신 옆 점이 잡힌다.
    static func slotIndex(atX x: CGFloat, count: Int, width: CGFloat) -> Int {
        guard count > 1 else { return 0 }
        let slot = slotWidth(count: count, width: width)
        // `slotCenterX`와 같은 갈림길을 탄다 — 슬롯이 음수면 그쪽은 전부 가운데에
        // 모이므로 여기서 나눠 봐야 범위 밖 인덱스만 나온다.
        guard slot > 0 else { return 0 }
        let raw = Int(((x - slot / 2) / (slot + slotSpacing(count: count))).rounded())
        // 양 끝 바깥을 눌러도 맨 앞·맨 뒤 슬롯이 받는다.
        return min(count - 1, max(0, raw))
    }
}

/// 강조·콜아웃이 가리킬 id를 고른다. **네 섹션(`StatsDriveSection`·`StatsChargeSection`·
/// `StatsParkSection`·`StatsPlaceSection`)이 공유한다** — 「선택된 id가 지금 배열에
/// 있으면 그것을 쓰고, 없으면 기본값으로 떨어진다」는 규칙 자체는 같고 **기본값을
/// 고르는 식만 다르다**(월별은 마지막 값 있는 점, 분포는 최댓값 칸, 순위는 1등).
///
/// **`@State`로 든 선택은 뷰가 다시 그려져도 살아남는다.** 기간 칩을 바꾸거나
/// 새로고침으로 상위 N 목록이 갈리면 그 id가 새 배열에 없을 수 있는데, 존재 여부를
/// 안 보고 그대로 돌려주면 강조는 「어느 막대도 아님」이 되어 카드 전체가 흐려지고
/// 콜아웃은 `nil`이 되어 사라진다. **원인은 안 가린다** — 기간이 바뀌었든, 다른
/// 이유로 그 id가 빠졌든 규칙은 하나다.
enum ChartAnchor {
    static func resolve(selected: String?, in ids: [String], fallback: () -> String?) -> String? {
        if let selected, ids.contains(selected) {
            return selected
        }
        return fallback()
    }
}

/// x축 월 라벨. **칸이 많으면 솎는다** — 60칸을 다 적으면 글자가 서로 덮는다.
enum MonthLabel {
    /// 라벨 하나가 최소 이만큼은 떨어져 있어야 읽힌다(9pt 글자 두 자리 기준).
    private static let maxLabels = 12

    static func shows(index: Int, count: Int) -> Bool {
        guard count > maxLabels else { return true }
        // `maxLabels`가 아니라 `maxLabels - 1`로 올림 나눗셈한다. 분모를 `maxLabels`로
        // 두면 60칸처럼 딱 떨어지는 칸 수에서 간격이 5(60÷12)로 나와 여섯 달마다 하나라는
        // 뜻과 어긋난다 — `maxLabels - 1`개의 간격으로 나눠야 6이 나온다.
        let stride = (count + maxLabels - 2) / (maxLabels - 1)
        return index % stride == 0
    }

    /// `"2026-08"` → `"8"`. **월 숫자만 적는다** — 열두 칸에 「26.8」까지 넣으면 겹친다.
    /// 어느 해인지는 콜아웃이 말한다.
    static func axis(_ yearMonth: String) -> String {
        guard let month = yearMonth.split(separator: "-").last,
              let value = Int(month) else { return yearMonth }
        return String(value)
    }
}
