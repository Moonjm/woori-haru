import Foundation

// MARK: - 응답

/// 월 요약 — 그 달 숫자·지난달·12개월 추이·그 달 충전 목록이 한 응답에 온다.
/// 화면이 하나라 호출도 하나다.
struct VehicleSummaryResponse: Codable {
    let month: VehiclePeriod
    /// 직전 달. 그 달에 아무것도 없으면 필드가 전부 nil인 항목이 온다.
    let previous: VehiclePeriod?
    /// 기준 달 포함 거슬러 12개월. 기록이 없는 달도 자리를 지킨다.
    let trend: [VehiclePeriod]
    let charges: [ChargeItem]
}

/// 한 달치 집계. **0과 nil은 다르다** — 0은 「안 탔다」, nil은 「기록이 없다」다.
struct VehiclePeriod: Codable, Identifiable, Equatable {
    let yearMonth: String
    let distanceKm: Decimal?
    let drivingMin: Int?
    let driveCount: Int?
    let energyAddedKwh: Decimal?
    let energyUsedKwh: Decimal?
    let cost: Decimal?
    let chargeCount: Int?

    var id: String { yearMonth }
    /// "2026-08" → 8
    var monthNumber: Int { Int(yearMonth.suffix(2)) ?? 0 }

    /// km당 비용 — 추이 차트와 지표 줄이 같은 값을 쓴다.
    var costPerKm: Decimal? { VehicleMath.costPerKm(cost: cost, distanceKm: distanceKm) }
    /// 전비(km/kWh) — 1kWh로 몇 km를 갔나. 국내 제원표가 쓰는 단위다.
    var efficiency: Decimal? {
        VehicleMath.kmPerKwh(energyAddedKwh: energyAddedKwh, distanceKm: distanceKm)
    }
}

/// 차량 현재 상태. **모든 값은 `asOf` 시점의 것이다** — 주차 중에는 몇 시간 전 값일 수 있다.
struct VehicleStatus: Codable, Equatable {
    /// 위치 기록 자체가 없으면 nil이다. 그때는 다른 값도 볼 것이 없다.
    let asOf: String?
    /// TeslaMate 원문(`online`·`asleep`·`offline`·`driving`·`charging`).
    let state: String?
    let stateSince: String?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let ratedRangeKm: Decimal?
    let estRangeKm: Decimal?
    let odometerKm: Decimal?
    let insideTempC: Decimal?
    let outsideTempC: Decimal?
    let climateOn: Bool?
    let locationName: String?
    let tpmsBar: TpmsBar?

    struct TpmsBar: Codable, Equatable {
        let fl: Decimal?
        let fr: Decimal?
        let rl: Decimal?
        let rr: Decimal?
    }

    /// **KST로 읽는다.** 서버는 KST 벽시계 값을 주는데, 이 값만은 「지금」과 빼서 경과 시간을 내므로
    /// 기기 시간대로 읽으면 시차만큼 어긋난다 — 한국 밖에서는 늘 「방금 기준」이 되거나
    /// 멀쩡한 값이 오래된 것으로 표시된다. 화면에 글자로만 그리는 다른 시각들과 다른 점이다.
    var asOfDate: Date? { asOf.flatMap(VehicleFormat.parseKST) }
}

/// 금액이 빈 충전 — 기간과 무관하게 최신순.
struct MissingCostResponse: Codable {
    /// `limit`과 무관한 전체 개수. 배지에 쓴다.
    let totalCount: Int
    let items: [ChargeItem]
}

// MARK: - 계산

/// 목록·요약·상태가 같은 값을 같은 뜻으로 내야 하는 계산.
/// 분모가 없거나 0이면 결과가 nil이다 — 서버가 그 처리를 정해 버리면 화면이 따라야 한다.
enum VehicleMath {
    static func costPerKm(cost: Decimal?, distanceKm: Decimal?) -> Decimal? {
        guard let cost, let distanceKm, distanceKm > 0 else { return nil }
        return cost / distanceKm
    }

    /// 전비 — 1kWh로 간 거리(km/kWh). **분모가 충전량이다**(차에 들어간 양, 벽에서 뽑아쓴 양은
    /// 지갑 쪽 수치다). kWh/100km 대신 이 단위를 쓰는 이유는 국내 제원표와 같아 읽는 사람이
    /// 자기 차 숫자와 바로 견줄 수 있어서다.
    static func kmPerKwh(energyAddedKwh: Decimal?, distanceKm: Decimal?) -> Decimal? {
        guard let energyAddedKwh, energyAddedKwh > 0, let distanceKm else { return nil }
        return distanceKm / energyAddedKwh
    }

    /// 증감 %. 지난달이 없거나 0이면 nil이다 — 0에서 늘었다고 말할 수 없다.
    static func deltaPercent(current: Decimal?, previous: Decimal?) -> Int? {
        guard let current, let previous, previous > 0 else { return nil }
        return NSDecimalNumber(decimal: rounded((current - previous) / previous * 100)).intValue
    }

    static func psi(fromBar bar: Decimal?) -> Decimal? {
        guard let bar else { return nil }
        return bar * Decimal(string: "14.5038")!
    }

    /// 등록 화면의 제안값 — 직전에 저장한 단가 × 이 건의 사용 전력. 원 단위로 반올림한다.
    static func suggestedCost(unitPrice: Decimal?, energyUsedKwh: Decimal?) -> Decimal? {
        guard let unitPrice, let energyUsedKwh, energyUsedKwh > 0 else { return nil }
        return rounded(unitPrice * energyUsedKwh)
    }

    /// 기준 시각이 몇 분 전인지. 시계가 어긋나 미래 값이 와도 음수를 내지 않는다.
    static func minutesAgo(from date: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 60))
    }

    /// **`VehicleHealthModels.swift`의 확장도 쓴다** — 그래서 private가 아니다.
    /// 반올림 규칙을 두 벌 두면 잔존율과 열화가 화면에서 101%가 되는 달이 나온다.
    static func rounded(_ value: Decimal) -> Decimal {
        var original = value
        var result = Decimal()
        NSDecimalRound(&result, &original, 0, .plain)
        return result
    }
}

// MARK: - 표기

/// 차량 화면 전용 표기. 없는 값은 `ChargeFormat.placeholder`("—")로 통일한다.
enum VehicleFormat {
    /// 서버 시각 문자열을 **KST로** 읽는다. 경과 시간을 재는 값에만 쓴다 —
    /// 글자로만 그리는 시각은 기기 시간대로 읽고 그대로 되돌려 쓰는 `LedgerFormat` 쪽이 맞다.
    private static let kstFormatters: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss.SSS",
                                                         "yyyy-MM-dd'T'HH:mm:ss",
                                                         "yyyy-MM-dd'T'HH:mm"].map { pattern in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.dateFormat = pattern
        return formatter
    }

    static func parseKST(_ raw: String) -> Date? {
        for formatter in kstFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    /// **`VehicleHealthModels.swift`의 확장도 쓴다** — 그래서 private가 아니다.
    /// `minFraction`은 기본 0이라 기존 호출부(`distance`·`odometer`·`againstBaseline` 등)는
    /// 그대로다 — 소수점 끝자리 0을 지금처럼 잘라낸다. `efficiency`만 1을 넘겨 예외를 둔다.
    static func number(_ value: Decimal, fraction: Int, minFraction: Int = 0, grouping: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.maximumFractionDigits = fraction
        formatter.minimumFractionDigits = minFraction
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// 842.3 → "842km"
    static func distance(_ km: Decimal?) -> String {
        guard let km else { return ChargeFormat.placeholder }
        return "\(number(km, fraction: 0))km"
    }

    /// 41203.8 → "41,204km"
    static func odometer(_ km: Decimal?) -> String { distance(km) }

    /// 4.518… → "4.5km/kWh", 6.0349… → "6.0km/kWh".
    /// **소수 한 자리를 늘 낸다** — 전비는 여러 값을 나란히 견주는 자리에 쓰이는데
    /// 「6」과 「6.7」이 한 열에 섞이면 자릿수가 흔들려 읽기 어렵다. 측정값이라 `5.0`이 `5`보다 옳기도 하다.
    static func efficiency(_ value: Decimal?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return "\(number(value, fraction: 1, minFraction: 1))km/kWh"
    }

    /// 62.09… → "₩62/km"
    static func costPerKm(_ value: Decimal?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return "\(LedgerFormat.amount(value, currency: "KRW"))/km"
    }

    /// 2.9 → "42psi". **화면에는 psi만 낸다** — 서버가 주는 bar는 TeslaMate의 저장 단위일 뿐,
    /// 타이어에 넣을 때 쓰는 단위도 차 문틀의 권장값도 psi다.
    ///
    /// bar→psi 변환만 하고 나머지는 `VehicleHealthModels.psiText(_:)`에 그대로 맡긴다 —
    /// 반올림-후-표기 규칙을 두 곳에 따로 두면 한쪽만 고쳤을 때 표기와 판정이 갈린다
    /// (`tireStatus(bar:)`가 겪었던 그 불일치). 임의로 되돌려 두 벌로 쪼개지 말 것.
    static func pressurePsi(_ bar: Decimal?) -> String {
        psiText(VehicleMath.psi(fromBar: bar))
    }

    static func relative(minutes: Int) -> String {
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분 전" }
        if minutes < 60 * 24 { return "\(minutes / 60)시간 전" }
        return "\(minutes / (60 * 24))일 전"
    }

    /// **모르는 값은 원문 그대로 낸다** — 상류가 상태를 늘렸다는 사실이 숨으면 안 된다.
    static func stateLabel(_ raw: String?) -> String {
        guard let raw else { return ChargeFormat.placeholder }
        switch raw {
        case "online": return "온라인"
        case "asleep": return "잠자는 중"
        case "offline": return "오프라인"
        case "driving": return "주행 중"
        case "charging": return "충전 중"
        default: return raw
        }
    }
}
