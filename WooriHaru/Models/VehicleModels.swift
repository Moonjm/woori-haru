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

    /// 두 값의 나눗셈 하나. **분모가 0 이하면 nil이다** — 서버가 그 처리를 정해 버리면
    /// 화면이 따라야 한다. #26 명예의 전당의 최고효율(`distanceKm ÷ ratedRangeUsedKm`)이
    /// 첫 소비자다.
    static func ratio(_ numerator: Decimal, _ denominator: Decimal) -> Decimal? {
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    /// 월 평균 주행거리 = 총거리 / 기록이 있는 달 수.
    ///
    /// **분모가 0이거나 없으면 nil이다.** 서버는 주행이 하나도 없을 때 `recordedMonths: 0`을
    /// 그대로 낸다 — 그 자리를 서버가 정해 버리면 화면이 따라야 하므로, 막는 것은 여기다.
    ///
    /// 총거리가 0인 것은 막지 않는다 — 「안 탔다」는 사실이고 평균 0km가 옳다.
    static func avgMonthlyDistanceKm(totalKm: Decimal?, months: Int?) -> Decimal? {
        guard let totalKm, let months, months > 0 else { return nil }
        return totalKm / Decimal(months)
    }

    /// 연 평균 = 월 평균 × 12. **월 평균을 거쳐 낸다** — 두 값이 갈리면
    /// 화면의 두 칸이 서로 어긋난 이야기를 한다.
    static func avgYearlyDistanceKm(totalKm: Decimal?, months: Int?) -> Decimal? {
        guard let monthly = avgMonthlyDistanceKm(totalKm: totalKm, months: months) else { return nil }
        return monthly * 12
    }

    /// 누적합. **기록이 없는 달(`nil`)은 자리를 지키되 누적을 끊지 않는다** —
    /// 그 달을 0으로 읽으면 누적선이 주저앉고, 건너뛰어 배열에서 빼면 x축이 어긋난다.
    /// 「값 없음」은 그 달의 점만 없는 것이지 그때까지 간 거리가 없어지는 것이 아니다.
    static func runningTotals(_ values: [Decimal?]) -> [Decimal?] {
        var sum: Decimal?
        return values.map { value in
            guard let value else { return nil }
            let next = (sum ?? 0) + value
            sum = next
            return next
        }
    }

    /// 그 달 충전비가 지난달과 달라진 이유를 셋으로 쪼갠다.
    ///
    /// **세 효과의 합이 총 증감과 정확히 같다.** 충전비 = 충전량 × 단가이고
    /// 충전량 = 주행거리 ÷ 전비이므로, 항을 차례로 고정해 가면 남김없이 갈린다.
    ///
    /// **여기 단가는 `cost ÷ energyAddedKwh`다** — 누적 카드의 `wonPerKwh`(분모가
    /// 벽에서 뽑아쓴 `energyUsedKwh`)와 다른 값이다. 세 항의 곱이 비용이 되려면
    /// 분모가 차에 들어간 양이어야 한다.
    static func costBreakdown(current: VehiclePeriod, previous: VehiclePeriod) -> CostBreakdown? {
        guard let d1 = current.distanceKm, let e1 = current.energyAddedKwh, let c1 = current.cost,
              let d0 = previous.distanceKm, let e0 = previous.energyAddedKwh, let c0 = previous.cost,
              d1 > 0, e1 > 0, d0 > 0, e0 > 0
        else { return nil }

        let p0 = c0 / e0                 // 지난달 충전량당 단가
        let p1 = c1 / e1

        // 「지난달 전비 그대로 이번 달 거리를 갔다면 필요했을 충전량」.
        // **eff0(= d0/e0)로 나누지 않고 e0/d0를 곱한다** — 나눗셈을 두 번 거치면
        // 무한소수에서 잔차가 남아, 같은 달끼리 비교해도 전비 효과가 0이 되지 않는다
        // (실측 -6.29e-30). 대수적으로는 같은 식이다.
        let neededKwh = d1 * e0 / d0

        let distance   = (d1 - d0) * e0 / d0 * p0
        let efficiency = (e1 - neededKwh) * p0
        let unitPrice  = e1 * (p1 - p0)

        return CostBreakdown(total: c1 - c0,
                             distance: distance,
                             efficiency: efficiency,
                             unitPrice: unitPrice)
    }

    /// 충전량 1kWh당 금액. **분모가 `energyAddedKwh`(차에 들어간 양)다** — 누적 카드의
    /// `wonPerKwh`(분모가 `energyUsedKwh`)와 다른 값이다. `costBreakdown`의 세 항이 남김없이
    /// 갈리려면 이 분모가 차에 들어간 양이어야 한다.
    static func wonPerAddedKwh(cost: Decimal?, energyAddedKwh: Decimal?) -> Decimal? {
        guard let cost, let energyAddedKwh, energyAddedKwh > 0 else { return nil }
        return cost / energyAddedKwh
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

    /// 요일별 평균처럼 「합 ÷ 발생 횟수」꼴 평균 하나. 분모가 0이면 nil이다 — **0이 아니다.**
    /// 그 요일이 범위에 한 번도 없었다는 것과 「평균 0km」는 다른 말이다.
    static func avgPerOccurrence(total: Decimal, occurrences: Int) -> Decimal? {
        guard occurrences > 0 else { return nil }
        return total / Decimal(occurrences)
    }

    /// 팬텀 드레인 — km/시간. **표본이 없으면 nil이다** — 0km/시간은 「안 샜다」는
    /// 거짓말이다. `hours`가 0 이하일 때도 나눗셈이 뜻을 잃으므로 nil이다.
    static func drainPerHour(_ drain: ParkDrain) -> Decimal? {
        guard drain.samples > 0, drain.hours > 0 else { return nil }
        return drain.ratedKm / drain.hours
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

    /// `parseKST`가 읽은 값을 되찍을 때 쓴다. **`LedgerFormat.time`을 대신 쓰지 않는다** —
    /// 그쪽은 기기 시간대(`.current`)로 찍어서, `parseKST`가 KST 벽시계로 읽은 값을 그대로
    /// 되돌려 찍으면 기기가 한국 밖에 있을 때 시각이 어긋난다.
    private static let kstClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 2026-08-20T13:05:00(KST) → "13:05"
    static func clockTime(_ date: Date) -> String { kstClockFormatter.string(from: date) }

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

    /// 138 → "138km/h". **소수를 두지 않는다** — `drives.speed_max`가 `smallint`다.
    static func speed(_ kmh: Int?) -> String {
        guard let kmh else { return ChargeFormat.placeholder }
        return "\(kmh)km/h"
    }

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
    /// 반올림-후-표기 규칙을 두 곳에 따로 두면 한쪽만 고쳤을 때 표기와 판정이 갈린다.
    /// 임의로 되돌려 두 벌로 쪼개지 말 것.
    static func pressurePsi(_ bar: Decimal?) -> String {
        psiText(VehicleMath.psi(fromBar: bar))
    }

    static func relative(minutes: Int) -> String {
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분 전" }
        if minutes < 60 * 24 { return "\(minutes / 60)시간 전" }
        return "\(minutes / (60 * 24))일 전"
    }

    /// 「지금 이 상태로 얼마나」 — `relative`가 과거 시점을 읽는 것과 달리 **지속 시간**을 읽는다.
    ///
    /// **`relative`의 출력을 잘라 쓰지 않는다.** 「방금」에는 잘라낼 " 전"이 없어 「방금째」가 되고,
    /// 그쪽 표기가 바뀌면 컴파일도 테스트도 깨지지 않은 채 글자만 이상해진다.
    ///
    /// **하루 안에서는 분을 버리지 않는다** — 「3시간 12분째」다. 이 카드는 1분마다 다시 그려지는데
    /// (`TimelineView(.periodic(by: 60))`), 시간만 남기면 한 시간에 한 번만 바뀌어 갱신이 무의미해진다.
    /// 하루를 넘기면 「N일째」다 — 그 크기에서 분은 뜻이 없다.
    static func elapsed(minutes: Int) -> String {
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분째" }
        if minutes < 60 * 24 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)시간째" : "\(hours)시간 \(rest)분째"
        }
        return "\(minutes / (60 * 24))일째"
    }

    /// 0.0435 → "0.04km/시간". 팬텀 드레인 전용 표기 — 소수 둘째 자리까지 낸다.
    /// SOC 표기(정수 %)와 달리 시간당 스밈은 값 자체가 작아, 소수를 버리면 늘 "0km/시간"이
    /// 되어 「샜다」와 「안 샜다」가 화면에서 구분되지 않는다.
    static func drainRate(_ value: Decimal?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return "\(number(value, fraction: 2, minFraction: 2))km/시간"
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

/// 충전비 증감의 세 갈래. 부호는 **비용 기준**이다 — 양수면 그만큼 더 썼다는 뜻이고,
/// `efficiency`가 양수면 전비가 나빠져 돈이 더 들었다는 말이다.
struct CostBreakdown: Equatable {
    /// 이번 달 − 지난달.
    let total: Decimal
    let distance: Decimal
    let efficiency: Decimal
    let unitPrice: Decimal
}
