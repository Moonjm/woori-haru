import Foundation

/// 고지서 항목 한 줄. **한 달 안에서 이름이 유일하다**는 고지서 표의 성질에 기대 `id`를 이름으로 둔다.
/// 편집 중에는 이름이 겹칠 수 있어 폼은 이 `id`를 쓰지 않는다(`MaintenanceItemDraft`).
struct MaintenanceBillItem: Codable, Equatable, Identifiable {
    let name: String
    let amount: Decimal
    var id: String { name }
}

/// 사용량 다섯 값. **전부 옵셔널이다** — 여름엔 난방 Gcal이 아예 안 찍히고, 사진이 잘리면
/// 어느 것이든 빠진다. `nil`(못 읽음)과 `0`(안 씀)은 다른 뜻이라 접지 않는다.
struct MaintenanceUsage: Codable, Equatable {
    let electricityKwh: Decimal?
    let waterM3: Decimal?
    let hotWaterM3: Decimal?
    let heatingGcal: Decimal?
    let foodKg: Decimal?
}

/// 저장된 한 달.
///
/// **금액이 `Decimal`인 이유.** 검수 화면이 항목 합계와 부과액을 견주는데, `Double`이면
/// 원 단위 합계에 없던 오차가 생겨 사람이 고칠 수 없는 「불일치」가 뜬다.
struct MaintenanceBill: Codable, Equatable, Identifiable {
    let yearMonth: String
    let dong: String?
    let ho: String?
    let areaM2: Decimal?
    let items: [MaintenanceBillItem]
    /// **옵셔널로 둔다** — 키가 통째로 빠진 한 달 때문에 목록 전체 디코딩이 깨지면 화면이 빈다.
    let usage: MaintenanceUsage?
    let chargedAmount: Decimal
    let discountTotal: Decimal
    let unpaidAmount: Decimal
    let unpaidLateFee: Decimal
    /// **실제로 내는 돈.** 목록·상세가 앞세우는 값이다(추이에는 이 값이 없다).
    let dueAmount: Decimal
    let dueDate: String?

    var id: String { yearMonth }
}

struct MaintenanceBillList: Codable, Equatable {
    let bills: [MaintenanceBill]
}

/// 사진에서 읽은 결과. **아무것도 저장되지 않았다** — 검수를 거쳐 확정한다.
///
/// `MaintenanceBill`을 품지 않고 필드를 펼쳐 갖는다. 서버가 평평하게 주기도 하고,
/// `yearMonth`가 여기서는 옵셔널이라 애초에 같은 타입이 될 수 없다.
struct MaintenanceRecognition: Codable, Equatable {
    /// 고지서 제목이 잘려 서버가 못 읽으면 nil이다. **검수 화면이 채운다.**
    let yearMonth: String?
    let dong: String?
    let ho: String?
    let areaM2: Decimal?
    let items: [MaintenanceBillItem]
    let usage: MaintenanceUsage?
    let chargedAmount: Decimal
    let discountTotal: Decimal
    let unpaidAmount: Decimal
    let unpaidLateFee: Decimal
    let dueAmount: Decimal
    let dueDate: String?
    /// 항목 합계가 부과액과 맞는가. false면 어딘가 잘못 읽혔다는 뜻이다.
    let sumMatched: Bool
    /// **이미 사용자용 한국어다** — 앱이 다시 쓰지 않고 그대로 띄운다.
    let warnings: [String]
}

/// 추이 한 달. **`dueAmount`가 없다** — 서버가 부과액만 준다. 통계 화면이 「부과액 기준」이라고 적는다.
struct MaintenanceTrendMonth: Codable, Equatable, Identifiable {
    let yearMonth: String
    let chargedAmount: Decimal
    let items: [MaintenanceBillItem]
    let usage: MaintenanceUsage?

    var id: String { yearMonth }
}

struct MaintenanceTrend: Codable, Equatable {
    let months: [MaintenanceTrendMonth]
}

struct MaintenanceBillItemRequest: Encodable, Equatable {
    /// 서버 한도 50자.
    let name: String
    let amount: Decimal
}

/// 저장·수정 요청. 둘이 같은 바디를 쓴다(`POST`는 새로, `PUT`은 그 달을 통째로 갈아 끼운다).
///
/// **`JSONEncoder`는 nil 프로퍼티의 키를 아예 뺀다.** 비운 사용량 칸을 0으로 채우지 않고
/// nil로 두는 이유가 이것이다 — 0으로 보내면 서버에 「0을 썼다」가 저장된다.
struct MaintenanceBillSaveRequest: Encodable, Equatable {
    let yearMonth: String
    /// 서버 `minItems: 1` — 빈 배열이면 400이다. 폼이 저장 버튼을 잠가 막는다.
    let items: [MaintenanceBillItemRequest]
    let chargedAmount: Decimal
    let dueAmount: Decimal
    let dong: String?
    let ho: String?
    let areaM2: Decimal?
    let usage: MaintenanceUsage?
    let discountTotal: Decimal
    let unpaidAmount: Decimal
    let unpaidLateFee: Decimal
    let dueDate: String?
}
