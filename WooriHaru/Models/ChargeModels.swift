import Foundation

// MARK: - 응답

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
    /// 벽에서 뽑아쓴 양 — 단가의 분모다. 구버전 데이터·구버전 서버에서 nil일 수 있다.
    let energyUsedKwh: Decimal?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let cost: Decimal?

    var startDate: Date { LedgerFormat.parseDateTime(startedAt) ?? .distantPast }
    var endDate: Date? { LedgerFormat.parseDateTime(endedAt) }

    /// kWh당 단가. 분모가 없거나 0이면 nil이다. 자세한 기준은 `ChargeDetail.costPerKwh` 참고.
    var costPerKwh: Decimal? { ChargeMath.costPerKwh(cost: cost, energyUsedKwh: energyUsedKwh) }
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

    var costPerKwh: Decimal? { ChargeMath.costPerKwh(cost: cost, energyUsedKwh: energyUsedKwh) }

    /// 주행가능거리 증가분.
    var ratedRangeGainKm: Decimal? {
        guard let startRatedRangeKm, let endRatedRangeKm else { return nil }
        return endRatedRangeKm - startRatedRangeKm
    }
}

// MARK: - 계산

/// 목록과 상세가 같은 값을 같은 뜻으로 내야 하는 계산. **나눗셈은 서버가 아니라 여기서 한다** —
/// 분모가 0이거나 nil일 때의 처리를 서버가 정해 버리면 화면이 그것을 따라야 한다.
enum ChargeMath {
    /// kWh당 단가. **분모는 벽에서 뽑아쓴 양(`energyUsedKwh`)이다** — 요금은 차에 들어간 양이
    /// 아니라 충전기에서 나간 양으로 매겨진다. 들어간 양으로 나누면 충전 손실만큼 단가가
    /// 실제보다 싸 보인다.
    ///
    /// 구버전 데이터·구버전 서버에는 사용 전력이 없다. 그때는 **충전량으로 갈음하지 않고 nil이다** —
    /// 기준이 다른 값을 같은 자리에 섞으면 두 건을 비교할 수 없다.
    static func costPerKwh(cost: Decimal?, energyUsedKwh: Decimal?) -> Decimal? {
        guard let cost, let energyUsedKwh, energyUsedKwh > 0 else { return nil }
        return cost / energyUsedKwh
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

    /// 금액이 가질 수 있는 소수 자릿수 — 서버 `@Digits(fraction = 2)`이자 컬럼의 `numeric(10,2)`다.
    static let costFractionDigits = 2

    /// 입력 칸에 채워 넣을 값 — 자리구분 없이, 소수부가 0이면 떼어 낸다.
    /// 서버가 `numeric(10,2)`로 내려 준 "14100.00"을 그대로 두면 숫자 키패드로는 고칠 수 없다.
    ///
    /// **로케일을 고정한다.** 기기 로케일을 따르면 소수 구분자가 쉼표인 지역에서 "14100,5"가
    /// 채워지는데, `parseCost`는 그 쉼표를 자리구분으로 보고 지워 141005로 읽는다 —
    /// 열어서 저장만 눌러도 금액이 10배가 된다.
    static func plainNumber(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = posix
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = costFractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// 입력 칸의 글자를 금액으로 읽는다. `plainNumber`와 **같은 로케일로** 읽어야 한다.
    ///
    /// 다음은 전부 nil이다 — 저장 버튼을 살려 두면 서버가 400으로 돌려줄 뿐이다.
    /// - 비었거나 숫자가 아님
    /// - 음수
    /// - 상한(99,999,999.99, 서버 `@Digits(integer = 8)`) 초과
    /// - 소수 셋째 자리 이상 (서버 `@Digits(fraction = 2)`)
    static func parseCost(_ text: String) -> Decimal? {
        let trimmed = text
            .replacingOccurrences(of: ",", with: "") // 사용자가 넣은 자리구분
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: posix),
              value >= 0,
              value <= maxCost,
              hasAllowedScale(value)
        else { return nil }
        return value
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// 소수 자릿수가 두 자리 이하인지 — 반올림한 값이 원래 값과 같은지로 본다.
    private static func hasAllowedScale(_ value: Decimal) -> Bool {
        var original = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, costFractionDigits, .plain)
        return rounded == value
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

    /// 기간 합계 금액. **「미입력」을 쓰지 않는다** — 그것은 충전 1건의 금액이 비었다는 뜻이라
    /// 합계 자리에 놓으면 「아직 못 받았다」·「충전이 없다」와 구분되지 않는다.
    ///
    /// - `loaded == false`: 아직 못 받았다 → 「—」
    /// - 충전 0건: 쓴 돈이 없다 → 「₩0」
    /// - 충전은 있는데 합계가 없다(전 건의 금액이 빔): 그 사실을 그대로 → 「금액 없음」
    static func summaryTotal(_ total: Decimal?, count: Int, loaded: Bool) -> String {
        guard loaded else { return placeholder }
        if let total { return LedgerFormat.amount(total, currency: "KRW") }
        return count == 0 ? LedgerFormat.amount(0, currency: "KRW") : "금액 없음"
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

    /// 292.5 → "₩293/kWh". 반올림은 `VehicleMath.rounded`를 거친다 — 누적 카드와 같은 규칙이라
    /// 정확히 .5에서 두 화면이 갈리지 않는다.
    static func unitPrice(_ value: Decimal?) -> String {
        guard let value else { return placeholder }
        return "\(LedgerFormat.amount(VehicleMath.rounded(value), currency: "KRW"))/kWh"
    }
}
