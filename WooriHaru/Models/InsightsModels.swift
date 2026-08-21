import Foundation

/// 통계 탭 한 장을 채우는 한 응답. **나누면 화면 하나가 열 번 넘게 부른다.**
/// `/tesla/drive-insights`의 여덟 필드를 이름까지 그대로 실어, 기존 카드 넷은 매핑 없이 옮겨 온다.
struct InsightsResponse: Codable, Equatable {
    /// 받은 범위가 되돌아 온다. **0은 전체 기간이다.**
    let months: Int
    /// 오래된 달부터 이번 달까지. **기록이 없는 달도 자리를 지킨다.**
    let monthly: [InsightsMonth]
    let efficiencyKwhPerKm: Decimal?
    let temperatureBuckets: [TemperatureBucket]
    /// **`weekday`가 0=일요일이다.** 0인 칸은 빠진다.
    let driveTimes: [DriveTime]
    let distanceBuckets: [DistanceBucket]
    /// 도착지 상위 10곳. 지오펜스가 없으면 서버가 주소로 이름을 짓는다.
    let places: [DrivePlace]
    /// **`months`를 안 따른다** — 범위마다 바뀌면 기록이 아니다.
    let maxSpeedKmh: Int?
    /// 전 기간 총합. **`months`를 안 따르고 non-null이다**(주행이 없으면 0).
    let totalDistanceKm: Decimal
    /// 평균의 분모. **0으로 올 수 있다** — 나누기 전에 앱이 막는다.
    let recordedMonths: Int
    /// **`weekday`가 1=월요일(ISO)이다.** 일곱 개가 늘 온다.
    let weekday: [InsightsWeekday]
    /// **`weekday`가 0=일요일이다** — `driveTimes`와 같고 `weekday` 배열과 다르다.
    let chargeTimes: [DriveTime]
    let speedBuckets: [SpeedBucket]
    let speedEnergyBuckets: [SpeedEnergyBucket]
    let chargeStartLevels: [ChargeLevelBucket]
    let chargeEndLevels: [ChargeLevelBucket]
    let chargers: [Charger]
    let regions: Regions
    let records: InsightsRecords
}

/// 한 달치. **기록이 없는 필드는 0이 아니라 nil이다.** 예외 셋(`idleMin`·
/// `parkDrainRatedKm`·`parkDrainSamples`)은 기록 없어도 값이 온다 — 정지 시간은
/// 「내내 서 있었다」, 팬텀 드레인은 표본 0이 「잴 구간 없었다」를 뜻해서다.
struct InsightsMonth: Codable, Identifiable, Equatable {
    let yearMonth: String
    let distanceKm: Decimal?
    let driveCount: Int?
    let drivingMin: Int?
    let energyAddedKwh: Decimal?
    let energyUsedKwh: Decimal?
    let cost: Decimal?
    let chargeCount: Int?
    let chargingMin: Int?
    /// 효율 추세의 분모 재료. kWh 환산과 나눗셈은 앱이 한다.
    let ratedRangeUsedKm: Decimal?
    let idleMin: Int
    /// **음수 구간이 부호 그대로 섞여 있다**(BMS 재보정). 0으로 자르지 않는다.
    let parkDrainRatedKm: Decimal
    /// **0이면 막대를 그리지 않는다** — `parkDrainRatedKm` 0.0은 「안 샜다」가 아니다.
    let parkDrainSamples: Int

    var id: String { yearMonth }
}

/// 요일 하나의 합. **평균이 아니라 분자와 분모가 온다.**
struct InsightsWeekday: Codable, Identifiable, Equatable {
    /// **1 = 월요일**(ISO). `DriveFormat.isoWeekdayLabel(_:)`로 적는다.
    let weekday: Int
    let driveCount: Int
    let distanceKm: Decimal
    /// **서버가 `Int?`로 낸다** — 그 요일에 한 번도 안 탔으면 `?: 0` 없이 nil이 온다
    /// (`driveCount`와 다르다). `Int`로 두면 `valueNotFound`로 통계 탭 전체가 빈다.
    ///
    /// **앱은 이 필드를 읽지 않지만 옵셔널로 남긴다** — 안 읽는 필드도 타입이 틀리면
    /// 응답 전체를 무너뜨린다.
    let drivingMin: Int?
    /// 범위 안에 그 요일이 며칠 있었나 — **요일 평균의 분모다.**
    let occurrences: Int
    let idleMin: Int

    var id: Int { weekday }
}

/// 주행 한 건의 **최고** 속도 분포. 경계는 `fromKmh` 포함, `toKmh` 미만이다.
struct SpeedBucket: Codable, Identifiable, Equatable {
    let fromKmh: Int
    let toKmh: Int?
    let driveCount: Int

    var id: Int { fromKmh }

    var label: String {
        guard let toKmh else { return "\(fromKmh)+" }
        return "\(fromKmh)~\(toKmh)"
    }
}

/// 주행 한 건의 **평균** 속도별 거리·정격거리 소모.
///
/// **`driveCount`가 없다.** 건수는 `speedBuckets`가 내고 이쪽은 `ΔratedRange > 0`인 주행만
/// 들어 모집단이 다르다 — 두 카드가 각자 자기 수를 낸다.
struct SpeedEnergyBucket: Codable, Identifiable, Equatable {
    let fromKmh: Int
    let toKmh: Int?
    let distanceKm: Decimal
    let ratedRangeUsedKm: Decimal

    var id: Int { fromKmh }

    var label: String {
        guard let toKmh else { return "\(fromKmh)+" }
        return "\(fromKmh)~\(toKmh)"
    }
}

/// 충전 SoC 분포. 경계는 `fromPct` 포함 `toPct` 미만인데 **마지막 칸(90~100)만 양끝이
/// 닫힌다** — 정확히 100%로 끝난 충전이 실측 71건이라 「미만」이면 가장 흔한 값이 사라진다.
struct ChargeLevelBucket: Codable, Identifiable, Equatable {
    let fromPct: Int
    let toPct: Int
    let count: Int

    var id: Int { fromPct }

    var label: String { "\(fromPct)" }
}

/// 충전소 하나. **표시 이름으로 묶여 오므로 이 목록 안에서 `name`이 유일하다** —
/// 그래서 `Identifiable`을 달 수 있다.
struct Charger: Codable, Identifiable, Equatable {
    let name: String
    let chargeCount: Int
    let energyAddedKwh: Decimal?
    /// **실제로 낸 돈이다.** 전부 금액 미입력이면 nil이다 — 0이 아니다.
    let cost: Decimal?
    /// 금액 미입력 건수. 없으면 순위가 조용히 뒤집힌다.
    let costMissingCount: Int

    var id: String { name }
}

/// 다녀온 지역 수. 주소가 없으면 셋 다 0이다 — nil이 아니다.
struct Regions: Codable, Equatable {
    let cities: Int
    let states: Int
    let countries: Int
}

/// 명예의 전당. **셋 다 각각 nil일 수 있다**(`bestEfficiency`는 20km 하한 때문에 따로 빈다).
/// **`months`를 안 따른다** — 서버가 전 기간을 조회한다(`maxSpeedKmh`와 같다).
struct InsightsRecords: Codable, Equatable {
    let longestDistance: DistanceRecord?
    let longestDuration: DurationRecord?
    let bestEfficiency: EfficiencyRecord?
}

/// **`startedAt`이 `String`이다** — 이 저장소의 모든 응답 시각이 그렇다(디코더에 날짜
/// 전략이 없다). 파싱은 화면이 필요할 때 `VehicleFormat.parseKST(_:)`로 한다.
struct DistanceRecord: Codable, Equatable {
    let driveId: Int
    let startedAt: String
    let distanceKm: Decimal

    var startDate: Date? { VehicleFormat.parseKST(startedAt) }
}

struct DurationRecord: Codable, Equatable {
    let driveId: Int
    let startedAt: String
    let durationMin: Int

    var startDate: Date? { VehicleFormat.parseKST(startedAt) }
}

/// **거리 하한 20km를 넘은 주행 중** 정격거리 대비 실주행이 가장 좋았던 것.
/// 비율은 앱이 낸다 — `distanceKm ÷ ratedRangeUsedKm`.
struct EfficiencyRecord: Codable, Equatable {
    let driveId: Int
    let startedAt: String
    let distanceKm: Decimal
    let ratedRangeUsedKm: Decimal

    var startDate: Date? { VehicleFormat.parseKST(startedAt) }
}
