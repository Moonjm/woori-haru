# 「차량」 미니앱 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 드로어 「충전 내역」을 「차량」 미니앱(요약·상태 두 탭)으로 넓히고, 금액이 빈 충전을 연달아 채우는 화면을 더한다.

**Architecture:** 가계부(`LedgerView`)와 같은 미니앱 구조다 — 하단 글래스 탭바를 가진 컨테이너(`VehicleView`) 아래 요약·상태 탭이 붙고, 각 탭이 자기 뷰모델과 엔드포인트를 하나씩 쓴다. 서버가 월 요약과 그 달 충전 목록을 한 응답으로 주므로 요약 탭은 호출 하나로 그린다. 계산(km당 비용·전비·psi)은 서버가 아니라 앱의 순수 함수(`VehicleMath`)가 하고, 그 함수들이 테스트의 대부분을 차지한다.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), `@Observable` 뷰모델, Swift Testing(`import Testing`), 기존 `APIClientProtocol`·`MockAPIClient`. 차트는 Swift Charts를 새로 들이지 않고 가계부처럼 손으로 그린 막대다.

**Spec:** `docs/superpowers/specs/2026-08-13-vehicle-mini-app-design.md`
(서버 계약: toy-back `docs/superpowers/specs/2026-08-13-tesla-vehicle-summary-design.md`)

## Global Constraints

- **백엔드는 이 계획의 범위가 아니다.** 서버는 별도 작업으로 진행 중이고, 앱은 스펙에 적힌 계약을 그대로 믿는다. 서버가 아직 없어도 이 계획의 모든 테스트는 `MockAPIClient`로 통과한다.
- **앱 타겟은 파일 자동 인식이 안 된다.** `WooriHaru/` 아래 새 `.swift`를 만들면 반드시 `ruby scripts/xcode-add-files.rb <경로…>`로 등록한다. 테스트 타겟(`WooriHaruTests/`)은 폴더 동기화라 등록이 필요 없다.
- **증분 빌드가 변경을 놓치는 일이 있다.** 각 태스크의 마지막 테스트 실행 전에 바꾼 파일을 `touch`하고, 태스크 9의 최종 확인은 `clean test`로 한다.
- 테스트 명령: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test`
- **없는 값은 0이 아니라 「—」다.** 0은 「그렇게 측정됐다」는 뜻이라 「모른다」와 구분되지 않는다.
- **못 받은 것을 「기록 없음」으로 그리지 않는다.** 실패는 재시도가 있는 실패 상태, 로딩은 「—」다.
- **나눗셈은 앱이 한다.** 분모가 없거나 0이면 결과는 nil이다.
- 금액은 `Decimal`, 서버 시각은 KST `LocalDateTime` 문자열이며 `LedgerFormat.parseDateTime`으로 읽는다.
- 커밋 메시지는 한국어 관례를 따른다(`feat:`/`fix:`/`refactor:` + 한 줄 요약 + 왜).

---

### Task 1: 차량 응답 모델과 계산·표기

**Files:**
- Create: `WooriHaru/Models/VehicleModels.swift`
- Test: `WooriHaruTests/VehicleMathTests.swift`

**Interfaces:**
- Consumes: `ChargeItem`, `ChargeMath`, `ChargeFormat`, `LedgerFormat` (기존)
- Produces:
  - `struct VehicleSummaryResponse: Codable { let month: VehiclePeriod; let previous: VehiclePeriod?; let trend: [VehiclePeriod]; let charges: [ChargeItem] }`
  - `struct VehiclePeriod: Codable, Identifiable, Equatable` — `yearMonth: String`, 나머지 전부 옵셔널, `id == yearMonth`, `monthNumber: Int`
  - `struct VehicleStatus: Codable, Equatable` — `asOf: String?` 외 옵셔널 필드, 중첩 `TpmsBar`
  - `struct MissingCostResponse: Codable { let totalCount: Int; let items: [ChargeItem] }`
  - `enum VehicleMath` — `costPerKm`, `consumptionKwhPer100km`, `deltaPercent`, `psi(fromBar:)`, `suggestedCost(unitPrice:energyUsedKwh:)`, `minutesAgo(from:now:)`
  - `enum VehicleFormat` — `distance`, `odometer`, `consumption`, `costPerKm`, `pressureBar`, `pressurePsi`, `relative(minutes:)`, `stateLabel`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleMathTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VehicleMathTests {
    /// 분모가 없거나 0이면 계산하지 않는다 — 0으로 내면 「0원에 탔다」가 된다.
    @Test func 주행이_없으면_km당_비용도_전비도_없다() {
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: nil) == nil)
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: 0) == nil)
        #expect(VehicleMath.costPerKm(cost: nil, distanceKm: 842) == nil)
        #expect(VehicleMath.consumptionKwhPer100km(energyAddedKwh: 186, distanceKm: 0) == nil)
    }

    @Test func km당_비용과_전비를_계산한다() {
        let costPerKm = VehicleMath.costPerKm(cost: 52300, distanceKm: Decimal(string: "842.3"))
        #expect(VehicleFormat.costPerKm(costPerKm) == "₩62/km")

        let consumption = VehicleMath.consumptionKwhPer100km(
            energyAddedKwh: Decimal(string: "186.4"), distanceKm: Decimal(string: "842.3")
        )
        #expect(VehicleFormat.consumption(consumption) == "22.1kWh/100km")
    }

    /// 지난달이 비면 증감을 내지 않는다 — 0에서 늘었다고 말할 수 없다.
    @Test func 지난달이_비면_증감이_없다() {
        #expect(VehicleMath.deltaPercent(current: 62, previous: nil) == nil)
        #expect(VehicleMath.deltaPercent(current: 62, previous: 0) == nil)
        #expect(VehicleMath.deltaPercent(current: 62, previous: 50) == 24)
        #expect(VehicleMath.deltaPercent(current: 40, previous: 50) == -20)
    }

    @Test func bar를_psi로_바꾼다() {
        #expect(VehicleFormat.pressurePsi(Decimal(string: "2.9")) == "42psi")
        #expect(VehicleFormat.pressureBar(nil) == "—")
        #expect(VehicleFormat.pressurePsi(nil) == "—")
    }

    /// 제안값은 직전 저장 단가 × 이 건의 사용 전력이다. 첫 건은 직전 단가가 없어 제안이 없다.
    @Test func 제안값은_직전_단가에서_나온다() {
        #expect(VehicleMath.suggestedCost(unitPrice: nil, energyUsedKwh: Decimal(string: "51.8")) == nil)
        #expect(VehicleMath.suggestedCost(unitPrice: 272, energyUsedKwh: nil) == nil)
        #expect(VehicleMath.suggestedCost(unitPrice: 272, energyUsedKwh: Decimal(string: "51.8")) == 14090)
    }

    @Test func 기준_시각을_상대로_읽는다() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(-30), now: now) == 0)
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(-4 * 3600), now: now) == 240)
        // 시계가 어긋나 미래 시각이 와도 음수를 내지 않는다.
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(120), now: now) == 0)

        #expect(VehicleFormat.relative(minutes: 0) == "방금")
        #expect(VehicleFormat.relative(minutes: 45) == "45분 전")
        #expect(VehicleFormat.relative(minutes: 240) == "4시간 전")
        #expect(VehicleFormat.relative(minutes: 2880) == "2일 전")
    }

    /// 모르는 상태 문자열은 원문 그대로 낸다 — 상류가 값을 늘렸다는 사실이 숨으면 안 된다.
    @Test func 모르는_상태는_원문을_낸다() {
        #expect(VehicleFormat.stateLabel("asleep") == "잠자는 중")
        #expect(VehicleFormat.stateLabel("driving") == "주행 중")
        #expect(VehicleFormat.stateLabel("hibernating") == "hibernating")
        #expect(VehicleFormat.stateLabel(nil) == "—")
    }

    @Test func 거리를_읽기_좋게_쓴다() {
        #expect(VehicleFormat.distance(Decimal(string: "842.3")) == "842km")
        #expect(VehicleFormat.odometer(Decimal(string: "41203.8")) == "41,204km")
        #expect(VehicleFormat.distance(nil) == "—")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: FAIL — `cannot find 'VehicleMath' in scope`

- [ ] **Step 3: 모델과 계산을 쓴다**

`WooriHaru/Models/VehicleModels.swift`:

```swift
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
    /// 전비(kWh/100km)
    var consumption: Decimal? {
        VehicleMath.consumptionKwhPer100km(energyAddedKwh: energyAddedKwh, distanceKm: distanceKm)
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

    var asOfDate: Date? { asOf.flatMap(LedgerFormat.parseDateTime) }
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

    /// 전비의 분자는 **차에 들어간 양**(`energyAddedKwh`)이다. 벽에서 뽑아쓴 양은 지갑 쪽 수치다.
    static func consumptionKwhPer100km(energyAddedKwh: Decimal?, distanceKm: Decimal?) -> Decimal? {
        guard let energyAddedKwh, let distanceKm, distanceKm > 0 else { return nil }
        return energyAddedKwh / distanceKm * 100
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

    private static func rounded(_ value: Decimal) -> Decimal {
        var original = value
        var result = Decimal()
        NSDecimalRound(&result, &original, 0, .plain)
        return result
    }
}

// MARK: - 표기

/// 차량 화면 전용 표기. 없는 값은 `ChargeFormat.placeholder`("—")로 통일한다.
enum VehicleFormat {
    private static func number(_ value: Decimal, fraction: Int, grouping: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.maximumFractionDigits = fraction
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// 842.3 → "842km"
    static func distance(_ km: Decimal?) -> String {
        guard let km else { return ChargeFormat.placeholder }
        return "\(number(km, fraction: 0))km"
    }

    /// 41203.8 → "41,204km"
    static func odometer(_ km: Decimal?) -> String { distance(km) }

    /// 22.13… → "22.1kWh/100km"
    static func consumption(_ value: Decimal?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return "\(number(value, fraction: 1))kWh/100km"
    }

    /// 62.09… → "₩62/km"
    static func costPerKm(_ value: Decimal?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return "\(LedgerFormat.amount(value, currency: "KRW"))/km"
    }

    /// 2.9 → "2.9bar"
    static func pressureBar(_ bar: Decimal?) -> String {
        guard let bar else { return ChargeFormat.placeholder }
        return "\(number(bar, fraction: 1))bar"
    }

    /// 2.9 → "42psi"
    static func pressurePsi(_ bar: Decimal?) -> String {
        guard let psi = VehicleMath.psi(fromBar: bar) else { return ChargeFormat.placeholder }
        return "\(number(psi, fraction: 0))psi"
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
```

- [ ] **Step 4: Xcode 타겟에 등록하고 테스트가 통과하는지 본다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Models/VehicleModels.swift
touch WooriHaru/Models/VehicleModels.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/VehicleModels.swift WooriHaruTests/VehicleMathTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 차량 요약·상태 모델과 계산을 더한다

km당 비용·전비·psi·제안 금액을 앱이 계산한다. 분모가 없거나 0이면 nil이다 —
0으로 내면 「모른다」와 「그렇게 측정됐다」가 구분되지 않는다."
```

---

### Task 2: VehicleService (엔드포인트 셋)

**Files:**
- Create: `WooriHaru/Services/VehicleService.swift`
- Test: `WooriHaruTests/VehicleServiceTests.swift`

**Interfaces:**
- Consumes: Task 1의 `VehicleSummaryResponse`·`VehicleStatus`·`MissingCostResponse`, 기존 `APIClientProtocol`·`DataResponse`
- Produces: `struct VehicleService: Sendable` — `init(api:)`, `fetchSummary(yearMonth: String) async throws -> VehicleSummaryResponse`, `fetchStatus() async throws -> VehicleStatus`, `fetchMissingCost(limit: Int) async throws -> MissingCostResponse`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VehicleServiceTests {
    static func period(_ yearMonth: String) -> VehiclePeriod {
        VehiclePeriod(
            yearMonth: yearMonth, distanceKm: 842, drivingMin: 1043, driveCount: 61,
            energyAddedKwh: 186, energyUsedKwh: 201, cost: 52300, chargeCount: 5
        )
    }

    @Test func 요약은_연월을_붙여_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/summary", result: DataResponse<VehicleSummaryResponse>(
            data: VehicleSummaryResponse(
                month: Self.period("2026-08"), previous: Self.period("2026-07"),
                trend: [Self.period("2026-08")], charges: []
            )
        ))
        let service = VehicleService(api: mock)

        let summary = try await service.fetchSummary(yearMonth: "2026-08")

        #expect(summary.month.yearMonth == "2026-08")
        #expect(mock.getCalls.map(\.path) == ["/tesla/summary"])
        #expect(mock.getCalls.first?.query == ["yearMonth": "2026-08"])
    }

    @Test func 상태는_파라미터_없이_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(
            data: VehicleStatus(
                asOf: "2026-08-13T14:02:00", state: "asleep", stateSince: nil,
                batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: 312, estRangeKm: nil,
                odometerKm: 41203, insideTempC: nil, outsideTempC: nil, climateOn: false,
                locationName: "집", tpmsBar: nil
            )
        ))
        let service = VehicleService(api: mock)

        let status = try await service.fetchStatus()

        #expect(status.batteryLevel == 72)
        #expect(mock.getCalls.first?.query == [:])
    }

    @Test func 미등록은_limit을_붙여_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: 37, items: [])
        ))
        let service = VehicleService(api: mock)

        let response = try await service.fetchMissingCost(limit: 50)

        #expect(response.totalCount == 37)
        #expect(mock.getCalls.first?.query == ["limit": "50"])
    }

    /// 서버가 200에 빈 본문을 주면 화면이 빈 달로 착각하지 않게 에러로 끊는다.
    @Test func 본문이_비면_에러다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/summary", result: DataResponse<VehicleSummaryResponse>(data: nil))
        let service = VehicleService(api: mock)

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchSummary(yearMonth: "2026-08")
        }
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: FAIL — `cannot find 'VehicleService' in scope`

- [ ] **Step 3: 서비스를 쓴다**

`WooriHaru/Services/VehicleService.swift`:

```swift
import Foundation

/// 차량 API — 월 요약(그 달 충전 목록 포함)·현재 상태·금액 미등록 목록.
/// 충전 상세와 금액 수정은 `ChargeService`가 그대로 맡는다.
struct VehicleService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func fetchSummary(yearMonth: String) async throws -> VehicleSummaryResponse {
        let response: DataResponse<VehicleSummaryResponse> =
            try await api.get("/tesla/summary", query: ["yearMonth": yearMonth])
        guard let summary = response.data else {
            throw APIError.serverError(statusCode: 200, message: "차량 요약 응답이 비어 있습니다")
        }
        return summary
    }

    func fetchStatus() async throws -> VehicleStatus {
        let response: DataResponse<VehicleStatus> = try await api.get("/tesla/status")
        guard let status = response.data else {
            throw APIError.serverError(statusCode: 200, message: "차량 상태 응답이 비어 있습니다")
        }
        return status
    }

    /// 기간이 없다. 채워 넣으려는 사람에게 필요한 것은 「빈 건 전부」다.
    func fetchMissingCost(limit: Int = 50) async throws -> MissingCostResponse {
        let response: DataResponse<MissingCostResponse> =
            try await api.get("/tesla/charges/missing-cost", query: ["limit": String(limit)])
        guard let missing = response.data else {
            throw APIError.serverError(statusCode: 200, message: "미등록 목록 응답이 비어 있습니다")
        }
        return missing
    }
}
```

- [ ] **Step 4: 등록하고 통과를 확인한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Services/VehicleService.swift
touch WooriHaru/Services/VehicleService.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/VehicleService.swift WooriHaruTests/VehicleServiceTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 차량 요약·상태·미등록 조회를 더한다"
```

---

### Task 3: VehicleSummaryViewModel (월 이동·요약 로드·미등록 배지)

**Files:**
- Create: `WooriHaru/ViewModels/VehicleSummaryViewModel.swift`
- Test: `WooriHaruTests/VehicleSummaryTests.swift`

**Interfaces:**
- Consumes: Task 2의 `VehicleService`, 기존 `LedgerYearMonth`·`ChargeItem`
- Produces: `@MainActor @Observable final class VehicleSummaryViewModel`
  - `init(service: VehicleService = VehicleService(), now: @escaping @Sendable () -> Date = { .now }, calendar: Calendar = .current)`
  - `var month: LedgerYearMonth`, `private(set) var summary: VehicleSummaryResponse?`, `private(set) var missingCostCount: Int`, `private(set) var isLoading: Bool`, `var errorMessage: String?`
  - `var isMonthLoaded: Bool`, `var isAtCurrentMonth: Bool`, `var sections: [DaySection]`
  - `struct DaySection: Identifiable { let id: Date; let date: Date; let items: [ChargeItem] }`
  - `func load() async`, `func reload() async`, `func shiftMonth(_ delta: Int) async`, `func selectMonth(year: Int, month: Int) async`, `func refreshMissingCount() async`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleSummaryTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleSummaryViewModelTests {
    private nonisolated static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    private nonisolated static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        seoulCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private nonisolated static func charge(id: Int, startedAt: String) -> ChargeItem {
        ChargeItem(
            id: id, startedAt: startedAt, endedAt: "2026-08-12T02:31:00", durationMin: 257,
            locationName: "집", energyAddedKwh: Decimal(string: "48.2"),
            energyUsedKwh: Decimal(string: "51.8"), startBatteryLevel: 18, endBatteryLevel: 90,
            cost: 14100
        )
    }

    private nonisolated static func stub(_ mock: MockAPIClient, charges: [ChargeItem] = []) {
        let month = VehiclePeriod(
            yearMonth: "2026-08", distanceKm: 842, drivingMin: 1043, driveCount: 61,
            energyAddedKwh: 186, energyUsedKwh: 201, cost: 52300, chargeCount: charges.count
        )
        mock.stubGet("/tesla/summary", result: DataResponse<VehicleSummaryResponse>(
            data: VehicleSummaryResponse(month: month, previous: nil, trend: [month], charges: charges)
        ))
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: 12, items: [])
        ))
    }

    private func makeViewModel(mock: MockAPIClient) -> VehicleSummaryViewModel {
        VehicleSummaryViewModel(
            service: VehicleService(api: mock),
            now: { Self.date(2026, 8, 13) },
            calendar: Self.seoulCalendar
        )
    }

    @Test func 진입하면_이번_달_요약과_미등록_수를_받는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, charges: [Self.charge(id: 1, startedAt: "2026-08-11T22:14:00")])
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(mock.getCalls.contains { $0.path == "/tesla/summary" && $0.query == ["yearMonth": "2026-08"] })
        #expect(viewModel.summary?.month.distanceKm == 842)
        #expect(viewModel.missingCostCount == 12)
        #expect(viewModel.isMonthLoaded)
    }

    /// 미등록 수는 월과 무관하다 — 달을 옮길 때마다 다시 받지 않는다.
    @Test func 달을_옮겨도_미등록_수는_다시_받지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.shiftMonth(-1)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 7))
        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/missing-cost" }.count == 1)
    }

    @Test func 이번_달_다음으로는_이동하지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()
        let calls = mock.getCalls.count

        await viewModel.shiftMonth(1)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 8))
        #expect(mock.getCalls.count == calls)
        #expect(viewModel.isAtCurrentMonth)
    }

    @Test func 피커가_미래_달을_주면_이번_달로_되돌린다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        let viewModel = makeViewModel(mock: mock)

        await viewModel.selectMonth(year: 2027, month: 3)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 8))
    }

    /// 실패를 빈 달로 눙치지 않는다 — 「안 탔다」와 구분되지 않는다.
    @Test func 실패하면_에러를_드러내고_로드되지_않은_상태다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/summary")
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: 0, items: [])
        ))
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.summary == nil)
        #expect(!viewModel.isMonthLoaded)
    }

    /// 미등록 수를 못 받아도 요약은 그대로 보여준다 — 배지 하나 때문에 화면을 죽이지 않는다.
    @Test func 미등록_수만_실패하면_요약은_남는다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/missing-cost")
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.summary != nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.missingCostCount == 0)
    }

    @Test func 충전을_하루_단위로_묶는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, charges: [
            Self.charge(id: 1, startedAt: "2026-08-11T22:14:00"),
            Self.charge(id: 2, startedAt: "2026-08-10T22:14:00"),
            Self.charge(id: 3, startedAt: "2026-08-10T09:00:00"),
        ])
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.sections.map(\.items.count) == [1, 2]) // 최신 날짜 먼저
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: FAIL — `cannot find 'VehicleSummaryViewModel' in scope`

- [ ] **Step 3: 뷰모델을 쓴다**

`WooriHaru/ViewModels/VehicleSummaryViewModel.swift`:

```swift
import Foundation
import Observation

/// 요약 탭 — 월 단위 차량 집계와 그 달 충전 목록. 미등록 배지 수만 월과 무관하게 따로 받는다.
@MainActor
@Observable
final class VehicleSummaryViewModel {

    // MARK: - State

    var month: LedgerYearMonth
    private(set) var summary: VehicleSummaryResponse?
    /// 전체 기간 미등록 건수. 배지와 등록 화면 진입점에 쓴다.
    private(set) var missingCostCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    // MARK: - 의존성

    private let service: VehicleService
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        service: VehicleService = VehicleService(),
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.service = service
        self.now = now
        self.calendar = calendar
        let components = calendar.dateComponents([.year, .month], from: now())
        self.month = LedgerYearMonth(year: components.year ?? 2026, month: components.month ?? 1)
    }

    // MARK: - 파생 값

    struct DaySection: Identifiable {
        let id: Date
        let date: Date
        let items: [ChargeItem]
    }

    var sections: [DaySection] {
        let grouped = Dictionary(grouping: summary?.charges ?? []) { calendar.startOfDay(for: $0.startDate) }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(id: day, date: day, items: grouped[day]!.sorted { $0.startDate > $1.startDate })
        }
    }

    /// 보고 있는 달의 응답을 실제로 받았는지. 로딩·실패의 빈 값을 「0km 탔다」로 그리지 않기 위한 구분이다.
    var isMonthLoaded: Bool { loadedMonth == month }

    var isAtCurrentMonth: Bool { month >= currentMonth }

    private var currentMonth: LedgerYearMonth {
        let components = calendar.dateComponents([.year, .month], from: now())
        return LedgerYearMonth(year: components.year ?? 2026, month: components.month ?? 1)
    }

    // MARK: - 로드

    private var loadedMonth: LedgerYearMonth?
    /// 겹친 요청 중 최신 것만 결과를 반영한다.
    private var reloadGeneration = 0

    func load() async {
        await reload()
        await refreshMissingCount()
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let requested = month
        if requested != loadedMonth {
            summary = nil
            isLoading = true
        }
        defer {
            if generation == reloadGeneration { isLoading = false }
        }
        do {
            let loaded = try await service.fetchSummary(yearMonth: requested.apiValue)
            guard generation == reloadGeneration else { return }
            summary = loaded
            loadedMonth = requested
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration else { return }
            if requested != loadedMonth {
                summary = nil
                loadedMonth = nil
            }
            errorMessage = "차량 요약을 불러오지 못했습니다."
        }
    }

    /// 배지 하나 때문에 화면을 죽이지 않는다 — 실패하면 조용히 0으로 둔다.
    func refreshMissingCount() async {
        do {
            missingCostCount = try await service.fetchMissingCost(limit: 1).totalCount
        } catch {
            return
        }
    }

    func shiftMonth(_ delta: Int) async {
        let next = month.adding(months: delta)
        guard next <= currentMonth else { return }
        month = next
        await reload()
    }

    func selectMonth(year: Int, month selected: Int) async {
        month = min(LedgerYearMonth(year: year, month: selected), currentMonth)
        await reload()
    }
}
```

- [ ] **Step 4: 등록하고 통과를 확인한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/ViewModels/VehicleSummaryViewModel.swift
touch WooriHaru/ViewModels/VehicleSummaryViewModel.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/VehicleSummaryViewModel.swift WooriHaruTests/VehicleSummaryTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 요약 탭 뷰모델을 더한다

미등록 배지 수는 월과 무관하므로 월 이동과 분리해 받는다. 배지 조회가 실패해도
요약은 그대로 남긴다 — 배지 하나 때문에 화면을 죽일 이유가 없다."
```

---

### Task 4: VehicleStatusViewModel (기준 시각·오래됨 판정)

**Files:**
- Create: `WooriHaru/ViewModels/VehicleStatusViewModel.swift`
- Test: `WooriHaruTests/VehicleStatusTests.swift`

**Interfaces:**
- Consumes: `VehicleService`, `VehicleStatus`, `VehicleMath`
- Produces: `@MainActor @Observable final class VehicleStatusViewModel`
  - `init(service: VehicleService = VehicleService(), now: @escaping @Sendable () -> Date = { .now })`
  - `private(set) var status: VehicleStatus?`, `private(set) var isLoading: Bool`, `var errorMessage: String?`
  - `var minutesAgo: Int?`, `var isStale: Bool`, `var hasRecord: Bool`
  - `func load() async`, `func reload() async`
  - `static let staleMinutes = 30`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleStatusTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleStatusViewModelTests {
    private nonisolated static func status(asOf: String?) -> VehicleStatus {
        VehicleStatus(
            asOf: asOf, state: "asleep", stateSince: "2026-08-13T09:30:00",
            batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: Decimal(string: "312.4"),
            estRangeKm: nil, odometerKm: Decimal(string: "41203.8"),
            insideTempC: Decimal(string: "31.5"), outsideTempC: Decimal(string: "33.0"),
            climateOn: false, locationName: "집",
            tpmsBar: VehicleStatus.TpmsBar(fl: Decimal(string: "2.9"), fr: Decimal(string: "2.9"),
                                           rl: Decimal(string: "2.8"), rr: nil)
        )
    }

    /// 앱은 KST로 읽는다. 테스트도 같은 시간대에서 비교한다.
    private nonisolated static func kst(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: hour, minute: minute))!
    }

    private func makeViewModel(mock: MockAPIClient, now: Date) -> VehicleStatusViewModel {
        VehicleStatusViewModel(service: VehicleService(api: mock), now: { now })
    }

    @Test func 기준_시각이_몇_분_전인지_센다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(data: Self.status(asOf: "2026-08-13T10:02:00")))
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(viewModel.minutesAgo == 240)
        #expect(viewModel.isStale)
        #expect(viewModel.hasRecord)
    }

    @Test func 방금_받은_값은_오래되지_않았다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(data: Self.status(asOf: "2026-08-13T13:50:00")))
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(viewModel.minutesAgo == 12)
        #expect(!viewModel.isStale)
    }

    /// 기록이 아예 없는 것과 못 받은 것은 다르다.
    @Test func 기록이_없으면_에러가_아니다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse<VehicleStatus>(data: Self.status(asOf: nil)))
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(!viewModel.hasRecord)
        #expect(viewModel.minutesAgo == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/status")
        let viewModel = makeViewModel(mock: mock, now: Self.kst(14, 2))

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.status == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: FAIL — `cannot find 'VehicleStatusViewModel' in scope`

- [ ] **Step 3: 뷰모델을 쓴다**

`WooriHaru/ViewModels/VehicleStatusViewModel.swift`:

```swift
import Foundation
import Observation

/// 상태 탭 — 서버 DB에 쌓인 마지막 값을 그대로 본다. 자동 폴링도, 차를 깨우는 일도 없다.
@MainActor
@Observable
final class VehicleStatusViewModel {
    /// 이만큼 지난 값은 「지금」으로 읽히면 안 된다. 주차 중에는 몇 시간 전 값이 정상이다.
    static let staleMinutes = 30

    private(set) var status: VehicleStatus?
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: VehicleService
    private let now: @Sendable () -> Date

    init(service: VehicleService = VehicleService(), now: @escaping @Sendable () -> Date = { .now }) {
        self.service = service
        self.now = now
    }

    /// 위치 기록 자체가 있는지 — 없는 것과 못 받은 것은 다르다.
    var hasRecord: Bool { status?.asOfDate != nil }

    var minutesAgo: Int? {
        guard let asOf = status?.asOfDate else { return nil }
        return VehicleMath.minutesAgo(from: asOf, now: now())
    }

    var isStale: Bool { (minutesAgo ?? 0) > Self.staleMinutes }

    private var generation = 0

    func load() async {
        await reload()
    }

    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let loaded = try await service.fetchStatus()
            guard current == generation else { return }
            status = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            errorMessage = "차량 상태를 불러오지 못했습니다."
        }
    }
}
```

- [ ] **Step 4: 등록하고 통과를 확인한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/ViewModels/VehicleStatusViewModel.swift
touch WooriHaru/ViewModels/VehicleStatusViewModel.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/VehicleStatusViewModel.swift WooriHaruTests/VehicleStatusTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 상태 탭 뷰모델을 더한다

값보다 기준 시각을 먼저 읽게 한다 — 주차 중에는 몇 시간 전 값이 정상이라
시각 없이 배터리 %만 보면 지금 값으로 읽힌다."
```

---

### Task 5: ChargeCostQueueViewModel (미등록 큐)

**Files:**
- Create: `WooriHaru/ViewModels/ChargeCostQueueViewModel.swift`
- Test: `WooriHaruTests/ChargeCostQueueTests.swift`

**Interfaces:**
- Consumes: `VehicleService.fetchMissingCost`, 기존 `ChargeService.updateCost`, `ChargeMath.costPerKwh`, `VehicleMath.suggestedCost`
- Produces: `@MainActor @Observable final class ChargeCostQueueViewModel`
  - `init(vehicleService: VehicleService = VehicleService(), chargeService: ChargeService = ChargeService())`
  - `private(set) var items: [ChargeItem]`, `private(set) var index: Int`, `private(set) var totalCount: Int`, `private(set) var isLoading: Bool`, `private(set) var isSaving: Bool`, `var errorMessage: String?`
  - `var current: ChargeItem?`, `var isFinished: Bool`, `var savedCount: Int`, `var suggestedCost: Decimal?`
  - `func load() async`, `func save(cost: Decimal) async`, `func skip()`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ChargeCostQueueTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct ChargeCostQueueViewModelTests {
    private nonisolated static func item(id: Int, energyUsedKwh: Decimal? = Decimal(string: "51.8")) -> ChargeItem {
        ChargeItem(
            id: id, startedAt: "2026-08-11T22:14:00", endedAt: "2026-08-12T02:31:00",
            durationMin: 257, locationName: "집", energyAddedKwh: Decimal(string: "48.2"),
            energyUsedKwh: energyUsedKwh, startBatteryLevel: 18, endBatteryLevel: 90, cost: nil
        )
    }

    private nonisolated static func stub(_ mock: MockAPIClient, items: [ChargeItem], totalCount: Int? = nil) {
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: totalCount ?? items.count, items: items)
        ))
    }

    private func makeViewModel(mock: MockAPIClient) -> ChargeCostQueueViewModel {
        ChargeCostQueueViewModel(
            vehicleService: VehicleService(api: mock),
            chargeService: ChargeService(api: mock)
        )
    }

    @Test func 첫_건에는_제안값이_없다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.current?.id == 1)
        #expect(viewModel.suggestedCost == nil)
        #expect(viewModel.totalCount == 2)
    }

    /// 저장하면 다음 건으로 넘어가고, 그 단가가 다음 건의 제안값이 된다.
    @Test func 저장하면_다음_건과_제안값이_생긴다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(mock.putVoidCalls.map(\.path) == ["/tesla/charges/1/cost"])
        #expect(viewModel.current?.id == 2)
        #expect(viewModel.savedCount == 1)
        // 14100 ÷ 51.8 = 272.2… → × 51.8 ≈ 14100
        #expect(viewModel.suggestedCost == 14100)
    }

    /// 사용 전력이 없으면 제안할 근거가 없다 — 비워 둔다.
    @Test func 사용_전력이_없으면_제안하지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2, energyUsedKwh: nil)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.current?.id == 2)
        #expect(viewModel.suggestedCost == nil)
    }

    /// 건너뛰기는 서버를 부르지 않는다. 이번 큐에서만 빠지고 다음에 열면 다시 나온다.
    @Test func 건너뛰면_서버를_부르지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        viewModel.skip()

        #expect(viewModel.current?.id == 2)
        #expect(mock.putVoidCalls.isEmpty)
        #expect(viewModel.savedCount == 0)
    }

    @Test func 저장에_실패하면_그_자리에_남는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1), Self.item(id: 2)])
        mock.setPutVoidError(MockAPIClient.MockAPIError.forced)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.current?.id == 1)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.savedCount == 0)
    }

    /// 진행 중인 충전은 서버가 404로 막는다 — 그 사실을 그대로 알린다.
    @Test func 없는_충전은_안내가_다르다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1)])
        mock.setPutVoidError(APIError.serverError(statusCode: 404, message: "RESOURCE_NOT_FOUND"))
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.errorMessage?.contains("끝나지 않았거나") == true)
    }

    @Test func 마지막_건을_저장하면_끝난다() async {
        let mock = MockAPIClient()
        Self.stub(mock, items: [Self.item(id: 1)])
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.save(cost: 14100)

        #expect(viewModel.isFinished)
        #expect(viewModel.current == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: FAIL — `cannot find 'ChargeCostQueueViewModel' in scope`

- [ ] **Step 3: 뷰모델을 쓴다**

`WooriHaru/ViewModels/ChargeCostQueueViewModel.swift`:

```swift
import Foundation
import Observation

/// 금액이 빈 충전을 연달아 채우는 큐. 여기서 하는 일은 채워 넣기 하나뿐이다 —
/// 합계도 월 이동도 상세도 없다.
@MainActor
@Observable
final class ChargeCostQueueViewModel {
    private(set) var items: [ChargeItem] = []
    private(set) var index = 0
    /// 서버가 센 전체 미등록 수(요청 `limit`과 무관).
    private(set) var totalCount = 0
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var savedCount = 0
    var errorMessage: String?

    private let vehicleService: VehicleService
    private let chargeService: ChargeService
    /// 직전에 저장한 건의 kWh당 단가 — 다음 건의 제안값을 만든다.
    private var lastUnitPrice: Decimal?

    init(
        vehicleService: VehicleService = VehicleService(),
        chargeService: ChargeService = ChargeService()
    ) {
        self.vehicleService = vehicleService
        self.chargeService = chargeService
    }

    var current: ChargeItem? { index < items.count ? items[index] : nil }
    var isFinished: Bool { !isLoading && current == nil }

    /// 직전 단가 × 이 건의 사용 전력. 첫 건은 근거가 없어 nil이다.
    /// **자동 저장하지 않는다** — 제안값이 그대로 들어가면 틀린 금액이 조용히 쌓인다.
    var suggestedCost: Decimal? {
        VehicleMath.suggestedCost(unitPrice: lastUnitPrice, energyUsedKwh: current?.energyUsedKwh)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await vehicleService.fetchMissingCost(limit: 50)
            items = response.items
            totalCount = response.totalCount
            index = 0
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "미등록 목록을 불러오지 못했습니다."
        }
    }

    func save(cost: Decimal) async {
        guard let item = current, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await chargeService.updateCost(id: item.id, cost: cost)
            lastUnitPrice = ChargeMath.costPerKwh(cost: cost, energyUsedKwh: item.energyUsedKwh)
            savedCount += 1
            index += 1
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            // 404는 「없는 충전」이 아니라 「아직 안 끝난 충전」인 경우가 대부분이다.
            if case let APIError.serverError(status, _) = error, status == 404 {
                errorMessage = "아직 끝나지 않았거나 사라진 충전이라 금액을 적을 수 없어요."
            } else {
                errorMessage = "금액을 저장하지 못했습니다."
            }
        }
    }

    /// 이번 큐에서만 뺀다. 서버에 아무것도 보내지 않으므로 다음에 열면 다시 나온다.
    func skip() {
        guard current != nil else { return }
        index += 1
        errorMessage = nil
    }
}
```

- [ ] **Step 4: 등록하고 통과를 확인한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/ViewModels/ChargeCostQueueViewModel.swift
touch WooriHaru/ViewModels/ChargeCostQueueViewModel.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/ChargeCostQueueViewModel.swift WooriHaruTests/ChargeCostQueueTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 금액 미등록 큐 뷰모델을 더한다

제안값은 직전 저장 단가 × 이 건 사용 전력이고 자동 저장은 하지 않는다 —
제안이 그대로 들어가면 틀린 금액이 조용히 쌓인다."
```

---

### Task 6: 요약 탭 화면과 추이 차트

**Files:**
- Create: `WooriHaru/Views/Vehicle/VehicleSummaryTab.swift`
- Create: `WooriHaru/Views/Vehicle/VehicleTrendChart.swift`

**Interfaces:**
- Consumes: `VehicleSummaryViewModel`, `VehiclePeriod`, `VehicleFormat`, 기존 `ChargeRow`·`GlassCard`·`MonthPickerSheet`·`ChargeDetailView`
- Produces:
  - `struct VehicleSummaryTab: View` — `init(viewModel: VehicleSummaryViewModel, onOpenQueue: @escaping () -> Void)`
  - `struct VehicleTrendChart: View` — `init(trend: [VehiclePeriod], selectedKey: String?, onSelect: @escaping (String) -> Void)`

- [ ] **Step 1: 추이 차트를 쓴다**

`WooriHaru/Views/Vehicle/VehicleTrendChart.swift`:

```swift
import SwiftUI

/// 12개월 전비 추이 — 손으로 그린 막대(가계부 통계와 같은 방식, Swift Charts를 들이지 않는다).
/// **막대 탭은 콜아웃만 바꾼다.** 달을 옮기는 수단은 이미 셋(스와이프·화살표·피커)이다.
struct VehicleTrendChart: View {
    let trend: [VehiclePeriod]
    let selectedKey: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxValue = trend.compactMap(\.consumption).max() ?? 0
        let selected = trend.first { $0.yearMonth == selectedKey }
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("전비 추이 (kWh/100km)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                if let selected {
                    HStack(spacing: 6) {
                        Text("\(selected.monthNumber)월")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(Color.blue600)
                        Text(VehicleFormat.consumption(selected.consumption))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text(VehicleFormat.distance(selected.distanceKm))
                            .font(.caption2)
                            .foregroundStyle(Color.slate500)
                        Text(ChargeFormat.cost(selected.cost))
                            .font(.caption2)
                            .foregroundStyle(Color.slate500)
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .animation(.snappy, value: selected.yearMonth)
                }

                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(trend) { period in
                        bar(period, maxValue: maxValue)
                    }
                }
                .frame(height: 96)
            }
        }
    }

    private func bar(_ period: VehiclePeriod, maxValue: Decimal) -> some View {
        let isSelected = period.yearMonth == selectedKey
        let ratio: CGFloat = {
            guard let value = period.consumption, maxValue > 0 else { return 0 }
            return CGFloat(truncating: (value / maxValue) as NSDecimalNumber)
        }()
        return VStack(spacing: 5) {
            Spacer(minLength: 0)
            // 기록이 없는 달도 자리를 지킨다 — 건너뛰면 계절 비교가 어긋난다.
            RoundedRectangle(cornerRadius: 4)
                .fill(period.consumption == nil
                      ? AnyShapeStyle(Color.slate200)
                      : AnyShapeStyle(isSelected ? Color.blue600 : Color.blue300))
                .frame(height: max(3, ratio * 72))
            Text("\(period.monthNumber)")
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? Color.blue600 : Color.slate400)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(period.yearMonth) }
    }
}
```

- [ ] **Step 2: 요약 탭을 쓴다**

`WooriHaru/Views/Vehicle/VehicleSummaryTab.swift`:

```swift
import SwiftUI

/// 요약 탭 — 그 달 주행·충전, 지표, 12개월 추이, 미등록 배지, 그 달 충전 목록.
struct VehicleSummaryTab: View {
    @Bindable var viewModel: VehicleSummaryViewModel
    let onOpenQueue: () -> Void

    @State private var selectedItem: ChargeItem?
    @State private var selectedTrendKey: String?

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 30

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                heroCard.padding(.top, 8)
                metricsCard.padding(.top, 12)

                if let summary = viewModel.summary {
                    VehicleTrendChart(
                        trend: summary.trend,
                        selectedKey: selectedTrendKey ?? viewModel.month.apiValue,
                        onSelect: { selectedTrendKey = $0 }
                    )
                    .padding(.top, 12)
                }

                if viewModel.missingCostCount > 0 {
                    missingCostBadge.padding(.top, 12)
                }

                if let error = viewModel.errorMessage, viewModel.summary != nil {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                if viewModel.isLoading && viewModel.summary == nil {
                    ProgressView().padding(.top, 60)
                } else if let error = viewModel.errorMessage, viewModel.summary == nil {
                    // 못 불러온 것을 「기록 없음」으로 그리지 않는다.
                    errorState(error).padding(.top, 48)
                } else if viewModel.sections.isEmpty {
                    emptyState.padding(.top, 48)
                } else {
                    ForEach(viewModel.sections) { section in
                        daySection(section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110) // 하단 탭바에 가리지 않게
        }
        .refreshable { await viewModel.reload() }
        .sheet(item: $selectedItem) { item in
            ChargeDetailView(item: item) { await viewModel.reload() }
        }
        .onChange(of: viewModel.month) { selectedTrendKey = nil }
    }

    // MARK: - 카드

    private var heroTitle: String {
        let current = LedgerYearMonth.current()
        if viewModel.month == current { return "이번 달" }
        if viewModel.month.year == current.year { return "\(viewModel.month.month)월" }
        return viewModel.month.displayLong
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heroTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(loaded ? VehicleFormat.distance(viewModel.summary?.month.distanceKm) : ChargeFormat.placeholder)
                Text(loaded
                     ? ChargeFormat.summaryTotal(viewModel.summary?.month.cost,
                                                 count: viewModel.summary?.month.chargeCount ?? 0,
                                                 loaded: true)
                     : ChargeFormat.placeholder)
            }
            .font(.system(size: heroSize, weight: .heavy))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.top, 4)

            if loaded {
                HStack(spacing: 6) {
                    chip("\(viewModel.summary?.month.chargeCount ?? 0)회 충전")
                    chip(ChargeFormat.energy(viewModel.summary?.month.energyAddedKwh))
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Color.green600, Color.blue700],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: Color.blue600.opacity(0.35), radius: 14, y: 8)
    }

    private var loaded: Bool { viewModel.isMonthLoaded }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.2), in: Capsule())
    }

    private var metricsCard: some View {
        let month = viewModel.summary?.month
        let delta = VehicleMath.deltaPercent(current: month?.costPerKm,
                                             previous: viewModel.summary?.previous?.costPerKm)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    metric("km당 비용", VehicleFormat.costPerKm(loaded ? month?.costPerKm : nil))
                    Divider().frame(height: 28)
                    metric("전비", VehicleFormat.consumption(loaded ? month?.consumption : nil))
                }
                if let delta {
                    Text(delta >= 0 ? "지난달보다 ▲ \(delta)%" : "지난달보다 ▼ \(-delta)%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(delta >= 0 ? Color.red500 : Color.green600)
                }
                Text("그 달 충전량을 그 달 주행으로 나눈 값이라 월 경계에서 조금 흔들려요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missingCostBadge: some View {
        Button(action: onOpenQueue) {
            HStack(spacing: 8) {
                Image(systemName: "wonsign.circle")
                Text("금액 미등록 \(viewModel.missingCostCount)건")
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(Color.orange700)
            .padding(14)
            .background(Color.orange100, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func daySection(_ section: VehicleSummaryViewModel.DaySection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LedgerFormat.dayHeader(section.date))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.slate500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 16)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        // Button 대신 onTapGesture — 월 스와이프와 함께 두면 Button은
                        // 끌고 놓는 동안에도 눌린 것으로 쳐서 상세가 열린다.
                        ChargeRow(item: item)
                            .onTapGesture { selectedItem = item }
                        if index < section.items.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("이 달 기록이 없어요", systemImage: "car")
        } description: {
            Text("다른 달을 보려면 위 연월을 눌러 주세요")
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await viewModel.reload() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 3: 등록하고 빌드한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Vehicle/VehicleSummaryTab.swift WooriHaru/Views/Vehicle/VehicleTrendChart.swift
touch WooriHaru/Views/Vehicle/*.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:|BUILD" | head
```
Expected: `** BUILD SUCCEEDED **` (아직 어디서도 안 쓰이지만 컴파일은 된다)

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Vehicle WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 요약 탭 화면과 전비 추이 차트를 더한다

추이는 비용이 아니라 전비로 그린다 — 계절 차이를 보려는 것이고, 비용은
요금제가 바뀌면 계절과 무관하게 움직인다. 기록이 없는 달도 자리를 지킨다."
```

---

### Task 7: 상태 탭 화면

**Files:**
- Create: `WooriHaru/Views/Vehicle/VehicleStatusTab.swift`

**Interfaces:**
- Consumes: `VehicleStatusViewModel`, `VehicleFormat`, `ChargeFormat`
- Produces: `struct VehicleStatusTab: View` — `init(viewModel: VehicleStatusViewModel)`

- [ ] **Step 1: 화면을 쓴다**

`WooriHaru/Views/Vehicle/VehicleStatusTab.swift`:

```swift
import SwiftUI

/// 상태 탭 — 서버 DB에 쌓인 마지막 값. **기준 시각을 값보다 먼저 읽게 둔다.**
struct VehicleStatusTab: View {
    @Bindable var viewModel: VehicleStatusViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                asOfLine.padding(.top, 8)

                if viewModel.isLoading && viewModel.status == nil {
                    ProgressView().padding(.top, 60)
                } else if let error = viewModel.errorMessage, viewModel.status == nil {
                    errorState(error).padding(.top, 48)
                } else if let status = viewModel.status, viewModel.hasRecord {
                    batteryCard(status)
                    cabinCard(status)
                    tpmsCard(status)
                } else if viewModel.status != nil {
                    // 기록이 아직 없는 것과 못 받은 것은 다르다.
                    ContentUnavailableView {
                        Label("아직 기록이 없어요", systemImage: "car")
                    } description: {
                        Text("차가 한 번 깨어나면 값이 쌓여요")
                    }
                    .padding(.top, 48)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await viewModel.reload() }
    }

    private var asOfLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text(viewModel.minutesAgo.map { "\(VehicleFormat.relative(minutes: $0)) 기준" } ?? "기준 시각 없음")
                .fontWeight(.bold)
            if let state = viewModel.status?.state {
                Text("· \(VehicleFormat.stateLabel(state))")
            }
            Spacer()
        }
        .font(.caption)
        // 오래된 값도 값이다. 가리지 않고 시각만 눈에 띄게 한다.
        .foregroundStyle(viewModel.isStale ? Color.orange700 : Color.slate500)
    }

    private func batteryCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                row("배터리", status.batteryLevel.map { level in
                    status.usableBatteryLevel.map { "\(level)% (사용 가능 \($0)%)" } ?? "\(level)%"
                } ?? ChargeFormat.placeholder)
                Divider().padding(.vertical, 8)
                row("주행가능", VehicleFormat.distance(status.ratedRangeKm))
                Divider().padding(.vertical, 8)
                row("주행거리", VehicleFormat.odometer(status.odometerKm))
            }
        }
    }

    private func cabinCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                row("실내 온도", ChargeFormat.temperature(status.insideTempC))
                Divider().padding(.vertical, 8)
                row("외기 온도", ChargeFormat.temperature(status.outsideTempC))
                Divider().padding(.vertical, 8)
                row("에어컨", status.climateOn.map { $0 ? "켜짐" : "꺼짐" } ?? ChargeFormat.placeholder)
                Divider().padding(.vertical, 8)
                row("위치", status.locationName ?? ChargeFormat.placeholder)
            }
        }
    }

    private func tpmsCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("타이어 공기압")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)
                HStack(spacing: 10) {
                    wheel("FL", status.tpmsBar?.fl)
                    wheel("FR", status.tpmsBar?.fr)
                }
                HStack(spacing: 10) {
                    wheel("RL", status.tpmsBar?.rl)
                    wheel("RR", status.tpmsBar?.rr)
                }
            }
        }
    }

    private func wheel(_ label: String, _ bar: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate400)
            Text(VehicleFormat.pressureBar(bar))
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
            Text(VehicleFormat.pressurePsi(bar))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.slate400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await viewModel.reload() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 2: 등록하고 빌드한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Vehicle/VehicleStatusTab.swift
touch WooriHaru/Views/Vehicle/VehicleStatusTab.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:|BUILD" | head
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Views/Vehicle/VehicleStatusTab.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 상태 탭 화면을 더한다

기준 시각을 맨 위에 두고, 30분이 넘으면 그 줄만 강조한다 — 오래된 값도 값이라
가리지 않는다."
```

---

### Task 8: 금액 등록 화면

**Files:**
- Create: `WooriHaru/Views/Vehicle/ChargeCostQueueView.swift`

**Interfaces:**
- Consumes: `ChargeCostQueueViewModel`, `ChargeFormat.parseCost`·`plainNumber`, `LedgerFormat`
- Produces: `struct ChargeCostQueueView: View` — `init(onClose: @escaping () async -> Void)` (닫힐 때 요약 탭이 다시 받도록)

- [ ] **Step 1: 화면을 쓴다**

`WooriHaru/Views/Vehicle/ChargeCostQueueView.swift`:

```swift
import SwiftUI

/// 금액이 빈 충전을 연달아 채우는 화면. 채워 넣는 일 하나만 한다 —
/// 합계도 월 이동도 상세도 없다.
struct ChargeCostQueueView: View {
    /// 닫을 때 요약 탭이 배지와 목록을 다시 받게 한다.
    let onClose: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ChargeCostQueueViewModel()
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsedCost: Decimal? { ChargeFormat.parseCost(text) }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let item = viewModel.current {
                    form(item)
                } else {
                    finishedState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassScreenBackground()
            .navigationTitle("금액 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.totalCount > 0 {
                        Text("\(min(viewModel.index + 1, viewModel.items.count)) / \(viewModel.items.count)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.slate500)
                    }
                }
            }
            .task {
                await viewModel.load()
                fillSuggestion()
            }
        }
    }

    private func form(_ item: ChargeItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LedgerFormat.dayWithYear(item.startDate))
                    .font(.title3)
                    .fontWeight(.heavy)
                Text([item.locationName ?? "장소 없음",
                      ChargeFormat.energy(item.energyUsedKwh),
                      ChargeFormat.duration(item.durationMin),
                      ChargeFormat.batteryRange(item.startBatteryLevel, item.endBatteryLevel)]
                        .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }

            HStack(spacing: 8) {
                Text("₩")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.slate500)
                TextField("금액", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .focused($focused)
            }
            .padding(14)
            .background(Color.slate100, in: RoundedRectangle(cornerRadius: 14))

            if let suggested = viewModel.suggestedCost {
                Text("직전 단가 기준 약 \(LedgerFormat.amount(suggested, currency: "KRW"))")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red500)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("건너뛰기") {
                    viewModel.skip()
                    fillSuggestion()
                }
                .buttonStyle(.bordered)
                Button("저장 · 다음") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedCost == nil || viewModel.isSaving)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .onAppear { focused = true }
    }

    private var finishedState: some View {
        ContentUnavailableView {
            Label(viewModel.savedCount > 0 ? "다 채웠어요" : "채울 게 없어요", systemImage: "checkmark.circle")
        } description: {
            Text(viewModel.savedCount > 0 ? "\(viewModel.savedCount)건을 등록했어요" : "금액이 빈 충전이 없어요")
        } actions: {
            Button("닫기") { close() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func save() {
        guard let cost = parsedCost else { return }
        Task {
            await viewModel.save(cost: cost)
            // 실패하면 같은 건이 남아 있으므로 입력도 그대로 둔다.
            if viewModel.errorMessage == nil { fillSuggestion() }
        }
    }

    /// 다음 건으로 넘어갈 때 제안값을 채워 둔다. 근거가 없으면 비운다.
    private func fillSuggestion() {
        text = viewModel.suggestedCost.map(ChargeFormat.plainNumber) ?? ""
        focused = viewModel.current != nil
    }

    private func close() {
        Task {
            await onClose()
            dismiss()
        }
    }
}
```

- [ ] **Step 2: 등록하고 빌드한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Vehicle/ChargeCostQueueView.swift
touch WooriHaru/Views/Vehicle/ChargeCostQueueView.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:|BUILD" | head
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Views/Vehicle/ChargeCostQueueView.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 금액 등록 화면을 더한다

저장하면 곧바로 다음 건으로 넘어가고 키패드는 내려가지 않는다. 실패하면 같은 건이
남으므로 입력도 그대로 둔다."
```

---

### Task 9: 컨테이너 연결과 옛 화면 제거

**Files:**
- Create: `WooriHaru/Views/Vehicle/VehicleView.swift`
- Modify: `WooriHaru/ContentView.swift` (`AppDestination.charges` → `.vehicle`, destination 교체)
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift` (라벨 「충전 내역」 → 「차량」)
- Modify: `WooriHaru/Services/ChargeService.swift` (`fetchCharges` 제거)
- Delete: `WooriHaru/Views/Charge/ChargeListView.swift`, `WooriHaru/ViewModels/ChargeListViewModel.swift`
- Modify: `WooriHaruTests/ChargeTests.swift` (`ChargeListViewModelTests` 삭제, `ChargeRow`가 쓰던 픽스처는 `VehicleSummaryTests`가 이미 가진다)

**Interfaces:**
- Consumes: Task 3·4의 뷰모델, Task 6~8의 뷰
- Produces: `struct VehicleView: View` — 인자 없음. `AppDestination.vehicle`이 띄운다

- [ ] **Step 1: 컨테이너를 쓴다**

`WooriHaru/Views/Vehicle/VehicleView.swift`:

```swift
import SwiftUI

/// 「차량」 미니앱 — 요약·상태 두 탭. 가계부와 같은 하단 글래스 탭바 구조다.
struct VehicleView: View {
    private enum Tab { case summary, status }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .summary
    @State private var summaryViewModel = VehicleSummaryViewModel()
    @State private var statusViewModel = VehicleStatusViewModel()
    @State private var showingMonthPicker = false
    @State private var showingQueue = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            tabBar
        }
        .glassScreenBackground()
        // 좌우 스와이프 = 월 이동. 상태 탭에는 월이 없으므로 마스크로 끈다
        // (`nil`을 넘길 수 없는 API라 including으로 제어한다).
        .simultaneousGesture(monthSwipeGesture, including: tab == .summary ? .all : .subviews)
        .navigationBarBackButtonHidden(true) // 월 이동 스와이프와 겹치는 엣지 뒤로가기 차단
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel("뒤로")
            }
            ToolbarItem(placement: .principal) { principalTitle }
        }
        .sensoryFeedback(.selection, trigger: summaryViewModel.month)
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(
                initialYear: summaryViewModel.month.year,
                initialMonth: summaryViewModel.month.month
            ) { year, month in
                Task { await summaryViewModel.selectMonth(year: year, month: month) }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showingQueue) {
            ChargeCostQueueView {
                await summaryViewModel.reload()
                await summaryViewModel.refreshMissingCount()
            }
        }
        .task { await summaryViewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .summary:
            VehicleSummaryTab(viewModel: summaryViewModel) { showingQueue = true }
        case .status:
            VehicleStatusTab(viewModel: statusViewModel)
                .task { await statusViewModel.load() }
        }
    }

    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .summary: monthSwitcher
        case .status: Text("차량 상태").font(.subheadline).fontWeight(.bold)
        }
    }

    private var monthSwitcher: some View {
        HStack(spacing: 0) {
            Button { Task { await summaryViewModel.shiftMonth(-1) } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("이전 달")
            Button { showingMonthPicker = true } label: {
                Text(summaryViewModel.month.displayLong)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 4)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("연월 선택 열기")
            Button { Task { await summaryViewModel.shiftMonth(1) } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("다음 달")
            .disabled(summaryViewModel.isAtCurrentMonth)
            .opacity(summaryViewModel.isAtCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Color.slate700)
    }

    /// 수직 스크롤과 헷갈리지 않게 가로 성분이 확실할 때만 반응한다.
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.5 else { return }
                Task { await summaryViewModel.shiftMonth(dx > 0 ? -1 : 1) }
            }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.summary, icon: "chart.bar.fill", label: "요약")
            tabButton(.status, icon: "car.fill", label: "상태")
        }
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        // 버튼 사이 여백 탭이 아래 목록으로 새지 않게 바 전체를 히트 영역으로 만든다.
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {}
        .padding(.horizontal, 60)
        .padding(.bottom, 8)
    }

    private func tabButton(_ target: Tab, icon: String, label: String) -> some View {
        let selected = tab == target
        return Button {
            withAnimation(.snappy(duration: 0.2)) { tab = target }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : Color.slate500)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: [Color.blue500, Color.blue700],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color.blue600.opacity(0.4), radius: 8, y: 3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: 라우팅과 드로어를 바꾼다**

`WooriHaru/ContentView.swift` — `AppDestination`의 `case charges`를 `case vehicle`로 바꾸고, destination을 교체한다:

```swift
                    case .vehicle: VehicleView()
```

`WooriHaru/Views/Components/SideDrawerView.swift` — 드로어 항목을 바꾼다:

```swift
                drawerItem(icon: "bolt.car", label: "차량") { isOpen = false; navPath.append(AppDestination.vehicle) }
```

- [ ] **Step 3: 옛 화면과 옛 조회를 지운다**

`WooriHaru/Services/ChargeService.swift`에서 `fetchCharges(yearMonth:)`를 통째로 지운다(상세·금액 수정만 남는다). 파일 주석도 바꾼다:

```swift
/// 충전 상세와 금액 수정. 월 목록은 `/tesla/summary`가 함께 내려주므로 여기 없다.
```

파일을 지우고 Xcode 타겟에서도 뺀다:

```bash
git rm WooriHaru/Views/Charge/ChargeListView.swift WooriHaru/ViewModels/ChargeListViewModel.swift
ruby -e "require 'xcodeproj'; \
project = Xcodeproj::Project.open('WooriHaru.xcodeproj'); \
target = project.targets.find { |t| t.name == 'WooriHaru' }; \
%w[WooriHaru/Views/Charge/ChargeListView.swift WooriHaru/ViewModels/ChargeListViewModel.swift].each do |path| \
  abs = File.expand_path(path); \
  target.source_build_phase.files.select { |bf| bf.file_ref && bf.file_ref.real_path.to_s == abs }.each(&:remove_from_project); \
  project.files.select { |fr| fr.real_path.to_s == abs }.each(&:remove_from_project); \
end; \
project.save"
```

`WooriHaruTests/ChargeTests.swift`에서 `ChargeListViewModelTests` 구조체 전체를 지운다(월 이동·실패 상태는 `VehicleSummaryTests`가 덮는다). **`ChargeServiceTests`·`ChargeDetailTests`·`ChargeFormatTests`는 그대로 둔다.** `ChargeServiceTests`에 `fetchCharges`를 부르는 테스트가 있으면 그것만 지운다.

- [ ] **Step 4: 정리가 됐는지 기계로 확인한다**

```bash
grep -rn "ChargeListView\|ChargeListViewModel\|fetchCharges\|AppDestination.charges" --include='*.swift' WooriHaru WooriHaruTests
grep -c "ChargeListView" WooriHaru.xcodeproj/project.pbxproj
```
Expected: 첫 명령은 출력 없음, 두 번째는 `0`

- [ ] **Step 5: 등록하고 전체를 깨끗하게 돌린다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Vehicle/VehicleView.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' clean test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```
Expected: `** TEST SUCCEEDED **` (증분 빌드가 변경을 놓치는 일이 있어 여기서만은 `clean`을 쓴다)

- [ ] **Step 6: 실기기에서 손으로 확인한다**

테스트가 못 잡는 것들이다(이 저장소에 ViewInspector가 없다). 하나씩 눌러 본다.

- 드로어 「차량」 → 요약 탭이 뜨고 상단에 연월, 하단에 탭 2개
- 요약 탭에서 **좌우로 쓸면 달이 바뀌고, 그때 충전 상세가 열리지 않는다**
- 충전 한 줄을 탭하면 상세 시트가 뜬다
- 상태 탭으로 옮기면 상단 타이틀이 「차량 상태」로 바뀌고 월 화살표가 사라진다
- 상태 탭에서 당겨서 새로고침이 돈다
- 미등록 배지 → 등록 화면 → 저장하면 다음 건으로 넘어가고 **키패드가 내려가지 않는다**
- 등록 화면을 닫으면 배지 수와 목록이 갱신된다

- [ ] **Step 7: 커밋**

```bash
git add -A
git commit -m "feat: 충전 내역을 「차량」 미니앱으로 넓힌다

요약 탭이 월 단위로 주행·충전·그 달 목록까지 한 스크롤에 답하고, 상태 탭이 지금
차의 상태를 낸다. 월 목록 조회는 요약 응답에 흡수되어 사라진다."
```

---

## 완료 기준

- `xcodebuild clean test`가 통과한다
- `grep -rn "ChargeListView\|fetchCharges" --include='*.swift'`가 비어 있다
- 드로어에서 「차량」으로 들어가 두 탭과 등록 화면이 손으로 확인된다
- 서버 배포 전이라면 세 엔드포인트가 404를 주므로 각 탭이 **실패 상태(재시도 버튼)** 를 보여 준다 — 빈 화면이 아니다
