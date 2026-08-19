import Foundation

// MARK: - 응답

/// 주행 인사이트 — 네 카드가 **한 응답**에 온다. 나누면 같은 화면이 네 번 부르고
/// 그중 셋은 나머지 하나를 기다린다.
struct DriveInsightsResponse: Codable {
    /// 받은 창을 되돌려 싣는다 — 앱이 무엇을 받았는지 알 수 있게.
    let months: Int
    /// `cars.efficiency` 그대로(kWh/km). **null일 수 있다** — TeslaMate가 아직 못 채운
    /// 경우다. 그때 화면은 전비 카드를 감춘다.
    let efficiencyKwhPerKm: Decimal?
    /// 다섯 개가 늘 온다. 서버가 빈 버킷 자리를 채워 준다.
    let temperatureBuckets: [TemperatureBucket]
    /// **0인 칸은 빠진다.** 168칸 중 대부분이 0이라 히트맵이 빈칸으로 그리면 된다.
    let driveTimes: [DriveTime]
    /// 다섯 개가 늘 온다.
    let distanceBuckets: [DistanceBucket]
    /// 지오펜스를 붙인 도착지만, 건수 많은 순 상위 10개. **주소는 오지 않는다.**
    let places: [DrivePlace]
}

/// 온도대별 주행 합. 경계는 **`fromC` 포함, `toC` 미만**이고, 없는 쪽이 nil이다.
///
/// **빈 버킷의 숫자는 0이지 nil이 아니다.** 이 앱의 다른 곳에서 0과 nil이 「측정됐다」와
/// 「모른다」로 갈리는 것과 반대인데, 여기서 0은 **「그 온도대에 실제로 안 탔다」**는 사실이다.
///
/// **모든 주행이 어느 한 버킷에 드는 것은 아니다** — 주행가능거리 소모가 0 이하인 주행은
/// 빠진 뒤 집계된다. 그래서 온도 버킷 건수의 합이 거리 버킷 건수의 합보다 작다
/// (실측 최근 12개월: 939 대 959). **두 카드가 각자 자기 수를 낸다.**
struct TemperatureBucket: Codable, Identifiable, Equatable {
    let fromC: Int?
    let toC: Int?
    /// 주행가능거리 소모가 0 이하인 주행은 빠진 뒤의 건수다.
    let driveCount: Int
    let distanceKm: Decimal
    /// `start_rated_range_km − end_rated_range_km`의 합. **kWh 환산은 앱이 한다.**
    let ratedRangeUsedKm: Decimal

    var id: String { "\(fromC.map(String.init) ?? "-")_\(toC.map(String.init) ?? "-")" }

    var label: String {
        switch (fromC, toC) {
        case (nil, _): return "영하"
        case let (from?, nil): return "\(from)℃ 이상"
        case let (from?, to?): return "\(from)~\(to)℃"
        }
    }
}

/// 요일·시각별 주행 건수. **`weekday`는 0이 일요일이고**(PostgreSQL `dow` 그대로),
/// 시각은 서버가 이미 KST로 옮겨 준 값이다 — 앱이 다시 옮기지 않는다.
struct DriveTime: Codable, Identifiable, Equatable {
    let weekday: Int
    let hour: Int
    let count: Int

    var id: Int { weekday * 24 + hour }
}

/// 한 번에 얼마나 갔나. 경계는 **`fromKm` 포함, `toKm` 미만**이다.
struct DistanceBucket: Codable, Identifiable, Equatable {
    let fromKm: Int
    let toKm: Int?
    let driveCount: Int
    let distanceKm: Decimal

    var id: String { "\(fromKm)_\(toKm.map(String.init) ?? "-")" }

    var label: String {
        guard let toKm else { return "\(fromKm)km 이상" }
        return "\(fromKm)~\(toKm)km"
    }
}

/// 자주 가는 곳. **이름만 온다** — `/tesla/status`가 좌표와 주소를 싣지 않는 방침과 같다.
struct DrivePlace: Codable, Identifiable, Equatable {
    let name: String
    let driveCount: Int
    let distanceKm: Decimal

    var id: String { name }
}

// MARK: - 기간

/// 화면 맨 위 기간 칩. **네 카드가 같은 기간을 본다** — 카드마다 기간이 다르면 서로 비교가 안 된다.
/// 서버가 받는 범위는 1~60이고, 화면은 그중 둘만 낸다.
enum DrivePeriod: Int, CaseIterable, Identifiable {
    case threeMonths = 3
    case twelveMonths = 12

    var id: Int { rawValue }

    var label: String { "최근 \(rawValue)개월" }
}

// MARK: - 계산

extension VehicleMath {
    /// 전비(km/kWh). `drives`에는 kWh가 없어 **주행가능거리 소모량으로 환산한다.**
    ///
    /// ```
    /// 소비 kWh = 소모 rated km × cars.efficiency(kWh/km)
    /// 전비     = 실주행 km ÷ 소비 kWh
    /// ```
    ///
    /// 서버는 버킷별 **합**만 내고 이 나눗셈은 앱이 한다 — 분모가 0일 때의 처리를 서버가
    /// 정해 버리면 화면이 그것을 따라야 한다.
    static func kmPerKwh(
        distanceKm: Decimal, ratedRangeUsedKm: Decimal, efficiencyKwhPerKm: Decimal?
    ) -> Decimal? {
        guard let efficiencyKwhPerKm, efficiencyKwhPerKm > 0, ratedRangeUsedKm > 0 else { return nil }
        let usedKwh = ratedRangeUsedKm * efficiencyKwhPerKm
        guard usedKwh > 0, distanceKm > 0 else { return nil }
        return distanceKm / usedKwh
    }
}

// MARK: - 표기

/// 주행 화면 전용 표기.
enum DriveFormat {
    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    /// **0이 일요일이다.** 여기서 어긋나면 히트맵 전체가 하루씩 밀린다.
    /// 범위 밖은 「—」다 — 상류가 늘었다는 사실이 0으로 숨으면 안 된다.
    static func weekdayLabel(_ weekday: Int) -> String {
        guard weekdays.indices.contains(weekday) else { return ChargeFormat.placeholder }
        return weekdays[weekday]
    }

    static func hourLabel(_ hour: Int) -> String { "\(hour)시" }

    /// 62 → "62회"
    static func count(_ value: Int) -> String { "\(value)회" }
}
