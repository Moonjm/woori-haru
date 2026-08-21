import SwiftUI

/// 차트 원형이 받는 한 점. **`value`가 nil이면 기록 없음이다** — 자리는 지키되
/// 막대는 안 그린다.
struct ChartPoint: Identifiable, Equatable {
    let id: String
    let label: String
    let value: Decimal?
}

/// 값 → 화면 비율. **원형 넷이 같은 규칙을 쓴다** — 규칙을 원형마다 두면
/// 한쪽만 고쳤을 때 나란히 놓인 차트 둘의 높이가 서로 다른 뜻을 갖는다.
enum ChartScale {
    static func maxValue(_ points: [ChartPoint]) -> Decimal {
        points.compactMap(\.value).max() ?? 0
    }

    /// 0…1. 분모가 0이면 나누지 않고, 음수는 0으로 자른다.
    ///
    /// **나머지 스물다섯 장이 이 가드에 기댄다 — 고치지 않는다.** 부호가 뜻을 갖는 화면(#21)은
    /// 대신 `divergingRatio`/`divergingBarHeight`를 쓴다.
    static func ratio(_ value: Decimal?, max: Decimal) -> CGFloat {
        guard let value, max > 0, value > 0 else { return 0 }
        return CGFloat(truncating: (value / max) as NSDecimalNumber)
    }

    // MARK: - 발산형(음수 보존)

    /// 절댓값 기준 최댓값. **발산형 막대 전용이다** — `maxValue`는 부호 그대로 골라
    /// [-50, 10]이면 10을 고르지만, 발산형은 기준선에서 가장 멀리 뻗는 막대(-50)가
    /// 스케일을 정해야 한다. 값이 전부 0 이상인 나머지 카드에서는 결과가 `maxValue`와 같다.
    static func maxAbsValue(_ points: [ChartPoint]) -> Decimal {
        points.compactMap(\.value).map { abs($0) }.max() ?? 0
    }

    /// 0…1, 부호는 버리고 크기만 낸다. 방향은 `divergingBarHeight`가 다시 붙인다.
    static func divergingRatio(_ value: Decimal?, max: Decimal) -> CGFloat {
        guard let value, max > 0 else { return 0 }
        return CGFloat(truncating: (abs(value) / max) as NSDecimalNumber)
    }

    /// 발산형 막대의 **부호 있는** 픽셀 높이 — 양수는 위(+), 음수는 아래(-)로 뻗을 양이다.
    ///
    /// 셋이 갈린다. `nil`은 0을 내고 부르는 쪽이 트랙 색 자리표시자를 그린다(기록 없음).
    /// **정확히 0도 0을 낸다** — 재 봤는데 0이었다는 뜻이라 기준선에 머물러야 한다.
    /// 0이 아닌 작은 값만 부호를 지킨 채 최소 3pt를 받는다(「거의 없다」 ≠ 「0이었다」).
    static func divergingBarHeight(_ value: Decimal?, maxAbs: Decimal, halfHeight: CGFloat) -> CGFloat {
        guard let value, value != 0 else { return 0 }
        let magnitude = max(3, divergingRatio(value, max: maxAbs) * halfHeight)
        return value < 0 ? -magnitude : magnitude
    }

    // MARK: - 슬롯 기하

    /// 막대·라벨 사이 간격 — HStack과 x 계산이 같은 값을 봐야 선의 점이 자기 막대 위에 선다.
    /// 칸 수에 따라 좁아진다(60칸에서 5pt를 그대로 두면 막대 폭이 음수가 된다).
    static func slotSpacing(count: Int) -> CGFloat {
        switch count {
        case ..<16: 5
        case ..<32: 3
        default: 1
        }
    }

    private static func slotWidth(count: Int, width: CGFloat) -> CGFloat {
        (width - slotSpacing(count: count) * CGFloat(count - 1)) / CGFloat(count)
    }

    /// 슬롯 `index`의 중심 x — 선·점은 좌표를 직접 찍으므로 이 식과 맞아야 자기 막대 위에 선다.
    static func slotCenterX(index: Int, count: Int, width: CGFloat) -> CGFloat {
        // 점이 하나뿐이면 가운데에 찍는다.
        guard count > 1 else { return width / 2 }
        let slot = slotWidth(count: count, width: width)
        // 슬롯이 음수가 되면(카드가 아직 폭을 못 받은 첫 프레임 등) 가운데에 모은다.
        guard slot > 0 else { return width / 2 }
        return CGFloat(index) * (slot + slotSpacing(count: count)) + slot / 2
    }

    /// x를 슬롯 인덱스로 되돌린다 — **`slotCenterX`의 역이어야 한다.**
    static func slotIndex(atX x: CGFloat, count: Int, width: CGFloat) -> Int {
        guard count > 1 else { return 0 }
        let slot = slotWidth(count: count, width: width)
        // `slotCenterX`와 같은 갈림길을 탄다 — 슬롯이 음수면 나눠 봐야 범위 밖 인덱스만 나온다.
        guard slot > 0 else { return 0 }
        let raw = Int(((x - slot / 2) / (slot + slotSpacing(count: count))).rounded())
        // 양 끝 바깥을 눌러도 맨 앞·맨 뒤 슬롯이 받는다.
        return min(count - 1, max(0, raw))
    }
}

/// 강조·콜아웃이 가리킬 id를 고른다. 네 섹션이 공유하는 규칙 — 선택된 id가 지금 배열에
/// 있으면 쓰고, 없으면 기본값으로 떨어진다(기본값 고르는 식만 카드마다 다르다).
///
/// **`@State` 선택은 배열이 갈려도 남는다** — 기간 칩·새로고침으로 그 id가 사라질 수
/// 있는데, 존재 확인 없이 그대로 쓰면 강조·콜아웃이 조용히 사라진다.
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
        // `maxLabels`가 아니라 `maxLabels - 1`로 나눈다 — 60칸에서 분모를 12로 두면
        // 간격이 5로 나와 "여섯 달마다 하나"라는 뜻과 어긋난다.
        let stride = (count + maxLabels - 2) / (maxLabels - 1)
        return index % stride == 0
    }

    /// `"2026-08"` → `"8"`. 열두 칸에 「26.8」까지 넣으면 겹친다 — 어느 해인지는 콜아웃이 말한다.
    static func axis(_ yearMonth: String) -> String {
        guard let month = yearMonth.split(separator: "-").last,
              let value = Int(month) else { return yearMonth }
        return String(value)
    }
}
