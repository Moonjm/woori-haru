# 차량 대시보드 3단계(곁가지) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 누적 스탯 타일·충전 행 배터리 게이지·급속 충전 곡선 셋을 더한다.

**Architecture:** 서로 독립한 세 조각이라 순서가 없다. 누적 타일은 건강 화면 위쪽에 `GET /tesla/charges/totals` 하나로 붙고, 배터리 게이지는 요약 탭 목록의 기존 `ChargeRow`에 **서버 변경 없이** 붙으며, 곡선은 충전 상세에서 `GET /tesla/charges/{id}/curve`를 부른다. 1·2단계 화면은 건드리지 않는다. 차트는 앞 단계와 같이 전부 손으로 그린다.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), `@Observable` 뷰모델, Swift Testing(`import Testing`), 기존 `APIClientProtocol`·`MockAPIClient`·`GlassCard`.

**Spec:** `docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md` (「3단계 — 곁가지」 절)
(서버 계약: toy-back `docs/superpowers/plans/2026-08-18-tesla-charge-totals-curve.md`, 구현은 `apps/daily-record/src/main/kotlin/com/toy/backend/tesla/TeslaChargeDtos.kt`)

## Global Constraints

- **테스트 명령:** `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test`. 현재 **671**건 통과.
- **증분 빌드가 변경을 놓치는 일이 있다.** 마지막 테스트 실행 전에 바꾼 파일을 `touch`하고, 마지막 태스크는 `clean test`로 확인한다.
- **1·2단계 화면을 건드리지 않는다.** `VehicleHealthTab`·`BatteryHealthCard`·`DegradationTrendChart`·`TirePressureCard`·`VehicleHealthViewModel`·`VehicleDriveTab`·`DriveBucketCards`·`DriveTimeHeatmap`·`VehicleDriveViewModel`은 한 줄도 수정하지 않는다. 예외는 Task 3이 건강 화면에 타일 카드 **한 줄을 얹는 것**뿐이다.
- **금액 입력 경로를 건드리지 않는다.** `ChargeCostQueueView`·`ChargeService`의 금액 수정 경로는 diff 0줄이어야 한다.
- **나눗셈은 앱이 한다.** 분모가 없거나 0이면 결과는 nil이다.
- **없는 값은 0이 아니라 「—」다**(`ChargeFormat.placeholder`).
- **표기와 판정은 같은 반올림을 쓴다.** 정수로 낼 값은 `VehicleFormat.number`에 넘기기 전에 `VehicleMath.rounded`로 먼저 반올림한다(1단계에서 세운 규칙).
- **`Decimal`에 부동소수 리터럴을 쓰지 않는다** — Double을 거쳐 값이 틀어진다. `Decimal(string:)`을 쓴다.
- 커밋 메시지는 한국어 관례를 따른다. 코드 주석도 한국어로, 저장소의 기존 밀도·어투를 따른다.

### 이 계획이 확정한 것 (설계 문서가 미뤄 둔 결정)

설계 문서가 「이 결정은 이 문서가 내리지 않는다 — 화면을 만들 때 정한다」고 남긴 것들이다. 실측과 사용자 판단으로 확정했다(2026-08-19).

1. **누적 스탯 타일의 넷째 칸은 「급속·완속 단가」다.** 원래 후보였던 **주유비 대비 절감액은 폐기한다** — 유가·연비 상수를 앱에 박아야 하는데 박는 순간부터 틀려지기 시작하고, 「내연차였으면」이라는 가정 자체가 임의적이다. 단가는 **상수 없이 서버 데이터만으로** 나오고 행동을 바꾸는 숫자다(실측: 급속 289원 대 완속 209원, **38% 차이**).
2. **충전 곡선의 x축은 경과 시간이다.** 서버가 KST 시각만 주므로 앱이 첫 샘플에서 빼서 분으로 바꾼다. SoC 축이 테이퍼는 더 선명하지만, 곡선을 여는 이유가 대개 「왜 오래 걸렸지」라 그 질문에 답하는 축이 시간이다. 실측 사례: 세션 468은 앞 8분이 63kW에 묶여 있었는데 **SoC 축이면 그 구간이 왼쪽 끝에 짓눌려 사라진다.**
3. **곡선은 급속에만 그린다.** 완속은 실측으로 7시간 내내 6kW 한 줄이고(세션 475: 1,214샘플, 421분, 최고 6kW), 볼 것이 없는데 샘플만 급속의 3.4배다. `ChargeDetail.fastCharger`가 이미 오므로 서버 변경이 필요 없다.

### 실측된 참값 (테스트 픽스처는 이 값을 쓴다)

라즈베리파이 실 DB, 2026-08-19:

| 항목 | 급속 | 완속 |
|---|---|---|
| 세션 수(`charge_energy_used > 0`) | 39 | 431 |
| 금액 미입력 | **22** | 10 |
| 사용 전력 합 | 1,320.2kWh | 16,877.1kWh |
| 미입력분 사용 전력 | 833.9kWh | 143.1kWh |
| 낸 돈 | 140,479원 | 3,493,723원 |
| **단가** | **288.9원/kWh** | **208.8원/kWh** |

곡선 샘플 수: 급속 중앙값 254개·최대 **510개**(간격 5.5초), 완속 중앙값 1,155개·최대 1,980개(간격 20.5초).

---

### Task 1: 누적 스탯 응답 모델과 단가 계산

**Files:**
- Create: `WooriHaru/Models/ChargeTotalsModels.swift`
- Test: `WooriHaruTests/ChargeTotalsTests.swift`

**Interfaces:**
- Consumes: `VehicleMath`·`VehicleFormat`·`ChargeFormat`·`LedgerFormat` (기존)
- Produces:
  - `struct ChargeTotalsResponse: Codable, Equatable` — `chargeCount: Int`, `energyAddedKwh: Decimal?`, `energyUsedKwh: Decimal?`, `cost: Decimal?`, `costMissingCount: Int`, `costMissingEnergyUsedKwh: Decimal?`, `firstChargedAt: String?`, `fast: ChargeTotalsBreakdown`, `slow: ChargeTotalsBreakdown`
  - `struct ChargeTotalsBreakdown: Codable, Equatable` — `chargeCount`, `energyAddedKwh`, `energyUsedKwh`, `cost`, `costMissingCount`, `costMissingEnergyUsedKwh`; 파생 `pricedCount: Int`
  - `extension VehicleMath` — `wonPerKwh(cost:energyUsedKwh:costMissingEnergyUsedKwh:) -> Decimal?`
  - `extension VehicleFormat` — `wonPerKwh(_:) -> String`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ChargeTotalsTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct ChargeTotalsTests {

    /// **미입력분 사용 전력을 분모에서 뺀다.** 안 빼면 낸 돈은 그대로인데 분모만 커져
    /// 단가가 낮게 나온다 — 실측(2026-08-18) 200.3 대 211.6원/kWh로 5.6% 어긋났다.
    @Test func 단가는_미입력분을_분모에서_뺀다() {
        let priced = VehicleMath.wonPerKwh(
            cost: 3644562,
            energyUsedKwh: Decimal(string: "18197.2")!,
            costMissingEnergyUsedKwh: Decimal(string: "977.0")!
        )
        #expect(VehicleFormat.wonPerKwh(priced) == "₩212/kWh")

        // 빼지 않으면 이 값이 된다 — 회귀를 잡으려고 함께 못박는다.
        let naive = VehicleMath.wonPerKwh(
            cost: 3644562, energyUsedKwh: Decimal(string: "18197.2")!, costMissingEnergyUsedKwh: 0
        )
        #expect(VehicleFormat.wonPerKwh(naive) == "₩200/kWh")
        #expect(priced! > naive!)
    }

    /// 실측 그대로다 — 급속이 완속보다 38% 비싸다. 이 차이가 넷째 칸의 존재 이유다.
    @Test func 급속이_완속보다_비싸다() {
        let fast = VehicleMath.wonPerKwh(cost: 140479,
                                         energyUsedKwh: Decimal(string: "1320.2")!,
                                         costMissingEnergyUsedKwh: Decimal(string: "833.9")!)
        let slow = VehicleMath.wonPerKwh(cost: 3493723,
                                         energyUsedKwh: Decimal(string: "16877.1")!,
                                         costMissingEnergyUsedKwh: Decimal(string: "143.1")!)
        #expect(VehicleFormat.wonPerKwh(fast) == "₩289/kWh")
        #expect(VehicleFormat.wonPerKwh(slow) == "₩209/kWh")
        #expect(fast! > slow!)
    }

    /// 분모가 사라지는 경우들. **전부 미입력이면 단가를 낼 수 없다** — 0원이 아니다.
    @Test func 낼_수_없으면_단가도_없다() {
        #expect(VehicleMath.wonPerKwh(cost: nil, energyUsedKwh: 100, costMissingEnergyUsedKwh: 0) == nil)
        #expect(VehicleMath.wonPerKwh(cost: 1000, energyUsedKwh: nil, costMissingEnergyUsedKwh: 0) == nil)
        // 전부 미입력 — 분모가 0이 된다.
        #expect(VehicleMath.wonPerKwh(cost: 0, energyUsedKwh: 100, costMissingEnergyUsedKwh: 100) == nil)
        // 미입력분이 사용 전력보다 크게 오는 일은 없어야 하지만, 와도 죽지 않는다.
        #expect(VehicleMath.wonPerKwh(cost: 1000, energyUsedKwh: 100, costMissingEnergyUsedKwh: 120) == nil)
        #expect(VehicleFormat.wonPerKwh(nil) == ChargeFormat.placeholder)
    }

    /// 단가를 낸 표본이 몇 건인지 화면이 적어야 한다 — 급속은 39건 중 22건이 미입력이라
    /// **17건에서만 나온 값**이다. 「289원」만 크게 적으면 그 얇음이 숨는다.
    @Test func 단가를_낸_표본_수를_센다() {
        let fast = ChargeTotalsBreakdown(
            chargeCount: 39, energyAddedKwh: nil, energyUsedKwh: nil,
            cost: nil, costMissingCount: 22, costMissingEnergyUsedKwh: nil
        )
        #expect(fast.pricedCount == 17)
    }

    /// `fast + slow = 최상위` 불변식이 선다. 최상위 중복은 의도된 것이다 — 헤드라인과 내역이다.
    @Test func 급속과_완속을_더하면_최상위다() throws {
        let json = """
        { "chargeCount": 474, "energyAddedKwh": 17442.0, "energyUsedKwh": 18197.2,
          "cost": 3644562, "costMissingCount": 35, "costMissingEnergyUsedKwh": 977.0,
          "firstChargedAt": "2021-09-03",
          "fast": { "chargeCount": 42, "energyAddedKwh": 1358.4, "energyUsedKwh": 1329.0,
                    "cost": 143337, "costMissingCount": 24, "costMissingEnergyUsedKwh": 833.9 },
          "slow": { "chargeCount": 432, "energyAddedKwh": 16083.6, "energyUsedKwh": 16868.2,
                    "cost": 3501225, "costMissingCount": 11, "costMissingEnergyUsedKwh": 143.1 } }
        """.data(using: .utf8)!

        let t = try JSONDecoder().decode(ChargeTotalsResponse.self, from: json)

        #expect(t.fast.chargeCount + t.slow.chargeCount == t.chargeCount)
        #expect(t.fast.costMissingCount + t.slow.costMissingCount == t.costMissingCount)
        #expect(t.fast.cost! + t.slow.cost! == t.cost!)
        #expect(t.firstChargedAt == "2021-09-03")
    }

    /// 구버전 데이터에서 합이 nil일 수 있다. 0으로 읽지 않는다.
    @Test func 합이_비어도_디코딩된다() throws {
        let json = """
        { "chargeCount": 0, "energyAddedKwh": null, "energyUsedKwh": null,
          "cost": null, "costMissingCount": 0, "costMissingEnergyUsedKwh": null,
          "firstChargedAt": null,
          "fast": { "chargeCount": 0, "energyAddedKwh": null, "energyUsedKwh": null,
                    "cost": null, "costMissingCount": 0, "costMissingEnergyUsedKwh": null },
          "slow": { "chargeCount": 0, "energyAddedKwh": null, "energyUsedKwh": null,
                    "cost": null, "costMissingCount": 0, "costMissingEnergyUsedKwh": null } }
        """.data(using: .utf8)!

        let t = try JSONDecoder().decode(ChargeTotalsResponse.self, from: json)

        #expect(t.energyAddedKwh == nil)
        #expect(t.firstChargedAt == nil)
        #expect(t.fast.pricedCount == 0)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: 컴파일 실패 — `cannot find 'ChargeTotalsResponse' in scope`

- [ ] **Step 3: `ChargeTotalsModels.swift`를 만든다**

```swift
import Foundation

// MARK: - 응답

/// 전 기간 충전 누적. 파라미터가 없다.
///
/// **`/tesla/summary`의 월별 합과도, `/tesla/charges/missing-cost`의 `totalCount`와도 다른 수다** —
/// 그쪽 배지는 최근 한 달 창이고 이쪽은 전 기간이다. **두 값을 같은 배지로 쓰면 어긋난다.**
struct ChargeTotalsResponse: Codable, Equatable {
    let chargeCount: Int
    let energyAddedKwh: Decimal?
    /// 벽에서 뽑아쓴 양. **kWh당 단가의 분모는 이쪽이다.**
    let energyUsedKwh: Decimal?
    /// **실제로 낸 돈이다.** 금액이 빈 세션은 여기 없다.
    let cost: Decimal?
    /// 금액이 비어 있는 건수. **서버는 이것을 「무료 충전」이라고 부르지 않는다** —
    /// DB에 남은 것은 「금액 없음」이지 「0원」이 아니다. 라벨은 앱이 붙인다.
    let costMissingCount: Int
    /// 그 미입력 건들이 쓴 전력. **단가의 분모에서 이만큼을 뺀다.**
    let costMissingEnergyUsedKwh: Decimal?
    let firstChargedAt: String?
    /// **`fast + slow = 최상위`가 선다.** 최상위와 겹치는 것은 의도된 것이다 — 헤드라인과 내역이다.
    let fast: ChargeTotalsBreakdown
    let slow: ChargeTotalsBreakdown
}

struct ChargeTotalsBreakdown: Codable, Equatable {
    let chargeCount: Int
    let energyAddedKwh: Decimal?
    let energyUsedKwh: Decimal?
    let cost: Decimal?
    let costMissingCount: Int
    let costMissingEnergyUsedKwh: Decimal?

    /// 단가를 실제로 낸 표본 수. **급속은 39건 중 22건이 미입력이라 17건에서만 나온다** —
    /// 화면이 「289원」만 크게 적으면 그 얇음이 숨는다.
    var pricedCount: Int { max(0, chargeCount - costMissingCount) }
}

// MARK: - 계산

extension VehicleMath {
    /// kWh당 단가. **미입력분 사용 전력을 분모에서 뺀다.**
    ///
    /// 안 빼면 낸 돈은 그대로인데 분모만 커져 단가가 낮게 나온다 — 실측(2026-08-18)으로
    /// 200.3 대 211.6원/kWh, 5.6% 어긋났다. 「무료로 받은 전기까지 돈 주고 산 것처럼」 세는 셈이다.
    ///
    /// 전부 미입력이면 분모가 0이 되어 nil이다 — **0원이 아니다.**
    static func wonPerKwh(
        cost: Decimal?, energyUsedKwh: Decimal?, costMissingEnergyUsedKwh: Decimal?
    ) -> Decimal? {
        guard let cost, let energyUsedKwh else { return nil }
        let priced = energyUsedKwh - (costMissingEnergyUsedKwh ?? 0)
        guard priced > 0 else { return nil }
        return cost / priced
    }
}

// MARK: - 표기

extension VehicleFormat {
    /// 211.6… → "₩212/kWh". `costPerKm`과 같은 모양이다.
    static func wonPerKwh(_ value: Decimal?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return "\(LedgerFormat.amount(rounded(value), currency: "KRW"))/kWh"
    }
}
```

> `VehicleMath.rounded`·`VehicleFormat.number`는 1단계에서 이미 파일 밖으로 열려 있다.
> `LedgerFormat.amount`는 `VehicleFormat.costPerKm`이 쓰는 것과 같다.

- [ ] **Step 4: 테스트를 통과시킨다**

```bash
touch WooriHaru/Models/ChargeTotalsModels.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: PASS (`ChargeTotalsTests` 6건 포함, 기존 671건도 통과)

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/ChargeTotalsModels.swift WooriHaruTests/ChargeTotalsTests.swift \
        WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 충전 누적 응답 모델과 kWh당 단가를 더한다

단가의 분모에서 금액 미입력분 사용 전력을 뺀다 — 안 빼면 무료로 받은 전기까지
돈 주고 산 것처럼 세어 5.6% 낮게 나온다."
```

---

### Task 2: 서비스 호출 둘

**Files:**
- Modify: `WooriHaru/Services/ChargeService.swift`
- Test: `WooriHaruTests/ChargeTests.swift`

**Interfaces:**
- Consumes: `ChargeTotalsResponse` (Task 1), `ChargeCurveResponse` (아래에서 함께 정의), `APIClientProtocol`·`DataResponse` (기존)
- Produces:
  - `ChargeService.fetchTotals() async throws -> ChargeTotalsResponse`
  - `ChargeService.fetchCurve(id: Int) async throws -> ChargeCurveResponse`
  - `WooriHaru/Models/ChargeTotalsModels.swift`에 추가: `struct ChargeCurveResponse: Codable, Equatable { let samples: [ChargeCurveSample] }`, `struct ChargeCurveSample: Codable, Equatable, Identifiable { let at: String; let powerKw: Int?; let batteryLevel: Int? }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ChargeTests.swift` 안 `ChargeServiceTests`(또는 같은 성격의 struct) 끝에 넣는다. 파일의 기존 스텁 방식을 그대로 따른다:

```swift
    /// 파라미터가 없다. 전 기간이다.
    @Test func 누적은_파라미터_없이_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/totals", result: DataResponse<ChargeTotalsResponse>(
            data: ChargeTotalsResponse(
                chargeCount: 474, energyAddedKwh: nil, energyUsedKwh: nil, cost: nil,
                costMissingCount: 35, costMissingEnergyUsedKwh: nil, firstChargedAt: "2021-09-03",
                fast: ChargeTotalsBreakdown(chargeCount: 42, energyAddedKwh: nil, energyUsedKwh: nil,
                                            cost: nil, costMissingCount: 24,
                                            costMissingEnergyUsedKwh: nil),
                slow: ChargeTotalsBreakdown(chargeCount: 432, energyAddedKwh: nil, energyUsedKwh: nil,
                                            cost: nil, costMissingCount: 11,
                                            costMissingEnergyUsedKwh: nil)
            )
        ))
        let service = ChargeService(api: mock)

        let totals = try await service.fetchTotals()

        #expect(totals.chargeCount == 474)
        #expect(mock.getCalls.map(\.path) == ["/tesla/charges/totals"])
        #expect(mock.getCalls.first?.query == [:])
    }

    @Test func 곡선은_id를_경로에_넣어_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/402/curve", result: DataResponse<ChargeCurveResponse>(
            data: ChargeCurveResponse(samples: [
                ChargeCurveSample(at: "2025-09-10T13:02:11", powerKw: 166, batteryLevel: 11),
            ])
        ))
        let service = ChargeService(api: mock)

        let curve = try await service.fetchCurve(id: 402)

        #expect(curve.samples.count == 1)
        #expect(mock.getCalls.map(\.path) == ["/tesla/charges/402/curve"])
    }

    /// **샘플이 없는 세션은 빈 배열이다** — 없는 id·진행 중(404)과 다르게 그려야 한다.
    @Test func 샘플이_없어도_에러가_아니다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/9/curve",
                     result: DataResponse<ChargeCurveResponse>(data: ChargeCurveResponse(samples: [])))
        let service = ChargeService(api: mock)

        #expect(try await service.fetchCurve(id: 9).samples.isEmpty)
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다** — `has no member 'fetchTotals'`

- [ ] **Step 3: 모델과 서비스를 더한다**

`WooriHaru/Models/ChargeTotalsModels.swift` 끝에:

```swift
// MARK: - 곡선

/// 한 세션의 kW 곡선. **서버가 줄이지 않고 그대로 낸다** — 실측으로 급속 최대 510개,
/// 완속 최대 1,980개다. 어느 점을 버릴지는 앱이 정한다.
struct ChargeCurveResponse: Codable, Equatable {
    /// 시각순. **샘플이 없는 세션은 빈 배열이다**(null이 아니다).
    /// 없는 id·진행 중인 세션은 404라 여기까지 오지 않는다 — 둘을 다르게 그려야 한다.
    let samples: [ChargeCurveSample]
}

struct ChargeCurveSample: Codable, Equatable, Identifiable {
    /// KST 벽시계. **경과 분은 서버가 내지 않는다** — 첫 샘플에서 빼는 것이 앱 몫이다.
    let at: String
    /// **null일 수 있고 0kW와 구분된다** — 0은 「그때 안 들어갔다」, null은 「모른다」다.
    let powerKw: Int?
    let batteryLevel: Int?

    var id: String { at }
    /// **`LedgerFormat.parseDateTime`을 쓴다** — 서버 시각끼리 빼는 값이라 기기 시간대로 읽어도
    /// 차이가 같다. `VehicleFormat.parseKST`는 「지금」과 빼서 경과 시간을 내는 자리 전용이다.
    var date: Date? { LedgerFormat.parseDateTime(at) }
}
```

`WooriHaru/Services/ChargeService.swift`에:

```swift
    /// 파라미터가 없다. 전 기간이다. **`/tesla/charges/missing-cost`의 `totalCount`와 다른 수를 낸다** —
    /// 그쪽은 최근 한 달 창이라 배지에 섞어 쓰면 어긋난다.
    func fetchTotals() async throws -> ChargeTotalsResponse {
        let response: DataResponse<ChargeTotalsResponse> = try await api.get("/tesla/charges/totals")
        guard let totals = response.data else {
            throw APIError.serverError(statusCode: 200, message: "충전 누적 응답이 비어 있습니다")
        }
        return totals
    }

    /// 그 세션의 kW 곡선. **끝난 충전만 온다** — 진행 중이면 서버가 404다.
    func fetchCurve(id: Int) async throws -> ChargeCurveResponse {
        let response: DataResponse<ChargeCurveResponse> = try await api.get("/tesla/charges/\(id)/curve")
        guard let curve = response.data else {
            throw APIError.serverError(statusCode: 200, message: "충전 곡선 응답이 비어 있습니다")
        }
        return curve
    }
```

- [ ] **Step 4: 테스트를 통과시키고 커밋**

```bash
touch WooriHaru/Services/ChargeService.swift WooriHaru/Models/ChargeTotalsModels.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
git add WooriHaru/Services/ChargeService.swift WooriHaru/Models/ChargeTotalsModels.swift \
        WooriHaruTests/ChargeTests.swift
git commit -m "feat: 충전 누적과 곡선 엔드포인트를 부른다

곡선은 끝난 충전만 온다 — 진행 중이면 서버가 404다."
```

---

### Task 3: 누적 스탯 타일

**Files:**
- Create: `WooriHaru/ViewModels/ChargeTotalsViewModel.swift`
- Create: `WooriHaru/Views/Vehicle/ChargeTotalsCard.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleHealthTab.swift` (카드 한 줄 추가)
- Test: `WooriHaruTests/ChargeTotalsViewModelTests.swift`

**Interfaces:**
- Consumes: `ChargeService.fetchTotals()` (Task 2), `VehicleMath.wonPerKwh`·`VehicleFormat.wonPerKwh` (Task 1), `VehicleStatus.odometerKm` (기존, 건강 탭이 이미 들고 있다), `GlassCard`
- Produces:
  - `@MainActor @Observable final class ChargeTotalsViewModel` — `totals`, `isLoading`, `errorMessage`, `hasTotals`, `fastWonPerKwh`, `slowWonPerKwh`, `load()`, `reload()`
  - `struct ChargeTotalsCard: View` — `init(totals: ChargeTotalsResponse?, odometerKm: Decimal?)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ChargeTotalsViewModelTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct ChargeTotalsViewModelTests {

    /// 실측(2026-08-19) 그대로다.
    private nonisolated static func totals() -> ChargeTotalsResponse {
        ChargeTotalsResponse(
            chargeCount: 474,
            energyAddedKwh: Decimal(string: "17442.0"),
            energyUsedKwh: Decimal(string: "18197.2"),
            cost: 3644562, costMissingCount: 35,
            costMissingEnergyUsedKwh: Decimal(string: "977.0"),
            firstChargedAt: "2021-09-03",
            fast: ChargeTotalsBreakdown(
                chargeCount: 39, energyAddedKwh: Decimal(string: "1358.4"),
                energyUsedKwh: Decimal(string: "1320.2"), cost: 140479,
                costMissingCount: 22, costMissingEnergyUsedKwh: Decimal(string: "833.9")),
            slow: ChargeTotalsBreakdown(
                chargeCount: 431, energyAddedKwh: Decimal(string: "16083.6"),
                energyUsedKwh: Decimal(string: "16877.1"), cost: 3493723,
                costMissingCount: 10, costMissingEnergyUsedKwh: Decimal(string: "143.1")))
    }

    private func makeViewModel(_ mock: MockAPIClient) -> ChargeTotalsViewModel {
        ChargeTotalsViewModel(service: ChargeService(api: mock))
    }

    private func stub(_ mock: MockAPIClient, _ t: ChargeTotalsResponse?) {
        mock.stubGet("/tesla/charges/totals", result: DataResponse<ChargeTotalsResponse>(data: t))
    }

    @Test func 급속과_완속_단가를_각자_낸다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(VehicleFormat.wonPerKwh(viewModel.fastWonPerKwh) == "₩289/kWh")
        #expect(VehicleFormat.wonPerKwh(viewModel.slowWonPerKwh) == "₩209/kWh")
        #expect(viewModel.hasTotals)
    }

    /// 탭을 오갈 때마다 전 기간 집계를 다시 부르지 않는다. **오류가 남아 있으면 재시도한다** —
    /// 1·2단계 뷰모델과 같은 규칙이다.
    @Test func 다시_열어도_한_번만_부른다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.load()

        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/totals" }.count == 1)
    }

    @Test func 오류가_남아_있으면_다시_들어올_때_재시도한다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/totals")
        await viewModel.reload()
        await viewModel.load()

        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/totals" }.count == 3)
    }

    /// **있던 값을 새로고침 실패로 지우지 않는다.**
    @Test func 새로고침이_실패해도_있던_값은_남는다() async {
        let mock = MockAPIClient(); stub(mock, Self.totals())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/totals")
        await viewModel.reload()

        #expect(viewModel.hasTotals)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/totals")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.hasTotals)
        #expect(viewModel.errorMessage != nil)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

- [ ] **Step 3: `ChargeTotalsViewModel.swift`를 만든다**

`VehicleHealthViewModel`의 제너레이션 카운터·`CancellationError` 처리·에러 문구 모양을 그대로 따른다. `load()`의 가드는 **`totals == nil || errorMessage != nil`**이다 — 1·2단계에서 이 자리를 두 번 틀렸다.

```swift
import Foundation
import Observation

/// 누적 스탯 타일 — `/tesla/charges/totals` 하나만 본다. 전 기간 집계라 한 번만 받는다.
@MainActor
@Observable
final class ChargeTotalsViewModel {
    private(set) var totals: ChargeTotalsResponse?
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: ChargeService
    private var generation = 0

    init(service: ChargeService = ChargeService()) { self.service = service }

    var hasTotals: Bool { totals != nil }

    var fastWonPerKwh: Decimal? {
        VehicleMath.wonPerKwh(cost: totals?.fast.cost,
                              energyUsedKwh: totals?.fast.energyUsedKwh,
                              costMissingEnergyUsedKwh: totals?.fast.costMissingEnergyUsedKwh)
    }

    var slowWonPerKwh: Decimal? {
        VehicleMath.wonPerKwh(cost: totals?.slow.cost,
                              energyUsedKwh: totals?.slow.energyUsedKwh,
                              costMissingEnergyUsedKwh: totals?.slow.costMissingEnergyUsedKwh)
    }

    /// 탭에 들어올 때마다 부른다. **전 기간 집계는 한 번만 받되, 오류가 서 있으면 다시 받는다** —
    /// 안 그러면 실패한 채로 탭을 나갔다 돌아와도 빨간 배너가 영영 그대로 남는다.
    func load() async {
        guard totals == nil || errorMessage != nil else { return }
        await reload()
    }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다.**
    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let loaded = try await service.fetchTotals()
            guard current == generation else { return }
            totals = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            errorMessage = "충전 누적을 불러오지 못했습니다."
        }
    }
}
```

- [ ] **Step 4: `ChargeTotalsCard.swift`를 만든다**

```swift
import SwiftUI

/// 누적 스탯 2×2 타일 — 누적 주행 / 누적 충전 / 누적 충전비 / 급속·완속 단가.
///
/// **넷째 칸이 단가인 이유:** 원래 후보였던 「주유비 대비 절감액」은 유가·연비 상수를 앱에 박아야
/// 하는데 박는 순간부터 틀려지기 시작한다. 단가는 상수 없이 나오고 행동을 바꾸는 숫자다 —
/// 실측으로 급속이 완속보다 38% 비싸다.
struct ChargeTotalsCard: View {
    let totals: ChargeTotalsResponse?
    /// `/tesla/status`에서 온다 — **누적 주행거리는 이 응답에 없다.**
    let odometerKm: Decimal?

    private var fast: Decimal? {
        VehicleMath.wonPerKwh(cost: totals?.fast.cost,
                              energyUsedKwh: totals?.fast.energyUsedKwh,
                              costMissingEnergyUsedKwh: totals?.fast.costMissingEnergyUsedKwh)
    }

    private var slow: Decimal? {
        VehicleMath.wonPerKwh(cost: totals?.slow.cost,
                              energyUsedKwh: totals?.slow.energyUsedKwh,
                              costMissingEnergyUsedKwh: totals?.slow.costMissingEnergyUsedKwh)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("누적")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    if let since = totals?.firstChargedAt {
                        Text("\(since)부터")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.slate400)
                    }
                }
                HStack(spacing: 10) {
                    tile(VehicleFormat.odometer(odometerKm), "주행")
                    tile(ChargeFormat.energy(totals?.energyAddedKwh), "충전")
                }
                HStack(spacing: 10) {
                    tile(totals?.cost.map { LedgerFormat.amount($0, currency: "KRW") }
                         ?? ChargeFormat.placeholder, "충전비")
                    unitPriceTile
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
    }

    /// **표본 수를 함께 적는다.** 급속은 39건 중 22건이 미입력이라 17건에서만 나온 값이고,
    /// 「289원」만 크게 적으면 그 얇음이 숨는다.
    private var unitPriceTile: some View {
        VStack(spacing: 2) {
            row("급속", fast, totals?.fast.pricedCount)
            row("완속", slow, totals?.slow.pricedCount)
            Text("kWh당")
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: Decimal?, _ count: Int?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.slate500)
            Text(value.map { LedgerFormat.amount(VehicleMath.rounded($0), currency: "KRW") }
                 ?? ChargeFormat.placeholder)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
            if let count {
                Text("\(count)건")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Color.slate400)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

#Preview("누적") {
    let t = ChargeTotalsResponse(
        chargeCount: 474, energyAddedKwh: Decimal(string: "17442.0"),
        energyUsedKwh: Decimal(string: "18197.2"), cost: 3644562, costMissingCount: 35,
        costMissingEnergyUsedKwh: Decimal(string: "977.0"), firstChargedAt: "2021-09-03",
        fast: ChargeTotalsBreakdown(chargeCount: 39, energyAddedKwh: nil,
                                    energyUsedKwh: Decimal(string: "1320.2"), cost: 140479,
                                    costMissingCount: 22,
                                    costMissingEnergyUsedKwh: Decimal(string: "833.9")),
        slow: ChargeTotalsBreakdown(chargeCount: 431, energyAddedKwh: nil,
                                    energyUsedKwh: Decimal(string: "16877.1"), cost: 3493723,
                                    costMissingCount: 10,
                                    costMissingEnergyUsedKwh: Decimal(string: "143.1")))
    return VStack(spacing: 12) {
        ChargeTotalsCard(totals: t, odometerKm: Decimal(string: "41203.8"))
        // 아직 못 받았을 때 — 자리는 지키고 값만 「—」다.
        ChargeTotalsCard(totals: nil, odometerKm: nil)
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 5: 건강 탭에 한 줄 얹는다**

`WooriHaru/Views/Vehicle/VehicleHealthTab.swift` — **이 태스크가 1단계 파일을 건드리는 유일한 자리다.** 배지 아래, `healthSection` 위에 넣는다(설계 문서: 「건강 화면 위쪽에 놓는다」):

```swift
                ChargeTotalsCard(totals: totalsViewModel.totals,
                                 odometerKm: statusViewModel.status?.odometerKm)
```

`VehicleHealthTab`에 프로퍼티를 하나 더 받는다:

```swift
    @Bindable var totalsViewModel: ChargeTotalsViewModel
```

`.refreshable`에 `await totalsViewModel.reload()`를 더한다.

`WooriHaru/Views/Vehicle/VehicleView.swift`에서 뷰모델을 만들어 넘기고, 건강 탭의 `.task`에 `totalsViewModel.load()`를 `async let`으로 함께 건다.

> **누적 카드는 실패해도 조용하다.** 별도 오류 배너를 두지 않는다 — 값이 없으면 「—」로 남는다.
> 건강 화면의 주인공은 배터리 카드이고, 곁가지 하나 때문에 배너를 늘리지 않는다.

- [ ] **Step 6: 테스트·커밋**

```bash
touch WooriHaru/ViewModels/ChargeTotalsViewModel.swift WooriHaru/Views/Vehicle/ChargeTotalsCard.swift \
      WooriHaru/Views/Vehicle/VehicleHealthTab.swift WooriHaru/Views/Vehicle/VehicleView.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```

```bash
git add -A WooriHaru/ViewModels WooriHaru/Views/Vehicle WooriHaruTests/ChargeTotalsViewModelTests.swift \
        WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 건강 화면에 누적 스탯 타일을 더한다

넷째 칸은 급속·완속 단가다 — 원래 후보였던 주유비 대비 절감액은 유가 상수를
앱에 박아야 하는데 박는 순간부터 틀려진다. 단가는 상수 없이 나오고
급속이 완속보다 38% 비싸다는 것이 바로 보인다."
```

---

### Task 4: 충전 행 배터리 게이지

**Files:**
- Modify: `WooriHaru/Views/Charge/ChargeRow.swift`

**서버 변경이 없다.** `ChargeItem`에 `startBatteryLevel`·`endBatteryLevel`이 이미 온다.

- [ ] **Step 1: 게이지를 더한다**

`ChargeRow`의 기존 레이아웃 아래에, 배터리 값이 **둘 다 있을 때만** 얇은 막대를 그린다:

```swift
    /// 시작→종료 SoC를 얇은 막대로. **완속·급속·짧은 보충이 목록에서 한눈에 갈린다** —
    /// 「63% → 80%」를 글자로 읽는 것과 폭으로 보는 것은 다르다.
    ///
    /// **둘 중 하나라도 없으면 그리지 않는다.** 한쪽만으로 그린 막대는 거짓말이다.
    @ViewBuilder private var batteryGauge: some View {
        if let start = item.startBatteryLevel, let end = item.endBatteryLevel, end > start {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.slate200)
                    // 시작 지점까지는 옅게 — 「원래 들어 있던 만큼」이다.
                    Capsule()
                        .fill(Color.slate300)
                        .frame(width: w * CGFloat(start) / 100)
                    // 이번에 채운 구간만 진하게.
                    Capsule()
                        .fill(Color.green600)
                        .frame(width: w * CGFloat(end - start) / 100)
                        .offset(x: w * CGFloat(start) / 100)
                }
            }
            .frame(height: 4)
            .accessibilityLabel("배터리 \(start)%에서 \(end)%로")
        }
    }
```

`body`의 마지막 줄로 `batteryGauge`를 넣고 위쪽에 `.padding(.top, 6)`을 준다. **기존 텍스트 줄은 건드리지 않는다.**

- [ ] **Step 2: 빌드·프리뷰 확인·커밋**

프리뷰(있다면)에서 확인할 것: `63% → 80%`가 왼쪽 63%까지 옅고 그 뒤 17%가 진하다. 시작·종료가 같거나 하나가 nil이면 막대가 아예 없다.

```bash
touch WooriHaru/Views/Charge/ChargeRow.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
git add WooriHaru/Views/Charge/ChargeRow.swift
git commit -m "feat: 충전 목록 행에 배터리 게이지를 더한다

63%→80%를 글자로 읽는 것과 폭으로 보는 것은 다르다 — 완속·급속·짧은 보충이
목록에서 한눈에 갈린다. 서버 변경은 없다."
```

---

### Task 5: 충전 곡선 (급속 상세에만)

**Files:**
- Create: `WooriHaru/Views/Charge/ChargeCurveChart.swift`
- Modify: `WooriHaru/Views/Charge/ChargeDetailView.swift`
- Test: `WooriHaruTests/ChargeCurveTests.swift`

**Interfaces:**
- Consumes: `ChargeService.fetchCurve(id:)`·`ChargeCurveSample` (Task 2), `ChargeDetail.fastCharger` (기존), `GlassCard`
- Produces:
  - `enum ChargeCurveMath` — `downsample(_:to:) -> [ChargeCurveSample]`, `elapsedMinutes(_:) -> [(minutes: Double, powerKw: Int)]`
  - `struct ChargeCurveChart: View` — `init(samples: [ChargeCurveSample])`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ChargeCurveTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct ChargeCurveTests {

    private static func sample(_ minute: Int, _ kw: Int?) -> ChargeCurveSample {
        let base = 60 * 13 + minute // 13:00 + minute
        return ChargeCurveSample(
            at: String(format: "2025-09-10T%02d:%02d:00", base / 60, base % 60),
            powerKw: kw, batteryLevel: nil
        )
    }

    /// 폰 차트 폭이 ~340pt라 1,980개는 어차피 못 그린다. **줄이되 봉우리를 잃지 않는다.**
    @Test func 상한보다_많으면_줄인다() {
        let many = (0..<510).map { Self.sample($0, 100) }
        #expect(ChargeCurveMath.downsample(many, to: 150).count <= 150)
    }

    /// **상한 이하면 손대지 않는다.** 줄일 이유가 없는데 줄이면 없던 왜곡이 생긴다.
    @Test func 상한_이하면_그대로_둔다() {
        let few = (0..<80).map { Self.sample($0, 50) }
        #expect(ChargeCurveMath.downsample(few, to: 150).count == 80)
    }

    /// **최고점을 잃지 않는 것이 이 함수의 존재 이유다.** 균등 간격으로 솎으면 166kW 봉우리가
    /// 통째로 빠져 「최고 100kW였네」가 된다 — 곡선을 여는 이유가 그 봉우리인데.
    @Test func 줄여도_최고점은_남는다() {
        var samples = (0..<400).map { Self.sample($0, 60) }
        samples[137] = Self.sample(137, 166)
        let reduced = ChargeCurveMath.downsample(samples, to: 100)
        #expect(reduced.compactMap(\.powerKw).max() == 166)
    }

    /// 첫 점과 끝 점은 늘 남는다 — 곡선의 시작과 끝이 잘리면 소요 시간이 틀려 보인다.
    @Test func 양_끝은_늘_남는다() {
        let samples = (0..<300).map { Self.sample($0, 70) }
        let reduced = ChargeCurveMath.downsample(samples, to: 50)
        #expect(reduced.first?.at == samples.first?.at)
        #expect(reduced.last?.at == samples.last?.at)
    }

    /// **경과 분은 앱이 낸다** — 서버는 KST 시각만 준다.
    @Test func 첫_샘플에서_빼서_경과_분을_낸다() {
        let points = ChargeCurveMath.elapsedMinutes([
            Self.sample(0, 166), Self.sample(16, 100), Self.sample(33, 66),
        ])
        #expect(points.map(\.minutes) == [0, 16, 33])
        #expect(points.map(\.powerKw) == [166, 100, 66])
    }

    /// **`powerKw`가 null인 샘플은 버린다.** 0으로 읽으면 곡선이 바닥까지 떨어졌다 올라온
    /// 것처럼 보인다 — null은 「모른다」이지 「안 들어갔다」가 아니다.
    @Test func 전력이_없는_샘플은_빼고_그린다() {
        let points = ChargeCurveMath.elapsedMinutes([
            Self.sample(0, 166), Self.sample(5, nil), Self.sample(10, 120),
        ])
        #expect(points.map(\.minutes) == [0, 10])
    }

    /// 시각을 못 읽는 샘플도 빠진다. 그리고 남은 것이 없으면 빈 배열이다.
    @Test func 읽을_수_없으면_빈_배열이다() {
        #expect(ChargeCurveMath.elapsedMinutes([]).isEmpty)
        let broken = [ChargeCurveSample(at: "not-a-date", powerKw: 10, batteryLevel: nil)]
        #expect(ChargeCurveMath.elapsedMinutes(broken).isEmpty)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

- [ ] **Step 3: `ChargeCurveChart.swift`를 만든다**

```swift
import SwiftUI

/// 곡선을 화면에 맞게 줄이는 계산. 뷰 밖에 두어 테스트가 닿게 한다.
enum ChargeCurveMath {
    /// 폰 차트 폭이 ~340pt라 이보다 많은 점은 어차피 픽셀에 겹친다.
    static let maxPoints = 150

    /// **버킷마다 최고점을 남긴다.** 균등 간격으로 솎으면 166kW 봉우리가 통째로 빠져
    /// 「최고 100kW였네」가 되는데, 곡선을 여는 이유가 바로 그 봉우리다.
    ///
    /// 골짜기를 잃는 대가는 받아들인다 — 충전 곡선에서 읽는 것은 「얼마나 들어갔나」이지
    /// 순간적인 흔들림이 아니다. **양 끝은 늘 남긴다** — 잘리면 소요 시간이 틀려 보인다.
    static func downsample(_ samples: [ChargeCurveSample], to limit: Int = maxPoints)
        -> [ChargeCurveSample] {
        guard samples.count > limit, limit > 2 else { return samples }
        let inner = limit - 2
        let body = samples.dropFirst().dropLast()
        let bucket = Double(body.count) / Double(inner)
        var picked: [ChargeCurveSample] = [samples[0]]
        for i in 0..<inner {
            let lo = body.startIndex + Int(Double(i) * bucket)
            let hi = min(body.startIndex + Int(Double(i + 1) * bucket), body.endIndex)
            guard lo < hi else { continue }
            // 이 버킷에서 가장 높은 점 하나. 전부 null이면 첫 점을 남긴다.
            let slice = body[lo..<hi]
            let best = slice.max { ($0.powerKw ?? -1) < ($1.powerKw ?? -1) }
            if let best { picked.append(best) }
        }
        picked.append(samples[samples.count - 1])
        return picked
    }

    /// 첫 샘플에서 뺀 경과 분. **서버는 KST 시각만 주고 경과 분을 내지 않는다.**
    ///
    /// `powerKw`가 null이거나 시각을 못 읽는 샘플은 **버린다** — 0으로 읽으면 곡선이
    /// 바닥까지 떨어졌다 올라온 것처럼 보인다. null은 「모른다」이지 「안 들어갔다」가 아니다.
    static func elapsedMinutes(_ samples: [ChargeCurveSample]) -> [(minutes: Double, powerKw: Int)] {
        let usable = samples.compactMap { s -> (Date, Int)? in
            guard let date = s.date, let kw = s.powerKw else { return nil }
            return (date, kw)
        }
        guard let first = usable.first?.0 else { return [] }
        return usable.map { (minutes: $0.0.timeIntervalSince(first) / 60, powerKw: $0.1) }
    }
}

/// 급속 충전 한 건의 kW 곡선. 손으로 그린다(Swift Charts를 들이지 않는 관례).
///
/// **x축은 경과 시간이다.** SoC 축이 테이퍼는 더 선명하지만, 곡선을 여는 이유가 대개
/// 「왜 오래 걸렸지」라 그 질문에 답하는 축이 시간이다 — 실측 사례로 어떤 세션은 앞 8분이
/// 63kW에 묶여 있었는데, SoC 축이면 그 구간이 왼쪽 끝에 짓눌려 사라진다.
struct ChargeCurveChart: View {
    let samples: [ChargeCurveSample]

    private static let height: CGFloat = 130

    private var points: [(minutes: Double, powerKw: Int)] {
        ChargeCurveMath.elapsedMinutes(ChargeCurveMath.downsample(samples))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                if points.count < 2 {
                    // 점 하나로는 곡선이 아니다.
                    Text("이 충전엔 그릴 만한 곡선이 없어요")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                } else {
                    GeometryReader { proxy in plot(in: proxy.size) }
                        .frame(height: Self.height)
                    axis
                }
            }
        }
    }

    private var peak: Int { points.map(\.powerKw).max() ?? 0 }
    private var duration: Double { points.last?.minutes ?? 0 }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("충전 곡선")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.slate500)
            Spacer(minLength: 8)
            if points.count >= 2 {
                Text("최고 \(peak)kW")
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(Color.slate900)
            }
        }
    }

    private func plot(in size: CGSize) -> some View {
        let maxKw = max(1, peak)
        let span = max(1, duration)
        func at(_ p: (minutes: Double, powerKw: Int)) -> CGPoint {
            CGPoint(x: size.width * CGFloat(p.minutes / span),
                    y: size.height * (1 - CGFloat(Double(p.powerKw) / Double(maxKw))))
        }
        return ZStack(alignment: .topLeading) {
            // 채운 면 — 곡선 아래가 곧 들어간 에너지다.
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height))
                for p in points { path.addLine(to: at(p)) }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color.blue300.opacity(0.55), Color.blue300.opacity(0.05)],
                                 startPoint: .top, endPoint: .bottom))
            Path { path in
                for (i, p) in points.enumerated() {
                    if i == 0 { path.move(to: at(p)) } else { path.addLine(to: at(p)) }
                }
            }
            .stroke(Color.blue600, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private var axis: some View {
        HStack {
            Text("0분")
            Spacer()
            Text("\(Int(duration.rounded()))분")
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(Color.slate400)
    }
}

#Preview("곡선") {
    // 실측 세션 402의 모양 — 166kW로 시작해 33분간 66kW까지 테이퍼.
    let curve = (0...33).map { m -> ChargeCurveSample in
        let kw = Int(166.0 - Double(m) * 3.0)
        return ChargeCurveSample(at: String(format: "2025-09-10T13:%02d:00", m),
                                 powerKw: kw, batteryLevel: nil)
    }
    return VStack(spacing: 12) {
        ChargeCurveChart(samples: curve)
        ChargeCurveChart(samples: [])
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 4: 충전 상세에 붙인다**

`WooriHaru/Views/Charge/ChargeDetailView.swift` — **급속일 때만** 부르고 그린다.

```swift
    @State private var curve: [ChargeCurveSample]?
    @State private var curveFailed = false
```

상세 로드가 끝난 뒤, `detail.fastCharger == true`일 때만:

```swift
    /// **급속에만 곡선을 그린다.** 완속은 실측으로 7시간 내내 6kW 한 줄이라 볼 것이 없는데
    /// 샘플만 급속의 3.4배다(1,980개까지 온다). `fastCharger`가 nil이면 급속 여부를 모르는
    /// 것이므로 그리지 않는다 — 「완속」이라고 단정하지도 않는 기존 표기와 같은 규칙이다.
    private func loadCurveIfFast(_ detail: ChargeDetail) async {
        guard detail.fastCharger == true, curve == nil, !curveFailed else { return }
        do {
            curve = try await ChargeService().fetchCurve(id: detail.id).samples
        } catch is CancellationError {
            return
        } catch {
            // 곡선 하나 때문에 상세를 죽이지 않는다. 조용히 접는다.
            curveFailed = true
        }
    }
```

본문에는 값이 있을 때만 카드를 넣는다:

```swift
                if let curve, !curve.isEmpty {
                    ChargeCurveChart(samples: curve)
                }
```

- [ ] **Step 5: `clean test`·커밋**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test 2>&1 | tail -50
```

- [ ] **Step 6: 실기로 확인한다**

**코드로 확인할 수 없는 항목이다.** 시뮬레이터에서:

1. 건강 화면 위쪽에 **누적 타일 2×2**가 보이고, 넷째 칸에 급속·완속 단가가 건수와 함께 뜬다.
2. 요약 탭 충전 목록의 각 행에 **얇은 배터리 게이지**가 있고, 짧은 보충과 만충이 폭으로 갈린다.
3. **급속** 충전 하나를 열면 곡선이 뜨고, 최고 kW가 헤더에 적힌다.
4. **완속** 충전을 열면 곡선 카드가 **아예 없다**.
5. 곡선이 있는 급속에서 봉우리가 뭉개지지 않았다(최고값이 헤더 숫자와 눈으로 맞는다).

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/Views/Charge/ChargeCurveChart.swift WooriHaru/Views/Charge/ChargeDetailView.swift \
        WooriHaruTests/ChargeCurveTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 급속 충전 상세에 kW 곡선을 그린다

x축은 경과 시간이다 — 곡선을 여는 이유가 대개 「왜 오래 걸렸지」라서다.
버킷마다 최고점을 남겨 줄인다. 균등 간격으로 솎으면 봉우리가 통째로 빠진다.
완속은 7시간 6kW 직선이라 그리지 않는다."
```

---

### Task 6: 설계 문서에 3단계 완료를 적는다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md`

- [ ] **Step 1: 단계 표와 3단계 절에 상태를 적는다**

「단계」 표의 3단계 `내용` 칸 끝에 `**(구현 완료, 2026-08-19)**`를 붙이고, `# 3단계 — 곁가지` 제목 아래에 넣는다. **항목 수와 「셋」/「넷」 같은 말이 맞는지 세어 보고 적는다** — 1단계 때 이 자리에서 한 번 어긋났다.

```markdown
> **구현 완료(2026-08-19).** 계획은 `docs/superpowers/plans/2026-08-19-vehicle-charge-extras.md`다.
> 이 문서가 미뤄 둔 결정 둘을 확정했고, 갈라진 곳이 하나 더 있다.
>
> - **누적 스탯 타일의 넷째 칸은 「급속·완속 단가」다.** 후보였던 **주유비 대비 절감액은 폐기했다** —
>   유가·연비 상수를 앱에 박아야 하는데 박는 순간부터 틀려지기 시작하고, 「내연차였으면」이라는
>   가정 자체가 임의적이다. 단가는 상수 없이 서버 데이터만으로 나오고 행동을 바꾸는 숫자다
>   (실측 2026-08-19: 급속 289원 대 완속 209원, **38% 차이**). **표본 수를 함께 적는다** —
>   급속은 39건 중 22건이 미입력이라 17건에서만 나온 값이다.
> - **충전 곡선의 x축은 경과 시간이다.** SoC 축이 테이퍼는 더 선명하지만, 곡선을 여는 이유가
>   대개 「왜 오래 걸렸지」라 그 질문에 답하는 축이 시간이다. 실측 사례로 어떤 세션은 앞 8분이
>   63kW에 묶여 있었는데, SoC 축이면 그 구간이 왼쪽 끝에 짓눌려 사라진다.
> - **곡선은 급속에만 그린다.** 이 문서는 그 구분을 적지 않았다. 완속은 실측으로 7시간 내내
>   6kW 한 줄이고(1,214샘플, 421분, 최고 6kW), 볼 것이 없는데 샘플만 급속의 3.4배다.
>   `ChargeDetail.fastCharger`가 이미 오므로 서버 변경은 없다.
>
> 다운샘플링은 **버킷마다 최고점을 남기는 방식**으로 150점까지 줄인다. 균등 간격으로 솎으면
> 166kW 봉우리가 통째로 빠져 「최고 100kW였네」가 되는데, 곡선을 여는 이유가 그 봉우리다.
```

- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md
git commit -m "docs: 3단계 구현 완료와 확정한 결정을 적는다"
```

---

## 이 계획이 다루지 않는 것

- **보류(`positions`).** 경로 지도·개별 주행 속도·전력·고도 차트·속도 분포다. 인덱스는 확인됐고(BRIN, 11.7ms) 접지 않기로 했지만, **다운샘플링 방식 결정이 선행**이다 — 주행 하나에 평균 4,281샘플, 최대 14,386샘플, km당 478개다. 이번 곡선에서 쓴 「버킷 최고점」은 kW에는 맞지만 좌표에는 안 맞는다(경로는 봉우리가 아니라 모양을 지켜야 한다). 4단계 계획의 첫 항목이다.
- **1·2단계 화면.** 건강 탭에 카드 한 줄을 얹는 것 외에는 건드리지 않는다.
- **금액 입력 경로.** 큐 화면과 금액 수정은 손대지 않는다.
- **배지 카운트 주인이 둘인 문제.** 1단계에서 파킹한 그대로다. 이 계획은 배지를 건드리지 않아 그 문제를 키우지 않는다.
