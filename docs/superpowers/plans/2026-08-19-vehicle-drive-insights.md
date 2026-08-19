# 차량 대시보드 2단계(주행 인사이트) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 차량 미니앱에 「주행」 탭을 더해, 온도별 전비·주행 시간대·거리 분포·자주 가는 곳을 한 화면에서 본다.

**Architecture:** 탭이 하나 늘 뿐 1단계 화면을 건드리지 않는다. 네 카드가 **한 응답**(`GET /tesla/drive-insights?months=N`)에서 나오므로 뷰모델도 호출도 하나다 — 나누면 같은 화면이 네 번 부르고 그중 셋은 나머지 하나를 기다린다. 기간 칩(3개월·12개월)이 화면 맨 위에 하나 있고 네 카드가 같은 기간을 본다. 서버는 버킷별 **합**만 내고 전비 나눗셈은 앱의 `VehicleMath`가 한다. 차트는 1단계와 같이 전부 손으로 그린다.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), `@Observable` 뷰모델, Swift Testing(`import Testing`), 기존 `APIClientProtocol`·`MockAPIClient`·`GlassCard`.

**Spec:** `docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md` (「2단계 — 주행 인사이트」 절)
(서버 계약: toy-back `docs/superpowers/plans/2026-08-17-tesla-drive-insights.md`, 구현은 `apps/daily-record/src/main/kotlin/com/toy/backend/tesla/TeslaVehicleDtos.kt`)

## Global Constraints

- **테스트 명령:** `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test`
- **앱 타겟은 파일 자동 인식이 안 된다.** `WooriHaru/` 아래 새 `.swift`를 만들면 반드시 `ruby scripts/xcode-add-files.rb <경로…>`로 등록하고, `WooriHaru.xcodeproj/project.pbxproj` 변경을 그 커밋에 포함한다. 테스트 타겟(`WooriHaruTests/`)은 폴더 동기화라 등록이 필요 없다.
- **증분 빌드가 변경을 놓치는 일이 있다.** 각 태스크의 마지막 테스트 실행 전에 바꾼 파일을 `touch`하고, 마지막 태스크의 최종 확인은 `clean test`로 한다.
- **1단계 화면을 건드리지 않는다.** `VehicleHealthTab`·`BatteryHealthCard`·`DegradationTrendChart`·`TirePressureCard`·`VehicleHealthViewModel`은 이 계획에서 한 줄도 수정하지 않는다. `VehicleView`만 탭이 하나 느는 만큼 바뀐다.
- **금액 입력 경로를 건드리지 않는다.** `ChargeCostQueueView`·`ChargeDetailView`·`ChargeService`는 diff 0줄이어야 한다.
- **나눗셈은 앱이 한다.** 분모가 없거나 0이면 결과는 nil이다.
- **없는 값은 0이 아니라 「—」다**(`ChargeFormat.placeholder`). **단 이 응답의 버킷은 반대다** — 빈 버킷의 `driveCount`·`distanceKm`은 **0이고 그것이 사실이다**(「그 온도대에 안 탔다」). nil이 아니다.
- **못 받은 것을 「기록 없음」으로 그리지 않는다.**
- **표기와 판정은 같은 반올림을 쓴다** — 1단계에서 세운 규칙이다. 정수로 낼 값은 `VehicleFormat.number`에 넘기기 전에 `VehicleMath.rounded`로 먼저 반올림한다.
- **기간 칩은 화면 맨 위 하나.** 네 카드가 같은 기간을 본다. 카드마다 기간이 다르면 서로 비교가 안 된다.
- **요약 탭의 월 스와이프를 주행 탭에 걸지 않는다.** 여기 기간 단위는 달이 아니다.
- **주소를 내지 않는다.** 지오펜스 **이름**만 낸다 — `/tesla/status`가 좌표와 주소를 싣지 않는 방침과 같다.
- 거리·전비는 `Decimal`.
- 커밋 메시지는 한국어 관례를 따른다(`feat:`/`fix:`/`refactor:` + 한 줄 요약 + 왜).
- 코드 주석은 한국어로, 저장소의 기존 밀도·어투를 따른다.

### 백엔드 계약에서 확인한 것 (2026-08-19, 실코드 대조)

1. **버킷 다섯 칸은 늘 온다.** `TeslaVehicleService.driveInsights`가 `TEMPERATURE_BUCKETS`·`DISTANCE_BUCKETS`를 `map`하며 없는 버킷을 `driveCount: 0`, `distanceKm: 0`으로 채운다. 백엔드 문서의 JSON 예시가 두 칸만 보여 주는 것은 **줄임 표기**다. 앱이 빈 칸을 만들 필요가 없다.
2. **`driveTimes`만 성기다(sparse).** 0인 칸은 빠진다 — 168칸 중 대부분이 0이라 히트맵이 빈칸으로 그리면 된다.
3. **`efficiencyKwhPerKm`은 nullable이다.** null이면 **전비 카드를 감춘다**(서버 DTO 주석의 지시). 실측값은 `0.1367`이다.
4. **`weekday`는 0이 일요일이다**(PostgreSQL `dow` 그대로). 시각은 **KST**로 뽑혀 온다 — 앱이 시간대를 다시 옮기지 않는다.
5. **`months`는 1~60이고, 벗어나면 서버가 400을 낸다.** 응답에 되돌아 실려 온다.
6. **온도 버킷의 건수 합 < 거리 버킷의 건수 합이다.** 온도 쪽은 `ΔratedRange <= 0`인 주행을 뺀 뒤 세기 때문이다. 실측(최근 12개월): 거리·시간대는 **959건**, 온도는 **939건**. **두 카드가 각자 자기 수를 낸다** — 한 곳에서 뽑아 「12개월 N건」으로 쓰면 어긋난다.
7. **`places`는 이 차량에서 항상 빈 배열이다.** `geofences`가 0행이다. 「가끔 비는 경우」가 아니라 **지금의 기본 상태**다.

### 실측된 참값 (테스트 픽스처는 이 값을 쓴다)

최근 12개월, 라즈베리파이 실 DB(2026-08-17):

| 버킷 | 주행 | 실주행 km | 소모 rated km | 소모÷실주행 |
|---|---|---|---|---|
| 영하 | 82 | 2,424.8 | 2,939.2 | 1.21 |
| 0~10 | 229 | 6,507.3 | 7,097.1 | 1.09 |
| 10~20 | 244 | 5,990.4 | 5,723.9 | 0.96 |
| 20~30 | 266 | 5,748.4 | 5,798.5 | 1.01 |
| 30 이상 | 118 | 2,494.6 | 2,551.5 | 1.02 |

`efficiencyKwhPerKm = 0.1367`. 시간대 상위 칸은 월 08시(43)·화 17시(41)·월 17시(41)·화 08시(40) — 출퇴근이다.

---

### Task 1: 주행 인사이트 응답 모델과 전비 계산

**Files:**
- Create: `WooriHaru/Models/DriveInsightsModels.swift`
- Test: `WooriHaruTests/DriveInsightsMathTests.swift`

**Interfaces:**
- Consumes: `VehicleMath`, `VehicleFormat`, `ChargeFormat.placeholder` (기존)
- Produces:
  - `struct DriveInsightsResponse: Codable` — `months: Int`, `efficiencyKwhPerKm: Decimal?`, `temperatureBuckets: [TemperatureBucket]`, `driveTimes: [DriveTime]`, `distanceBuckets: [DistanceBucket]`, `places: [DrivePlace]`
  - `struct TemperatureBucket: Codable, Identifiable, Equatable` — `fromC: Int?`, `toC: Int?`, `driveCount: Int`, `distanceKm: Decimal`, `ratedRangeUsedKm: Decimal`, `id: String`, `label: String`
  - `struct DriveTime: Codable, Identifiable, Equatable` — `weekday: Int`, `hour: Int`, `count: Int`, `id: Int`
  - `struct DistanceBucket: Codable, Identifiable, Equatable` — `fromKm: Int`, `toKm: Int?`, `driveCount: Int`, `distanceKm: Decimal`, `id: String`, `label: String`
  - `struct DrivePlace: Codable, Identifiable, Equatable` — `name: String`, `driveCount: Int`, `distanceKm: Decimal`, `id: String`
  - `enum DrivePeriod: Int, CaseIterable, Identifiable` — `.threeMonths = 3`, `.twelveMonths = 12`, `label: String`
  - `extension VehicleMath` — `kmPerKwh(distanceKm:ratedRangeUsedKm:efficiencyKwhPerKm:) -> Decimal?`
  - `enum DriveFormat` — `weekdayLabel(_:) -> String`, `hourLabel(_:) -> String`, `count(_:) -> String`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DriveInsightsMathTests.swift`를 만든다:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct DriveInsightsMathTests {

    // MARK: - 전비

    /// `drives`에는 kWh가 없다. **주행가능거리 소모량으로 환산한다** —
    /// 소비 kWh = 소모 rated km × `cars.efficiency`, 전비 = 실주행 km ÷ 소비 kWh.
    /// 실측값(2026-08-17 최근 12개월 영하 버킷)으로 검산한다.
    @Test func 주행가능거리_소모로_전비를_환산한다() {
        let value = VehicleMath.kmPerKwh(
            distanceKm: Decimal(string: "2424.8")!,
            ratedRangeUsedKm: Decimal(string: "2939.2")!,
            efficiencyKwhPerKm: Decimal(string: "0.1367")!
        )
        // 2424.8 ÷ (2939.2 × 0.1367) = 2424.8 ÷ 401.788… = 6.03…
        #expect(VehicleFormat.efficiency(value) == "6.0km/kWh")
    }

    /// 온화한 구간이 더 멀리 간다 — 이 카드가 답하려는 질문이 그것이다.
    @Test func 온도대마다_전비가_다르다() {
        let cold = VehicleMath.kmPerKwh(distanceKm: Decimal(string: "2424.8")!,
                                        ratedRangeUsedKm: Decimal(string: "2939.2")!,
                                        efficiencyKwhPerKm: Decimal(string: "0.1367")!)!
        let mild = VehicleMath.kmPerKwh(distanceKm: Decimal(string: "5990.4")!,
                                        ratedRangeUsedKm: Decimal(string: "5723.9")!,
                                        efficiencyKwhPerKm: Decimal(string: "0.1367")!)!
        #expect(mild > cold)
    }

    /// 분모가 없거나 0이면 계산하지 않는다 — 0으로 내면 「1kWh로 0km 갔다」가 된다.
    /// `efficiency`가 nil인 것은 TeslaMate가 아직 못 채운 경우다.
    @Test func 분모가_없으면_전비도_없다() {
        let eff = Decimal(string: "0.1367")!
        #expect(VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 0, efficiencyKwhPerKm: eff) == nil)
        #expect(VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 120, efficiencyKwhPerKm: nil) == nil)
        #expect(VehicleMath.kmPerKwh(distanceKm: 100, ratedRangeUsedKm: 120, efficiencyKwhPerKm: 0) == nil)
        // 빈 버킷은 0으로 오는 것이 사실이다. 그래도 전비는 낼 수 없다.
        #expect(VehicleMath.kmPerKwh(distanceKm: 0, ratedRangeUsedKm: 0, efficiencyKwhPerKm: eff) == nil)
    }

    // MARK: - 라벨

    /// 하한/상한이 없으면 nil이다. 경계는 `fromC` 포함, `toC` 미만이다.
    @Test func 온도_버킷_이름을_경계에서_짓는다() {
        #expect(TemperatureBucket.stub(from: nil, to: 0).label == "영하")
        #expect(TemperatureBucket.stub(from: 0, to: 10).label == "0~10℃")
        #expect(TemperatureBucket.stub(from: 10, to: 20).label == "10~20℃")
        #expect(TemperatureBucket.stub(from: 30, to: nil).label == "30℃ 이상")
    }

    @Test func 거리_버킷_이름을_경계에서_짓는다() {
        #expect(DistanceBucket.stub(from: 0, to: 5).label == "0~5km")
        #expect(DistanceBucket.stub(from: 50, to: 100).label == "50~100km")
        #expect(DistanceBucket.stub(from: 100, to: nil).label == "100km 이상")
    }

    /// **0이 일요일이다**(PostgreSQL `dow` 그대로). 여기서 어긋나면 히트맵 전체가 하루씩 밀린다.
    @Test func 요일은_0이_일요일이다() {
        #expect(DriveFormat.weekdayLabel(0) == "일")
        #expect(DriveFormat.weekdayLabel(1) == "월")
        #expect(DriveFormat.weekdayLabel(6) == "토")
        // 범위 밖은 「—」다. 상류가 늘었다는 사실이 0으로 숨으면 안 된다.
        #expect(DriveFormat.weekdayLabel(7) == ChargeFormat.placeholder)
    }

    @Test func 시각은_두_자리로_적는다() {
        #expect(DriveFormat.hourLabel(0) == "0시")
        #expect(DriveFormat.hourLabel(17) == "17시")
    }

    // MARK: - 기간

    @Test func 기간은_두_가지다() {
        #expect(DrivePeriod.allCases.map(\.rawValue) == [3, 12])
        #expect(DrivePeriod.threeMonths.label == "최근 3개월")
        #expect(DrivePeriod.twelveMonths.label == "최근 12개월")
    }

    // MARK: - 디코딩

    /// 서버가 주는 그대로 읽는다. **버킷 다섯 칸은 늘 오고 빈 칸은 0이다**(nil이 아니다).
    /// `driveTimes`만 0인 칸이 빠져 성기게 온다.
    @Test func 응답을_디코딩한다() throws {
        let json = """
        { "months": 12,
          "efficiencyKwhPerKm": 0.1367,
          "temperatureBuckets": [
            { "fromC": null, "toC": 0, "driveCount": 82, "distanceKm": 2424.8, "ratedRangeUsedKm": 2939.2 },
            { "fromC": 30, "toC": null, "driveCount": 0, "distanceKm": 0, "ratedRangeUsedKm": 0 }
          ],
          "driveTimes": [ { "weekday": 1, "hour": 8, "count": 43 } ],
          "distanceBuckets": [ { "fromKm": 100, "toKm": null, "driveCount": 3, "distanceKm": 412.0 } ],
          "places": [] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DriveInsightsResponse.self, from: json)

        #expect(decoded.months == 12)
        #expect(decoded.temperatureBuckets[0].label == "영하")
        #expect(decoded.temperatureBuckets[1].driveCount == 0)
        #expect(decoded.driveTimes[0].weekday == 1)
        #expect(decoded.distanceBuckets[0].toKm == nil)
        #expect(decoded.places.isEmpty)
    }

    /// TeslaMate가 `cars.efficiency`를 아직 못 채운 경우다. 화면은 전비 카드를 감춘다.
    @Test func 효율_계수가_없을_수_있다() throws {
        let json = """
        { "months": 3, "efficiencyKwhPerKm": null, "temperatureBuckets": [],
          "driveTimes": [], "distanceBuckets": [], "places": [] }
        """.data(using: .utf8)!

        #expect(try JSONDecoder().decode(DriveInsightsResponse.self, from: json).efficiencyKwhPerKm == nil)
    }
}

// 테스트 전용 생성 도우미 — 라벨만 보는 자리에서 숫자 넷을 매번 적지 않게 한다.
extension TemperatureBucket {
    static func stub(from: Int?, to: Int?) -> TemperatureBucket {
        TemperatureBucket(fromC: from, toC: to, driveCount: 0, distanceKm: 0, ratedRangeUsedKm: 0)
    }
}

extension DistanceBucket {
    static func stub(from: Int, to: Int?) -> DistanceBucket {
        DistanceBucket(fromKm: from, toKm: to, driveCount: 0, distanceKm: 0)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: 컴파일 실패 — `cannot find 'DriveInsightsResponse' in scope`, `cannot find type 'TemperatureBucket' in scope`.

- [ ] **Step 3: `DriveInsightsModels.swift`를 만든다**

```swift
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
```

- [ ] **Step 4: 앱 타겟에 파일을 등록한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Models/DriveInsightsModels.swift
```
Expected: `등록: WooriHaru/Models/DriveInsightsModels.swift`

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

```bash
touch WooriHaru/Models/DriveInsightsModels.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: PASS (`DriveInsightsMathTests` 9건 포함, 기존 643건도 통과)

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Models/DriveInsightsModels.swift \
        WooriHaruTests/DriveInsightsMathTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 주행 인사이트 응답 모델과 전비 환산을 더한다

drives에는 kWh가 없어 주행가능거리 소모량 × cars.efficiency로 환산한다.
서버는 버킷별 합만 내고 나눗셈은 앱이 한다."
```

---

### Task 2: 서비스 호출

**Files:**
- Modify: `WooriHaru/Services/VehicleService.swift`
- Test: `WooriHaruTests/VehicleServiceTests.swift`

**Interfaces:**
- Consumes: `DriveInsightsResponse` (Task 1), `APIClientProtocol`, `DataResponse` (기존)
- Produces: `VehicleService.fetchDriveInsights(months: Int) async throws -> DriveInsightsResponse`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleServiceTests.swift`의 `본문이_비면_에러다` 테스트 **앞에** 넣는다:

```swift
    /// 기간은 쿼리로 간다. 서버가 받는 범위는 1~60이고 화면은 3·12만 쓴다.
    @Test func 주행_인사이트는_개월수를_붙여_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/drive-insights", result: DataResponse<DriveInsightsResponse>(
            data: DriveInsightsResponse(
                months: 12, efficiencyKwhPerKm: Decimal(string: "0.1367"),
                temperatureBuckets: [], driveTimes: [], distanceBuckets: [], places: []
            )
        ))
        let service = VehicleService(api: mock)

        let insights = try await service.fetchDriveInsights(months: 12)

        #expect(insights.months == 12)
        #expect(mock.getCalls.map(\.path) == ["/tesla/drive-insights"])
        #expect(mock.getCalls.first?.query == ["months": "12"])
    }

    /// 그 기간에 주행이 없는 것은 에러가 아니다 — 「이 기간에 주행 기록이 없어요」다.
    @Test func 주행이_없어도_에러가_아니다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/drive-insights", result: DataResponse<DriveInsightsResponse>(
            data: DriveInsightsResponse(
                months: 3, efficiencyKwhPerKm: nil,
                temperatureBuckets: [], driveTimes: [], distanceBuckets: [], places: []
            )
        ))
        let service = VehicleService(api: mock)

        let insights = try await service.fetchDriveInsights(months: 3)

        #expect(insights.distanceBuckets.isEmpty)
        #expect(insights.efficiencyKwhPerKm == nil)
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: 컴파일 실패 — `value of type 'VehicleService' has no member 'fetchDriveInsights'`

- [ ] **Step 3: 최소 구현을 쓴다**

`WooriHaru/Services/VehicleService.swift`의 `fetchBatteryHealth()` 아래에 넣는다:

```swift
    /// 네 카드가 **한 응답**에 온다 — 나누면 같은 화면이 네 번 부르고 그중 셋은
    /// 나머지 하나를 기다린다. `months`는 응답에 되돌아 실려 온다.
    func fetchDriveInsights(months: Int) async throws -> DriveInsightsResponse {
        let response: DataResponse<DriveInsightsResponse> =
            try await api.get("/tesla/drive-insights", query: ["months": String(months)])
        guard let insights = response.data else {
            throw APIError.serverError(statusCode: 200, message: "주행 인사이트 응답이 비어 있습니다")
        }
        return insights
    }
```

같은 파일 맨 위 주석도 고친다:
```swift
/// 차량 API — 월 요약(그 달 충전 목록 포함)·현재 상태·배터리 건강·주행 인사이트·금액 미등록 목록.
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
touch WooriHaru/Services/VehicleService.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/VehicleService.swift WooriHaruTests/VehicleServiceTests.swift
git commit -m "feat: 주행 인사이트 엔드포인트를 부른다

네 카드가 한 응답에 온다 — 나누면 같은 화면이 네 번 부른다."
```

---

### Task 3: 주행 뷰모델

**Files:**
- Create: `WooriHaru/ViewModels/VehicleDriveViewModel.swift`
- Test: `WooriHaruTests/VehicleDriveTests.swift`

**Interfaces:**
- Consumes: `VehicleService.fetchDriveInsights(months:)` (Task 2), `DriveInsightsResponse`·`DrivePeriod`·`VehicleMath.kmPerKwh` (Task 1)
- Produces: `@MainActor @Observable final class VehicleDriveViewModel`
  - `private(set) var insights: DriveInsightsResponse?`, `isLoading: Bool`, `period: DrivePeriod`
  - `var errorMessage: String?`
  - `var hasDrives: Bool`, `showsEfficiency: Bool`, `showsPlaces: Bool`
  - `var temperatureRows: [TemperatureRow]` (`struct TemperatureRow: Identifiable` — `bucket`, `kmPerKwh: Decimal?`)
  - `var temperatureDriveCount: Int`, `distanceDriveCount: Int`
  - `func heatCount(weekday: Int, hour: Int) -> Int`, `private(set) var maxHeatCount: Int`
  - `func load() async`, `func reload() async`, `func select(_ period: DrivePeriod) async`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleDriveTests.swift`를 만든다:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleDriveViewModelTests {

    /// 실측(2026-08-17 최근 12개월) 그대로다 — 온도 939건, 거리 959건.
    private nonisolated static func insights(
        months: Int = 12, efficiency: String? = "0.1367", places: [DrivePlace] = []
    ) -> DriveInsightsResponse {
        DriveInsightsResponse(
            months: months,
            efficiencyKwhPerKm: efficiency.flatMap { Decimal(string: $0) },
            temperatureBuckets: [
                TemperatureBucket(fromC: nil, toC: 0, driveCount: 82,
                                  distanceKm: Decimal(string: "2424.8")!,
                                  ratedRangeUsedKm: Decimal(string: "2939.2")!),
                TemperatureBucket(fromC: 0, toC: 10, driveCount: 229,
                                  distanceKm: Decimal(string: "6507.3")!,
                                  ratedRangeUsedKm: Decimal(string: "7097.1")!),
                TemperatureBucket(fromC: 10, toC: 20, driveCount: 244,
                                  distanceKm: Decimal(string: "5990.4")!,
                                  ratedRangeUsedKm: Decimal(string: "5723.9")!),
                TemperatureBucket(fromC: 20, toC: 30, driveCount: 266,
                                  distanceKm: Decimal(string: "5748.4")!,
                                  ratedRangeUsedKm: Decimal(string: "5798.5")!),
                TemperatureBucket(fromC: 30, toC: nil, driveCount: 118,
                                  distanceKm: Decimal(string: "2494.6")!,
                                  ratedRangeUsedKm: Decimal(string: "2551.5")!),
            ],
            driveTimes: [
                DriveTime(weekday: 1, hour: 8, count: 43),
                DriveTime(weekday: 2, hour: 17, count: 41),
                DriveTime(weekday: 0, hour: 14, count: 12),
            ],
            distanceBuckets: [
                DistanceBucket(fromKm: 0, toKm: 5, driveCount: 620, distanceKm: 1802),
                DistanceBucket(fromKm: 5, toKm: 20, driveCount: 210, distanceKm: 2400),
                DistanceBucket(fromKm: 20, toKm: 50, driveCount: 90, distanceKm: 2700),
                DistanceBucket(fromKm: 50, toKm: 100, driveCount: 36, distanceKm: 2500),
                DistanceBucket(fromKm: 100, toKm: nil, driveCount: 3, distanceKm: 412),
            ],
            places: places
        )
    }

    private nonisolated static func empty(months: Int = 3) -> DriveInsightsResponse {
        DriveInsightsResponse(
            months: months, efficiencyKwhPerKm: Decimal(string: "0.1367"),
            temperatureBuckets: [], driveTimes: [], distanceBuckets: [], places: []
        )
    }

    private func makeViewModel(_ mock: MockAPIClient) -> VehicleDriveViewModel {
        VehicleDriveViewModel(service: VehicleService(api: mock))
    }

    private func stub(_ mock: MockAPIClient, _ response: DriveInsightsResponse) {
        mock.stubGet("/tesla/drive-insights",
                     result: DataResponse<DriveInsightsResponse>(data: response))
    }

    /// 기본은 12개월이다.
    @Test func 기본_기간은_12개월이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.period == .twelveMonths)
        #expect(mock.getCalls.first?.query == ["months": "12"])
        #expect(viewModel.hasDrives)
    }

    /// 기간을 바꾸면 다시 받는다 — 네 카드가 같은 기간을 봐야 한다.
    @Test func 기간을_바꾸면_다시_받는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        await viewModel.select(.threeMonths)

        #expect(viewModel.period == .threeMonths)
        #expect(mock.getCalls.map { $0.query["months"] } == ["12", "3"])
    }

    /// 같은 기간을 다시 누르면 부르지 않는다.
    @Test func 같은_기간은_다시_부르지_않는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        await viewModel.select(.twelveMonths)

        #expect(mock.getCalls.count == 1)
    }

    /// 버킷별 전비를 앱이 낸다. 영하가 가장 나쁘고 10~20℃가 가장 좋다 — 실측 그대로다.
    @Test func 버킷마다_전비를_낸다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let rows = viewModel.temperatureRows
        #expect(rows.count == 5)
        #expect(rows[0].bucket.label == "영하")
        let cold = rows[0].kmPerKwh!
        let mild = rows[2].kmPerKwh!
        #expect(mild > cold)
        #expect(rows.allSatisfy { $0.kmPerKwh != nil })
    }

    /// **두 카드의 총합이 다르다.** 온도 쪽은 주행가능거리 소모가 0 이하인 주행을 뺀 뒤 센다.
    /// 한 곳에서 뽑아 「N건」으로 쓰면 어긋난다.
    @Test func 온도와_거리의_건수가_다르다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.temperatureDriveCount == 939)
        #expect(viewModel.distanceDriveCount == 959)
    }

    /// TeslaMate가 `cars.efficiency`를 아직 못 채운 경우다 — 전비 카드를 감춘다.
    /// 나머지 카드는 그대로 그린다.
    @Test func 효율_계수가_없으면_전비_카드를_감춘다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights(efficiency: nil))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.showsEfficiency)
        #expect(viewModel.hasDrives)
        #expect(viewModel.temperatureRows.allSatisfy { $0.kmPerKwh == nil })
    }

    /// **지오펜스가 하나도 없는 것이 이 차량의 기본 상태다.** 「가끔 비는 경우」가 아니다.
    @Test func 지오펜스가_없으면_자주_가는_곳을_감춘다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.showsPlaces)
    }

    @Test func 지오펜스가_있으면_자주_가는_곳을_낸다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights(places: [DrivePlace(name: "집", driveCount: 124, distanceKm: 812)]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.showsPlaces)
    }

    /// 히트맵은 성기게 온다 — 없는 칸은 0이다. `weekday` 0이 일요일이다.
    @Test func 히트맵의_없는_칸은_0이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.heatCount(weekday: 1, hour: 8) == 43)
        #expect(viewModel.heatCount(weekday: 0, hour: 14) == 12)
        #expect(viewModel.heatCount(weekday: 3, hour: 3) == 0)
        #expect(viewModel.maxHeatCount == 43)
    }

    /// 그 기간에 주행이 없는 것은 에러가 아니다. 카드마다 비우지 않고 화면 하나로 말한다.
    @Test func 주행이_없어도_에러가_아니다() async {
        let mock = MockAPIClient()
        stub(mock, Self.empty())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.hasDrives)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.maxHeatCount == 0)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/drive-insights")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.insights == nil)
    }

    /// **있던 값을 새로고침 실패로 지우지 않는다** — 1단계 건강 화면과 같은 규칙이다.
    @Test func 새로고침이_실패해도_있던_값은_남는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/drive-insights")
        await viewModel.reload()

        #expect(viewModel.hasDrives)
        #expect(viewModel.errorMessage != nil)
    }

    /// **기간을 바꾸다 실패하면 옛 기간의 값을 남기지 않는다** — 칩은 3개월인데 화면이
    /// 12개월 값이면 거짓말이 된다. 새로고침 실패와 다르게 다뤄야 한다.
    @Test func 기간_변경이_실패하면_옛_기간_값을_지운다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/drive-insights")
        await viewModel.select(.threeMonths)

        #expect(viewModel.period == .threeMonths)
        #expect(viewModel.insights == nil)
        #expect(viewModel.errorMessage != nil)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: 컴파일 실패 — `cannot find 'VehicleDriveViewModel' in scope`

- [ ] **Step 3: `VehicleDriveViewModel.swift`를 만든다**

```swift
import Foundation
import Observation

/// 주행 탭 — `/tesla/drive-insights` 하나만 본다. 네 카드가 한 응답에서 나오므로
/// 호출도 하나이고, **기간 칩이 바뀌면 넷이 함께 바뀐다.**
@MainActor
@Observable
final class VehicleDriveViewModel {

    private(set) var insights: DriveInsightsResponse? {
        didSet { rebuildHeatMap() }
    }
    private(set) var isLoading = false
    private(set) var period: DrivePeriod = .twelveMonths
    var errorMessage: String?

    private let service: VehicleService
    /// 겹친 요청 중 최신 것만 결과를 반영한다.
    private var generation = 0

    init(service: VehicleService = VehicleService()) {
        self.service = service
    }

    // MARK: - 파생 값

    /// 거리 버킷 기준이다 — 시간대 카드와 같은 모수를 쓴다.
    var hasDrives: Bool { distanceDriveCount > 0 }

    /// `cars.efficiency`가 없으면 전비를 낼 수 없다. 카드를 감춘다.
    var showsEfficiency: Bool { insights?.efficiencyKwhPerKm != nil }

    /// **지오펜스가 하나도 없는 것이 이 차량의 기본 상태다**(`geofences` 0행).
    /// 「가끔 비는 경우」로 다루면 안 되고, 등록하기 전까지 이 카드는 늘 감춰진다.
    var showsPlaces: Bool { !(insights?.places.isEmpty ?? true) }

    struct TemperatureRow: Identifiable {
        let bucket: TemperatureBucket
        /// 서버는 합만 낸다. 이 나눗셈이 앱 몫이다.
        let kmPerKwh: Decimal?

        var id: String { bucket.id }
    }

    var temperatureRows: [TemperatureRow] {
        let efficiency = insights?.efficiencyKwhPerKm
        return (insights?.temperatureBuckets ?? []).map { bucket in
            TemperatureRow(
                bucket: bucket,
                kmPerKwh: VehicleMath.kmPerKwh(
                    distanceKm: bucket.distanceKm,
                    ratedRangeUsedKm: bucket.ratedRangeUsedKm,
                    efficiencyKwhPerKm: efficiency
                )
            )
        }
    }

    /// **두 수가 다르다.** 온도 쪽은 주행가능거리 소모가 0 이하인 주행을 뺀 뒤 센다
    /// (실측 최근 12개월: 939 대 959). 한 곳에서 뽑아 두 카드에 쓰면 어긋난다.
    var temperatureDriveCount: Int {
        (insights?.temperatureBuckets ?? []).reduce(0) { $0 + $1.driveCount }
    }

    var distanceDriveCount: Int {
        (insights?.distanceBuckets ?? []).reduce(0) { $0 + $1.driveCount }
    }

    /// 요일×시각 조회표. **응답을 받을 때 한 번만 편다.**
    ///
    /// 계산 속성으로 두면 히트맵이 한 번 그려질 때마다 168칸이 각자 딕셔너리를 새로 만든다 —
    /// 표본이 100칸만 돼도 draw 한 번에 1만 7천 번 도는 셈이다. 응답은 성기게 오므로
    /// (0인 칸은 빠진다) 저장 시점에 펴 두고 조회만 한다.
    private var heatMap: [Int: Int] = [:]
    private(set) var maxHeatCount = 0

    private func rebuildHeatMap() {
        let times = insights?.driveTimes ?? []
        // **`uniqueKeysWithValues`를 쓰지 않는다** — 서버가 같은 칸을 두 번 보내면 크래시한다.
        // 지금 SQL은 그러지 않지만, 서버 데이터로 앱이 죽는 길을 열어 둘 이유가 없다.
        heatMap = Dictionary(times.map { ($0.id, $0.count) }, uniquingKeysWith: +)
        maxHeatCount = heatMap.values.max() ?? 0
    }

    /// 없는 칸은 **0이다.** 「기록이 없다」가 아니라 「그 시각에 안 탔다」다.
    func heatCount(weekday: Int, hour: Int) -> Int { heatMap[weekday * 24 + hour] ?? 0 }

    // MARK: - 로드

    func load() async {
        guard insights == nil else { return }
        await fetch(period, clearingOnFailure: false)
    }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다** — 1단계 건강 화면과 같은 규칙이다.
    func reload() async {
        await fetch(period, clearingOnFailure: false)
    }

    /// 기간 칩. **실패하면 옛 기간의 값을 지운다** — 칩은 3개월인데 화면이 12개월 값이면
    /// 거짓말이 된다. 새로고침 실패와 다르게 다뤄야 하는 유일한 자리다.
    func select(_ next: DrivePeriod) async {
        guard next != period else { return }
        period = next
        await fetch(next, clearingOnFailure: true)
    }

    private func fetch(_ months: DrivePeriod, clearingOnFailure: Bool) async {
        generation += 1
        let current = generation
        if clearingOnFailure { insights = nil }
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let loaded = try await service.fetchDriveInsights(months: months.rawValue)
            guard current == generation else { return }
            insights = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            if clearingOnFailure { insights = nil }
            errorMessage = "주행 인사이트를 불러오지 못했습니다."
        }
    }
}
```

- [ ] **Step 4: 앱 타겟에 파일을 등록한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/ViewModels/VehicleDriveViewModel.swift
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

```bash
touch WooriHaru/ViewModels/VehicleDriveViewModel.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: PASS (`VehicleDriveViewModelTests` 13건 포함)

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/ViewModels/VehicleDriveViewModel.swift \
        WooriHaruTests/VehicleDriveTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 주행 인사이트 뷰모델을 더한다

네 카드가 한 응답에서 나오므로 기간 칩이 바뀌면 넷이 함께 바뀐다.
기간 변경 실패는 옛 기간 값을 지운다 — 칩과 화면이 어긋나면 거짓말이 된다."
```

---

### Task 4: 온도별 전비 카드와 거리 분포 카드

**Files:**
- Create: `WooriHaru/Views/Vehicle/DriveBucketCards.swift`

**Interfaces:**
- Consumes: `VehicleDriveViewModel.TemperatureRow`·`DistanceBucket`·`DriveFormat`·`VehicleFormat` (Task 1·3), `GlassCard` (기존)
- Produces:
  - `struct TemperatureEfficiencyCard: View` — `init(rows: [VehicleDriveViewModel.TemperatureRow], driveCount: Int)`
  - `struct DistanceDistributionCard: View` — `init(buckets: [DistanceBucket], driveCount: Int)`

두 카드가 같은 모양(라벨 + 가로 막대 + 값)이라 한 파일에 둔다. 단위 테스트는 없다 — 그리기만 하는 뷰이고 계산은 Task 1·3에서 테스트했다.

- [ ] **Step 1: `DriveBucketCards.swift`를 만든다**

```swift
import SwiftUI

/// 온도별 전비 — 가로 막대. 1단계와 같이 손으로 그린다(Swift Charts를 들이지 않는 관례).
///
/// **막대 길이는 전비에 비례하고, 0에서 시작하지 않는다.** 6.0과 7.6은 26% 차이인데
/// 0부터 그리면 둘 다 긴 막대가 되어 차이가 안 보인다. 가장 낮은 버킷을 짧게 남기고
/// 나머지를 그 위에 얹는다.
struct TemperatureEfficiencyCard: View {
    let rows: [VehicleDriveViewModel.TemperatureRow]
    /// **거리 카드와 다른 수다** — 주행가능거리 소모가 0 이하인 주행이 여기선 빠진다.
    let driveCount: Int

    /// 막대가 아무리 짧아도 이만큼은 남긴다 — 0이면 라벨만 뜬 빈 줄로 보인다.
    private static let minimumRatio: CGFloat = 0.12

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header("온도별 전비", "\(driveCount)회 기준")
                ForEach(rows) { row in
                    bar(row)
                }
                Text("주행가능거리가 준 만큼으로 환산한 값이라 실제 충전량과는 조금 달라요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private var maxValue: Decimal { rows.compactMap(\.kmPerKwh).max() ?? 0 }
    private var minValue: Decimal { rows.compactMap(\.kmPerKwh).min() ?? 0 }

    private func bar(_ row: VehicleDriveViewModel.TemperatureRow) -> some View {
        let ratio: CGFloat = {
            guard let value = row.kmPerKwh, maxValue > minValue else {
                return row.kmPerKwh == nil ? 0 : 1
            }
            let span = maxValue - minValue
            let scaled = (value - minValue) / span
            let raw = CGFloat(truncating: scaled as NSDecimalNumber)
            return Self.minimumRatio + raw * (1 - Self.minimumRatio)
        }()
        // 가장 좋은 버킷을 진하게 — 「언제가 제일 멀리 가나」가 이 카드의 질문이다.
        let isBest = row.kmPerKwh != nil && row.kmPerKwh == maxValue
        return HStack(spacing: 8) {
            Text(row.bucket.label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
                .frame(width: 54, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(isBest ? Color.blue600 : Color.blue300)
                    .frame(width: max(3, proxy.size.width * ratio))
            }
            .frame(height: 14)
            Text(VehicleFormat.efficiency(row.kmPerKwh))
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .frame(width: 74, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.bucket.label) \(VehicleFormat.efficiency(row.kmPerKwh)), \(DriveFormat.count(row.bucket.driveCount))")
    }
}

/// 한 번에 얼마나 — 건수 분포. **여기는 0에서 시작한다.** 건수는 절대량이라
/// 「0~5km가 압도적으로 많다」가 이 카드가 보여 줘야 하는 사실이다.
struct DistanceDistributionCard: View {
    let buckets: [DistanceBucket]
    /// **전비 카드와 다른 수다.** 여기선 걸러 내는 주행이 없다.
    let driveCount: Int

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header("한 번에 얼마나", "\(driveCount)회 기준")
                ForEach(buckets) { bucket in
                    bar(bucket)
                }
            }
        }
    }

    private var maxCount: Int { buckets.map(\.driveCount).max() ?? 0 }

    private func bar(_ bucket: DistanceBucket) -> some View {
        let ratio = maxCount > 0 ? CGFloat(bucket.driveCount) / CGFloat(maxCount) : 0
        return HStack(spacing: 8) {
            Text(bucket.label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
                .frame(width: 66, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    // 0인 버킷도 자리를 지킨다 — 건너뛰면 분포가 어긋나 보인다.
                    .fill(bucket.driveCount == 0 ? Color.slate200 : Color.green600)
                    .frame(width: max(3, proxy.size.width * ratio))
            }
            .frame(height: 14)
            Text(DriveFormat.count(bucket.driveCount))
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucket.label) \(DriveFormat.count(bucket.driveCount))")
    }
}

/// 두 카드가 같은 머리 모양을 쓴다 — 제목 왼쪽, 모수 오른쪽.
/// **모수를 카드마다 따로 적는다.** 두 카드의 총합이 다르기 때문이다.
private func header(_ title: String, _ trailing: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.slate500)
        Spacer(minLength: 8)
        Text(trailing)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Color.slate400)
    }
}

#Preview("버킷 카드") {
    let buckets = [
        // **`Decimal`에 부동소수 리터럴을 쓰지 않는다** — Double을 거쳐 값이 틀어진다.
        TemperatureBucket(fromC: nil, toC: 0, driveCount: 82,
                          distanceKm: Decimal(string: "2424.8")!,
                          ratedRangeUsedKm: Decimal(string: "2939.2")!),
        TemperatureBucket(fromC: 0, toC: 10, driveCount: 229,
                          distanceKm: Decimal(string: "6507.3")!,
                          ratedRangeUsedKm: Decimal(string: "7097.1")!),
        TemperatureBucket(fromC: 10, toC: 20, driveCount: 244,
                          distanceKm: Decimal(string: "5990.4")!,
                          ratedRangeUsedKm: Decimal(string: "5723.9")!),
        TemperatureBucket(fromC: 20, toC: 30, driveCount: 266,
                          distanceKm: Decimal(string: "5748.4")!,
                          ratedRangeUsedKm: Decimal(string: "5798.5")!),
        TemperatureBucket(fromC: 30, toC: nil, driveCount: 0,
                          distanceKm: 0, ratedRangeUsedKm: 0),
    ]
    let efficiency = Decimal(string: "0.1367")!
    let rows = buckets.map { bucket in
        VehicleDriveViewModel.TemperatureRow(
            bucket: bucket,
            kmPerKwh: VehicleMath.kmPerKwh(distanceKm: bucket.distanceKm,
                                           ratedRangeUsedKm: bucket.ratedRangeUsedKm,
                                           efficiencyKwhPerKm: efficiency)
        )
    }
    return ScrollView {
        VStack(spacing: 12) {
            TemperatureEfficiencyCard(rows: rows, driveCount: 939)
            DistanceDistributionCard(buckets: [
                DistanceBucket(fromKm: 0, toKm: 5, driveCount: 620, distanceKm: 1802),
                DistanceBucket(fromKm: 5, toKm: 20, driveCount: 210, distanceKm: 2400),
                DistanceBucket(fromKm: 20, toKm: 50, driveCount: 90, distanceKm: 2700),
                DistanceBucket(fromKm: 50, toKm: 100, driveCount: 36, distanceKm: 2500),
                DistanceBucket(fromKm: 100, toKm: nil, driveCount: 3, distanceKm: 412),
            ], driveCount: 959)
        }
        .padding(16)
    }
    .background(Color.slate50)
}
```

- [ ] **Step 2: 앱 타겟에 파일을 등록한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Vehicle/DriveBucketCards.swift
```

- [ ] **Step 3: 빌드가 통과하는지 확인한다**

```bash
touch WooriHaru/Views/Vehicle/DriveBucketCards.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: PASS

- [ ] **Step 4: 프리뷰를 눈으로 확인한다**

- 전비 카드: 「10~20℃」가 가장 긴 진한 막대, 「영하」가 가장 짧다. 「30℃ 이상」은 값이 없어 막대가 없고 「—」다.
- 거리 카드: 「0~5km」가 가장 긴 막대, 오른쪽 숫자가 「620회」.
- 두 카드의 모수가 각각 「939회 기준」·「959회 기준」으로 **다르게** 적혀 있다.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Vehicle/DriveBucketCards.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 온도별 전비와 거리 분포 카드를 그린다

전비는 0에서 시작하지 않는다 — 6.0과 7.6이 0부터면 둘 다 긴 막대가 된다.
건수는 절대량이라 0에서 시작한다. 두 카드는 모수가 달라 각자 적는다."
```

---

### Task 5: 시간대 히트맵

**Files:**
- Create: `WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift`

**Interfaces:**
- Consumes: `DriveFormat.weekdayLabel/hourLabel/count` (Task 1), `GlassCard` (기존)
- Produces: `struct DriveTimeHeatmap: View` — `init(count: @escaping (Int, Int) -> Int, maxCount: Int)`

- [ ] **Step 1: `DriveTimeHeatmap.swift`를 만든다**

```swift
import SwiftUI

/// 언제 타나 — 요일 × 시각 7 × 24 히트맵. 손으로 그린다.
///
/// **조회를 클로저로 받는다.** 서버가 0인 칸을 빼고 성기게 주므로 168칸을 배열로 펴서
/// 넘기면 뷰가 그 펴는 일을 알아야 한다. 뷰모델이 편 뒤 여기는 「이 칸 몇 회」만 묻는다.
///
/// **`weekday`는 0이 일요일이다**(PostgreSQL `dow` 그대로). 여기서 어긋나면 히트맵 전체가
/// 하루씩 밀리는데, 밀린 채로도 그럴듯해 보여서 눈으로는 잡히지 않는다.
struct DriveTimeHeatmap: View {
    let count: (Int, Int) -> Int
    let maxCount: Int

    /// 눈금을 다는 시각. 24개를 다 적으면 읽을 수 없다.
    private static let markedHours = [0, 6, 12, 18]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("언제 타나")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                ForEach(0..<7, id: \.self) { weekday in
                    row(weekday)
                }
                hourAxis
            }
        }
    }

    private func row(_ weekday: Int) -> some View {
        HStack(spacing: 2) {
            Text(DriveFormat.weekdayLabel(weekday))
                .font(.system(size: 10))
                // 주말을 조금 다르게 둔다 — 출퇴근 패턴이 주중에 몰리는지 보는 자리다.
                .foregroundStyle(weekday == 0 || weekday == 6 ? Color.orange700 : Color.slate500)
                .frame(width: 16, alignment: .leading)
            ForEach(0..<24, id: \.self) { hour in
                cell(weekday: weekday, hour: hour)
            }
        }
    }

    private func cell(weekday: Int, hour: Int) -> some View {
        let value = count(weekday, hour)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color(for: value))
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(
                "\(DriveFormat.weekdayLabel(weekday))요일 \(DriveFormat.hourLabel(hour)) \(DriveFormat.count(value))"
            )
    }

    /// 0은 **빈칸**이다 — 옅은 색으로 칠하면 「조금 탔다」로 읽힌다.
    private func color(for value: Int) -> Color {
        guard value > 0, maxCount > 0 else { return Color.slate100 }
        let ratio = Double(value) / Double(maxCount)
        return Color.blue600.opacity(0.15 + 0.85 * ratio)
    }

    private var hourAxis: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: 16)
            ForEach(0..<24, id: \.self) { hour in
                Text(Self.markedHours.contains(hour) ? "\(hour)" : "")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview("히트맵") {
    // 출퇴근이 보이는 모양 — 월~금 08시·17시가 진하다.
    let sample: [Int: Int] = {
        var map: [Int: Int] = [:]
        for weekday in 1...5 {
            map[weekday * 24 + 8] = 35 + weekday
            map[weekday * 24 + 17] = 30 + weekday
            map[weekday * 24 + 12] = 8
        }
        map[0 * 24 + 14] = 12
        map[6 * 24 + 11] = 15
        return map
    }()
    return VStack(spacing: 12) {
        DriveTimeHeatmap(count: { sample[$0 * 24 + $1] ?? 0 }, maxCount: 40)
        // 표본이 없을 때
        DriveTimeHeatmap(count: { _, _ in 0 }, maxCount: 0)
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 2: 앱 타겟에 파일을 등록한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift
```

- [ ] **Step 3: 빌드가 통과하는지 확인한다**

```bash
touch WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: PASS

- [ ] **Step 4: 프리뷰를 눈으로 확인한다**

- 24칸이 가로로 다 들어가고 잘리지 않는다(아이폰 폭에서 칸 하나가 대략 11pt다).
- 첫 줄이 「일」이고 그 줄의 14시가 옅게 차 있다 — **0이 일요일**인지 여기서 보인다.
- 월~금 08시·17시가 진하다. 주말 라벨이 주황이다.
- 둘째 프리뷰(표본 없음)는 전부 `slate100` 빈칸이다.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 요일×시각 히트맵을 그린다

응답이 0인 칸을 빼고 성기게 오므로 뷰모델이 편 뒤 뷰는 조회만 한다.
0은 빈칸이다 — 옅게 칠하면 「조금 탔다」로 읽힌다."
```

---

### Task 6: 자주 가는 곳 카드와 주행 탭 조립

**Files:**
- Create: `WooriHaru/Views/Vehicle/VehicleDriveTab.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleView.swift`

**Interfaces:**
- Consumes: `VehicleDriveViewModel` (Task 3), `TemperatureEfficiencyCard`·`DistanceDistributionCard` (Task 4), `DriveTimeHeatmap` (Task 5), `DrivePlace`·`DrivePeriod` (Task 1), `GlassCard` (기존)
- Produces: `struct VehicleDriveTab: View` — `init(viewModel: VehicleDriveViewModel)`

「자주 가는 곳」은 카드 하나뿐이고 이 탭에서만 쓰므로 탭 파일 안에 둔다.

- [ ] **Step 1: `VehicleDriveTab.swift`를 만든다**

```swift
import SwiftUI

/// 주행 탭 — 온도별 전비·시간대·거리 분포·자주 가는 곳. 네 카드가 **한 응답**에서 나온다.
///
/// **기간 칩은 화면 맨 위 하나다.** 카드마다 기간이 다르면 서로 비교가 안 된다.
/// 요약 탭의 월 스와이프는 여기 걸지 않는다 — 이 탭의 기간 단위는 달이 아니다.
struct VehicleDriveTab: View {
    @Bindable var viewModel: VehicleDriveViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                periodChips.padding(.top, 8)

                // 값이 남아 있는 새로고침 실패는 한 줄로만 알린다 — 1단계 건강 화면과 같다.
                if let error = viewModel.errorMessage, viewModel.insights != nil {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await viewModel.reload() }
    }

    private var periodChips: some View {
        HStack(spacing: 8) {
            ForEach(DrivePeriod.allCases) { period in
                chip(period)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ period: DrivePeriod) -> some View {
        let selected = viewModel.period == period
        return Button {
            Task { await viewModel.select(period) }
        } label: {
            Text(period.label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(selected ? .white : Color.slate500)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(Color.blue600)
                    } else {
                        Capsule().fill(Color.slate100)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// **네 갈래다** — 못 받음 / 아직 안 받음 / 그 기간에 주행 없음 / 값 있음.
    /// 「기록 없음」과 「못 받음」을 한 화면으로 뭉개지 않는 관례를 따른다.
    @ViewBuilder private var content: some View {
        if viewModel.insights == nil, let error = viewModel.errorMessage {
            errorState(error).padding(.top, 48)
        } else if viewModel.insights == nil {
            ProgressView().padding(.top, 60)
        } else if !viewModel.hasDrives {
            // 카드마다 비우지 않고 화면 하나로 말한다.
            ContentUnavailableView {
                Label("이 기간에 주행 기록이 없어요", systemImage: "car")
            } description: {
                Text("기간을 늘려 보세요")
            }
            .padding(.top, 48)
        } else {
            cards
        }
    }

    @ViewBuilder private var cards: some View {
        // `cars.efficiency`가 없으면 전비를 낼 수 없다. 카드째 감춘다 —
        // 다섯 줄이 전부 「—」인 카드는 자리만 차지한다.
        if viewModel.showsEfficiency {
            TemperatureEfficiencyCard(rows: viewModel.temperatureRows,
                                      driveCount: viewModel.temperatureDriveCount)
        }
        DriveTimeHeatmap(count: { viewModel.heatCount(weekday: $0, hour: $1) },
                         maxCount: viewModel.maxHeatCount)
        DistanceDistributionCard(buckets: viewModel.insights?.distanceBuckets ?? [],
                                 driveCount: viewModel.distanceDriveCount)
        // **지오펜스가 없는 것이 이 차량의 기본 상태다**(`geofences` 0행). 등록하기
        // 전까지 이 카드는 늘 감춰진다 — 「가끔 비는 경우」가 아니다.
        if viewModel.showsPlaces {
            placesCard
        }
    }

    private var placesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("자주 가는 곳")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)
                ForEach(viewModel.insights?.places ?? []) { place in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // **이름만 낸다** — 주소는 서버가 싣지 않는다.
                        Text(place.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.slate900)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(DriveFormat.count(place.driveCount))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.slate500)
                        Text(VehicleFormat.distance(place.distanceKm))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.slate400)
                            .frame(width: 66, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("주행 인사이트를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await viewModel.reload() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 2: `VehicleView.swift`에 탭을 하나 더한다**

다섯 곳을 고친다.

(1) 파일 맨 위 주석과 탭 정의·뷰모델:

```swift
/// 「차량」 미니앱 — 건강·주행·요약 세 탭. 가계부와 같은 하단 글래스 탭바 구조다.
/// **여는 순간 건강 화면이 먼저 뜬다** — 첫 화면이 답을 하나 해야 한다.
/// **세 개가 상한이다** — 더 늘리려는 순간 화면을 합칠 자리를 먼저 찾는다.
struct VehicleView: View {
    private enum Tab { case health, drive, summary }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .health
    @State private var summaryViewModel = VehicleSummaryViewModel()
    @State private var statusViewModel = VehicleStatusViewModel()
    @State private var healthViewModel = VehicleHealthViewModel()
    @State private var driveViewModel = VehicleDriveViewModel()
    @State private var showingMonthPicker = false
    @State private var showingQueue = false
```

(2) `content`에 갈래를 하나 더한다. **주행 탭은 처음 열 때만 받는다** — 전 기간 집계라 탭을 오갈 때마다 다시 부를 일이 아니다(`load()`가 `insights == nil`로 거른다):

```swift
        case .drive:
            VehicleDriveTab(viewModel: driveViewModel)
                .task { await driveViewModel.load() }
```

`.health` 갈래와 `.summary` 갈래는 그대로 둔다.

(3) `principalTitle`:

```swift
    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .health: Text("차량 건강").font(.subheadline).fontWeight(.bold)
        case .drive: Text("주행").font(.subheadline).fontWeight(.bold)
        case .summary: monthSwitcher
        }
    }
```

(4) 탭바 — 건강·주행·요약 순. **버튼이 셋이 되므로 좌우 여백을 줄인다**(60은 두 개일 때의 값이다):

```swift
    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.health, icon: "bolt.batteryblock.fill", label: "건강")
            tabButton(.drive, icon: "steeringwheel", label: "주행")
            tabButton(.summary, icon: "chart.bar.fill", label: "요약")
        }
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        // 버튼 사이 여백 탭이 아래 목록으로 새지 않게 바 전체를 히트 영역으로 만든다.
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {}
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }
```

**손대지 않는 곳:** `monthSwipeGesture`의 `including: tab == .summary ? .all : .subviews`는 그대로 맞다 — 주행 탭도 월이 없으므로 `.subviews`로 꺼진다. `fullScreenCover(onDismiss:)`도 그대로다(주행 탭에는 배지가 없다).

- [ ] **Step 3: 앱 타겟에 파일을 등록한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Vehicle/VehicleDriveTab.swift
```

- [ ] **Step 4: 전체 테스트를 clean으로 돌린다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test 2>&1 | tail -50
```
Expected: PASS — 기존 643건 + 이 계획의 신규분이 전부 통과.

`steeringwheel` SF Symbol이 이 SDK에 없어 빌드가 깨지면 `car.side.fill`로 바꾸고 보고한다.

- [ ] **Step 5: 실기로 확인한다**

**이 계획에서 코드로 확인할 수 없는 항목이다.** 시뮬레이터에서 차량 미니앱을 연다:

1. 탭바에 **건강 · 주행 · 요약** 세 개가 있고 글자가 겹치지 않는다.
2. 미니앱을 열면 **건강 화면이 먼저** 뜬다.
3. 「주행」을 누르면 기간 칩이 **최근 12개월**로 선택돼 있고 카드가 그려진다.
4. **최근 3개월**을 누르면 네 카드가 **함께** 바뀐다.
5. 주행 탭에서 좌우로 쓸어도 **아무 일도 없다**(요약 탭에서만 달이 바뀐다).
6. 건강 탭으로 갔다 주행 탭으로 돌아오면 **다시 부르지 않고** 보던 화면 그대로다.
7. 「자주 가는 곳」 카드는 **보이지 않는다**(지오펜스가 0행이다).

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Views/Vehicle/VehicleDriveTab.swift WooriHaru/Views/Vehicle/VehicleView.swift \
        WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 차량 미니앱에 주행 탭을 더한다

탭이 하나 늘 뿐 건강 화면을 건드리지 않는다. 기간 칩은 화면 맨 위 하나이고
네 카드가 같은 기간을 본다 — 카드마다 기간이 다르면 서로 비교가 안 된다."
```

---

### Task 7: 설계 문서에 2단계 완료를 적는다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md`

- [ ] **Step 1: 단계 표와 2단계 절에 상태를 적는다**

「단계」 표의 2단계 행 `내용` 칸 끝에 `**(구현 완료, 2026-08-19)**`를 붙이고, `# 2단계 — 주행 인사이트` 제목 바로 아래에 넣는다:

```markdown
> **구현 완료(2026-08-19).** 계획은 `docs/superpowers/plans/2026-08-19-vehicle-drive-insights.md`다.
> 구현하며 이 문서와 갈라진 곳이 넷이다.
>
> - **`/tesla/drive-insights` 응답도 `data` 래퍼 안에 온다.** 1단계와 같다.
> - **버킷 다섯 칸은 서버가 늘 채워 보낸다.** 백엔드 문서의 JSON 예시가 두 칸만 보여 주는
>   것은 줄임 표기이고, 실제로는 빈 버킷도 `driveCount: 0`으로 자리를 지킨다 —
>   **앱이 빈 칸을 만들 필요가 없다.** `driveTimes`만 0인 칸이 빠져 성기게 온다.
> - **`efficiencyKwhPerKm`이 null이면 전비 카드를 카드째 감춘다.** 아래 본문은 이 경우를
>   적지 않았다. 다섯 줄이 전부 「—」인 카드는 자리만 차지한다.
> - **기간 칩을 바꾸다 실패하면 옛 기간의 값을 지운다.** 당겨서 새로고침이 실패할 때
>   있던 값을 남기는 것과 **반대로** 다룬다 — 칩은 「최근 3개월」인데 화면이 12개월 값이면
>   거짓말이 된다. 이 문서의 「엣지 케이스」 절은 이 구분을 적지 않았다.
>
> 아래 본문이 적은 「12개월 N건이 카드마다 다른 수다」는 그대로 지켜진다 —
> 전비 카드는 939, 거리·시간대 카드는 959를 각자 낸다.
```

- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md
git commit -m "docs: 2단계 구현 완료와 문서에서 갈라진 곳을 적는다"
```

---

## 이 계획이 다루지 않는 것

- **3단계(곁가지)와 보류(`positions`).** 각 단계는 그 자체로 쓸 만한 화면이 하나씩 완성되므로 계획도 따로 쓴다. 3단계 서버 API(`/tesla/charges/totals`·`/tesla/charges/{id}/curve`)는 이미 확정돼 있고, **누적 스탯 타일의 넷째 칸**과 **충전 곡선 다운샘플링 방식**이 그 계획의 첫 결정 사항이다.
- **1단계 화면.** 건강 탭은 한 줄도 바꾸지 않는다.
- **금액 입력 경로.** 큐 화면과 상세 「금액 수정」은 손대지 않는다.
- **배지 카운트 주인이 둘인 문제.** 1단계 최종 리뷰에서 파킹했다 — 근본 해법이 `VehicleView`로 카운트를 올리는 구조 변경이라 별도 작업이다. 주행 탭에는 배지가 없어 이 계획이 그 문제를 키우지 않는다.
