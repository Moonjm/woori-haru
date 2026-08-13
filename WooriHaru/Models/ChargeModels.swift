import Foundation

// MARK: - 응답

/// 충전 내역 목록 — 합계는 서버가 같은 필터로 SQL 집계한 값이다.
/// **목록을 순회해 다시 더하지 않는다** — 나중에 페이지네이션이 붙으면 조용히 틀린 합계가 된다.
struct ChargeListResponse: Codable {
    let summary: ChargeSummary
    let items: [ChargeItem]
}

struct ChargeSummary: Codable, Equatable {
    let count: Int
    let totalEnergyAddedKwh: Decimal?
    let totalCost: Decimal?

    static let empty = ChargeSummary(count: 0, totalEnergyAddedKwh: nil, totalCost: nil)
}

/// 목록 한 줄. 진행 중인 충전(`end_date IS NULL`)은 서버가 걸러서 내려주지 않는다.
struct ChargeItem: Codable, Identifiable, Hashable {
    let id: Int
    /// KST LocalDateTime 문자열("2026-08-11T22:14:00"). TeslaMate는 UTC로 저장하고 서버가 되돌린다.
    let startedAt: String
    let endedAt: String
    let durationMin: Int?
    /// 등록한 지오펜스 이름이 있으면 그것, 없으면 주소. 둘 다 없으면 nil.
    let locationName: String?
    let energyAddedKwh: Decimal?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let cost: Decimal?

    var startDate: Date { LedgerFormat.parseDateTime(startedAt) ?? .distantPast }
    var endDate: Date? { LedgerFormat.parseDateTime(endedAt) }
}

/// 상세. 목록은 `locationName` 하나로 합치지만 상세는 지오펜스 이름과 주소를 따로 낸다 —
/// 「집」이라고만 적힌 항목의 실제 주소를 확인하는 것이 상세를 여는 이유 중 하나다.
struct ChargeDetail: Codable, Identifiable, Equatable {
    let id: Int
    let startedAt: String
    let endedAt: String
    let durationMin: Int?
    let energyAddedKwh: Decimal?
    /// 벽에서 뽑아쓴 양. 구버전 데이터에서 nil일 수 있다.
    let energyUsedKwh: Decimal?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let startRatedRangeKm: Decimal?
    let endRatedRangeKm: Decimal?
    let outsideTempAvg: Decimal?
    let geofenceName: String?
    let address: String?
    let cost: Decimal?
    /// charges 샘플이 하나도 없으면 아래 다섯은 전부 nil이다 — 0이 아니다.
    let maxPowerKw: Int?
    let avgPowerKw: Decimal?
    let fastCharger: Bool?
    let fastChargerBrand: String?
    let fastChargerType: String?

    var startDate: Date { LedgerFormat.parseDateTime(startedAt) ?? .distantPast }
    var endDate: Date? { LedgerFormat.parseDateTime(endedAt) }

    /// 충전 효율(넣은 양 ÷ 뽑아쓴 양). **나눗셈은 앱이 한다** — 서버가 0·nil 처리를 정해 버리면
    /// 화면이 그것을 따라야 한다. 분모가 없거나 0이면 nil이다.
    var efficiency: Decimal? {
        guard let energyAddedKwh, let energyUsedKwh, energyUsedKwh > 0 else { return nil }
        return energyAddedKwh / energyUsedKwh
    }

    /// kWh당 단가. 금액이나 충전량이 없으면 nil이다.
    var costPerKwh: Decimal? {
        guard let cost, let energyAddedKwh, energyAddedKwh > 0 else { return nil }
        return cost / energyAddedKwh
    }

    /// 주행가능거리 증가분.
    var ratedRangeGainKm: Decimal? {
        guard let startRatedRangeKm, let endRatedRangeKm else { return nil }
        return endRatedRangeKm - startRatedRangeKm
    }
}

// MARK: - 요청

/// 금액은 비울 수 없다(`@NotNull`). 잘못 넣은 값은 다시 보내 바로잡는다 —
/// 서버에 되돌리기(null) 수단이 없다.
struct ChargeCostRequest: Encodable {
    let cost: Decimal
}

// MARK: - 표시 형식

/// 충전 화면 전용 숫자 표기. 없는 값은 0이 아니라 「—」다 —
/// 0kW로 충전했다는 뜻이 되면 없는 데이터와 구분되지 않는다.
enum ChargeFormat {
    static let placeholder = "—"

    /// `charging_processes.cost`가 `numeric(10,2)`라 서버가 8자리 초과를 400으로 돌려준다.
    static let maxCost: Decimal = 99_999_999

    private static func number(_ value: Decimal, fraction: Int, minFraction: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minFraction
        formatter.maximumFractionDigits = fraction
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// 입력 칸에 채워 넣을 값 — 자리구분 없이, 소수부가 0이면 떼어 낸다.
    /// 서버가 `numeric(10,2)`로 내려 준 "14100.00"을 그대로 두면 숫자 키패드로는 고칠 수 없다.
    static func plainNumber(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// 48.2 → "48.2kWh"
    static func energy(_ value: Decimal?) -> String {
        guard let value else { return placeholder }
        return "\(number(value, fraction: 1))kWh"
    }

    /// 14100 → "₩14,100". 금액이 없는 건은 「미입력」으로 드러낸다 — 이 화면은 금액을 매기러 오는 곳이다.
    static func cost(_ value: Decimal?) -> String {
        guard let value else { return "미입력" }
        return LedgerFormat.amount(value, currency: "KRW")
    }

    /// 257 → "4시간 17분", 45 → "45분"
    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return placeholder }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)분" }
        if rest == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(rest)분"
    }

    /// 48 → "48kW"
    static func power(_ value: Decimal?) -> String {
        guard let value else { return placeholder }
        return "\(number(value, fraction: 1))kW"
    }

    /// 18, 90 → "18% → 90%"
    static func batteryRange(_ start: Int?, _ end: Int?) -> String {
        guard let start, let end else { return placeholder }
        return "\(start)% → \(end)%"
    }

    /// 321.4 → "321km"
    static func distance(_ value: Decimal?) -> String {
        guard let value else { return placeholder }
        return "\(number(value, fraction: 0))km"
    }

    /// 26.5 → "26.5℃"
    static func temperature(_ value: Decimal?) -> String {
        guard let value else { return placeholder }
        return "\(number(value, fraction: 1))℃"
    }

    /// 0.9312 → "93%"
    static func percent(_ ratio: Decimal?) -> String {
        guard let ratio else { return placeholder }
        return "\(number(ratio * 100, fraction: 0))%"
    }

    /// 292.5 → "₩293/kWh"
    static func unitPrice(_ value: Decimal?) -> String {
        guard let value else { return placeholder }
        return "\(LedgerFormat.amount(value, currency: "KRW"))/kWh"
    }
}
