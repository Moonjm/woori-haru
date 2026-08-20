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
    /// **역대 최고다 — `months` 창을 따르지 않는다.** 창이 바뀔 때마다 바뀌면 기록이 아니다
    /// (실측 138km/h는 2024~2025년 것이라 12개월 창으로 자르면 134가 나온다). 화면 라벨을
    /// 「역대 최고」로 두어 옆 두 칸과 범위가 다름을 글자로 드러낸다.
    ///
    /// **그 주행의 날짜를 싣지 않는다** — 138km/h가 최소 3건 동률이라(2025-09-13·2025-03-22·
    /// 2024-03-09) 「그날 기록했다」고 말할 수 없다.
    let maxSpeedKmh: Int?
    /// 평균의 **분자와 분모**다 — 평균 자체가 아니다.
    ///
    /// 서버가 나눠 주지 않는 이유는 이 저장소가 단가·전비를 다루는 방식과 같다. 서버가 평균을
    /// 내 버리면 분모의 정의(「기록이 있는 달 수」)가 응답에서 사라져 화면이 그 뜻을 설명할 수 없다.
    ///
    /// **`recordedMonths`는 0으로 올 수 있다**(주행이 하나도 없을 때). 서버가 1로 보정하지
    /// 않으므로 나누기 전에 앱이 막는다 — `VehicleMath.avgMonthlyDistanceKm`이 그 자리다.
    ///
    /// **옵셔널인 이유는 `maxSpeedKmh`와 같다** — 서버가 개정 전 필드를 내는 동안 앱이 먼저
    /// 나가도 통계 탭 응답 전체가 디코딩 실패로 무너지지 않아야 한다.
    let totalDistanceKm: Decimal?
    let recordedMonths: Int?
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
///
/// **`name`이 목록 안에서 유일하다.** 서버가 지오펜스 id가 아니라 **표시 이름**으로 묶기
/// 때문이다(`GROUP BY 1`) — 주소는 재지오코딩할 때마다 행이 갈리는데, id로 묶으면 사람이
/// 같은 곳으로 읽는 것이 두 줄로 나온다. 그래서 이름을 아이디로 쓸 수 있다 — 이전 계약
/// (지오펜스 id로 묶고 DTO에는 그 id가 없던 시절)에서는 그렇지 않아 뷰가 `id: \.offset`으로
/// 그렸다.
struct DrivePlace: Codable, Identifiable, Equatable {
    let name: String
    let driveCount: Int
    let distanceKm: Decimal

    var id: String { name }
}

// MARK: - 기간

/// 화면 맨 위 기간 칩. **네 카드가 아니라 스물여섯 장이 같은 기간을 본다** —
/// 카드마다 기간이 다르면 서로 비교가 안 된다.
///
/// **`0`은 전체 기간이다**(서버 계약). 일 단위(오늘/7일)로 내려가지 않는 이유는 이 화면
/// 스물여섯 중 아홉이 월 단위 집계라, 짧은 기간을 고르면 그 아홉이 막대 한 개짜리가 되기
/// 때문이다.
enum DrivePeriod: Int, CaseIterable, Identifiable {
    case threeMonths = 3
    case sixMonths = 6
    case twelveMonths = 12
    case all = 0

    var id: Int { rawValue }

    /// **「최근」을 뗀다.** 칩이 넷이 되면서 「최근 12개월」이 칩 폭을 넘긴다.
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

/// 통계 탭의 시간·횟수 표기. **이름은 주행에서 왔지만 주행 전용이 아니다** —
/// 요일·시각·「N회」는 단위와 무관해 충전 쪽도 그대로 쓴다(`StatsChargeSection`,
/// 그리고 충전 히트맵이 쓸 `HeatmapGrid`). 이름을 바꾸지 않는 것은 호출부가 흩어져
/// 있어 개명의 값이 비용을 못 넘기 때문이고, 그 사실을 여기 적어 둔다.
enum DriveFormat {
    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    /// **0이 일요일이다.** 여기서 어긋나면 히트맵 전체가 하루씩 밀린다.
    /// 범위 밖은 「—」다 — 상류가 늘었다는 사실이 0으로 숨으면 안 된다.
    static func weekdayLabel(_ weekday: Int) -> String {
        guard weekdays.indices.contains(weekday) else { return ChargeFormat.placeholder }
        return weekdays[weekday]
    }

    /// **1이 월요일이다**(ISO). `/tesla/insights`의 `weekday` 배열 전용이고,
    /// 같은 응답의 `driveTimes`는 0=일요일이라 `weekdayLabel(_:)`을 쓴다.
    /// 두 규약이 한 응답에 있어서 함수를 갈라 둔다 — 호출부에서 어느 쪽인지 보여야 한다.
    static func isoWeekdayLabel(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return ChargeFormat.placeholder }
        // ISO 7(일요일)을 0번 자리로 돌린다.
        return weekdayLabel(weekday % 7)
    }

    static func hourLabel(_ hour: Int) -> String { "\(hour)시" }

    /// 62 → "62회"
    static func count(_ value: Int) -> String { "\(value)회" }

    /// **`nil`은 「0회」가 아니라 「—」다.** 기록이 없는 달과 안 탄 달을 한 글자로 뭉개면
    /// 같은 콜아웃 안에서 거리(「—」)와 횟수(「0회」)가 서로 다른 말을 한다.
    static func count(_ value: Int?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return count(value)
    }
}
