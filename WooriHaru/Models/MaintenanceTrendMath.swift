import SwiftUI

/// 앞 달과의 차이. `ratio`는 0…1이 아니라 **비율 그대로다**(0.0787 = 7.87%).
/// 앞 달이 0이면 nil — 0으로 나누지 않는다.
struct MaintenanceDelta: Equatable {
    let amount: Decimal
    let ratio: Decimal?
}

/// 관리비 파생 계산. **뷰도 뷰모델도 여기 말고 다른 데서 계산하지 않는다** —
/// 두 군데서 계산하면 테스트하는 값과 화면 값이 다른 코드가 된다.
enum MaintenanceTrendMath {
    /// `"2026-08"` → `"2026-07"`. **`Calendar`를 쓰지 않는다** — 기기 달력을 불교력으로 둔
    /// 기기에서 `2569-07`이 나온다. 서버로 나가는 값은 늘 ISO 그레고리력 문자열이라
    /// 문자열 산술이 오히려 정확하고 짧다.
    static func previousMonth(of yearMonth: String) -> String? {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        return month == 1
            ? String(format: "%04d-12", year - 1)
            : String(format: "%04d-%02d", year, month - 1)
    }

    /// `previousMonth(of:)`가 이미 하는 파싱을 이름으로만 다시 세운다 —
    /// 형식 검사기를 두 개 두면 한쪽만 고친 날 폼과 차트가 다른 연월을 받아들인다.
    static func isValidYearMonth(_ yearMonth: String) -> Bool {
        previousMonth(of: yearMonth) != nil
    }

    /// 목록에서 `index`번째 달과 **바로 다음 원소**를 견준다.
    ///
    /// **다음 원소가 바로 앞 달일 때만 낸다.** 목록은 최근 달부터라 다음 원소가 앞 달이지만,
    /// 등록을 건너뛴 달이 있으면 8월 다음이 6월이다 — 그 둘을 견주고 「전월 대비」라고
    /// 적으면 거짓이다.
    static func monthOverMonth(bills: [MaintenanceBill], at index: Int) -> MaintenanceDelta? {
        guard bills.indices.contains(index), bills.indices.contains(index + 1) else { return nil }
        let current = bills[index]
        let previous = bills[index + 1]
        guard previousMonth(of: current.yearMonth) == previous.yearMonth else { return nil }

        let amount = current.chargedAmount - previous.chargedAmount
        let ratio = previous.chargedAmount == 0 ? nil : amount / previous.chargedAmount
        return MaintenanceDelta(amount: amount, ratio: ratio)
    }
}

/// 전년 동월 대비 항목 하나의 증감. 양수면 올랐다.
struct MaintenanceItemDelta: Identifiable, Equatable {
    let name: String
    let delta: Decimal
    var id: String { name }
}

extension MaintenanceTrendMath {
    /// 사용량 다섯 종. 단위가 달라 한 차트에 겹쳐 그리지 않고 토글로 하나씩 본다.
    enum UsageKind: String, CaseIterable, Identifiable {
        case electricity, water, hotWater, heating, food

        var id: String { rawValue }

        var label: String {
            switch self {
            case .electricity: "전기"
            case .water: "수도"
            case .hotWater: "온수"
            case .heating: "난방"
            case .food: "음식물"
            }
        }

        var unit: String {
            switch self {
            case .electricity: "kWh"
            case .water, .hotWater: "m³"
            case .heating: "Gcal"
            case .food: "kg"
            }
        }

        func value(in usage: MaintenanceUsage?) -> Decimal? {
            switch self {
            case .electricity: usage?.electricityKwh
            case .water: usage?.waterM3
            case .hotWater: usage?.hotWaterM3
            case .heating: usage?.heatingGcal
            case .food: usage?.foodKg
            }
        }
    }

    /// **응답 순서를 믿지 않는다.** 차트 다섯 장이 전부 시간축이라 순서가 뒤집히면
    /// 전부 거짓말이 된다. 아래 함수들은 정렬된 배열을 받는 것을 전제한다 —
    /// 뷰모델이 받자마자 한 번만 정렬한다.
    static func sorted(_ months: [MaintenanceTrendMonth]) -> [MaintenanceTrendMonth] {
        months.sorted { $0.yearMonth < $1.yearMonth }
    }

    static func chargedPoints(_ months: [MaintenanceTrendMonth]) -> [ChartPoint] {
        months.map {
            ChartPoint(id: $0.yearMonth, label: MonthLabel.axis($0.yearMonth), value: $0.chargedAmount)
        }
    }

    /// **13개월 전체에서 모은다.** 고지서 표기가 바뀌거나 인식이 다르게 읽으면 이름이
    /// 갈리는데, 최근 달에만 있는 이름을 빼면 피커에서 사라진다.
    /// 정렬은 **금액 합이 큰 순** — 자주 큰 항목이 위에 온다.
    static func itemNames(_ months: [MaintenanceTrendMonth]) -> [String] {
        var totals: [String: Decimal] = [:]
        for month in months {
            for item in month.items {
                totals[item.name, default: 0] += item.amount
            }
        }
        // 합이 같으면 이름순 — 순서가 흔들리면 피커가 열 때마다 달라 보인다.
        return totals.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// **그 이름이 없는 달은 nil이다** — 0으로 채우면 「안 나왔다」가 「0원이었다」가 된다.
    static func itemPoints(_ months: [MaintenanceTrendMonth], name: String) -> [ChartPoint] {
        months.map { month in
            ChartPoint(
                id: month.yearMonth,
                label: MonthLabel.axis(month.yearMonth),
                value: month.items.first { $0.name == name }?.amount
            )
        }
    }

    static func usagePoints(_ months: [MaintenanceTrendMonth], kind: UsageKind) -> [ChartPoint] {
        months.map {
            ChartPoint(id: $0.yearMonth, label: MonthLabel.axis($0.yearMonth),
                       value: kind.value(in: $0.usage))
        }
    }

    /// 마지막 달과 그 전년 동월을 항목별로 견준다. 증감 절댓값이 큰 순 상위 `topCount`개.
    ///
    /// **전년 동월이 범위에 없으면 nil이다.** 없는 비교를 0으로 채우면 모든 항목이
    /// 「신설」로 보인다 — 화면은 nil일 때 카드 자리에 사유를 적는다.
    static func yearOverYearDeltas(
        _ months: [MaintenanceTrendMonth],
        topCount: Int = 8
    ) -> [MaintenanceItemDelta]? {
        guard let latest = months.last else { return nil }
        let parts = latest.yearMonth.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]) else { return nil }
        let lastYearKey = String(format: "%04d-%@", year - 1, String(parts[1]))
        // **13개월이면 첫 달이 그 달이지만 응답이 짧을 수 있다** — 실제로 있는지 찾아본다.
        guard let lastYear = months.first(where: { $0.yearMonth == lastYearKey }) else { return nil }

        var previousAmounts: [String: Decimal] = [:]
        for item in lastYear.items { previousAmounts[item.name, default: 0] += item.amount }

        var deltas: [MaintenanceItemDelta] = []
        var seen: Set<String> = []
        for item in latest.items {
            seen.insert(item.name)
            deltas.append(MaintenanceItemDelta(name: item.name,
                                               delta: item.amount - (previousAmounts[item.name] ?? 0)))
        }
        // 작년에는 있었는데 올해 사라진 항목도 증감이다 — 전액 감소로 남긴다.
        for (name, amount) in previousAmounts where !seen.contains(name) {
            deltas.append(MaintenanceItemDelta(name: name, delta: -amount))
        }

        return Array(
            deltas
                .filter { $0.delta != 0 }
                .sorted { (abs($0.delta), $1.name) > (abs($1.delta), $0.name) }
                .prefix(topCount)
        )
    }
}
