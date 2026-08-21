# 통계 탭 2단계 — 차트 스물여섯 장 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 통계 탭을 `/tesla/insights` 한 응답 위에 올리고, 여섯 섹션(주행 10 · 충전 8 · 주차 3 · 배터리 1 · 위치 3 · 기록 1)에 차트 스물여섯 장을 그린다.

**Architecture:** 1단계가 만든 차트 원형(`ChartPoint`/`ChartScale`/`MonthlyBarChart`/`MonthlyLineChart`/`MonthlyBarLineChart`/`DonutChart`/`ChartCard`)에 원형 셋(`DistributionBarChart`·`RankBarList`·`HeatmapGrid`)을 더해 아홉 개로 스물여섯 장을 그린다. 뷰모델은 `ChartPoint` 배열과 파생 행 타입만 내고 뷰는 나눗셈을 하지 않는다.

**Tech Stack:** SwiftUI (iOS 26), `@Observable`, Swift Testing. **Swift Charts를 들이지 않는다** — 이 저장소는 `Path`/`GeometryReader`/`RoundedRectangle`로 손수 그린다.

**Spec:** `docs/superpowers/specs/2026-08-20-vehicle-insights-tabs-design.md`
서버 계약 근거: `../toy-back/docs/superpowers/specs/2026-08-20-tesla-insights-design.md`

## Global Constraints

- **서버는 손대지 않는다.** `/tesla/insights`·`/tesla/battery-window`는 이미 배포돼 있다. 계약이 모자라 보이면 앱에서 파생시키고, 계약을 바꿔야 한다고 판단되면 멈추고 보고한다.
- **테스트는 Swift Testing이다** — `import Testing`, `@Test`, `#expect`, `try #require`. XCTest를 새로 쓰지 않는다.
- **`WooriHaru/`에 새 파일을 만들면 `ruby scripts/xcode-add-files.rb`를 돌린다.** 이 디렉터리는 `PBXFileSystemSynchronizedRootGroup`이 아니라 파일이 자동으로 타깃에 안 붙는다. `WooriHaruTests/`는 동기화되므로 안 돌려도 된다.
- **`nil`은 `0`이 아니다.** `nil` = 기록 없음, `0` = 안 탔다/안 썼다. 차트에서 `nil` 칸은 트랙 색으로 남기고 값 칸과 갈린다.
- **나눗셈은 뷰가 아니라 `VehicleMath` 또는 뷰모델에서 한다.** 뷰에서 다시 계산하면 테스트하는 값과 화면 값이 다른 코드가 된다.
- **차트 탭은 콜아웃만 바꾼다.** 화면을 옮기거나 기간을 바꾸지 않는다.
- **주석은 한국어로 「왜」를 적는다.** 코드가 이미 말하는 「무엇」을 반복하지 않는다.
- **요일 번호가 응답 안에서 둘이다** — `driveTimes`/`chargeTimes`는 **0=일요일**, `weekday`는 **1=월요일(ISO)**. 섞으면 차트가 하루씩 밀린다.
- 커밋은 태스크마다. 메시지는 저장소 관례(한국어 한 줄, `feat:`/`refactor:`/`docs:`)를 따른다.

---

## 파일 구조

**신규 — 모델/서비스**
- `WooriHaru/Models/InsightsModels.swift` — `/tesla/insights` 응답 전체
- `WooriHaru/Models/BatteryWindowModels.swift` — `/tesla/battery-window` 응답

**신규 — 차트 원형 (`WooriHaru/Views/Vehicle/Charts/`)**
- `DistributionBarChart.swift` — 세로 분포 막대 (#4 #5 #7 #8 #16 #17 #20)
- `RankBarList.swift` — 가로 순위 막대 (#24 #25)
- `HeatmapGrid.swift` — 요일×시각 격자 (#6 #15)

**신규 — 섹션 (`WooriHaru/Views/Vehicle/`)**
- `StatsParkSection.swift` · `StatsPlaceSection.swift` · `StatsRecordSection.swift`
- `BatteryWindowCard.swift` — 개요 탭

**수정**
- `WooriHaru/Models/DriveInsightsModels.swift` — `DrivePeriod` 넷, `DriveFormat.isoWeekdayLabel`
- `WooriHaru/Services/VehicleService.swift` — `fetchInsights` · `fetchBatteryWindow`
- `WooriHaru/ViewModels/VehicleStatsViewModel.swift` — 계약 갈아타기 + 파생 계열 전부
- `WooriHaru/Views/Vehicle/VehicleStatsTab.swift` · `StatsDriveSection.swift` · `StatsChargeSection.swift`
- `WooriHaru/Views/Vehicle/VehicleOverviewTab.swift` — 배터리 창 카드 자리

---

### Task 1: `/tesla/insights` 응답 모델과 서비스

**Files:**
- Create: `WooriHaru/Models/InsightsModels.swift`
- Modify: `WooriHaru/Services/VehicleService.swift`
- Modify: `WooriHaru/Models/DriveInsightsModels.swift` (`DriveFormat.isoWeekdayLabel` 추가)
- Test: `WooriHaruTests/InsightsModelsTests.swift`
- Test: `WooriHaruTests/InsightsStub.swift` (열한 태스크가 함께 쓰는 스텁 팩토리)

**Interfaces:**
- Consumes: 기존 `TemperatureBucket`·`DriveTime`·`DistanceBucket`·`DrivePlace`(`DriveInsightsModels.swift`) — 서버가 같은 타입을 그대로 쓰므로 **다시 정의하지 않는다.**
- Produces: `InsightsResponse`, `InsightsMonth`, `InsightsWeekday`, `SpeedBucket`, `SpeedEnergyBucket`, `ChargeLevelBucket`, `Charger`, `Regions`, `InsightsRecords`, `VehicleService.fetchInsights(months:)`, `DriveFormat.isoWeekdayLabel(_:)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/InsightsModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@Suite("통계 응답 디코딩")
struct InsightsModelsTests {
    /// 서버가 실제로 내는 모양이다. 필드를 줄이면 「우리가 아는 모양」만 테스트하게 된다.
    private static let json = """
    {
      "months": 12,
      "monthly": [{
        "yearMonth": "2026-08",
        "distanceKm": 780.4, "driveCount": 41, "drivingMin": 1120,
        "energyAddedKwh": 152.8, "energyUsedKwh": 161.0, "cost": 32700, "chargeCount": 7,
        "chargingMin": 640, "ratedRangeUsedKm": 812.1,
        "idleMin": 42800, "parkDrainRatedKm": 18.4, "parkDrainSamples": 34
      }, {
        "yearMonth": "2026-07",
        "distanceKm": null, "driveCount": null, "drivingMin": null,
        "energyAddedKwh": null, "energyUsedKwh": null, "cost": null, "chargeCount": null,
        "chargingMin": null, "ratedRangeUsedKm": null,
        "idleMin": 44640, "parkDrainRatedKm": 0.0, "parkDrainSamples": 0
      }],
      "efficiencyKwhPerKm": 0.168,
      "temperatureBuckets": [{"fromC": null, "toC": 0, "driveCount": 88,
                              "distanceKm": 910.0, "ratedRangeUsedKm": 1180.4}],
      "driveTimes": [{"weekday": 0, "hour": 8, "count": 12}],
      "distanceBuckets": [{"fromKm": 0, "toKm": 5, "driveCount": 120, "distanceKm": 380.2}],
      "places": [{"name": "집", "driveCount": 302, "distanceKm": 4120.8}],
      "maxSpeedKmh": 138,
      "totalDistanceKm": 107258.4,
      "recordedMonths": 59,
      "weekday": [{"weekday": 1, "driveCount": 38, "distanceKm": 612.0,
                   "drivingMin": 940, "occurrences": 52, "idleMin": 61200}],
      "chargeTimes": [{"weekday": 1, "hour": 23, "count": 4}],
      "speedBuckets": [{"fromKmh": 120, "toKmh": null, "driveCount": 3}],
      "speedEnergyBuckets": [{"fromKmh": 0, "toKmh": 20,
                              "distanceKm": 302.1, "ratedRangeUsedKm": 410.8}],
      "chargeStartLevels": [{"fromPct": 0, "toPct": 10, "count": 3}],
      "chargeEndLevels": [{"fromPct": 90, "toPct": 100, "count": 41}],
      "chargers": [{"name": "집", "chargeCount": 210, "energyAddedKwh": 4820.1,
                    "cost": 612000, "costMissingCount": 4}],
      "regions": {"cities": 34, "states": 8, "countries": 1},
      "records": {
        "longestDistance": {"driveId": 4821, "startedAt": "2025-09-13T07:12:00", "distanceKm": 412.8},
        "longestDuration": null,
        "bestEfficiency": {"driveId": 5002, "startedAt": "2026-05-02T14:20:00",
                           "distanceKm": 88.2, "ratedRangeUsedKm": 71.0}
      }
    }
    """

    /// **`APIClient`가 평범한 `JSONDecoder()`를 쓴다** — 날짜 전략이 없다.
    /// 그래서 모든 시각 필드가 `String`이고 파싱은 뷰가 필요할 때 한다.
    private func decoded() throws -> InsightsResponse {
        try JSONDecoder().decode(InsightsResponse.self, from: Data(Self.json.utf8))
    }

    @Test func 기록_없는_달은_0이_아니라_nil로_온다() throws {
        let month = try #require(try decoded().monthly.last)
        #expect(month.distanceKm == nil)
        #expect(month.driveCount == nil)
        // 셋만 예외다 — 기록이 없어도 값이 온다.
        #expect(month.idleMin == 44640)
        #expect(month.parkDrainSamples == 0)
    }

    @Test func 역대_기록은_셋이_따로_비어_올_수_있다() throws {
        let records = try decoded().records
        #expect(records.longestDistance != nil)
        #expect(records.longestDuration == nil)
        #expect(records.bestEfficiency != nil)
    }

    @Test func 전_기간_값_셋은_늘_온다() throws {
        let response = try decoded()
        #expect(response.totalDistanceKm == 107258.4)
        #expect(response.recordedMonths == 59)
        #expect(response.regions.countries == 1)
    }

    /// **한 응답 안에서 규약이 둘이다** — 섞으면 차트가 하루씩 밀린다.
    @Test func 요일_규약이_배열마다_다르다() throws {
        let response = try decoded()
        // driveTimes는 0 = 일요일
        #expect(DriveFormat.weekdayLabel(response.driveTimes[0].weekday) == "일")
        // weekday는 1 = 월요일
        #expect(DriveFormat.isoWeekdayLabel(response.weekday[0].weekday) == "월")
    }

    @Test func ISO_요일_라벨은_범위_밖에서_빈값을_낸다() {
        #expect(DriveFormat.isoWeekdayLabel(0) == ChargeFormat.placeholder)
        #expect(DriveFormat.isoWeekdayLabel(7) == "일")
        #expect(DriveFormat.isoWeekdayLabel(8) == ChargeFormat.placeholder)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/InsightsModelsTests`
Expected: 컴파일 실패 — `InsightsResponse`가 없다.

- [ ] **Step 3: `DriveFormat.isoWeekdayLabel`을 더한다**

`WooriHaru/Models/DriveInsightsModels.swift`의 `enum DriveFormat` 안, 기존 `weekdayLabel(_:)` 바로 아래:

```swift
    /// **1이 월요일이다**(ISO). `/tesla/insights`의 `weekday` 배열 전용이고,
    /// 같은 응답의 `driveTimes`는 0=일요일이라 `weekdayLabel(_:)`을 쓴다.
    /// 두 규약이 한 응답에 있어서 함수를 갈라 둔다 — 호출부에서 어느 쪽인지 보여야 한다.
    static func isoWeekdayLabel(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return ChargeFormat.placeholder }
        // ISO 7(일요일)을 0번 자리로 돌린다.
        return weekdayLabel(weekday % 7)
    }
```

- [ ] **Step 4: `InsightsModels.swift`를 만든다**

`WooriHaru/Models/InsightsModels.swift`. **기존 타입을 다시 정의하지 않는다** — `TemperatureBucket`·`DriveTime`·`DistanceBucket`·`DrivePlace`는 `DriveInsightsModels.swift`의 것을 그대로 쓴다.

```swift
import Foundation

/// 통계 탭 한 장을 채우는 한 응답. **나누면 화면 하나가 열 번 넘게 부른다.**
///
/// `/tesla/drive-insights`가 내던 여덟 필드를 이름까지 그대로 싣고 하위 타입도 같은 것을
/// 쓴다 — 그래서 기존 카드 넷(온도·시간대·거리 분포·자주 가는 곳)은 매핑 없이 옮겨 온다.
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

/// 한 달치. **기록이 없는 필드는 0이 아니라 nil이다.**
///
/// 예외가 셋이다. `idleMin`·`parkDrainRatedKm`·`parkDrainSamples`는 기록이 없어도 값이
/// 온다 — 정지 시간은 기록 없음이 곧 「내내 서 있었다」이고, 팬텀 드레인은 표본 수 0이
/// 이미 「잴 구간이 없었다」를 말하기 때문이다.
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
    let drivingMin: Int
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

/// 명예의 전당. **셋이 각각 nil일 수 있다** — `bestEfficiency`만 nil인 길이 따로 있다
/// (20km 넘는 주행이 없을 때).
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
```

**시각은 `Date`가 아니라 `String`으로 받는다.** `APIClient`(`APIClient.swift:237`)가 날짜 전략 없는 평범한 `JSONDecoder()`를 쓰기 때문이다 — `Date`로 선언하면 디코딩이 통째로 실패한다. `ChargeModels`·`StateTimelineModels`가 이미 그렇게 하고 있고, 필요할 때 `VehicleFormat.parseKST(_:)`(`VehicleModels.swift:216`)로 파싱한다. **새 디코더를 만들지 않는다.**

- [ ] **Step 5: 공용 스텁 팩토리를 만든다**

**Task 3부터 13까지 열한 태스크가 같은 응답을 스텁한다.** 태스크마다 따로 만들면 필드를
하나 더할 때 열한 군데를 고친다. `WooriHaruTests/InsightsStub.swift`에 한 벌 둔다.

이 저장소의 목 관례는 `MockVehicleService`가 아니라 **`MockAPIClient` + `stubGet`**이다
(`VehicleStatsTests.swift:389`의 `stubTrend` 참고). 테스트 이름도 **한국어**다.

```swift
import Foundation
@testable import WooriHaru

/// 통계 응답 스텁 한 벌. **열한 태스크가 같은 것을 쓴다** — 태스크마다 만들면 필드를
/// 하나 더할 때 열한 군데를 고치게 된다.
enum InsightsStub {
    /// `monthlyCount`개월치를 만든다. 노브는 **각각 하나의 경계**를 연다.
    /// - `emptyLastMonth`: 마지막 달이 기록 없는 달(값은 nil, `parkDrainSamples`는 0)
    /// - `emptyPlaces`: `places`·`chargers`가 빈 배열, `regions`가 전부 0
    /// - `emptyRecords`: `records` 셋 다 nil
    static func response(months: Int = 12,
                         monthlyCount: Int = 12,
                         emptyLastMonth: Bool = false,
                         emptyPlaces: Bool = false,
                         emptyRecords: Bool = false) -> InsightsResponse {
        let monthly = (0..<monthlyCount).map { index -> InsightsMonth in
            let isEmpty = emptyLastMonth && index == monthlyCount - 1
            // 2026-08에서 거슬러 올라간다. 자릿수를 두 자리로 맞춘다.
            let month = 8 - (monthlyCount - 1 - index)
            let yearMonth = String(format: "2026-%02d", max(1, month))
            return InsightsMonth(
                yearMonth: yearMonth,
                distanceKm: isEmpty ? nil : 780,
                driveCount: isEmpty ? nil : 41,
                drivingMin: isEmpty ? nil : 1120,
                energyAddedKwh: isEmpty ? nil : 153,
                energyUsedKwh: isEmpty ? nil : 161,
                cost: isEmpty ? nil : 32700,
                chargeCount: isEmpty ? nil : 7,
                chargingMin: isEmpty ? nil : 640,
                ratedRangeUsedKm: isEmpty ? nil : 812,
                // 셋은 기록이 없어도 온다.
                idleMin: isEmpty ? 44640 : 42800,
                parkDrainRatedKm: isEmpty ? 0 : Decimal(string: "18.4")!,
                parkDrainSamples: isEmpty ? 0 : 34)
        }
        // **1 = 월요일**(ISO)로 일곱 개. 순서가 곧 월~일이다.
        let weekday = (1...7).map { day in
            InsightsWeekday(weekday: day, driveCount: 38, distanceKm: 612,
                            drivingMin: 940, occurrences: 52, idleMin: 61200)
        }
        return InsightsResponse(
            months: months, monthly: monthly,
            efficiencyKwhPerKm: Decimal(string: "0.168")!,
            temperatureBuckets: [], 
            // **0 = 일요일**. `weekday` 배열과 규약이 다르다.
            driveTimes: [DriveTime(weekday: 0, hour: 8, count: 12)],
            distanceBuckets: [],
            places: emptyPlaces ? [] : [
                DrivePlace(name: "집", driveCount: 302, distanceKm: 4120),
                DrivePlace(name: "회사", driveCount: 151, distanceKm: 2010)],
            maxSpeedKmh: 138, totalDistanceKm: 107258, recordedMonths: 59,
            weekday: weekday,
            chargeTimes: [DriveTime(weekday: 0, hour: 23, count: 4)],
            speedBuckets: [SpeedBucket(fromKmh: 120, toKmh: nil, driveCount: 3)],
            speedEnergyBuckets: [SpeedEnergyBucket(fromKmh: 0, toKmh: 20,
                                                    distanceKm: 302, ratedRangeUsedKm: 410)],
            chargeStartLevels: [ChargeLevelBucket(fromPct: 0, toPct: 10, count: 3)],
            chargeEndLevels: [ChargeLevelBucket(fromPct: 80, toPct: 90, count: 12),
                              ChargeLevelBucket(fromPct: 90, toPct: 100, count: 41)],
            chargers: emptyPlaces ? [] : [
                Charger(name: "집", chargeCount: 210, energyAddedKwh: 4820,
                        cost: 612000, costMissingCount: 4)],
            regions: Regions(cities: emptyPlaces ? 0 : 34,
                             states: emptyPlaces ? 0 : 8,
                             countries: emptyPlaces ? 0 : 1),
            // **`longestDuration`만 nil이다** — 셋이 따로 빌 수 있음을 기본 스텁이 드러낸다.
            records: emptyRecords
                ? InsightsRecords(longestDistance: nil, longestDuration: nil, bestEfficiency: nil)
                : InsightsRecords(
                    longestDistance: DistanceRecord(driveId: 4821,
                                                    startedAt: "2025-09-13T07:12:00",
                                                    distanceKm: 412),
                    longestDuration: nil,
                    bestEfficiency: EfficiencyRecord(driveId: 5002,
                                                     startedAt: "2026-05-02T14:20:00",
                                                     distanceKm: 88, ratedRangeUsedKm: 71)))
    }

    /// `months`마다 다른 응답을 물릴 수 있다 — 기간 칩 테스트가 그것을 본다.
    static func stub(_ mock: MockAPIClient, _ response: InsightsResponse) {
        mock.stubGet("/tesla/insights", result: DataResponse<InsightsResponse>(data: response))
    }
}
```

**`MockAPIClient.stubGet`은 경로 하나에 결과 하나다.** 기간별로 다른 응답이 필요한 테스트
(Task 3)는 `select` 전후로 스텁을 갈아 끼우고, 무엇을 요청했는지는 `mock.getCalls`
(`MockAPIClient.swift:100`)로 본다.

- [ ] **Step 5: 서비스에 `fetchInsights`를 더한다**

`WooriHaru/Services/VehicleService.swift`, `fetchDriveInsights` 바로 아래:

```swift
    /// 통계 탭 스물여섯 장이 **한 응답**에 온다. `months`는 `0`(전체)과 `1...60`이고
    /// 응답에 되돌아 실려 온다.
    ///
    /// `fetchDriveInsights`는 아직 지우지 않는다 — 서버가 두 엔드포인트를 함께 내는 동안
    /// 앱만 먼저 옮기고, 통계 탭이 이쪽만 쓰게 된 뒤에 지운다.
    func fetchInsights(months: Int) async throws -> InsightsResponse {
        let response: DataResponse<InsightsResponse> =
            try await api.get("/tesla/insights", query: ["months": String(months)])
        guard let insights = response.data else {
            throw APIError.serverError(statusCode: 200, message: "통계 응답이 비어 있습니다")
        }
        return insights
    }
```

- [ ] **Step 7: 타깃에 붙이고 테스트가 통과하는지 본다**

```bash
ruby scripts/xcode-add-files.rb
xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/InsightsModelsTests
```
Expected: PASS (5개)

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/Models/InsightsModels.swift WooriHaru/Models/DriveInsightsModels.swift \
        WooriHaru/Services/VehicleService.swift WooriHaruTests/InsightsModelsTests.swift \
        WooriHaruTests/InsightsStub.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 통계 응답을 받고 요일 규약 둘을 가른다"
```

---

### Task 2: 기간 칩을 넷으로 늘린다

**Files:**
- Modify: `WooriHaru/Models/DriveInsightsModels.swift` (`DrivePeriod`)
- Modify: `WooriHaru/Views/Vehicle/Charts/ChartPoint.swift` (라벨·슬롯)
- Test: `WooriHaruTests/DrivePeriodTests.swift`, `WooriHaruTests/ChartPointTests.swift`

**Interfaces:**
- Consumes: `ChartScale.slotSpacing`·`slotCenterX`·`slotIndex` (Task 없음 — 1단계 산물)
- Produces: `DrivePeriod.sixMonths`/`.all`, `ChartScale.slotSpacing(count:)`, `MonthLabel.short(_:count:)`

**왜 이 태스크가 따로 있나:** 「전체」는 60개월이다. 지금 `ChartScale.slotSpacing`이 고정 5pt라 60칸이면 막대 폭이 음수가 되고, x축 라벨이 한 자리 월 숫자라 60개가 겹친다. **칩을 늘리는 것과 축을 고치는 것은 한 몸이다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DrivePeriodTests.swift`:

```swift
import Testing
@testable import WooriHaru

@Suite("기간 칩")
struct DrivePeriodTests {
    @Test func 칩이_넷이고_전체는_0이다() {
        #expect(DrivePeriod.allCases.map(\.rawValue) == [3, 6, 12, 0])
        #expect(DrivePeriod.all.rawValue == 0)
    }

    @Test func 전체만_라벨이_개월수가_아니다() {
        #expect(DrivePeriod.threeMonths.label == "3개월")
        #expect(DrivePeriod.twelveMonths.label == "12개월")
        #expect(DrivePeriod.all.label == "전체")
    }
}
```

`WooriHaruTests/ChartPointTests.swift`에 더한다:

```swift
    @Test func 칸이_많아지면_간격이_좁아진다() {
        #expect(ChartScale.slotSpacing(count: 12) == 5)
        // 60칸에서도 막대가 남아야 한다.
        let spacing = ChartScale.slotSpacing(count: 60)
        #expect(spacing < 5)
        let width: CGFloat = 320
        let barWidth = (width - spacing * 59) / 60
        #expect(barWidth > 0)
    }

    @Test func 칸이_많으면_x축_라벨을_솎는다() {
        // 12칸이면 전부 적는다.
        #expect(MonthLabel.shows(index: 5, count: 12))
        // 60칸이면 여섯 달에 하나만 적는다 — 다 적으면 글자가 겹친다.
        #expect(MonthLabel.shows(index: 0, count: 60))
        #expect(!MonthLabel.shows(index: 1, count: 60))
        #expect(MonthLabel.shows(index: 6, count: 60))
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/DrivePeriodTests -only-testing:WooriHaruTests/ChartPointTests`
Expected: 컴파일 실패

- [ ] **Step 3: `DrivePeriod`를 넷으로**

```swift
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
```

- [ ] **Step 4: 슬롯 간격과 라벨 솎기**

`ChartPoint.swift`의 `ChartScale`에서 `static let slotSpacing: CGFloat = 5`를 **함수로 바꾼다.** 기존 호출부(`MonthlyBarChart`·`MonthlyLineChart`·`MonthlyBarLineChart`)가 전부 상수를 참조하므로 함께 고친다.

```swift
    /// **칸 수에 따라 좁아진다.** 12칸이면 5pt인데 60칸에서 그대로 두면 320pt 폭에서
    /// 간격만 295pt를 먹어 막대 폭이 음수가 된다.
    static func slotSpacing(count: Int) -> CGFloat {
        switch count {
        case ..<16: 5
        case ..<32: 3
        default: 1
        }
    }
```

`slotWidth`·`slotCenterX`·`slotIndex`가 이 함수를 쓰도록 고친다 — **셋이 같은 간격을 봐야 한다.** 1단계에서 그리기와 히트테스트가 서로 다른 기하를 써서 탭이 어긋난 적이 있다.

`MonthLabel`을 `ChartPoint.swift`에 더한다:

```swift
/// x축 월 라벨. **칸이 많으면 솎는다** — 60칸을 다 적으면 글자가 서로 덮는다.
enum MonthLabel {
    /// 라벨 하나가 최소 이만큼은 떨어져 있어야 읽힌다(9pt 글자 두 자리 기준).
    private static let maxLabels = 12

    static func shows(index: Int, count: Int) -> Bool {
        guard count > maxLabels else { return true }
        let stride = (count + maxLabels - 1) / maxLabels
        return index % stride == 0
    }

    /// `"2026-08"` → `"8"`. **월 숫자만 적는다** — 열두 칸에 「26.8」까지 넣으면 겹친다.
    /// 어느 해인지는 콜아웃이 말한다.
    static func axis(_ yearMonth: String) -> String {
        guard let month = yearMonth.split(separator: "-").last,
              let value = Int(month) else { return yearMonth }
        return String(value)
    }
}
```

- [ ] **Step 5: 테스트 통과를 확인한다**

Run: 위 Step 2와 같은 명령
Expected: PASS

- [ ] **Step 6: 전체 스위트로 회귀를 본다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 기존 772개 + 신규가 전부 PASS. **`slotSpacing` 상수를 함수로 바꾼 자리가 셋이라 여기서 깨지면 그 셋 중 하나를 놓친 것이다.**

- [ ] **Step 7: 커밋**

```bash
git add -A && git commit -m "feat: 기간 칩을 넷으로 늘리고 축 라벨을 솎는다"
```

---

### Task 3: 뷰모델을 `/tesla/insights`로 갈아탄다

**Files:**
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleStatsTab.swift` (칩 넷 렌더)
- Test: `WooriHaruTests/VehicleStatsTests.swift`

**Interfaces:**
- Consumes: `InsightsResponse`, `VehicleService.fetchInsights(months:)`, `DrivePeriod` 넷
- Produces: `VehicleStatsViewModel.insights: InsightsResponse?`, `monthly: [InsightsMonth]`

**핵심:** 1단계의 아홉 장(✅)은 `/tesla/summary`의 `trend`(12개월 고정)로 그리고 있다. `monthly`로 갈아타면 **기간 칩이 그 아홉에도 먹는다.** 두 배열의 필드 이름이 같으므로 갈아타는 비용은 접근자 몇 줄이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleStatsTests.swift`에 더한다. 기존 목 서비스 관례를 그대로 따른다.

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1)을 쓴다. **`MockVehicleService` 같은 것은 이 저장소에 없다.** 테스트 이름은 한국어다 — `VehicleStatsTests.swift`의 기존 이름들과 같은 결로 짓는다.

```swift
    /// 1단계에서는 `trend`가 12개월 고정이라 칩이 월별 차트에 안 먹었다.
    @Test func 기간을_바꾸면_월별_계열도_함께_바뀐다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(months: 12, monthlyCount: 12))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.distancePoints.count == 12)

        InsightsStub.stub(mock, InsightsStub.response(months: 3, monthlyCount: 3))
        await viewModel.select(.threeMonths)
        #expect(viewModel.distancePoints.count == 3)
    }

    /// **0이 전체 기간이다.** 칩 라벨이 「전체」라고 해서 파라미터를 빼면 서버가 기본값
    /// 12로 답해 조용히 12개월만 나온다.
    @Test func 전체를_고르면_개월수_0으로_부른다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(months: 0, monthlyCount: 60))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))

        await viewModel.select(.all)

        let call = mock.getCalls.last { $0.path == "/tesla/insights" }
        #expect(call?.query["months"] == "0")
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/VehicleStatsTests`
Expected: 컴파일 실패

- [ ] **Step 3: 뷰모델을 갈아탄다**

- `insights` 타입을 `DriveInsightsResponse?` → `InsightsResponse?`로 바꾼다.
- `fetchDriveInsights(months:)` 호출을 `fetchInsights(months:)`로 바꾼다.
- **`trend` 병렬 호출을 뺀다.** 1단계에서 `/tesla/summary`를 함께 부른 것은 월별 계열 때문이었는데 이제 `monthly`가 그 자리를 채운다. `fetchSummary` 호출과 `hasTrend`·`trend` 프로퍼티를 지우고, `trend`를 쓰던 `ChartPoint` 접근자 일곱이 `monthly`를 보게 한다.
- `avgMonthlyKm`·`avgYearlyKm`이 쓰던 `totalDistanceKm`·`recordedMonths`가 **non-optional이 됐다.** `VehicleMath.avgMonthlyDistanceKm`의 옵셔널 처리는 그대로 두되(0 분모는 여전히 막아야 한다) 호출부의 `??`를 정리한다.
- `showsStats`는 이제 늘 참이다 — **프로퍼티를 지우고 호출부에서 뺀다.** 「셋 다 없으면 서버가 아직 안 낸다」는 판단은 1단계의 과도기 장치였고, 새 계약에서는 셋 다 non-null이라 거짓이 될 수 없는 조건이다.

**`ChargeTotalsViewModel`은 건드리지 않는다** — 급속/완속 도넛은 여전히 `/tesla/charges/totals`에서 온다.

- [ ] **Step 4: 칩 넷을 그린다**

`VehicleStatsTab.swift`의 `periodChips`는 `DrivePeriod.allCases`를 이미 돈다. **칩 폭만 확인한다** — 넷이 한 줄에 들어가는지, 안 들어가면 `.font(.caption2)`로 내린다. 스크롤을 넣지 않는다.

- [ ] **Step 5: 테스트 통과를 확인한다**

Run: Step 2와 같은 명령
Expected: PASS

- [ ] **Step 6: 전체 스위트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전부 PASS. **`trend`를 지운 자리가 넓으므로 여기서 실패가 나오면 접근자 하나를 안 옮긴 것이다.**

- [ ] **Step 7: 커밋**

```bash
git add -A && git commit -m "refactor: 통계 탭을 통계 응답 하나로 옮긴다"
```

---

### Task 4: `DistributionBarChart` 원형

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/DistributionBarChart.swift`
- Test: `WooriHaruTests/DistributionBarChartTests.swift`

**Interfaces:**
- Consumes: `ChartPoint`, `ChartScale`
- Produces: `DistributionBarChart(points:selectedID:onSelect:barHeight:)`

**쓰는 곳:** #4 요일별 평균 주행거리 · #5 주행 거리 분포 · #7 최고속도 분포 · #8 속도별 에너지 · #16 충전 시작 SoC · #17 충전 종료 SoC · #20 요일별 정지 시간 — **일곱 장.**

**`MonthlyBarChart`와 무엇이 다른가:** 월별 막대는 「기록 없는 달」이 있어 `value`가 옵셔널이고 라벨이 월 숫자다. 분포 막대는 **모든 칸에 값이 있고**(0은 「그 칸에 없었다」는 사실이다) 라벨이 버킷 이름이라 길다. 둘을 한 원형으로 묶으면 옵셔널 분기가 일곱 자리에서 죽은 코드가 된다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import Foundation
import Testing
@testable import WooriHaru

@Suite("분포 막대")
struct DistributionBarChartTests {
    @Test func 분포에서_0인_칸도_자리를_지킨다() {
        let points = [ChartPoint(id: "a", label: "0~5", value: 10),
                      ChartPoint(id: "b", label: "5~10", value: 0),
                      ChartPoint(id: "c", label: "10+", value: 4)]
        // 0은 「없었다」는 사실이라 비율 0이고, 칸은 남는다.
        #expect(ChartScale.ratio(points[1].value, max: 10) == 0)
        #expect(points.count == 3)
    }

    @Test func 최대가_0이면_모든_비율이_0이다() {
        let points = [ChartPoint(id: "a", label: "0~5", value: 0),
                      ChartPoint(id: "b", label: "5~10", value: 0)]
        let max = ChartScale.maxValue(points)
        #expect(max == 0)
        #expect(ChartScale.ratio(points[0].value, max: max) == 0)
    }
}
```

- [ ] **Step 2: 실패를 확인한다** — 이 테스트는 기존 타입만 쓰므로 **바로 통과할 수 있다.** 통과하면 그대로 두고 Step 3으로 간다(원형의 계약을 글로 못박는 회귀 테스트다).

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/DistributionBarChartTests`

- [ ] **Step 3: 원형을 만든다**

```swift
import SwiftUI

/// 버킷 분포 세로 막대. **카드가 아니라 막대만 그린다** — 껍데기는 `ChartCard`가 얹는다.
///
/// `MonthlyBarChart`와 가르는 이유: 월별 막대는 「기록 없는 달」 때문에 값이 옵셔널이고
/// 라벨이 월 숫자 두 자리다. 분포는 **모든 칸에 값이 있고**(0은 「그 칸에 아무것도 없었다」는
/// 사실이다) 라벨이 「0~20」처럼 길다 — 라벨을 눕혀야 하는 자리가 여기뿐이다.
///
/// **탭은 콜아웃만 바꾼다.**
struct DistributionBarChart: View {
    let points: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var barHeight: CGFloat = 84

    var body: some View {
        let maxValue = ChartScale.maxValue(points)
        let spacing = ChartScale.slotSpacing(count: points.count)
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(points) { point in
                bar(point, maxValue: maxValue)
            }
        }
        .frame(height: barHeight + 22)
    }

    private func bar(_ point: ChartPoint, maxValue: Decimal) -> some View {
        // 인라인으로 두면 SourceKit이 타입 검사를 포기한다 — 1단계 5번 태스크에서 겪었다.
        let isSelected = point.id == selectedID
        let ratio = ChartScale.ratio(point.value, max: maxValue)
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                // 값이 0이면 막대를 남기지 않는다 — 분포에서 0은 「없었다」이고,
                // 최소 높이를 주면 「조금 있었다」로 읽힌다.
                .frame(height: ratio > 0 ? max(3, ratio * barHeight) : 0)
            Text(point.label)
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(point.id) }
    }
}
```

- [ ] **Step 4: 타깃에 붙이고 빌드한다**

```bash
ruby scripts/xcode-add-files.rb
xcodebuild build -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 커밋**

```bash
git add -A && git commit -m "feat: 버킷 분포를 그리는 막대 원형을 둔다"
```

---

### Task 5: `RankBarList` 원형 — 자주 가는 곳·충전소 순위

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/RankBarList.swift`
- Test: `WooriHaruTests/RankBarListTests.swift`

**Interfaces:**
- Consumes: `ChartScale`
- Produces: `RankBarList(rows:selectedID:onSelect:)`, `RankBarList.Row`

**쓰는 곳:** #24 자주 가는 곳 · #25 충전소별 비용 TOP.

**왜 `ChartPoint`를 안 쓰나:** 순위 행은 값이 **둘**이다(자주 가는 곳은 건수와 거리, 충전소는 금액과 충전량). 막대 길이는 하나로 정하되 오른쪽에 둘을 적어야 해서 `ChartPoint`의 `label`/`value` 한 쌍으로는 모자란다.

**출발점:** `TemperatureEfficiencyCard`의 가로 막대. 다만 **거기는 0에서 시작하지 않고**(전비 6.0과 7.6을 견주는 자리라) 여기는 **0에서 시작한다** — 순위표는 「1등이 2등의 몇 배인가」가 질문이라 밑동을 잘라내면 그 배수가 거짓이 된다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import Foundation
import Testing
@testable import WooriHaru

@Suite("순위 막대")
struct RankBarListTests {
    private let rows = [
        RankBarList.Row(id: "집", label: "집", value: 302, primary: "302회", secondary: "4,120km"),
        RankBarList.Row(id: "회사", label: "회사", value: 151, primary: "151회", secondary: "2,010km"),
    ]

    /// 밑동을 자르면 「1등이 2등의 몇 배인가」가 거짓이 된다.
    @Test func 순위_막대는_0에서_시작한다() {
        let max = ChartScale.maxValue(rows.map(\.chartPoint))
        #expect(max == 302)
        #expect(ChartScale.ratio(rows[0].value, max: max) == 1)
        // 151/302 = 정확히 0.5
        #expect(abs(ChartScale.ratio(rows[1].value, max: max) - 0.5) < 0.0001)
    }

    @Test func 값이_0인_행도_이름은_남는다() {
        let row = RankBarList.Row(id: "미상", label: "미상", value: 0,
                                  primary: "0회", secondary: "—")
        #expect(ChartScale.ratio(row.value, max: 302) == 0)
        #expect(row.label == "미상")
    }

    @Test func 순위가_모두_0이면_0으로_나누지_않는다() {
        let zeros = [RankBarList.Row(id: "a", label: "a", value: 0, primary: "0", secondary: "—")]
        let max = ChartScale.maxValue(zeros.map(\.chartPoint))
        #expect(ChartScale.ratio(zeros[0].value, max: max) == 0)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/RankBarListTests`
Expected: 컴파일 실패 — `RankBarList`가 없다.

- [ ] **Step 3: 원형을 만든다**

```swift
import SwiftUI

/// 이름 있는 것들의 순위를 가로 막대로 낸다. **자주 가는 곳(#24)과 충전소별 비용(#25) 둘이 쓴다.**
///
/// 1단계에서 「자주 가는 곳」은 글자 목록이었다. 이 카드의 질문은 「어디를 제일 자주 가나」인데
/// 글자만 늘어놓으면 1등과 5등의 차이가 숫자를 읽어야만 보인다.
///
/// **막대는 0에서 시작한다.** `TemperatureEfficiencyCard`는 밑동을 잘라 그리는데(전비 6.0과
/// 7.6의 26% 차이를 보이려면 그래야 한다), 순위표는 「1등이 2등의 몇 배인가」가 질문이라
/// 밑동을 자르면 그 배수가 거짓이 된다.
///
/// **`id`는 서버가 유일성을 보장한다.** `places`·`chargers` 모두 표시 이름으로 묶여 오므로
/// 이름이 목록 안에서 유일하다 — 1단계에서 `id: \.offset`으로 그리던 이유가 사라졌다.
struct RankBarList: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        /// 막대 길이를 정하는 값. **순위 기준과 같아야 한다** — 다르면 짧은 막대가 위에 온다.
        let value: Decimal
        /// 오른쪽 첫 줄. 순위 기준을 그대로 적는다.
        let primary: String
        /// 오른쪽 둘째 줄. 없으면 「—」다.
        let secondary: String
        /// 그 행에 붙는 한 줄 단서(예: 「4건 금액 없음」). 없으면 nil.
        var note: String?

        var chartPoint: ChartPoint { ChartPoint(id: id, label: label, value: value) }
    }

    let rows: [Row]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxValue = ChartScale.maxValue(rows.map(\.chartPoint))
        VStack(spacing: 8) {
            ForEach(rows) { row in
                bar(row, maxValue: maxValue)
            }
        }
    }

    private func bar(_ row: Row, maxValue: Decimal) -> some View {
        let isSelected = row.id == selectedID
        let ratio = ChartScale.ratio(row.value, max: maxValue)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.primary)
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textSecondary)
                Text(row.secondary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textTertiary)
                    .frame(width: 72, alignment: .trailing)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(VehicleTheme.trackFill)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                        // 값이 0이면 막대를 안 그린다 — 순위표의 0은 「없었다」다.
                        .frame(width: ratio > 0 ? max(3, proxy.size.width * ratio) : 0)
                }
            }
            .frame(height: 8)
            if let note = row.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.warning)
            }
        }
        .contentShape(.rect)
        .onTapGesture { onSelect(row.id) }
    }
}
```

**`VehicleTheme.warning`이 없으면** 기존 테마에 있는 이름을 확인하고 그것을 쓴다 — 새 색을 만들지 않는다.

- [ ] **Step 4: 테스트 통과를 확인한다**

```bash
ruby scripts/xcode-add-files.rb
xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/RankBarListTests
```
Expected: PASS (3개)

- [ ] **Step 5: 커밋**

```bash
git add -A && git commit -m "feat: 순위를 가로 막대로 그리는 원형을 둔다"
```

---

### Task 6: `HeatmapGrid` 원형 — 주행·충전 시간대

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/HeatmapGrid.swift`
- Modify: `WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift` (원형을 쓰도록)
- Test: `WooriHaruTests/HeatmapGridTests.swift`

**Interfaces:**
- Produces: `HeatmapGrid(count:maxCount:accessibilityLabel:)`

**쓰는 곳:** #6 주행 시간대×요일 · #15 충전 시간대×요일.

**주의:** 둘 다 `DriveTime` 배열이고 **둘 다 0=일요일이다.** `weekday` 배열(1=월요일)과 섞지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import Testing
@testable import WooriHaru

@Suite("히트맵 격자")
struct HeatmapGridTests {
    @Test func 최대가_0이면_모든_칸이_빈칸이다() {
        #expect(HeatmapGrid.intensity(count: 0, maxCount: 0) == 0)
        #expect(HeatmapGrid.intensity(count: 3, maxCount: 0) == 0)
    }

    @Test func 가장_진한_칸이_1이다() {
        #expect(HeatmapGrid.intensity(count: 12, maxCount: 12) == 1)
    }

    /// 0에 최소 진하기를 주면 「조금 탔다」로 읽힌다.
    @Test func 히트맵의_0인_칸은_빈칸이다() {
        // 0에 최소 진하기를 주면 「조금 탔다」로 읽힌다.
        #expect(HeatmapGrid.intensity(count: 0, maxCount: 12) == 0)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/HeatmapGridTests`
Expected: 컴파일 실패

- [ ] **Step 3: 기존 `DriveTimeHeatmap`에서 격자를 뽑는다**

`DriveTimeHeatmap.swift`를 먼저 읽고, **격자를 그리는 부분만** `HeatmapGrid`로 옮긴다. `intensity(count:maxCount:)`를 `static`으로 노출해 테스트가 닿게 한다. `DriveTimeHeatmap`은 카드 껍데기와 「N회 기준」 콜아웃만 남기고 격자는 원형에 위임한다.

**동작을 바꾸지 않는다** — 이 스텝은 순수 추출이다. 색·크기·간격이 달라지면 그것은 버그다.

- [ ] **Step 4: 테스트와 전체 스위트를 돌린다**

Run: `ruby scripts/xcode-add-files.rb && xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전부 PASS — 기존 `DriveTimeHeatmap` 테스트가 있으면 그것도 그대로 통과해야 한다.

- [ ] **Step 5: 커밋**

```bash
git add -A && git commit -m "refactor: 히트맵 격자를 원형으로 뽑는다"
```

---

### Task 7: 주행 섹션 A — 월별 계열 넷 (#1 #2 #3 #10)

**Files:**
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/StatsDriveSection.swift`
- Test: `WooriHaruTests/VehicleStatsTests.swift`

**Interfaces:**
- Consumes: `InsightsMonth`, `MonthlyBarChart`, `MonthlyLineChart`, `MonthlyBarLineChart`, `ChartCard`
- Produces: `drivingMinPoints`, `efficiencyPoints`, `overallEfficiencyRatio`

| # | 차트 | 원형 | 재료 |
|---|---|---|---|
| 1 | 월별 주행거리 · 주행횟수 | `MonthlyBarLineChart` | `monthly[].distanceKm` / `.driveCount` |
| 2 | 월별 주행 시간 | `MonthlyBarChart` | `monthly[].drivingMin` |
| 3 | 누적 주행거리 | `MonthlyLineChart` | `VehicleMath.runningTotals(distanceKm)` |
| 10 | 효율 추세 | `MonthlyLineChart` | `distanceKm ÷ (ratedRangeUsedKm × efficiencyKwhPerKm)` |

**1·3은 1단계에 이미 있다** — 재료가 `trend`에서 `monthly`로 바뀐 것은 Task 3이 했으므로 여기서는 **2와 10만 새로 만든다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1)을 쓴다. **`MockVehicleService` 같은 것은 이 저장소에 없다.** 테스트 이름은 한국어다 — `VehicleStatsTests.swift`의 기존 이름들과 같은 결로 짓는다.

```swift
    @Test func 효율_추세는_정격거리_소모를_kWh로_환산해_나눈다() {
        // 100km를 정격 120km 쓰고 갔고 계수가 0.2kWh/km면 24kWh를 쓴 셈이라 4.17km/kWh.
        let value = VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 120,
                                         efficiencyKwhPerKm: 0.2)
        let unwrapped = try! #require(value)
        #expect(abs(unwrapped - Decimal(string: "4.1666")!) < Decimal(string: "0.001")!)
    }

    /// **0이 아니라 nil이다** — 계수가 없는 것은 「전비가 0」이 아니라 「모른다」다.
    @Test func 계수가_없으면_효율_점이_nil이다() {
        #expect(VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 120,
                                      efficiencyKwhPerKm: nil) == nil)
    }

    @Test func 주행_시간이_없는_달은_막대가_아니라_빈칸이다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 2, emptyLastMonth: true))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.drivingMinPoints.last?.value == nil)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WooriHaruTests/VehicleStatsTests`
Expected: FAIL

- [ ] **Step 3: 뷰모델 접근자를 더한다**

```swift
    /// #2 월별 주행 시간. **분을 그대로 값으로 쓴다** — 시간으로 바꾸는 것은 콜아웃이 한다.
    /// 막대 높이는 비율이라 단위가 무엇이든 같은 그림이 나오고, 여기서 60으로 나누면
    /// 나눗셈이 하나 더 늘 뿐이다.
    var drivingMinPoints: [ChartPoint] {
        monthly.map { ChartPoint(id: $0.yearMonth,
                                 label: MonthLabel.axis($0.yearMonth),
                                 value: $0.drivingMin.map(Decimal.init)) }
    }

    /// #10 효율 추세(km/kWh). **`ratedRangeUsedKm`을 계수로 kWh로 바꾼 뒤 나눈다** —
    /// `drives`에 kWh가 없어서다. 계수가 없으면 카드째 감춘다.
    var efficiencyPoints: [ChartPoint] {
        monthly.map { month in
            let value = month.distanceKm.flatMap { distance in
                month.ratedRangeUsedKm.flatMap { rated in
                    VehicleMath.kmPerKwh(distanceKm: distance, ratedRangeUsedKm: rated,
                                          efficiencyKwhPerKm: insights?.efficiencyKwhPerKm)
                }
            }
            return ChartPoint(id: month.yearMonth,
                              label: MonthLabel.axis(month.yearMonth), value: value)
        }
    }

    /// 효율 카드 머리에 얹는 한 줄 — 기간 전체의 정격 대비 실주행. 개요 누적 타일에서
    /// 옮겨온 자리다. **합끼리 나눈다** — 월별 비율의 평균은 짧은 달을 과대평가한다.
    var overallEfficiencyRatio: Decimal? {
        let distance = monthly.compactMap(\.distanceKm).reduce(0, +)
        let rated = monthly.compactMap(\.ratedRangeUsedKm).reduce(0, +)
        guard distance > 0, rated > 0 else { return nil }
        return distance / rated
    }

    var showsEfficiencyTrend: Bool {
        insights?.efficiencyKwhPerKm != nil && efficiencyPoints.contains { $0.value != nil }
    }
```

- [ ] **Step 4: 카드 둘을 그린다**

`StatsDriveSection.swift`에 #2와 #10을 더한다. **선택 상태는 섹션이 하나로 들고 있다** — 1단계에서 세운 `anchorID` 방식을 그대로 쓴다(콜아웃이 강조된 막대와 다른 달을 말하면 안 된다).

#10의 카드 머리에 `overallEfficiencyRatio`를 한 줄 얹는다: 「전 기간 정격 대비 92%」.

- [ ] **Step 5: 테스트와 전체 스위트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전부 PASS

- [ ] **Step 6: 커밋**

```bash
git add -A && git commit -m "feat: 월별 주행 시간과 효율 추세를 그린다"
```

---

### Task 8: 주행 섹션 B — 분포 셋 (#4 #7 #8)

**Files:**
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/StatsDriveSection.swift`
- Test: `WooriHaruTests/VehicleStatsTests.swift`

**Interfaces:**
- Consumes: `DistributionBarChart`, `InsightsWeekday`, `SpeedBucket`, `SpeedEnergyBucket`, `DriveFormat.isoWeekdayLabel`
- Produces: `weekdayDistancePoints`, `speedPoints`, `speedEfficiencyPoints`

| # | 차트 | 재료 | 나눗셈 |
|---|---|---|---|
| 4 | 요일별 평균 주행거리 | `weekday[].distanceKm ÷ .occurrences` | 뷰모델 |
| 7 | 최고속도 분포 | `speedBuckets[].driveCount` | 없음 |
| 8 | 속도별 전비 | `distanceKm ÷ (ratedRangeUsedKm × 계수)` | `VehicleMath.kmPerKwh` |

**#5 #6 #9는 이미 있는 카드다** — `DriveBucketCards`·`DriveTimeHeatmap`·`TemperatureEfficiencyCard`가 그대로 산다. 여기서는 **자리만 확인**하고 손대지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1)을 쓴다. **`MockVehicleService` 같은 것은 이 저장소에 없다.** 테스트 이름은 한국어다 — `VehicleStatsTests.swift`의 기존 이름들과 같은 결로 짓는다.

```swift
    @Test func 요일별_평균은_그_요일이_몇_번_있었나로_나눈다() {
        // 월요일 52번에 612km면 11.77km.
        let value = VehicleMath.avgPerOccurrence(total: 612, occurrences: 52)
        let unwrapped = try! #require(value)
        #expect(abs(unwrapped - Decimal(string: "11.769")!) < Decimal(string: "0.01")!)
    }

    @Test func 그_요일이_한_번도_없으면_nil이다() {
        #expect(VehicleMath.avgPerOccurrence(total: 0, occurrences: 0) == nil)
    }

    /// **이 차트가 하루 밀리는 것이 이 태스크의 가장 큰 위험이다.** 같은 응답의
    /// `driveTimes`는 0=일요일인데 `weekday`는 1=월요일이다.
    @Test func 요일_라벨이_ISO_규약을_따른다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        // 스텁의 weekday는 1...7이 월~일 순서다.
        #expect(viewModel.weekdayDistancePoints.map(\.label)
                == ["월", "화", "수", "목", "금", "토", "일"])
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `-only-testing:WooriHaruTests/VehicleStatsTests`
Expected: FAIL

- [ ] **Step 3: `VehicleMath.avgPerOccurrence`를 더한다**

`WooriHaru/Models/VehicleModels.swift`의 `enum VehicleMath`:

```swift
    /// 분모가 0이면 nil이다 — **0이 아니다.** 그 요일이 범위에 한 번도 없었다는 것과
    /// 「평균 0km」는 다른 말이다.
    static func avgPerOccurrence(total: Decimal, occurrences: Int) -> Decimal? {
        guard occurrences > 0 else { return nil }
        return total / Decimal(occurrences)
    }
```

- [ ] **Step 4: 접근자 셋과 카드 셋**

```swift
    /// #4 요일별 평균 주행거리. **`isoWeekdayLabel`을 쓴다** — 이 배열만 1=월요일이고
    /// 같은 응답의 `driveTimes`는 0=일요일이다. 섞으면 차트가 하루씩 밀린다.
    var weekdayDistancePoints: [ChartPoint] {
        (insights?.weekday ?? []).map { day in
            ChartPoint(id: "wd\(day.weekday)",
                       label: DriveFormat.isoWeekdayLabel(day.weekday),
                       value: VehicleMath.avgPerOccurrence(total: day.distanceKm,
                                                            occurrences: day.occurrences))
        }
    }

    /// #7 최고속도 분포. 주행 **한 건의 최고** 속도라 #8과 모집단이 다르다.
    var speedPoints: [ChartPoint] {
        (insights?.speedBuckets ?? []).map {
            ChartPoint(id: "sp\($0.fromKmh)", label: $0.label, value: Decimal($0.driveCount))
        }
    }

    /// #8 속도별 전비. **`driveCount`가 없는 배열이다** — 「N회 기준」을 적을 수 없으므로
    /// 카드 콜아웃에 건수를 쓰지 않는다.
    var speedEfficiencyPoints: [ChartPoint] {
        (insights?.speedEnergyBuckets ?? []).map { bucket in
            ChartPoint(id: "se\(bucket.fromKmh)", label: bucket.label,
                       value: VehicleMath.kmPerKwh(distanceKm: bucket.distanceKm,
                                                    ratedRangeUsedKm: bucket.ratedRangeUsedKm,
                                                    efficiencyKwhPerKm: insights?.efficiencyKwhPerKm))
        }
    }
```

카드 셋을 `StatsDriveSection`에 더한다. 각각 `ChartCard` + `DistributionBarChart`.

- [ ] **Step 5: 전체 스위트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전부 PASS

- [ ] **Step 6: 커밋**

```bash
git add -A && git commit -m "feat: 요일별 주행거리와 속도 분포 둘을 그린다"
```

---

### Task 9: 충전 섹션 A — 월별 계열 넷 (#11 #12 #13 #14)

**Files:**
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/StatsChargeSection.swift`
- Test: `WooriHaruTests/VehicleStatsTests.swift`

| # | 차트 | 원형 | 재료 |
|---|---|---|---|
| 11 | 월별 충전량 · 비용 | `MonthlyBarLineChart` | `energyAddedKwh` / `cost` |
| 12 | 월별 충전 시간 | `MonthlyBarChart` | `chargingMin` |
| 13 | 월별 충전 횟수 | `MonthlyBarChart` | `chargeCount` |
| 14 | 누적 충전비 | `MonthlyLineChart` | `runningTotals(cost)` |

**11·13·14는 1단계에 이미 있다** — Task 3이 재료를 옮겼으므로 여기서는 **12만 새로 만들고** 나머지 셋의 자리를 확인한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1)을 쓴다. **`MockVehicleService` 같은 것은 이 저장소에 없다.** 테스트 이름은 한국어다 — `VehicleStatsTests.swift`의 기존 이름들과 같은 결로 짓는다.

```swift
    @Test func 충전_시간이_없는_달은_빈칸이다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 2, emptyLastMonth: true))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.chargingMinPoints.last?.value == nil)
    }

    @Test func 누적_충전비는_기록_없는_달에서_끊기고_다음_값이_이어_붙는다() {
        // nil은 건너뛰되 누적은 잃지 않는다 — 1단계 runningTotals의 규칙이다.
        #expect(VehicleMath.runningTotals([10, nil, 5]) == [10, nil, 15])
    }
```

- [ ] **Step 2: 실패를 확인한다** — Run: `-only-testing:WooriHaruTests/VehicleStatsTests`

- [ ] **Step 3: `chargingMinPoints`를 더하고 카드를 그린다**

`drivingMinPoints`와 같은 모양이다. 카드는 `ChartCard` + `MonthlyBarChart`, 콜아웃은 선택한 달의 시간을 「12시간 40분」으로 적는다 — `ChargeFormat`에 분→시분 함수가 이미 있으면 그것을 쓰고, 없으면 `ChargeFormat`에 더한다(뷰에서 나누지 않는다).

- [ ] **Step 4: 전체 스위트** — Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add -A && git commit -m "feat: 월별 충전 시간을 그린다"
```

---

### Task 10: 충전 섹션 B — 히트맵·분포·도넛 (#15 #16 #17 #18)

**Files:**
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/StatsChargeSection.swift`
- Test: `WooriHaruTests/VehicleStatsTests.swift`

| # | 차트 | 원형 | 주의 |
|---|---|---|---|
| 15 | 충전 시간대 × 요일 | `HeatmapGrid` | `chargeTimes`는 **0=일요일** |
| 16 | 충전 시작 SoC 분포 | `DistributionBarChart` | 열 칸이 늘 온다 |
| 17 | 충전 종료 SoC 분포 | `DistributionBarChart` | **마지막 칸만 양끝이 닫힌다** |
| 18 | 급속 / 완속 비율 | `DonutChart` | `ChargeTotalsResponse` — 이미 온다 |

**#18은 이미 1단계에 있다** — 자리만 확인한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1)을 쓴다. **`MockVehicleService` 같은 것은 이 저장소에 없다.** 테스트 이름은 한국어다 — `VehicleStatsTests.swift`의 기존 이름들과 같은 결로 짓는다.

```swift
    /// **`chargeTimes`는 0=일요일이다** — `weekday` 배열(1=월요일)과 섞으면 밀린다.
    @Test func 충전_시간대는_0이_일요일이다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        // 스텁의 chargeTimes에 weekday 0, hour 23이 4건 있다.
        #expect(viewModel.chargeHeatCount(weekday: 0, hour: 23) == 4)
    }

    @Test func 종료_SoC_마지막_칸만_100을_품는다() async throws {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()

        let last = try #require(viewModel.insights?.chargeEndLevels.last)
        #expect(last.fromPct == 90 && last.toPct == 100)
        // 마지막 칸만 라벨이 다르다 — 양끝이 닫힘을 글자로 드러낸다.
        #expect(viewModel.chargeEndLevelPoints.last?.label == "90~100")
        #expect(viewModel.chargeEndLevelPoints.first?.label == "80")
    }
```

- [ ] **Step 2: 실패를 확인한다**

- [ ] **Step 3: 접근자 넷을 더한다**

```swift
    /// #15 충전 히트맵. **`chargeTimes`는 0=일요일이다** — `driveTimes`와 같고
    /// `weekday` 배열(1=월요일)과 다르다.
    func chargeHeatCount(weekday: Int, hour: Int) -> Int {
        insights?.chargeTimes.first { $0.weekday == weekday && $0.hour == hour }?.count ?? 0
    }

    var maxChargeHeatCount: Int { insights?.chargeTimes.map(\.count).max() ?? 0 }

    /// #16 충전 시작 SoC. 열 칸이 늘 오고 0인 칸도 자리를 지킨다.
    var chargeStartLevelPoints: [ChartPoint] {
        (insights?.chargeStartLevels ?? []).map {
            ChartPoint(id: "cs\($0.fromPct)", label: $0.label, value: Decimal($0.count))
        }
    }

    /// #17 충전 종료 SoC. **마지막 칸만 양끝이 닫혀 있다**(90 이상 100 이하) —
    /// 정확히 100%로 끝난 충전이 실측 71건이라 「미만」이면 가장 흔한 값이 사라진다.
    /// 그 칸만 라벨을 「90~100」으로 적어 다름을 글자로 드러낸다.
    var chargeEndLevelPoints: [ChartPoint] {
        let buckets = insights?.chargeEndLevels ?? []
        return buckets.enumerated().map { index, bucket in
            let isLast = index == buckets.count - 1
            return ChartPoint(id: "ce\(bucket.fromPct)",
                              label: isLast ? "\(bucket.fromPct)~\(bucket.toPct)" : bucket.label,
                              value: Decimal(bucket.count))
        }
    }
```

- [ ] **Step 4: 카드 셋을 그린다** — #15는 `HeatmapGrid`, #16·#17은 `DistributionBarChart`.

- [ ] **Step 5: 전체 스위트** — Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add -A && git commit -m "feat: 충전 시간대와 SoC 분포 둘을 그린다"
```

---

### Task 11: 주차 섹션 (#19 #20 #21)

**Files:**
- Create: `WooriHaru/Views/Vehicle/StatsParkSection.swift`
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleStatsTab.swift`
- Test: `WooriHaruTests/VehicleStatsTests.swift`

| # | 차트 | 재료 | 함정 |
|---|---|---|---|
| 19 | 월별 정지 시간 | `monthly[].idleMin` | **non-null이다** — 기록 없는 달도 값이 온다 |
| 20 | 요일별 정지 시간 | `weekday[].idleMin` | **1=월요일** |
| 21 | 월별 대기 중 소모 | `monthly[].parkDrainRatedKm` | **`parkDrainSamples == 0`이면 막대를 안 그린다** |

- [ ] **Step 1: 실패하는 테스트를 쓴다**

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1)을 쓴다. **`MockVehicleService` 같은 것은 이 저장소에 없다.** 테스트 이름은 한국어다 — `VehicleStatsTests.swift`의 기존 이름들과 같은 결로 짓는다.

```swift
    /// **0.0km는 「안 샜다」가 아니다** — 잴 구간이 없었다는 뜻이다. 0으로 그리면
    /// 그 달만 완벽했던 것처럼 보인다.
    @Test func 표본이_없는_달은_팬텀_드레인_막대를_안_그린다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 2, emptyLastMonth: true))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        // 스텁의 마지막 달은 parkDrainSamples가 0이고 parkDrainRatedKm이 0.0이다.
        #expect(viewModel.parkDrainPoints.last?.value == nil)
        // 앞 달은 표본이 있으므로 그린다 — 「전부 nil」로 통과하면 안 된다.
        #expect(viewModel.parkDrainPoints.first?.value != nil)
    }

    /// 안 탄 달은 「내내 서 있었다」다 — 다른 월별 계열과 옵셔널 여부가 다르다.
    @Test func 정지_시간은_기록이_없는_달에도_값이_온다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 2, emptyLastMonth: true))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.idleMinPoints.last?.value != nil)
    }
```

- [ ] **Step 2: 실패를 확인한다**

- [ ] **Step 3: 접근자 셋**

```swift
    /// #19 월별 정지 시간. **`idleMin`은 non-null이다** — 기록이 없는 달은 「내내 서
    /// 있었다」라서 값이 있는 것이 맞다. 다른 월별 계열과 옵셔널 여부가 다르다.
    var idleMinPoints: [ChartPoint] {
        monthly.map { ChartPoint(id: $0.yearMonth, label: MonthLabel.axis($0.yearMonth),
                                 value: Decimal($0.idleMin)) }
    }

    /// #20 요일별 정지 시간. **`isoWeekdayLabel`을 쓴다**(1=월요일).
    var weekdayIdlePoints: [ChartPoint] {
        (insights?.weekday ?? []).map {
            ChartPoint(id: "wi\($0.weekday)", label: DriveFormat.isoWeekdayLabel($0.weekday),
                       value: Decimal($0.idleMin))
        }
    }

    /// #21 월별 대기 중 소모. **표본이 0이면 nil이다** — `parkDrainRatedKm`이 0.0으로
    /// 와도 그것은 「안 샜다」가 아니라 「잴 구간이 없었다」다. 0으로 그리면 그 달만
    /// 「완벽했다」로 읽힌다.
    ///
    /// **음수를 0으로 자르지 않는다** — BMS 재보정으로 정격거리가 늘어난 구간이 섞여 있고,
    /// 자르면 합이 위로 편향된다.
    var parkDrainPoints: [ChartPoint] {
        monthly.map { month in
            ChartPoint(id: month.yearMonth, label: MonthLabel.axis(month.yearMonth),
                       value: month.parkDrainSamples > 0 ? month.parkDrainRatedKm : nil)
        }
    }
```

**`ChartScale.ratio`가 음수를 0으로 낸다** — 실측상 월 합은 전부 양수라 화면에서는 문제가 안 되지만, 음수가 오면 막대가 사라진다. **이 사실을 `parkDrainPoints` 주석에 적는다.**

- [ ] **Step 4: 섹션을 만든다**

`StatsParkSection.swift` — 헤더 「🅿️ 주차」와 카드 셋. `StatsDriveSection`의 구조를 그대로 따른다.

`VehicleStatsTab.swift`의 `body`에서 `StatsChargeSection` 다음에 끼운다.

- [ ] **Step 5: 타깃에 붙이고 전체 스위트**

```bash
ruby scripts/xcode-add-files.rb
xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 6: 커밋**

```bash
git add -A && git commit -m "feat: 주차 섹션에 정지 시간과 대기 소모를 그린다"
```

---

### Task 12: 위치 섹션 (#23 #24 #25) — 자주 가는 곳을 순위 막대로

**Files:**
- Create: `WooriHaru/Views/Vehicle/StatsPlaceSection.swift`
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleStatsTab.swift` (기존 `placesCard` 제거)
- Modify: `WooriHaru/Models/DriveInsightsModels.swift` (`DrivePlace: Identifiable`)
- Test: `WooriHaruTests/VehicleStatsTests.swift`

**Interfaces:**
- Consumes: `RankBarList`, `DrivePlace`, `Charger`, `Regions`
- Produces: `placeRows`, `chargerRows`, `showsPlaceSection`

| # | 차트 | 원형 |
|---|---|---|
| 23 | 도시 · 시도 · 국가 수 | 타일 셋 (`Regions`) |
| 24 | 자주 가는 곳 | `RankBarList` — **목록에서 바뀌는 것** |
| 25 | 충전소별 비용 TOP | `RankBarList` |

**전제가 바뀐 것을 잊지 말 것.** 1단계는 `geofences`가 0행이라 `places`가 늘 비어 카드를 감췄다. 서버가 **지오펜스가 없으면 주소로 이름을 짓도록** 바뀌어 이 차량에서도 채워진다. 감추기는 남기되 조건이 「배열이 비었다」가 된다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1). 테스트 이름은 한국어다.

```swift
    /// 서버가 **표시 이름으로 묶어** 주므로 목록 안에서 이름이 유일하다 —
    /// 1단계에서 `id: \.offset`으로 그리던 이유가 사라졌다.
    @Test func 자주_가는_곳은_이름이_유일해서_id로_쓸_수_있다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()

        let ids = viewModel.placeRows.map(\.id)
        #expect(ids == ["집", "회사"])
        #expect(Set(ids).count == ids.count)
    }

    /// **막대 길이가 순위 기준과 달라지면 짧은 막대가 위에 온다.**
    @Test func 순위_막대는_순위_기준과_같은_값으로_길이를_정한다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()

        // 서버가 건수 내림차순으로 준다.
        let values = viewModel.placeRows.map(\.value)
        #expect(values == [302, 151])
        #expect(values == values.sorted(by: >))
    }

    /// 미입력이 섞이면 위에 적힌 금액이 실제보다 적다 — 그 사실을 안 적으면
    /// 순위가 조용히 뒤집힌다.
    @Test func 금액_미입력이_섞인_충전소는_단서를_단다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.chargerRows.first?.note == "4건 금액 없음")
    }

    /// **0원이 아니라 「—」다.** 0원은 「공짜로 넣었다」는 거짓이다.
    @Test func 금액이_전부_미입력인_충전소는_비용이_없다() {
        let charger = Charger(name: "어딘가", chargeCount: 3, energyAddedKwh: 40,
                              cost: nil, costMissingCount: 3)
        #expect(ChargeFormat.cost(charger.cost) == ChargeFormat.placeholder)
    }

    /// **1단계의 「지오펜스가 없으면 감춘다」와 다르다** — 서버가 주소로 이름을 짓게 되어
    /// 남은 빈 길은 「그 기간에 주행·충전이 없었다」뿐이다.
    @Test func 배열이_비면_위치_섹션을_통째로_감춘다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1, emptyPlaces: true))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(!viewModel.showsPlaceSection)
    }

    /// 채워져 오는 것이 이 차량의 기본 상태다 — 감추기가 기본이 되면 안 된다.
    @Test func 주소로_이름이_붙은_곳들은_섹션을_연다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.showsPlaceSection)
    }
```

- [ ] **Step 2: 실패를 확인한다** — Run: `-only-testing:WooriHaruTests/VehicleStatsTests`

- [ ] **Step 3: `DrivePlace`에 `Identifiable`을 단다**

`DriveInsightsModels.swift`의 `DrivePlace` KDoc을 **다시 쓴다.** 지금은 「`Identifiable`을 달지 않는다」는 이유를 길게 적고 있는데 그 전제가 사라졌다.

```swift
/// 자주 가는 곳. **이름만 온다** — 좌표와 주소 전문은 싣지 않는다.
///
/// **`name`이 목록 안에서 유일하다.** 서버가 지오펜스 id가 아니라 **표시 이름**으로 묶기
/// 때문이다(주소는 재지오코딩할 때마다 행이 갈려서, id로 묶으면 사람이 같은 곳으로 읽는
/// 것이 두 줄로 나온다). 그래서 이름을 아이디로 쓸 수 있다 — 이전 계약에서는 그렇지 않아
/// 뷰가 `id: \.offset`으로 그렸다.
struct DrivePlace: Codable, Identifiable, Equatable {
    let name: String
    let driveCount: Int
    let distanceKm: Decimal

    var id: String { name }
}
```

- [ ] **Step 4: 접근자 셋**

```swift
    /// #24 자주 가는 곳. **막대 길이는 건수다** — 서버가 건수 내림차순으로 주므로
    /// 거리로 길이를 정하면 짧은 막대가 위에 온다.
    var placeRows: [RankBarList.Row] {
        (insights?.places ?? []).map { place in
            RankBarList.Row(id: place.name, label: place.name,
                            value: Decimal(place.driveCount),
                            primary: DriveFormat.count(place.driveCount),
                            secondary: VehicleFormat.distance(place.distanceKm))
        }
    }

    /// #25 충전소별 비용 TOP. **막대 길이는 충전 횟수다** — 서버 정렬 기준과 같다.
    /// 금액으로 정하면 금액 미입력이 섞인 곳이 실제보다 짧게 나와 순위와 어긋난다.
    var chargerRows: [RankBarList.Row] {
        (insights?.chargers ?? []).map { charger in
            RankBarList.Row(
                id: charger.name, label: charger.name,
                value: Decimal(charger.chargeCount),
                primary: ChargeFormat.cost(charger.cost),
                secondary: ChargeFormat.energy(charger.energyAddedKwh),
                // 미입력이 섞이면 위 금액이 실제보다 적다 — 그 사실을 적는다.
                note: charger.costMissingCount > 0
                      ? "\(charger.costMissingCount)건 금액 없음" : nil)
        }
    }

    /// 셋 다 비면 섹션 헤더까지 감춘다 — 제목만 남은 빈 섹션을 만들지 않는다.
    ///
    /// **1단계의 「지오펜스가 없으면 감춘다」와 다르다.** 서버가 주소로 이름을 짓게 되어
    /// 지오펜스 0행이어도 배열이 채워진다. 남은 빈 길은 「그 기간에 주행·충전이 없었다」뿐이다.
    var showsPlaceSection: Bool {
        guard let insights else { return false }
        return !insights.places.isEmpty || !insights.chargers.isEmpty
            || insights.regions.cities > 0
    }
```

**`ChargeFormat.cost(_:)`(`ChargeModels.swift:170`)와 `.energy(_:)`(:164)를 쓴다.** 둘 다 이미 `Decimal?`을 받아 nil이면 「—」를 낸다 — 새 포맷터를 만들지 않는다.

- [ ] **Step 5: 섹션을 만들고 기존 `placesCard`를 지운다**

`StatsPlaceSection.swift`:
- 헤더 「📍 위치」
- #23 타일 셋 — 「도시 34 · 시도 8 · 나라 1」. **나라가 1이면 그 타일을 감춘다**(「나라 1」은 아무것도 말하지 않는다).
- #24 `ChartCard("자주 가는 곳")` + `RankBarList(rows: viewModel.placeRows, ...)`
- #25 `ChartCard("충전소별 비용")` + `RankBarList(rows: viewModel.chargerRows, ...)`

**`VehicleStatsTab.swift`에서 `placesCard`와 `showsPlaces`를 지운다.** 이 태스크의 요점이 그 카드를 대체하는 것이므로, 남겨 두면 같은 내용이 두 번 나온다.

- [ ] **Step 6: 타깃에 붙이고 전체 스위트**

```bash
ruby scripts/xcode-add-files.rb
xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: 전부 PASS. **`showsPlaces`를 참조하던 기존 테스트가 있으면 함께 지운다.**

- [ ] **Step 7: 커밋**

```bash
git add -A && git commit -m "feat: 자주 가는 곳과 충전소를 순위 막대로 그린다"
```

---

### Task 13: 기록 섹션 (#26)과 배터리 이동 (#22), 섹션 조립

**Files:**
- Create: `WooriHaru/Views/Vehicle/StatsRecordSection.swift`
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleStatsTab.swift`
- Test: `WooriHaruTests/VehicleStatsTests.swift`

**#26 명예의 전당** — 최장거리 · 최장시간 · 최고효율 타일 셋. **셋이 각각 nil일 수 있다.**

**#22 열화 추세**는 이미 `batterySection`에 있다 — 섹션 헤더를 「🔋 배터리」로 맞추고 순서를 스펙대로 놓는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

**목 관례:** `MockAPIClient` + `InsightsStub`(Task 1). 테스트 이름은 한국어다.

```swift
    @Test func 최고효율은_분자와_분모로_앱이_낸다() {
        let record = EfficiencyRecord(driveId: 1, startedAt: "2026-05-02T14:20:00",
                                      distanceKm: 26.7, ratedRangeUsedKm: 15.3)
        let ratio = try! #require(VehicleMath.ratio(record.distanceKm, record.ratedRangeUsedKm))
        #expect(abs(ratio - Decimal(string: "1.745")!) < Decimal(string: "0.01")!)
    }

    /// **셋이 따로 nil일 수 있다** — `bestEfficiency`만 nil인 길이 따로 있다.
    @Test func 기록_셋이_따로_비어도_나머지는_그린다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()

        // 스텁은 longestDuration만 nil이다.
        #expect(viewModel.showsRecords)
        #expect(viewModel.insights?.records.longestDuration == nil)
        #expect(viewModel.insights?.records.longestDistance != nil)
    }

    @Test func 셋_다_비면_기록_섹션을_감춘다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1, emptyRecords: true))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(!viewModel.showsRecords)
    }
```

- [ ] **Step 2: 실패를 확인한다**

- [ ] **Step 3: `VehicleMath.ratio`와 `showsRecords`**

**`VehicleMath.ratio(_:_:)`는 없다** — 더한다(`VehicleModels.swift`의 `enum VehicleMath`):

```swift
    /// 분모가 0 이하면 nil이다.
    static func ratio(_ numerator: Decimal, _ denominator: Decimal) -> Decimal? {
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
```

```swift
    /// **셋이 각각 nil일 수 있다** — `bestEfficiency`만 nil인 길이 따로 있다(20km 넘는
    /// 주행이 없을 때). 하나라도 있으면 섹션을 그린다.
    var showsRecords: Bool {
        guard let records = insights?.records else { return false }
        return records.longestDistance != nil || records.longestDuration != nil
            || records.bestEfficiency != nil
    }
```

- [ ] **Step 4: 기록 섹션과 최종 조립**

`StatsRecordSection.swift` — 헤더 「🏆 기록」, 타일 셋. 각 타일은 값과 날짜(`startedAt`)를 적는다. **`driveId`는 화면에 안 쓴다** — 지금 앱에 주행 상세 화면이 없다.

`VehicleStatsTab.swift`의 `body` 순서를 스펙대로 확정한다:

```
기간 칩
(에러 한 줄)
DriveStatsCard                     ← 기간 칩과 무관한 전 기간 값 셋
🚗 주행 (StatsDriveSection)         10장
🔌 충전 (StatsChargeSection)         8장
🅿️ 주차 (StatsParkSection)           3장
🔋 배터리 (batterySection)            1장
📍 위치 (StatsPlaceSection)          3장
🏆 기록 (StatsRecordSection)         1장
```

- [ ] **Step 5: 타깃에 붙이고 전체 스위트**

```bash
ruby scripts/xcode-add-files.rb
xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 6: 커밋**

```bash
git add -A && git commit -m "feat: 명예의 전당을 더하고 여섯 섹션을 세운다"
```

---

### Task 14: 개요 탭 배터리 창 (`/tesla/battery-window`)

**Files:**
- Create: `WooriHaru/Models/BatteryWindowModels.swift`
- Create: `WooriHaru/Views/Vehicle/BatteryWindowCard.swift`
- Modify: `WooriHaru/Services/VehicleService.swift`
- Modify: `WooriHaru/ViewModels/VehicleStatusViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleOverviewTab.swift`
- Test: `WooriHaruTests/BatteryWindowTests.swift`

**Interfaces:**
- Produces: `BatteryWindowResponse`, `BatterySample`, `ParkDrain`, `VehicleService.fetchBatteryWindow(hours:)`

**함정 셋:**
1. `usableBatteryLevel`은 **실측 3%만 채워져 있다** — 주 계열은 `batteryLevel`이고 이것으로 선을 그리면 거의 다 끊긴다.
2. `parkDrain`은 **`hours`를 안 따르고 최근 7일 고정**이다 — 카드에 「최근 7일」이라고 적어야 범위 칩과 어긋나 보이지 않는다.
3. `samples`는 **이미 5분 슬롯으로 솎여서 온다** — 앱이 다시 솎지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import Foundation
import Testing
@testable import WooriHaru

@Suite("배터리 창")
struct BatteryWindowTests {
    /// **실측 3%만 채워져 있다** — 이것으로 선을 그리면 거의 다 끊긴다.
    @Test func 보조_계열은_대부분_비어_있다() {
        let samples = [
            BatterySample(at: "2026-08-18T15:02:00", batteryLevel: 62, usableBatteryLevel: 61),
            BatterySample(at: "2026-08-18T15:07:00", batteryLevel: 61, usableBatteryLevel: nil),
            BatterySample(at: "2026-08-18T15:12:00", batteryLevel: 60, usableBatteryLevel: nil),
        ]
        // 주 계열은 끊기지 않는다.
        #expect(samples.allSatisfy { $0.batteryLevel > 0 })
        // 보조 계열은 있을 때만 점을 찍는다.
        #expect(samples.compactMap(\.usableBatteryLevel).count == 1)
    }

    /// 0km/시간은 「안 샜다」는 거짓말이다.
    @Test func 표본이_없는_팬텀_드레인은_줄을_감춘다() {
        let drain = ParkDrain(ratedKm: 0, hours: 0, samples: 0)
        #expect(VehicleMath.drainPerHour(drain) == nil)
    }

    @Test func 팬텀_드레인은_뷰가_아니라_여기서_나눈다() {
        let drain = ParkDrain(ratedKm: 4.2, hours: 96.4, samples: 6)
        let value = try! #require(VehicleMath.drainPerHour(drain))
        #expect(abs(value - Decimal(string: "0.0435")!) < Decimal(string: "0.001")!)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `-only-testing:WooriHaruTests/BatteryWindowTests`
Expected: 컴파일 실패

- [ ] **Step 3: 모델과 서비스**

```swift
import Foundation

/// 개요 화면의 배터리 카드 하나. **시각은 전부 KST다.**
struct BatteryWindowResponse: Codable, Equatable {
    let hours: Int
    /// **`String`이다** — 디코더에 날짜 전략이 없다. `TimeSegment`도 같은 이유로 문자열이다.
    let from: String
    /// **요청 시각이다** — 자정에 맞추지 않는다. 화면의 오른쪽 끝이 「지금」이어야 한다.
    let to: String
    /// 오래된 것부터. **5분마다 최대 하나로 솎여서 온다** — 앱이 다시 솎지 않는다.
    /// 기록이 없으면 빈 배열이다.
    let samples: [BatterySample]
    /// 이 범위 안의 충전 구간, **범위 경계로 잘려서 온다.**
    let charges: [TimeSegment]
    /// **`hours`와 무관한 최근 7일 고정이다** — 48시간 안에 순수 주차 구간이 하나도 없는
    /// 날이 흔해서, 범위를 따르게 하면 숫자가 자주 사라진다.
    let parkDrain: ParkDrain
}

struct BatterySample: Codable, Identifiable, Equatable {
    /// **그 슬롯의 실제 표본 시각이다** — 5분 눈금으로 옮기지 않는다(없는 시각의 값이 된다).
    let at: String
    let batteryLevel: Int
    /// **실측 3%만 채워져 있다.** 주 계열은 `batteryLevel`이고 이것으로 선을 그리면
    /// 거의 다 끊긴다 — 있을 때만 점을 찍는 보조 계열이다.
    let usableBatteryLevel: Int?

    /// 5분마다 최대 하나라 시각이 유일하다.
    var id: String { at }

    var date: Date? { VehicleFormat.parseKST(at) }
}

/// 주차 중 정격거리가 얼마나 샜나. **나눗셈은 앱이 한다.**
struct ParkDrain: Codable, Equatable {
    /// **음수 구간도 부호 그대로 들어 있다**(BMS 재보정).
    let ratedKm: Decimal
    let hours: Decimal
    /// **0이면 줄을 감춘다.**
    let samples: Int
}
```

**`TimeSegment`는 `StateTimelineModels.swift:32`에 이미 있다** — `from`·`to`가 `String`인 그 타입을 그대로 쓴다. 다시 정의하지 않는다.

`VehicleMath`에:

```swift
    /// km/시간. **표본이 없으면 nil이다** — 0km/시간은 「안 샜다」는 거짓말이다.
    static func drainPerHour(_ drain: ParkDrain) -> Decimal? {
        guard drain.samples > 0, drain.hours > 0 else { return nil }
        return drain.ratedKm / drain.hours
    }
```

`VehicleService`에:

```swift
    /// 최근 `hours`시간의 SOC 표본·충전 구간·최근 7일 팬텀 드레인. `hours`는 1~168.
    ///
    /// **캐시하지 않는다** — 「최근 48시간」이 계속 움직인다.
    func fetchBatteryWindow(hours: Int = 48) async throws -> BatteryWindowResponse {
        let response: DataResponse<BatteryWindowResponse> =
            try await api.get("/tesla/battery-window", query: ["hours": String(hours)])
        guard let window = response.data else {
            throw APIError.serverError(statusCode: 200, message: "배터리 추이 응답이 비어 있습니다")
        }
        return window
    }
```

- [ ] **Step 4: 카드를 그린다**

`BatteryWindowCard.swift` — 48시간 SOC 선. `DegradationTrendChart`가 시간축 선을 이미 그리므로 **그 구현을 먼저 읽고 같은 방식으로 그린다.**

- **y축이 0에서 시작하지 않는다** — SOC 62%와 20%의 차이를 보여야 하는 자리다.
- **`charges` 구간을 선 아래 다른 색으로 깐다.**
- `usableBatteryLevel`은 **점만 찍는다.** 선으로 이으면 거의 다 끊긴다.
- 카드 아래 한 줄: 「최근 7일 대기 소모 0.04km/시간」. **`samples == 0`이면 그 줄을 감춘다.**

`VehicleOverviewTab.swift`에서 `BatteryNowCard` 다음에 놓는다. 뷰모델은 `VehicleStatusViewModel`에 `batteryWindow` 프로퍼티를 더해 개요 로딩과 함께 병렬로 받는다 — **하나가 실패해도 다른 카드는 그린다**는 기존 규칙을 지킨다.

- [ ] **Step 5: 타깃에 붙이고 전체 스위트**

```bash
ruby scripts/xcode-add-files.rb
xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: 전부 PASS

- [ ] **Step 6: 커밋**

```bash
git add -A && git commit -m "feat: 개요에 최근 48시간 배터리 추이를 그린다"
```

---

## 마무리 — 구현자가 아니라 사람이 할 일

**1. 실기기 확인.** 이 계획의 테스트는 값과 규약을 지키지만 **그림이 읽히는지는 못 잰다.** 특히 셋:
- 「전체」(60개월)에서 막대가 보이는지 — Task 2가 간격을 좁혔지만 실제 폭은 화면에서만 안다.
- 요일 차트가 하루 밀리지 않았는지 — 규약이 둘이라 가장 밟기 쉬운 함정이다.
- 스물여섯 장을 한 줄로 스크롤할 때 섹션 헤더가 이정표 노릇을 하는지.

**2. 접근성.** 1단계에서 차트 여덟 장에 접근성 라벨을 안 달고 넘어갔고 2단계가 열여덟 장을 더한다. `DriveTimeHeatmap`·`DriveBucketCards`에 관례가 있다 — **원형 셋(`DistributionBarChart`·`RankBarList`·`HeatmapGrid`)에 달면 스물여섯 장 중 열둘이 한 번에 해결된다.** 별도 태스크로 뺀 이유는 이것이 차트별이 아니라 원형별 작업이라서다.

**3. `/tesla/drive-insights` 정리.** 통계 탭이 `/tesla/insights`만 쓰게 된 뒤(Task 3), 앱의 `fetchDriveInsights`와 `DriveInsightsResponse`는 쓰이지 않는다. **이 계획에서는 안 지운다** — 지우는 커밋을 따로 두어야 되돌리기 쉽다. 서버 쪽 정리는 서버 설계 「기존 엔드포인트 처리」에 적혀 있다.
