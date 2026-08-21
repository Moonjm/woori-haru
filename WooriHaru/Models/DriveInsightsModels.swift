import Foundation

// MARK: - 응답

/// 주행 인사이트 — 네 카드가 **한 응답**에 온다. 나누면 같은 화면이 네 번 부르고
/// 그중 셋은 나머지 하나를 기다린다.
struct DriveInsightsResponse: Codable {
    /// 받은 창을 되돌려 싣는다 — 앱이 무엇을 받았는지 알 수 있게.
    let months: Int
    /// `cars.efficiency` 그대로(kWh/km). **null이면 전비 카드를 감춘다**(TeslaMate 미채움).
    let efficiencyKwhPerKm: Decimal?
    /// 다섯 개가 늘 온다(빈 버킷도 서버가 채운다).
    let temperatureBuckets: [TemperatureBucket]
    /// **0인 칸은 빠진다**(168칸 대부분이 0).
    let driveTimes: [DriveTime]
    /// 다섯 개가 늘 온다.
    let distanceBuckets: [DistanceBucket]
    /// 지오펜스를 붙인 도착지만, 건수 많은 순 상위 10개. **주소는 오지 않는다.**
    let places: [DrivePlace]
    /// **역대 최고 — `months`를 안 따른다.** 범위마다 바뀌면 기록이 아니다(실측: 12개월 창이면
    /// 138 대신 134가 나온다). **날짜는 안 싣는다** — 138km/h가 최소 3건 동률이라 「그날」을
    /// 특정할 수 없다.
    let maxSpeedKmh: Int?
    /// 평균의 **분자와 분모**다, 평균 자체가 아니다 — 분모 정의(「기록 있는 달 수」)를 화면이
    /// 설명할 수 있어야 해서 서버가 안 나눈다.
    ///
    /// **`recordedMonths`는 0일 수 있다**(주행 없음) — 서버가 1로 보정하지 않아 나누기 전에
    /// `VehicleMath.avgMonthlyDistanceKm`이 막는다. **옵셔널인 이유는 `maxSpeedKmh`와 같다.**
    let totalDistanceKm: Decimal?
    let recordedMonths: Int?
}

/// 온도대별 주행 합. 경계는 **`fromC` 포함, `toC` 미만**, 없는 쪽이 nil이다.
///
/// **빈 버킷은 0이지 nil이 아니다** — 여기 0은 「실제로 안 탔다」는 사실이다(다른 곳의
/// nil="모른다"와 반대).
///
/// **모든 주행이 어느 버킷에 들지는 않는다** — 소모 0 이하인 주행은 빠져, 온도 버킷 합이
/// 거리 버킷 합보다 작다(실측 939 대 959). 두 카드가 각자 수를 낸다.
struct TemperatureBucket: Codable, Identifiable, Equatable {
    let fromC: Int?
    let toC: Int?
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

/// 자주 가는 곳. **이름만 온다**(`/tesla/status`와 같은 방침) — **`name`이 유일하다**,
/// 서버가 표시 이름으로 묶어 보낸다(`GROUP BY 1`).
struct DrivePlace: Codable, Identifiable, Equatable {
    let name: String
    let driveCount: Int
    let distanceKm: Decimal

    var id: String { name }
}

// MARK: - 기간

/// 화면 맨 위 기간 칩. **스물여섯 장 전부가 같은 기간을 본다.**
///
/// **`0`은 전체 기간이다**(서버 계약). 일 단위로 안 내려가는 것은 스물여섯 중 아홉이
/// 월 단위 집계라 짧은 기간이면 막대 하나짜리가 되기 때문이다.
enum DrivePeriod: Int, CaseIterable, Identifiable {
    case threeMonths = 3
    case sixMonths = 6
    case twelveMonths = 12
    case all = 0

    var id: Int { rawValue }

    /// **「최근」을 뗀다** — 칩이 넷이 되면서 「최근 12개월」이 칩 폭을 넘긴다.
    var label: String {
        switch self {
        case .all: "전체"
        default: "\(rawValue)개월"
        }
    }
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
    /// 서버는 합만 내고 이 나눗셈은 앱이 한다 — 분모 0 처리를 서버가 정하면 화면이 따라야 한다.
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

/// 통계 탭의 시간·횟수 표기. **주행 전용이 아니다** — 충전 쪽(`StatsChargeSection`,
/// `HeatmapGrid`)도 그대로 쓴다.
enum DriveFormat {
    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    /// **0이 일요일이다.** 여기서 어긋나면 히트맵 전체가 하루씩 밀린다.
    /// 범위 밖은 「—」다 — 상류가 늘었다는 사실이 0으로 숨으면 안 된다.
    static func weekdayLabel(_ weekday: Int) -> String {
        guard weekdays.indices.contains(weekday) else { return ChargeFormat.placeholder }
        return weekdays[weekday]
    }

    /// **1이 월요일이다**(ISO) — `weekday` 배열 전용, `driveTimes`(0=일요일)와 반대라
    /// 함수를 갈라 둔다.
    static func isoWeekdayLabel(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return ChargeFormat.placeholder }
        // ISO 7(일요일)을 0번 자리로 돌린다.
        return weekdayLabel(weekday % 7)
    }

    static func hourLabel(_ hour: Int) -> String { "\(hour)시" }

    static func count(_ value: Int) -> String { "\(value)회" }

    /// **`nil`은 「0회」가 아니라 「—」다** — 기록 없음과 안 탄 것을 뭉개면 안 된다.
    static func count(_ value: Int?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return count(value)
    }
}
