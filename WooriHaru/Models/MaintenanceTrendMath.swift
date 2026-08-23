import Foundation

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
