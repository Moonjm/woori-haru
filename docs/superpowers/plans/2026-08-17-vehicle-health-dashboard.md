# 차량 대시보드 1단계(배터리 건강) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 차량 미니앱의 첫 화면을 「건강」 탭으로 바꿔, 배터리 잔존율·열화 추이·타이어 공기압 판정을 한눈에 보이게 한다.

**Architecture:** 기존 상태 탭(`VehicleStatusTab`)을 건강 탭(`VehicleHealthTab`)으로 넓힌다. 이 화면은 뷰모델 **둘**을 쓴다 — `/tesla/status`를 보는 기존 `VehicleStatusViewModel`과 `/tesla/battery-health`를 보는 새 `VehicleHealthViewModel`이다. 스펙이 「하나가 실패해도 다른 카드는 그린다」고 못박았으므로 한 뷰모델로 합치지 않는다. 서버는 월별 중앙값 표본만 내고, 신차 기준선(568km / 78.5kWh) 대비 잔존율·열화는 앱 상수와 `VehicleMath`가 낸다. 차트·링·차 도형은 전부 손으로 그린다(Swift Charts를 새로 들이지 않는 저장소 관례).

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), `@Observable` 뷰모델, Swift Testing(`import Testing`), 기존 `APIClientProtocol`·`MockAPIClient`·`GlassCard`.

**Spec:** `docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md`
(서버 계약: toy-back `docs/superpowers/specs/2026-08-17-tesla-battery-health-design.md`, 구현은 `apps/daily-record/src/main/kotlin/com/toy/backend/tesla/TeslaVehicleDtos.kt`)

## Global Constraints

- **테스트 명령:** `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test`
- **증분 빌드가 변경을 놓치는 일이 있다.** 각 태스크의 마지막 테스트 실행 전에 바꾼 파일을 `touch`하고, 마지막 태스크의 최종 확인은 `clean test`로 한다.
- **없는 값은 0이 아니라 「—」다.** 0은 「그렇게 측정됐다」는 뜻이라 「모른다」와 구분되지 않는다.
- **못 받은 것을 「기록 없음」으로 그리지 않는다.** 실패는 재시도가 있는 실패 상태, 로딩은 「—」다.
- **나눗셈은 앱이 한다.** 분모가 없거나 0이면 결과는 nil이다.
- **신차 기준선은 앱 상수다** — 568km / 78.5kWh. 서버 응답에 없다. 2021년 9월 출고 모델 3 롱 레인지(AWD) 한 대 전제다.
- **타이어 권장 42psi, 정상 38~46psi.** 상수로 둔다. 화면 표기는 **psi만** 낸다(bar는 서버 저장 단위일 뿐이다).
- **경고 문구를 넣지 않는다** — 열화는 고장이 아니다. 잔존율이 낮아지면 링 색만 바뀐다(90% 이상 초록, 80~90% 노랑, 80% 미만 주황).
- **잔존율은 100%를 넘어도 자르지 않는다**(냉간·BMS 재보정으로 실제로 넘는다). 대신 열화는 음수로 쓰지 않고 `0%`로 낸다.
- **금액 입력 경로를 건드리지 않는다.** 큐 화면(`ChargeCostQueueView`)과 상세 「금액 수정」 코드는 이 계획에서 한 줄도 수정하지 않는다. 건강 화면에 배지를 다는 것은 진입점 추가다.
- 금액·거리·용량은 `Decimal`, 서버 시각은 KST `LocalDateTime` 문자열이다.
- 커밋 메시지는 한국어 관례를 따른다(`feat:`/`fix:`/`refactor:` + 한 줄 요약 + 왜).

### 스펙에서 갈라진 두 지점 (실행자는 그대로 따른다)

1. **「만충 환산」·「용량 추정」·「중앙값」을 앱에 두지 않는다.** 스펙의 「계산」·「테스트」 절은 이 셋을 `VehicleMath`에 두라고 적었지만, 같은 문서의 「서버 API」 절이 **「표본 규칙과 월별 중앙값은 서버가 끝낸다」**고 확정했고 백엔드 구현도 그렇다(`BatteryHealthSample`이 이미 그 달 중앙값이다). 앱에 두면 아무도 부르지 않는 죽은 코드가 된다. **앱이 실제로 하는 나눗셈은 「잔존율 = 최근 값 ÷ 기준선」 하나이며, 그것과 열화·줄어든 거리·공기압 판정만 `VehicleMath`에 둔다.**
2. **응답은 `DataResponse` 래퍼 안에 온다.** 스펙 예시(`{ "samples": [...] }`)에는 래퍼가 빠져 있으나, 백엔드 컨트롤러가 `DataResponseBody(service.batteryHealth())`를 돌려준다. 다른 차량 엔드포인트와 같다.
3. **`fullRangeKm`은 non-optional이다.** 백엔드 DTO가 `BigDecimal`(non-null)이고, 표본이 없는 달은 배열에서 빠진다. `capacityKwh`만 nullable이다.

---

### Task 1: 배터리 건강 모델·상수·계산·표기

**Files:**
- Create: `WooriHaru/Models/VehicleHealthModels.swift`
- Modify: `WooriHaru/Models/VehicleModels.swift` (`VehicleMath.rounded`·`VehicleFormat.number`의 `private` 제거)
- Test: `WooriHaruTests/VehicleHealthMathTests.swift`

**Interfaces:**
- Consumes: `VehicleMath`, `VehicleFormat`, `VehicleStatus.TpmsBar`, `ChargeFormat.placeholder` (기존)
- Produces:
  - `struct BatteryHealthResponse: Codable { let samples: [BatteryHealthSample] }`
  - `struct BatteryHealthSample: Codable, Identifiable, Equatable` — `yearMonth: String`, `fullRangeKm: Decimal`, `capacityKwh: Decimal?`, `sampleCount: Int`, `capacitySampleCount: Int`, `id == yearMonth`, `monthOrdinal: Int`, `shortLabel: String`
  - `enum VehicleBaseline` — `newRangeKm: Decimal`, `newCapacityKwh: Decimal`
  - `enum TirePressureSpec` — `recommendedPsi: Decimal`, `normalRangePsi: ClosedRange<Decimal>`
  - `enum TireStatus: Equatable` — `.unknown`, `.low`, `.normal`, `.high`
  - `extension VehicleMath` — `remainingPercent(current:baseline:) -> Decimal?`, `degradationPercent(remainingPercent:) -> Decimal?`, `rangeLostKm(current:) -> Decimal?`, `tireStatus(bar:) -> TireStatus`, `averagePsi(_:) -> Decimal?`
  - `extension VehicleFormat` — `percent(_:) -> String`, `againstBaseline(_:baseline:unit:fraction:) -> String`, `psiText(_:) -> String`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleHealthMathTests.swift`를 만든다:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VehicleHealthMathTests {

    // MARK: - 잔존율·열화

    /// 실측 기준값이다 — 2026-08 만충 환산 525.3km. 568km 대비 92.4%.
    @Test func 잔존율은_신차_기준선으로_낸다() {
        let remaining = VehicleMath.remainingPercent(
            current: Decimal(string: "525.3"), baseline: VehicleBaseline.newRangeKm
        )
        #expect(VehicleFormat.percent(remaining) == "92%")
        #expect(VehicleFormat.percent(VehicleMath.degradationPercent(remainingPercent: remaining)) == "8%")
    }

    /// 값이 없거나 기준선이 0이면 계산하지 않는다 — 0%로 내면 「배터리가 다 죽었다」가 된다.
    @Test func 값이_없으면_잔존율도_없다() {
        #expect(VehicleMath.remainingPercent(current: nil, baseline: 568) == nil)
        #expect(VehicleMath.remainingPercent(current: 525, baseline: 0) == nil)
        #expect(VehicleMath.degradationPercent(remainingPercent: nil) == nil)
        #expect(VehicleMath.rangeLostKm(current: nil) == nil)
    }

    /// 냉간·BMS 재보정으로 실제로 넘는다. **자르지 않는다** — 자르면 튄 값이 화면에서 사라진다.
    /// 대신 열화는 음수로 쓰지 않는다. 「열화 -2%」는 읽을 말이 아니다.
    @Test func 잔존율이_100을_넘어도_자르지_않는다() {
        let remaining = VehicleMath.remainingPercent(current: 580, baseline: VehicleBaseline.newRangeKm)
        #expect(VehicleFormat.percent(remaining) == "102%")
        #expect(VehicleFormat.percent(VehicleMath.degradationPercent(remainingPercent: remaining)) == "0%")
        #expect(VehicleMath.rangeLostKm(current: 580) == 0)
    }

    /// 잔존율과 열화를 각자 반올림하면 화면에서 둘을 더해 101%가 되는 달이 나온다.
    /// 열화는 **반올림한 잔존율**에서 뺀다.
    @Test func 잔존율과_열화를_더하면_늘_100이다() {
        for value in [Decimal(string: "525.3")!, 520, Decimal(string: "512.5")!, 559] {
            let remaining = VehicleMath.remainingPercent(current: value, baseline: VehicleBaseline.newRangeKm)!
            let degradation = VehicleMath.degradationPercent(remainingPercent: remaining)!
            let sum = Int(VehicleFormat.percent(remaining).dropLast())! +
                      Int(VehicleFormat.percent(degradation).dropLast())!
            #expect(sum == 100)
        }
    }

    @Test func 줄어든_거리는_신차에서_뺀_값이다() {
        #expect(VehicleMath.rangeLostKm(current: 525) == 43)
    }

    // MARK: - 타이어 공기압

    /// 판정은 psi로 한다 — 화면이 psi로 그리므로 경계도 psi여야 한다.
    /// 42psi ≈ 2.896bar, 38psi ≈ 2.620bar, 46psi ≈ 3.172bar.
    @Test func 공기압을_범위로_판정한다() {
        #expect(VehicleMath.tireStatus(bar: Decimal(string: "2.9")) == .normal)
        #expect(VehicleMath.tireStatus(bar: Decimal(string: "2.62")) == .normal)   // 38psi 경계
        #expect(VehicleMath.tireStatus(bar: Decimal(string: "3.17")) == .normal)   // 46psi 경계
        #expect(VehicleMath.tireStatus(bar: Decimal(string: "2.5")) == .low)       // 36psi
        #expect(VehicleMath.tireStatus(bar: Decimal(string: "3.3")) == .high)      // 48psi
    }

    /// **값이 없는 것과 벗어난 것은 다르다.** 없는 바퀴를 경고로 칠하면 안 된다.
    @Test func 값이_없는_바퀴는_경고가_아니다() {
        #expect(VehicleMath.tireStatus(bar: nil) == .unknown)
        #expect(VehicleFormat.pressurePsi(nil) == ChargeFormat.placeholder)
    }

    @Test func 평균_공기압은_있는_바퀴만_센다() {
        let some = VehicleStatus.TpmsBar(fl: Decimal(string: "2.9"), fr: Decimal(string: "2.9"),
                                         rl: Decimal(string: "2.8"), rr: nil)
        #expect(VehicleFormat.psiText(VehicleMath.averagePsi(some)) == "42psi")
        #expect(VehicleMath.averagePsi(VehicleStatus.TpmsBar(fl: nil, fr: nil, rl: nil, rr: nil)) == nil)
        #expect(VehicleMath.averagePsi(nil) == nil)
    }

    // MARK: - 표기

    @Test func 기준선과_나란히_적는다() {
        #expect(VehicleFormat.againstBaseline(Decimal(string: "525.3"),
                                              baseline: VehicleBaseline.newRangeKm,
                                              unit: "km", fraction: 0) == "525 / 568 km")
        #expect(VehicleFormat.againstBaseline(Decimal(string: "71.6"),
                                              baseline: VehicleBaseline.newCapacityKwh,
                                              unit: "kWh", fraction: 1) == "71.6 / 78.5 kWh")
        // 값이 없어도 기준선은 남긴다 — 무엇과 견주는 자리인지 사라지면 안 된다.
        #expect(VehicleFormat.againstBaseline(nil, baseline: VehicleBaseline.newRangeKm,
                                              unit: "km", fraction: 0) == "— / 568 km")
    }

    @Test func 표본의_달을_읽는다() {
        let sample = BatteryHealthSample(yearMonth: "2026-08", fullRangeKm: Decimal(string: "525.3")!,
                                         capacityKwh: Decimal(string: "71.6")!,
                                         sampleCount: 3, capacitySampleCount: 1)
        #expect(sample.monthOrdinal == 2026 * 12 + 8)
        #expect(sample.shortLabel == "26년 8월")
        #expect(sample.id == "2026-08")
    }

    /// 서버가 주는 그대로 읽는다. `capacityKwh`만 null이 온다.
    @Test func 응답을_디코딩한다() throws {
        let json = """
        { "samples": [
          { "yearMonth": "2026-07", "fullRangeKm": 527.1, "capacityKwh": null,
            "sampleCount": 1, "capacitySampleCount": 0 },
          { "yearMonth": "2026-08", "fullRangeKm": 525.3, "capacityKwh": 71.6,
            "sampleCount": 3, "capacitySampleCount": 1 }
        ] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BatteryHealthResponse.self, from: json)

        #expect(decoded.samples.count == 2)
        #expect(decoded.samples[0].capacityKwh == nil)
        #expect(decoded.samples[1].capacityKwh == Decimal(string: "71.6"))
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run:
```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: 컴파일 실패 — `cannot find 'VehicleBaseline' in scope`, `cannot find 'BatteryHealthSample' in scope`.

- [ ] **Step 3: `VehicleModels.swift`의 두 헬퍼를 파일 밖에서 쓸 수 있게 연다**

`WooriHaru/Models/VehicleModels.swift`에서 두 줄만 고친다. Swift의 `private`는 **선언된 파일 안**에서만 보이므로, 다른 파일의 `extension VehicleMath`/`extension VehicleFormat`은 이 둘을 부를 수 없다.

`VehicleMath` 안:
```swift
    /// **`VehicleHealthModels.swift`의 확장도 쓴다** — 그래서 private가 아니다.
    /// 반올림 규칙을 두 벌 두면 잔존율과 열화가 화면에서 101%가 되는 달이 나온다.
    static func rounded(_ value: Decimal) -> Decimal {
        var original = value
        var result = Decimal()
        NSDecimalRound(&result, &original, 0, .plain)
        return result
    }
```

`VehicleFormat` 안:
```swift
    /// **`VehicleHealthModels.swift`의 확장도 쓴다** — 그래서 private가 아니다.
    static func number(_ value: Decimal, fraction: Int, grouping: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.maximumFractionDigits = fraction
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
```

- [ ] **Step 4: `VehicleHealthModels.swift`를 만든다**

```swift
import Foundation

// MARK: - 응답

/// 월별 배터리 열화 표본. **오래된 것부터** 오고, 파라미터가 없어 전 기간이 온다 —
/// 몇 개월을 그릴지는 앱이 정한다.
struct BatteryHealthResponse: Codable {
    let samples: [BatteryHealthSample]
}

/// 그 달의 **중앙값**이다. 표본 규칙(종료 80% 이상, 용량은 ΔSoC 40%p 이상)과 중앙값은
/// 서버가 끝낸다 — 앱이 전 건을 받아 거르지 않는다.
///
/// **표본이 없는 달은 배열에서 아예 빠진다.** `/tesla/summary`의 `trend`가 빈 달의 자리를
/// 채우는 것과 다르다 — 선을 이을지 끊을지를 앱이 정하라고 그렇게 온다.
struct BatteryHealthSample: Codable, Identifiable, Equatable {
    let yearMonth: String
    /// 만충 환산 주행거리(km). 이 값이 있는 달만 오므로 옵셔널이 아니다.
    let fullRangeKm: Decimal
    /// 사용 가능 용량(kWh). 그 달에 조건에 드는 충전이 없으면 **nil이다. 0이 아니다.**
    let capacityKwh: Decimal?
    let sampleCount: Int
    let capacitySampleCount: Int

    var id: String { yearMonth }

    /// "2026-08" → 24320. **달 사이 간격을 재는 데 쓴다** — 빠진 달을 찾아 추이 선을 끊고,
    /// x축을 시간에 비례해 놓아 빈 구간이 눈에 보이게 한다.
    var monthOrdinal: Int {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return 0 }
        return year * 12 + month
    }

    /// "2026-08" → "26년 8월". 추이가 24개월이라 연도가 섞인다 — 달 번호만으로는 갈리지 않는다.
    var shortLabel: String {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return yearMonth }
        return "\(year % 100)년 \(month)월"
    }
}

// MARK: - 상수

/// 신차 기준선. **서버 응답에 없다** — TeslaMate에 제원표가 없어 우리가 심어야 하는 값이다.
///
/// EPA 인증 353마일 = 568km이고, 국내 환경부 인증(528km)이 아니다. 실측이 갈랐다 —
/// 2026-08-15 충전 한 건(17%→99%, 90→520km, 58.7kWh)으로 낸 용량 71.6kWh가 78.5kWh 대비
/// 잔존 91%인데, 주행거리로 낸 92.4%와 같은 자리다. 528km를 기준선으로 잡았다면 5년 탄 차의
/// 열화가 0.6%로 표시될 뻔했다.
///
/// **차량 한 대 전제다** — 2021년 9월 출고 모델 3 롱 레인지(AWD). 차를 바꾸면 이 두 줄을 고친다.
enum VehicleBaseline {
    static let newRangeKm: Decimal = 568
    static let newCapacityKwh = Decimal(string: "78.5")!
}

/// 타이어 권장·정상 범위. 차 문틀 스티커 값이라 psi다.
enum TirePressureSpec {
    static let recommendedPsi: Decimal = 42
    static let normalRangePsi: ClosedRange<Decimal> = 38...46
}

/// 공기압 판정. **`.unknown`과 `.low`/`.high`는 다르다** — 값을 못 받은 바퀴를 경고로 칠하면
/// 멀쩡한 타이어를 의심하게 된다.
enum TireStatus: Equatable {
    case unknown, low, normal, high

    var isAbnormal: Bool { self == .low || self == .high }
}

// MARK: - 계산

extension VehicleMath {
    /// 잔존율(%) — 최근 값 ÷ 신차 기준선 × 100.
    ///
    /// **100%를 넘어도 자르지 않는다.** 냉간·BMS 재보정으로 실제로 넘는 달이 있고,
    /// 화면이 자르면 그 사실이 사라진다.
    static func remainingPercent(current: Decimal?, baseline: Decimal) -> Decimal? {
        guard let current, baseline > 0 else { return nil }
        return current / baseline * 100
    }

    /// 열화(%) — **반올림한 잔존율**에서 뺀다. 각자 반올림하면 화면에서 둘을 더해
    /// 101%가 되는 달이 나온다. 음수는 0으로 낸다 — 「열화 -2%」는 읽을 말이 아니다.
    static func degradationPercent(remainingPercent: Decimal?) -> Decimal? {
        guard let remainingPercent else { return nil }
        return max(0, 100 - rounded(remainingPercent))
    }

    /// 신차 대비 줄어든 거리(km). 늘어난 달(잔존율 100% 초과)은 0이다.
    static func rangeLostKm(current: Decimal?) -> Decimal? {
        guard let current else { return nil }
        return max(0, VehicleBaseline.newRangeKm - current)
    }

    /// 공기압 판정. 입력은 서버 저장 단위인 bar지만 **판정은 psi로 한다** —
    /// 화면이 psi로 그리므로 경계도 psi여야 「38psi인데 왜 빨간가」가 생기지 않는다.
    static func tireStatus(bar: Decimal?) -> TireStatus {
        guard let psi = psi(fromBar: bar) else { return .unknown }
        if psi < TirePressureSpec.normalRangePsi.lowerBound { return .low }
        if psi > TirePressureSpec.normalRangePsi.upperBound { return .high }
        return .normal
    }

    /// 네 바퀴 평균 psi — **있는 바퀴만 센다.** 없는 바퀴를 0으로 세면 평균이 무너진다.
    static func averagePsi(_ tpms: VehicleStatus.TpmsBar?) -> Decimal? {
        guard let tpms else { return nil }
        let values = [tpms.fl, tpms.fr, tpms.rl, tpms.rr].compactMap { psi(fromBar: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Decimal(values.count)
    }
}

// MARK: - 표기

extension VehicleFormat {
    /// 92.36… → "92%". 잔존율과 열화가 같은 자리수로 나와야 둘을 더해 100이 된다.
    static func percent(_ value: Decimal?) -> String {
        guard let value else { return ChargeFormat.placeholder }
        return "\(number(value, fraction: 0))%"
    }

    /// 이미 psi로 낸 값을 그대로 적는다. `pressurePsi(_:)`는 bar를 받으므로,
    /// 평균처럼 psi로 이미 계산한 값을 bar로 되돌렸다 다시 바꾸지 않게 이 자리를 둔다.
    static func psiText(_ psi: Decimal?) -> String {
        guard let psi else { return ChargeFormat.placeholder }
        return "\(number(psi, fraction: 0))psi"
    }

    /// 525.3 → "525 / 568 km". **값이 없어도 기준선은 남긴다** —
    /// 무엇과 견주는 자리인지가 사라지면 숫자만 남는다.
    static func againstBaseline(_ value: Decimal?, baseline: Decimal,
                                unit: String, fraction: Int) -> String {
        let left = value.map { number($0, fraction: fraction) } ?? ChargeFormat.placeholder
        return "\(left) / \(number(baseline, fraction: fraction)) \(unit)"
    }
}
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

```bash
touch WooriHaru/Models/VehicleHealthModels.swift WooriHaru/Models/VehicleModels.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: PASS (`VehicleHealthMathTests` 9건 포함, 기존 테스트도 전부 통과)

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Models/VehicleHealthModels.swift WooriHaru/Models/VehicleModels.swift \
        WooriHaruTests/VehicleHealthMathTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 배터리 건강 표본 모델과 잔존율·공기압 계산을 더한다

서버는 월별 중앙값 표본만 낸다. 신차 기준선(568km/78.5kWh)은 TeslaMate에
제원표가 없어 앱 상수로 심고, 잔존율·열화·공기압 판정을 앱이 낸다."
```

---

### Task 2: 서비스 호출

**Files:**
- Modify: `WooriHaru/Services/VehicleService.swift`
- Test: `WooriHaruTests/VehicleServiceTests.swift`

**Interfaces:**
- Consumes: `BatteryHealthResponse` (Task 1), `APIClientProtocol`, `DataResponse` (기존)
- Produces: `VehicleService.fetchBatteryHealth() async throws -> BatteryHealthResponse`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleServiceTests.swift`의 `본문이_비면_에러다` 테스트 **앞에** 두 테스트를 넣는다:

```swift
    /// 파라미터가 없다. 전 기간이 오고, 몇 개월을 그릴지는 앱이 정한다.
    @Test func 배터리_건강은_파라미터_없이_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/battery-health", result: DataResponse<BatteryHealthResponse>(
            data: BatteryHealthResponse(samples: [
                BatteryHealthSample(yearMonth: "2026-07", fullRangeKm: Decimal(string: "527.1")!,
                                    capacityKwh: nil, sampleCount: 1, capacitySampleCount: 0),
                BatteryHealthSample(yearMonth: "2026-08", fullRangeKm: Decimal(string: "525.3")!,
                                    capacityKwh: Decimal(string: "71.6")!,
                                    sampleCount: 3, capacitySampleCount: 1),
            ])
        ))
        let service = VehicleService(api: mock)

        let health = try await service.fetchBatteryHealth()

        #expect(health.samples.count == 2)
        #expect(mock.getCalls.map(\.path) == ["/tesla/battery-health"])
        #expect(mock.getCalls.first?.query == [:])
    }

    /// 표본이 하나도 없는 것은 에러가 아니다 — 「아직 잴 만한 충전이 없다」다.
    @Test func 표본이_없어도_에러가_아니다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/battery-health", result: DataResponse<BatteryHealthResponse>(
            data: BatteryHealthResponse(samples: [])
        ))
        let service = VehicleService(api: mock)

        #expect(try await service.fetchBatteryHealth().samples.isEmpty)
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: 컴파일 실패 — `value of type 'VehicleService' has no member 'fetchBatteryHealth'`

- [ ] **Step 3: 최소 구현을 쓴다**

`WooriHaru/Services/VehicleService.swift`의 `fetchStatus()` 아래에 넣는다:

```swift
    /// **파라미터가 없다.** 전 기간 월별 표본이 오고, 몇 개월을 그릴지는 화면이 정한다.
    /// `/tesla/status`와 독립이다 — 하나가 실패해도 다른 카드는 그린다.
    func fetchBatteryHealth() async throws -> BatteryHealthResponse {
        let response: DataResponse<BatteryHealthResponse> = try await api.get("/tesla/battery-health")
        guard let health = response.data else {
            throw APIError.serverError(statusCode: 200, message: "배터리 건강 응답이 비어 있습니다")
        }
        return health
    }
```

같은 파일 맨 위 주석도 고친다:
```swift
/// 차량 API — 월 요약(그 달 충전 목록 포함)·현재 상태·배터리 건강·금액 미등록 목록.
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
git commit -m "feat: 배터리 건강 엔드포인트를 부른다

파라미터가 없다. 전 기간이 오고 몇 개월을 그릴지는 화면이 정한다."
```

---

### Task 3: 건강 뷰모델

**Files:**
- Create: `WooriHaru/ViewModels/VehicleHealthViewModel.swift`
- Test: `WooriHaruTests/VehicleHealthTests.swift`

**Interfaces:**
- Consumes: `VehicleService.fetchBatteryHealth()` (Task 2), `VehicleService.fetchMissingCost(limit:)` (기존), `BatteryHealthSample`·`VehicleBaseline`·`VehicleMath` (Task 1)
- Produces: `@MainActor @Observable final class VehicleHealthViewModel`
  - `static let trendMonths = 24`
  - `private(set) var samples: [BatteryHealthSample]`, `isLoading: Bool`, `isLoaded: Bool`, `missingCostCount: Int`
  - `var errorMessage: String?`
  - `var hasSamples: Bool`, `latest: BatteryHealthSample?`, `latestCapacityKwh: Decimal?`
  - `var trendSamples: [BatteryHealthSample]`, `trendSegments: [[BatteryHealthSample]]`
  - `var remainingPercent: Decimal?`, `degradationPercent: Decimal?`, `rangeLostKm: Decimal?`
  - `func load() async`, `func reload() async`, `func refreshMissingCount() async`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleHealthTests.swift`를 만든다:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleHealthViewModelTests {

    private nonisolated static func sample(
        _ yearMonth: String, _ fullRangeKm: String, capacity: String? = nil, count: Int = 1
    ) -> BatteryHealthSample {
        BatteryHealthSample(
            yearMonth: yearMonth, fullRangeKm: Decimal(string: fullRangeKm)!,
            capacityKwh: capacity.flatMap { Decimal(string: $0) },
            sampleCount: count, capacitySampleCount: capacity == nil ? 0 : 1
        )
    }

    private func makeViewModel(_ mock: MockAPIClient) -> VehicleHealthViewModel {
        VehicleHealthViewModel(service: VehicleService(api: mock))
    }

    private func stub(_ mock: MockAPIClient, _ samples: [BatteryHealthSample], missing: Int = 0) {
        mock.stubGet("/tesla/battery-health",
                     result: DataResponse<BatteryHealthResponse>(data: BatteryHealthResponse(samples: samples)))
        mock.stubGet("/tesla/charges/missing-cost",
                     result: DataResponse<MissingCostResponse>(data: MissingCostResponse(totalCount: missing, items: [])))
    }

    /// 서버가 오래된 것부터 주므로 **마지막**이 최근이다.
    @Test func 최근_표본으로_잔존율을_낸다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-07", "527.1"), Self.sample("2026-08", "525.3", capacity: "71.6", count: 3)])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.latest?.yearMonth == "2026-08")
        #expect(VehicleFormat.percent(viewModel.remainingPercent) == "92%")
        #expect(VehicleFormat.percent(viewModel.degradationPercent) == "8%")
        #expect(VehicleFormat.distance(viewModel.rangeLostKm) == "43km")
        #expect(viewModel.latestCapacityKwh == Decimal(string: "71.6"))
    }

    /// 용량 표본은 주행거리 표본보다 드물다 — 최근 달에 없으면 **값이 있는 마지막 달**에서 온다.
    @Test func 용량은_값이_있는_마지막_달에서_온다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-06", "530.0", capacity: "72.4"),
                    Self.sample("2026-07", "527.1"),
                    Self.sample("2026-08", "525.3")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.latest?.yearMonth == "2026-08")
        #expect(viewModel.latestCapacityKwh == Decimal(string: "72.4"))
    }

    /// 5년 치를 다 그리면 최근 1년의 움직임이 뭉갠다. 24개월만 그린다.
    @Test func 최근_24개월만_그린다() async {
        let mock = MockAPIClient()
        let samples = (0..<30).map { index -> BatteryHealthSample in
            let ordinal = 2024 * 12 + 3 + index
            let year = (ordinal - 1) / 12
            let month = (ordinal - 1) % 12 + 1
            return Self.sample(String(format: "%04d-%02d", year, month), "540.0")
        }
        stub(mock, samples)
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.samples.count == 30)
        #expect(viewModel.trendSamples.count == 24)
        #expect(viewModel.trendSamples.last?.yearMonth == samples.last?.yearMonth)
    }

    /// **빠진 달에서 선을 끊는다.** 없는 값을 직선으로 메우면 그 달에도 잰 것처럼 보인다.
    @Test func 표본이_빠진_달에서_선이_갈린다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-03", "532.0"), Self.sample("2026-04", "530.5"),
                    // 2026-05가 없다
                    Self.sample("2026-06", "528.0"), Self.sample("2026-07", "527.1")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.trendSegments.map(\.count) == [2, 2])
        #expect(viewModel.trendSegments[0].map(\.yearMonth) == ["2026-03", "2026-04"])
        #expect(viewModel.trendSegments[1].map(\.yearMonth) == ["2026-06", "2026-07"])
    }

    @Test func 표본이_하나면_선분도_하나에_점_하나다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.hasSamples)
        #expect(viewModel.trendSegments.map(\.count) == [1])
    }

    /// 표본이 없는 것은 에러가 아니다 — 「아직 잴 만한 충전이 없다」다.
    @Test func 표본이_없어도_에러가_아니다() async {
        let mock = MockAPIClient()
        stub(mock, [])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.hasSamples)
        #expect(viewModel.isLoaded)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.remainingPercent == nil)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        stub(mock, [])
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/battery-health")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.hasSamples)
        #expect(!viewModel.isLoaded)
    }

    /// 배지 하나 때문에 화면을 죽이지 않는다. 요약 탭과 같은 규칙이다.
    @Test func 배지가_실패해도_건강_카드는_산다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")])
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/missing-cost")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.missingCostCount == 0)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.hasSamples)
    }

    @Test func 미등록_건수를_받는다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")], missing: 3)
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.missingCostCount == 3)
    }

    /// 탭을 오갈 때마다 전 기간 집계를 다시 부르지 않는다. 배지 수만 매번 맞춘다 —
    /// 큐에서 금액을 채우고 돌아오면 그 수가 달라져 있어야 한다.
    @Test func 다시_열어도_집계는_한_번만_부른다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")], missing: 3)
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.load()

        #expect(mock.getCalls.filter { $0.path == "/tesla/battery-health" }.count == 1)
        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/missing-cost" }.count == 2)
    }

    /// 당겨서 새로고침은 캐시를 무시한다.
    @Test func 새로고침은_다시_부른다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.reload()

        #expect(mock.getCalls.filter { $0.path == "/tesla/battery-health" }.count == 2)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: 컴파일 실패 — `cannot find 'VehicleHealthViewModel' in scope`

- [ ] **Step 3: `VehicleHealthViewModel.swift`를 만든다**

```swift
import Foundation
import Observation

/// 건강 탭의 배터리 쪽 — `/tesla/battery-health` 하나만 본다.
///
/// **`/tesla/status`와 합치지 않는다.** 한 뷰모델로 묶으면 둘 중 하나가 실패할 때 화면 전체가
/// 오류가 되는데, 이 화면은 「하나가 실패해도 다른 카드는 그린다」가 규칙이다.
@MainActor
@Observable
final class VehicleHealthViewModel {
    /// 이보다 오래된 표본은 서버가 주더라도 그리지 않는다. 5년 치를 다 그리면
    /// 최근 1년의 움직임이 선 굵기에 묻힌다.
    static let trendMonths = 24

    private(set) var samples: [BatteryHealthSample] = []
    private(set) var isLoading = false
    /// 응답을 **받은 적이 있는지.** 「받은 적 없다」와 「받았는데 표본이 비었다」는 다르다.
    private(set) var isLoaded = false
    var errorMessage: String?

    /// 금액 미등록 배지. 요약 탭이 쓰는 것과 같은 값을 각자 받는다 —
    /// 이 앱에서 사람이 실제로 손을 쓰는 일은 금액을 채우는 것 하나뿐이라,
    /// 첫 화면이 바뀌어도 그 일이 한 번의 탭 안에 있어야 한다.
    private(set) var missingCostCount = 0

    private let service: VehicleService
    /// 겹친 요청 중 최신 것만 결과를 반영한다.
    private var generation = 0

    init(service: VehicleService = VehicleService()) {
        self.service = service
    }

    // MARK: - 파생 값

    var hasSamples: Bool { !samples.isEmpty }

    /// 가장 최근 표본. 서버가 **오래된 것부터** 주므로 마지막이다.
    var latest: BatteryHealthSample? { samples.last }

    /// 최근 용량 표본. 주행거리 표본보다 드물어 **최근 달과 다른 달일 수 있다** —
    /// 최근 달에 없다고 「용량을 모른다」로 그리면 있는 값을 버리게 된다.
    var latestCapacityKwh: Decimal? { samples.last(where: { $0.capacityKwh != nil })?.capacityKwh }

    /// 그릴 구간만 자른다. **달 번호로 자른다** — 배열 끝에서 24개를 세면 표본이 빠진 달만큼
    /// 더 오래된 곳까지 거슬러 올라간다.
    var trendSamples: [BatteryHealthSample] {
        guard let last = samples.last else { return [] }
        let oldest = last.monthOrdinal - (Self.trendMonths - 1)
        return samples.filter { $0.monthOrdinal >= oldest }
    }

    /// **빠진 달에서 갈린 선분들.** 없는 값을 직선으로 메우면 그 달에도 잰 것처럼 보인다.
    var trendSegments: [[BatteryHealthSample]] {
        var segments: [[BatteryHealthSample]] = []
        for sample in trendSamples {
            if let previous = segments.last?.last, sample.monthOrdinal == previous.monthOrdinal + 1 {
                segments[segments.count - 1].append(sample)
            } else {
                segments.append([sample])
            }
        }
        return segments
    }

    var remainingPercent: Decimal? {
        VehicleMath.remainingPercent(current: latest?.fullRangeKm, baseline: VehicleBaseline.newRangeKm)
    }

    var degradationPercent: Decimal? {
        VehicleMath.degradationPercent(remainingPercent: remainingPercent)
    }

    var rangeLostKm: Decimal? { VehicleMath.rangeLostKm(current: latest?.fullRangeKm) }

    // MARK: - 로드

    /// 탭에 들어올 때마다 부른다. **전 기간 집계는 한 번만 받고**, 배지 수만 매번 맞춘다 —
    /// 큐에서 금액을 채우고 돌아오면 그 수가 달라져 있어야 한다.
    func load() async {
        if !isLoaded { await reload() }
        await refreshMissingCount()
    }

    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let loaded = try await service.fetchBatteryHealth()
            guard current == generation else { return }
            samples = loaded.samples
            isLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            errorMessage = "배터리 건강을 불러오지 못했습니다."
        }
    }

    /// 배지 하나 때문에 화면을 죽이지 않는다 — 실패하면 조용히 둔다. 요약 탭과 같은 규칙이다.
    func refreshMissingCount() async {
        do {
            missingCostCount = try await service.fetchMissingCost(limit: 1).totalCount
        } catch {
            return
        }
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
touch WooriHaru/ViewModels/VehicleHealthViewModel.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
```
Expected: PASS (`VehicleHealthViewModelTests` 11건 포함)

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/VehicleHealthViewModel.swift \
        WooriHaruTests/VehicleHealthTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 배터리 건강 뷰모델을 더한다

상태 뷰모델과 합치지 않는다 — 하나가 실패해도 다른 카드는 그려야 한다.
표본이 빠진 달에서 추이 선을 끊고, 24개월만 그린다."
```

---

### Task 4: 배터리 건강 카드 — 화면에서 유일한 진한 패널

**Files:**
- Create: `WooriHaru/Views/Vehicle/BatteryHealthCard.swift`
- Modify: `WooriHaru/Extensions/Color+Extensions.swift`

**Interfaces:**
- Consumes: `VehicleBaseline`·`VehicleFormat.percent`·`VehicleFormat.againstBaseline` (Task 1)
- Produces:
  - `struct BatteryHealthCard: View` — `init(remainingPercent: Decimal?, degradationPercent: Decimal?, fullRangeKm: Decimal?, capacityKwh: Decimal?, rangeLostKm: Decimal?)`
  - `struct BatteryHealthPlaceholderCard: View` — `init(icon: String, title: String, message: String, retry: (() -> Void)? = nil)`
  - `Color.navy800`, `Color.navy900`

이 태스크에는 단위 테스트가 없다. 그리기만 하는 뷰라 검증할 계산이 없고, 계산은 Task 1·3에서 이미 테스트했다. **확인은 프리뷰와 Task 7의 실기 확인이다.**

- [ ] **Step 1: 색 토큰을 더한다**

`WooriHaru/Extensions/Color+Extensions.swift`의 slate 묶음 아래에 넣는다:

```swift
    // MARK: - Navy (배터리 건강 패널 전용)
    /// 요약 탭 히어로(초록→파랑)와 **다른 색을 쓴다** — 같은 색을 두 화면 첫 카드에 두면
    /// 지금 어느 화면인지 헷갈린다.
    static let navy800 = Color(red: 0.118, green: 0.161, blue: 0.286)
    static let navy900 = Color(red: 0.055, green: 0.075, blue: 0.161)
```

- [ ] **Step 2: `BatteryHealthCard.swift`를 만든다**

```swift
import SwiftUI

/// 배터리 건강 — **화면에서 유일한 진한 패널이다.**
///
/// 앱 전체를 다크로 뒤집지 않는다. 지금 유리 토큰은 밝은 배경을 전제로 만들어졌고,
/// 우리하루의 다른 미니앱과 결도 어긋난다. 대신 화면에서 가장 중요한 값 하나만 어둡게 깔아
/// 눈이 먼저 가게 한다.
///
/// **경고 문구를 넣지 않는다** — 열화는 고장이 아니다. 잔존율이 낮아지면 링 색만 바뀐다.
struct BatteryHealthCard: View {
    let remainingPercent: Decimal?
    let degradationPercent: Decimal?
    let fullRangeKm: Decimal?
    let capacityKwh: Decimal?
    let rangeLostKm: Decimal?

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 96

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text("배터리 건강")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 10)
                row("주행가능", VehicleFormat.againstBaseline(
                    fullRangeKm, baseline: VehicleBaseline.newRangeKm, unit: "km", fraction: 0))
                row("용량", VehicleFormat.againstBaseline(
                    capacityKwh, baseline: VehicleBaseline.newCapacityKwh, unit: "kWh", fraction: 1))
                row("줄어든 거리", VehicleFormat.distance(rangeLostKm))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.navy800, Color.navy900],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: Color.navy900.opacity(0.35), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("배터리 건강 잔존 \(VehicleFormat.percent(remainingPercent)), 열화 \(VehicleFormat.percent(degradationPercent))")
    }

    // MARK: - 링

    /// 잔존율 링. Swift Charts를 들이지 않는 저장소 관례대로 `Circle().trim`으로 그린다.
    ///
    /// **100%를 넘는 달은 링이 한 바퀴에서 멈추지만 숫자는 그대로 낸다** — 원은 한 바퀴가
    /// 끝이라 넘는 만큼을 그릴 자리가 없다. 숫자까지 자르면 냉간·재보정으로 튄 값이 사라진다.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, ratio))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(VehicleFormat.percent(remainingPercent))
                    .font(.title2)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("열화 \(VehicleFormat.percent(degradationPercent))")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
        }
        .frame(width: ringSize, height: ringSize)
        .animation(.snappy, value: ratio)
    }

    private var ratio: CGFloat {
        guard let remainingPercent else { return 0 }
        return CGFloat(truncating: (remainingPercent / 100) as NSDecimalNumber)
    }

    /// 90% 이상 초록, 80~90% 노랑, 80% 미만 주황. **문구는 붙이지 않는다.**
    private var ringColor: Color {
        guard let remainingPercent else { return Color.slate500 }
        if remainingPercent >= 90 { return .green300 }
        if remainingPercent >= 80 { return .orange300 }
        return .orange500
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
    }
}

/// 표본이 없거나 못 받았을 때 **같은 자리·같은 색**으로 서는 패널.
/// 자리를 비우지 않는다 — 첫 화면의 주인공이 사라지면 화면이 무너져 보인다.
struct BatteryHealthPlaceholderCard: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button("다시 시도", action: retry)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.navy800, Color.navy900],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: Color.navy900.opacity(0.35), radius: 14, y: 8)
    }
}

#Preview("건강") {
    VStack(spacing: 12) {
        BatteryHealthCard(remainingPercent: Decimal(string: "92.4"), degradationPercent: 8,
                          fullRangeKm: Decimal(string: "525.3"), capacityKwh: Decimal(string: "71.6"),
                          rangeLostKm: 43)
        BatteryHealthCard(remainingPercent: Decimal(string: "78.1"), degradationPercent: 22,
                          fullRangeKm: 444, capacityKwh: nil, rangeLostKm: 124)
        BatteryHealthPlaceholderCard(icon: "bolt.badge.clock",
                                     title: "아직 잴 만한 충전이 없어요",
                                     message: "80% 이상 충전하면 값이 쌓여요")
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 3: 빌드가 통과하는지 확인한다**

```bash
touch WooriHaru/Views/Vehicle/BatteryHealthCard.swift WooriHaru/Extensions/Color+Extensions.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: PASS

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Vehicle/BatteryHealthCard.swift WooriHaru/Extensions/Color+Extensions.swift \
        WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 배터리 건강 카드를 그린다

화면에서 유일한 진한 패널이다. 앱 전체를 다크로 뒤집는 대신 가장 중요한 값
하나만 어둡게 깔아 눈이 먼저 가게 한다. 요약 히어로와 색을 갈라 둔다."
```

---

### Task 5: 열화 추이 차트

**Files:**
- Create: `WooriHaru/Views/Vehicle/DegradationTrendChart.swift`

**Interfaces:**
- Consumes: `BatteryHealthSample`·`VehicleBaseline`·`VehicleMath.remainingPercent`·`VehicleFormat` (Task 1), `GlassCard` (기존)
- Produces: `struct DegradationTrendChart: View` — `init(segments: [[BatteryHealthSample]], selectedKey: String?, onSelect: @escaping (String) -> Void)`

선분 나누기는 Task 3의 `trendSegments`에서 이미 테스트했다. 이 태스크는 좌표 계산과 그리기만 한다.

- [ ] **Step 1: `DegradationTrendChart.swift`를 만든다**

```swift
import SwiftUI

/// 열화 추이 — 월별 만충 환산 주행거리. 손으로 그린 선이다(Swift Charts를 들이지 않는 관례).
///
/// **y축을 0에서 시작하지 않는다.** 0부터 그리면 몇 %의 변화가 선 굵기에 묻힌다. 대신
/// 신차 기준선 568km를 점선으로 함께 그려, 무엇과 견주는 값인지 화면 안에 남긴다.
///
/// **점 탭은 콜아웃만 바꾼다.** 점 하나는 손가락보다 작아 개별 히트 영역을 두지 않고,
/// 차트 전체가 탭을 받아 x가 가장 가까운 달을 고른다.
struct DegradationTrendChart: View {
    /// **빠진 달에서 갈린 선분들.** 한 배열 안은 연속한 달이다.
    let segments: [[BatteryHealthSample]]
    let selectedKey: String?
    let onSelect: (String) -> Void

    private static let chartHeight: CGFloat = 120

    private var samples: [BatteryHealthSample] { segments.flatMap { $0 } }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("열화 추이")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                callout

                GeometryReader { proxy in
                    plot(in: proxy.size)
                }
                .frame(height: Self.chartHeight)

                footer
            }
        }
    }

    // MARK: - 콜아웃

    private var selected: BatteryHealthSample? {
        samples.first { $0.yearMonth == selectedKey } ?? samples.last
    }

    @ViewBuilder private var callout: some View {
        if let selected {
            let remaining = VehicleMath.remainingPercent(
                current: selected.fullRangeKm, baseline: VehicleBaseline.newRangeKm)
            HStack(spacing: 6) {
                Text(selected.shortLabel)
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(Color.blue600)
                Text(VehicleFormat.distance(selected.fullRangeKm))
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text("잔존 \(VehicleFormat.percent(remaining))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.slate500)
                // 표본 수는 그 달 값이 얼마나 단단한지다 — 한 건짜리 달은 튈 수 있다.
                Text("표본 \(selected.sampleCount)건")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.slate400)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .animation(.snappy, value: selected.yearMonth)
        }
    }

    // MARK: - 그리기

    private func plot(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // 신차 기준선. 점선이라 표본 선과 헷갈리지 않는다.
            Path { path in
                let y = baselineY(in: size)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(Color.slate300, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Path { path in
                    for (index, sample) in segment.enumerated() {
                        let point = position(sample, in: size)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Color.blue500, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(samples) { sample in
                let isSelected = sample.yearMonth == selected?.yearMonth
                Circle()
                    .fill(isSelected ? Color.blue600 : Color.blue300)
                    .frame(width: isSelected ? 9 : 5, height: isSelected ? 9 : 5)
                    .position(position(sample, in: size))
            }
        }
        .contentShape(.rect)
        .onTapGesture { location in
            guard let nearest = nearest(to: location, in: size) else { return }
            onSelect(nearest.yearMonth)
        }
    }

    /// y축 범위 — 표본과 신차 기준선을 모두 담고 위아래로 조금 띄운다.
    /// **0에서 시작하지 않으므로 기준선이 범위 안에 반드시 들어가야 한다** —
    /// 빠지면 점선이 차트 밖으로 나가 비교 대상이 화면에서 사라진다.
    private var domain: (low: Decimal, high: Decimal) {
        let values = samples.map(\.fullRangeKm) + [VehicleBaseline.newRangeKm]
        let low = values.min() ?? 0
        let high = values.max() ?? VehicleBaseline.newRangeKm
        let padding = max(5, (high - low) / 10)
        return (low - padding, high + padding)
    }

    /// x는 **달 번호에 비례한다.** 배열 순서로 놓으면 표본이 빠진 구간이 좁아져,
    /// 선을 끊어 둔 뜻이 사라진다.
    private func position(_ sample: BatteryHealthSample, in size: CGSize) -> CGPoint {
        let ordinals = samples.map(\.monthOrdinal)
        let first = ordinals.min() ?? 0
        let span = (ordinals.max() ?? first) - first
        // 표본이 한 달치뿐이면 왼쪽 끝에 붙는 대신 가운데에 찍는다.
        let x = span == 0 ? size.width / 2
                          : size.width * CGFloat(sample.monthOrdinal - first) / CGFloat(span)
        return CGPoint(x: x, y: y(for: sample.fullRangeKm, in: size))
    }

    private func baselineY(in size: CGSize) -> CGFloat {
        y(for: VehicleBaseline.newRangeKm, in: size)
    }

    private func y(for value: Decimal, in size: CGSize) -> CGFloat {
        let (low, high) = domain
        let span = max(1, high - low)
        let ratio = CGFloat(truncating: ((value - low) / span) as NSDecimalNumber)
        return size.height * (1 - ratio)
    }

    private func nearest(to location: CGPoint, in size: CGSize) -> BatteryHealthSample? {
        samples.min {
            abs(position($0, in: size).x - location.x) < abs(position($1, in: size).x - location.x)
        }
    }

    // MARK: - 아래 줄

    private var footer: some View {
        HStack(spacing: 8) {
            Text("┈ 신차 \(VehicleFormat.distance(VehicleBaseline.newRangeKm))")
                .foregroundStyle(Color.slate400)
            Spacer(minLength: 0)
            if samples.count > 1, let first = samples.first, let last = samples.last {
                Text("\(first.shortLabel) → \(last.shortLabel)")
                    .foregroundStyle(Color.slate400)
            } else {
                // 점 하나로는 추이가 아니다. 그 사실을 화면이 말해 준다.
                Text("값이 쌓이면 추이가 보여요")
                    .foregroundStyle(Color.slate500)
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
    }
}

#Preview("추이") {
    let ranges = ["556.0", "552.4", "548.1", "544.0", "541.2", "536.8",
                  "534.0", "530.5", "528.0", "527.1", "525.3"]
    let all = ranges.enumerated().map { index, value in
        BatteryHealthSample(yearMonth: String(format: "2025-%02d", index + 1),
                            fullRangeKm: Decimal(string: value)!, capacityKwh: nil,
                            sampleCount: index % 3 + 1, capacitySampleCount: 0)
    }
    return VStack(spacing: 12) {
        // 연속한 달
        DegradationTrendChart(segments: [all], selectedKey: nil) { _ in }
        // 가운데가 빠져 선이 갈린 경우
        DegradationTrendChart(segments: [Array(all.prefix(4)), Array(all.suffix(5))],
                              selectedKey: nil) { _ in }
        // 표본이 한 달치뿐
        DegradationTrendChart(segments: [[all[10]]], selectedKey: nil) { _ in }
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 2: 빌드가 통과하는지 확인한다**

```bash
touch WooriHaru/Views/Vehicle/DegradationTrendChart.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: PASS

- [ ] **Step 3: 프리뷰를 눈으로 확인한다**

Xcode에서 `DegradationTrendChart.swift`의 캔버스를 연다. 확인할 것:
- 신차 568km 점선이 표본 선 **위쪽**에 보인다(차트 밖으로 나가지 않았다).
- 가운데가 빠진 두 번째 차트에서 **선이 끊겨 있고**, 빈 구간이 가로로 넓다.
- 세 번째 차트는 점 하나가 **가운데**에 있고 아래 줄이 「값이 쌓이면 추이가 보여요」다.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Vehicle/DegradationTrendChart.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 열화 추이 차트를 그린다

y축을 0에서 시작하지 않는다 — 0부터 그리면 몇 %의 변화가 선 굵기에 묻힌다.
대신 신차 기준선을 점선으로 함께 그리고, 표본이 빠진 달에서는 선을 끊는다."
```

---

### Task 6: 타이어 공기압 카드

**Files:**
- Create: `WooriHaru/Views/Vehicle/TirePressureCard.swift`

**Interfaces:**
- Consumes: `VehicleStatus.TpmsBar` (기존), `TireStatus`·`VehicleMath.tireStatus(bar:)`·`VehicleMath.averagePsi(_:)`·`VehicleFormat.pressurePsi`·`VehicleFormat.psiText` (Task 1), `GlassCard` (기존)
- Produces: `struct TirePressureCard: View` — `init(tpms: VehicleStatus.TpmsBar?)`

- [ ] **Step 1: `TirePressureCard.swift`를 만든다**

```swift
import SwiftUI

/// 타이어 공기압 — 숫자 넷을 늘어놓는 대신 **차 도형 위 네 모서리**에 얹고,
/// 권장값에서 벗어난 바퀴만 색을 바꾼다. 값이 정상인지 사람이 판단하지 않게 하려는 것이다.
///
/// **psi만 낸다.** 서버는 TeslaMate 저장 단위인 bar로 주지만, 타이어에 넣을 때 쓰는 단위도
/// 차 문틀의 권장값도 psi다 — 두 단위를 함께 두면 읽을 때마다 어느 쪽인지 골라야 한다.
struct TirePressureCard: View {
    let tpms: VehicleStatus.TpmsBar?

    private struct Wheel {
        let name: String
        let bar: Decimal?
        var status: TireStatus { VehicleMath.tireStatus(bar: bar) }
    }

    private var wheels: [Wheel] {
        [Wheel(name: "앞 왼쪽", bar: tpms?.fl), Wheel(name: "앞 오른쪽", bar: tpms?.fr),
         Wheel(name: "뒤 왼쪽", bar: tpms?.rl), Wheel(name: "뒤 오른쪽", bar: tpms?.rr)]
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("타이어 공기압")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    Text("\(VehicleFormat.psiText(VehicleMath.averagePsi(tpms))) 평균")
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(Color.slate500)
                }

                diagram
                verdict
            }
        }
    }

    /// 차 도형을 가운데 두고 좌우에 바퀴를 놓는다 — 위에서 내려다본 배치라
    /// 화면의 왼쪽 위가 실제 앞 왼쪽 바퀴다.
    private var diagram: some View {
        HStack(spacing: 10) {
            VStack(spacing: 10) { wheel(wheels[0]); wheel(wheels[2]) }
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.slate100)
                .frame(width: 40)
                .overlay {
                    Image(systemName: "car.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.slate300)
                }
            VStack(spacing: 10) { wheel(wheels[1]); wheel(wheels[3]) }
        }
        .frame(height: 108)
    }

    private func wheel(_ wheel: Wheel) -> some View {
        VStack(spacing: 1) {
            Text(VehicleFormat.pressurePsi(wheel.bar))
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(wheel.status.foreground)
            Text(wheel.name)
                .font(.system(size: 9))
                .foregroundStyle(Color.slate400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(wheel.status.background, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(wheel.name) \(VehicleFormat.pressurePsi(wheel.bar)) \(wheel.status.spokenSuffix)")
    }

    /// 네 바퀴가 모두 정상이면 한 줄로 끝내고, 아니면 벗어난 바퀴 이름을 적는다.
    /// **값이 없는 바퀴는 경고가 아니라 「못 받았다」다.**
    @ViewBuilder private var verdict: some View {
        let abnormal = wheels.filter { $0.status.isAbnormal }
        let unknown = wheels.filter { $0.status == .unknown }
        if !abnormal.isEmpty {
            line("exclamationmark.triangle.fill",
                 "\(abnormal.map(\.name).joined(separator: "·")) 공기압을 확인해 주세요",
                 Color.orange700)
        } else if unknown.count == wheels.count {
            line("questionmark.circle", "아직 공기압 값을 받지 못했어요", Color.slate400)
        } else if !unknown.isEmpty {
            line("questionmark.circle",
                 "\(unknown.map(\.name).joined(separator: "·")) 값이 없어요",
                 Color.slate400)
        } else {
            line("checkmark.circle.fill", "네 바퀴 모두 정상", Color.green600)
        }
    }

    private func line(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(color)
    }
}

private extension TireStatus {
    var foreground: Color {
        switch self {
        case .normal: return .slate900
        case .low, .high: return .orange700
        case .unknown: return .slate400
        }
    }

    var background: Color {
        switch self {
        case .normal: return .slate100
        case .low, .high: return .orange100
        case .unknown: return .slate50
        }
    }

    var spokenSuffix: String {
        switch self {
        case .normal: return "정상"
        case .low: return "권장보다 낮음"
        case .high: return "권장보다 높음"
        case .unknown: return "값 없음"
        }
    }
}

#Preview("공기압") {
    VStack(spacing: 12) {
        TirePressureCard(tpms: VehicleStatus.TpmsBar(
            fl: Decimal(string: "2.90"), fr: Decimal(string: "2.83"),
            rl: Decimal(string: "2.97"), rr: Decimal(string: "2.90")))
        TirePressureCard(tpms: VehicleStatus.TpmsBar(
            fl: Decimal(string: "2.90"), fr: Decimal(string: "2.45"),
            rl: Decimal(string: "2.97"), rr: nil))
        TirePressureCard(tpms: nil)
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 2: 빌드가 통과하는지 확인한다**

```bash
touch WooriHaru/Views/Vehicle/TirePressureCard.swift
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: PASS

- [ ] **Step 3: 프리뷰를 눈으로 확인한다**

- 첫 카드: 네 바퀴 모두 `slate100` 배경, 아래 줄이 초록 「네 바퀴 모두 정상」.
- 둘째 카드: `앞 오른쪽`만 주황 배경(2.45bar ≈ 36psi), `뒤 오른쪽`은 「—」에 회색(경고가 아니다), 아래 줄은 주황 경고.
- 셋째 카드: 네 칸 모두 「—」, 아래 줄이 「아직 공기압 값을 받지 못했어요」.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Vehicle/TirePressureCard.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 타이어 공기압을 차 도형 위 판정으로 바꾼다

숫자 넷을 늘어놓으면 정상인지 사람이 판단해야 한다. 권장 42psi·정상 38~46psi를
상수로 두고 벗어난 바퀴만 색을 바꾼다. 값이 없는 바퀴는 경고가 아니다."
```

---

### Task 7: 건강 탭 조립과 탭 순서 변경

**Files:**
- Rename + Modify: `WooriHaru/Views/Vehicle/VehicleStatusTab.swift` → `WooriHaru/Views/Vehicle/VehicleHealthTab.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleView.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (파일명 sed)

**Interfaces:**
- Consumes: `VehicleHealthViewModel` (Task 3), `VehicleStatusViewModel` (기존), `BatteryHealthCard`·`BatteryHealthPlaceholderCard` (Task 4), `DegradationTrendChart` (Task 5), `TirePressureCard` (Task 6)
- Produces: `struct VehicleHealthTab: View` — `init(healthViewModel: VehicleHealthViewModel, statusViewModel: VehicleStatusViewModel, onOpenQueue: @escaping () -> Void)`

**설계에서 한 곳 벗어난다(의도한 것이다).** 스펙의 건강 화면 스케치는 실내·외기 온도 타일 둘만 두고, 지금 상태 탭에 있는 **에어컨·위치**를 그림에서 뺐다. 그 둘을 화면에서 지우자는 논의는 문서 어디에도 없어, **온도 타일을 큰 글씨로 올리되 에어컨·위치는 같은 카드 아래에 작은 두 줄로 남긴다.** 스케치가 노린 시각적 강조는 지키면서 이미 있던 값을 조용히 잃지 않는다.

- [ ] **Step 1: 파일을 옮기고 프로젝트 참조를 고친다**

```bash
git mv WooriHaru/Views/Vehicle/VehicleStatusTab.swift WooriHaru/Views/Vehicle/VehicleHealthTab.swift
sed -i '' 's/VehicleStatusTab\.swift/VehicleHealthTab.swift/g' WooriHaru.xcodeproj/project.pbxproj
grep -c "VehicleHealthTab.swift" WooriHaru.xcodeproj/project.pbxproj
```
Expected: `4` (build file, file reference, group, sources phase — 네 군데)

- [ ] **Step 2: `VehicleHealthTab.swift`를 새로 쓴다**

파일 전체를 아래로 바꾼다:

```swift
import SwiftUI

/// 건강 탭 — 미니앱을 열면 **여기가 먼저 뜬다.**
///
/// 뷰모델을 둘 받는다. 배터리 건강(`/tesla/battery-health`)과 현재 상태(`/tesla/status`)는
/// 서로 다른 호출이고, **하나가 실패해도 다른 카드는 그린다.**
struct VehicleHealthTab: View {
    @Bindable var healthViewModel: VehicleHealthViewModel
    @Bindable var statusViewModel: VehicleStatusViewModel
    /// 금액 미등록 큐를 여는 진입점. **입력 경로를 바꾸는 것이 아니라 하나 더 다는 것이다.**
    let onOpenQueue: () -> Void

    @State private var selectedTrendKey: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                asOfLine.padding(.top, 8)

                // 이 앱에서 사람이 실제로 손을 쓰는 일은 금액을 채우는 것 하나뿐이다.
                // 첫 화면이 바뀌어도 그 일이 한 번의 탭 안에 있어야 한다.
                if healthViewModel.missingCostCount > 0 {
                    missingCostBadge
                }

                healthSection

                statusSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable {
            await healthViewModel.reload()
            await healthViewModel.refreshMissingCount()
            await statusViewModel.reload()
        }
    }

    // MARK: - 기준 시각

    /// **1분마다 다시 그린다.** 경과 시간은 화면을 열어 둔 채로도 흐르는데, 뷰모델의 값만 읽으면
    /// 29분에 연 값이 30분을 넘겨도 「29분 전」에 멈춘 채 강조도 켜지지 않는다.
    private var asOfLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let minutes = statusViewModel.minutesAgo(at: context.date)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(minutes.map { "\(VehicleFormat.relative(minutes: $0)) 기준" } ?? "기준 시각 없음")
                    .fontWeight(.bold)
                if let state = statusViewModel.status?.state {
                    Text("· \(VehicleFormat.stateLabel(state))")
                }
                Spacer()
            }
            .font(.caption)
            // 오래된 값도 값이다. 가리지 않고 시각만 눈에 띄게 한다.
            .foregroundStyle(statusViewModel.isStale(at: context.date) ? Color.orange700 : Color.slate500)
        }
    }

    private var missingCostBadge: some View {
        Button(action: onOpenQueue) {
            HStack(spacing: 8) {
                Image(systemName: "wonsign.circle")
                Text("금액 미등록 \(healthViewModel.missingCostCount)건")
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

    // MARK: - 배터리 건강

    /// **네 갈래다** — 못 받음 / 아직 안 받음 / 표본 없음 / 값 있음.
    /// 「기록 없음」과 「못 받음」을 한 화면으로 뭉개지 않는 지금 관례를 따른다.
    @ViewBuilder private var healthSection: some View {
        if let error = healthViewModel.errorMessage {
            BatteryHealthPlaceholderCard(
                icon: "exclamationmark.triangle",
                title: "배터리 건강을 불러오지 못했어요",
                message: error,
                retry: { Task { await healthViewModel.reload() } }
            )
        } else if !healthViewModel.isLoaded {
            BatteryHealthPlaceholderCard(
                icon: "bolt.badge.clock",
                title: "불러오는 중",
                message: "충전 기록에서 값을 뽑고 있어요"
            )
        } else if !healthViewModel.hasSamples {
            BatteryHealthPlaceholderCard(
                icon: "bolt.badge.clock",
                title: "아직 잴 만한 충전이 없어요",
                message: "80% 이상 충전하면 값이 쌓여요"
            )
        } else {
            BatteryHealthCard(
                remainingPercent: healthViewModel.remainingPercent,
                degradationPercent: healthViewModel.degradationPercent,
                fullRangeKm: healthViewModel.latest?.fullRangeKm,
                capacityKwh: healthViewModel.latestCapacityKwh,
                rangeLostKm: healthViewModel.rangeLostKm
            )
            DegradationTrendChart(
                segments: healthViewModel.trendSegments,
                selectedKey: selectedTrendKey,
                onSelect: { selectedTrendKey = $0 }
            )
        }
    }

    // MARK: - 현재 상태

    @ViewBuilder private var statusSection: some View {
        // 보여줄 값이 남아 있는 새로고침 실패는 한 줄로만 알린다.
        if let error = statusViewModel.errorMessage, statusViewModel.status != nil {
            Text(error)
                .font(.caption)
                .foregroundStyle(Color.red500)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if statusViewModel.isLoading && statusViewModel.status == nil {
            ProgressView().padding(.top, 40)
        } else if let error = statusViewModel.errorMessage, statusViewModel.status == nil {
            statusErrorState(error).padding(.top, 32)
        } else if let status = statusViewModel.status, statusViewModel.hasRecord {
            batteryCard(status)
            TirePressureCard(tpms: status.tpmsBar)
            cabinCard(status)
        } else if statusViewModel.status != nil {
            // 기록이 아직 없는 것과 못 받은 것은 다르다.
            ContentUnavailableView {
                Label("아직 기록이 없어요", systemImage: "car")
            } description: {
                Text("차가 한 번 깨어나면 값이 쌓여요")
            }
            .padding(.top, 32)
        }
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

    /// 온도 둘을 타일로 올린다. **에어컨·위치는 지우지 않고 아래 두 줄로 남긴다** —
    /// 설계 스케치가 노린 것은 온도를 크게 보이게 하는 것이지 나머지를 없애는 것이 아니다.
    private func cabinCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    tile(ChargeFormat.temperature(status.insideTempC), "실내 온도")
                    tile(ChargeFormat.temperature(status.outsideTempC), "외기 온도")
                }
                VStack(spacing: 0) {
                    row("에어컨", status.climateOn.map { $0 ? "켜짐" : "꺼짐" } ?? ChargeFormat.placeholder)
                    Divider().padding(.vertical, 8)
                    row("위치", status.locationName ?? ChargeFormat.placeholder)
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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

    private func statusErrorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("차량 상태를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await statusViewModel.reload() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 3: `VehicleView.swift`에서 탭 순서를 바꾼다**

네 곳을 고친다.

(1) 파일 맨 위 주석과 탭 정의·초기값·뷰모델:

```swift
/// 「차량」 미니앱 — 건강·요약 두 탭. 가계부와 같은 하단 글래스 탭바 구조다.
/// **여는 순간 건강 화면이 먼저 뜬다** — 첫 화면이 답을 하나 해야 한다.
struct VehicleView: View {
    private enum Tab { case health, summary }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .health
    @State private var summaryViewModel = VehicleSummaryViewModel()
    @State private var statusViewModel = VehicleStatusViewModel()
    @State private var healthViewModel = VehicleHealthViewModel()
    @State private var showingMonthPicker = false
    @State private var showingQueue = false
```

(2) `content`와 `principalTitle`:

```swift
    @ViewBuilder private var content: some View {
        switch tab {
        case .health:
            VehicleHealthTab(healthViewModel: healthViewModel,
                             statusViewModel: statusViewModel) { showingQueue = true }
                // 상태는 탭에 들어올 때마다 새로 받는다. 배터리 건강은 전 기간 집계라
                // 뷰모델이 한 번만 받고, 배지 수만 매번 맞춘다.
                .task {
                    async let status: Void = statusViewModel.load()
                    async let health: Void = healthViewModel.load()
                    _ = await (status, health)
                }
        case .summary:
            VehicleSummaryTab(viewModel: summaryViewModel) { showingQueue = true }
        }
    }

    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .health: Text("차량 건강").font(.subheadline).fontWeight(.bold)
        case .summary: monthSwitcher
        }
    }
```

(3) 큐를 닫은 뒤 갱신 — **건강 탭의 배지도 함께 맞춘다.** 요약 쪽만 갱신하면 두 화면의 수가 벌어진다:

```swift
        .fullScreenCover(isPresented: $showingQueue, onDismiss: {
            Task {
                await summaryViewModel.reload()
                await summaryViewModel.refreshMissingCount()
                await healthViewModel.refreshMissingCount()
            }
        }) {
            ChargeCostQueueView()
        }
```

(4) 탭바 — 건강이 왼쪽이다:

```swift
    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.health, icon: "bolt.batteryblock.fill", label: "건강")
            tabButton(.summary, icon: "chart.bar.fill", label: "요약")
        }
```

**손대지 않는 곳:** `monthSwipeGesture`의 `including: tab == .summary ? .all : .subviews`는 그대로 맞다(건강 탭에는 월이 없다). 컨테이너의 `.task { await summaryViewModel.load() }`도 그대로 둔다 — 요약 탭을 열기 전에 미리 받아 두는 것이라 첫 탭이 바뀌어도 뜻이 같다.

- [ ] **Step 4: 전체 테스트를 clean으로 돌린다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test 2>&1 | tail -50
```
Expected: PASS — `VehicleHealthMathTests`·`VehicleHealthViewModelTests`·`VehicleServiceTests`를 포함해 전부 통과. `VehicleStatusTab` 참조가 남아 컴파일이 깨지면 `grep -rn "VehicleStatusTab" WooriHaru/`로 찾아 고친다.

- [ ] **Step 5: 실기로 금액 입력 경로를 확인한다**

**이 계획에서 유일하게 코드로 확인할 수 없는 항목이다.** 시뮬레이터에서 앱을 띄우고 차량 미니앱을 연다:

1. 미니앱을 열면 **건강 화면이 먼저 뜬다**.
2. 위쪽에 「금액 미등록 N건」 배지가 보인다.
3. 배지를 누르면 **지금과 같은 큐 화면**(`ChargeCostQueueView`)이 열린다.
4. 금액을 하나 저장하고 큐를 닫는다.
5. 건강 화면 배지 수가 **N-1**로 줄어 있다.
6. 아래 탭바에서 「요약」으로 옮기면 그쪽 배지 수도 같은 **N-1**이다.
7. 요약 탭에서 좌우로 쓸면 달이 바뀌고, 건강 탭에서 쓸면 **아무 일도 없다**.

- [ ] **Step 6: 커밋**

```bash
git add -A WooriHaru/Views/Vehicle WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 차량 미니앱 첫 화면을 배터리 건강으로 바꾼다

상태 탭은 지금 이 순간의 값만 있어 열어 봐도 알게 되는 것이 없었다. 잔존율·열화
추이·공기압 판정을 앞에 두고 탭 순서를 건강·요약으로 바꾼다. 금액 입력이 멀어지지
않게 미등록 배지를 건강 화면 위쪽에도 둔다."
```

---

### Task 8: 설계 문서에 1단계 완료를 적는다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md`

문서가 다음 사람에게 「무엇이 돌고 있고 무엇이 남았는지」를 말해야 한다. 계획 실행 중에 알아낸 것도 문서에 남긴다.

- [ ] **Step 1: 단계 표와 1단계 절에 상태를 적는다**

「단계」 표의 1단계 행 끝에 `**(구현 완료, 2026-08-17)**`를 붙이고, `# 1단계 — 배터리 건강` 제목 바로 아래에 한 문단을 넣는다:

```markdown
> **구현 완료(2026-08-17).** 계획은 `docs/superpowers/plans/2026-08-17-vehicle-health-dashboard.md`다.
> 구현하며 이 문서와 갈라진 곳이 셋이다.
>
> - **`/tesla/battery-health` 응답은 `data` 래퍼 안에 온다.** 아래 「서버 API」 예시에는 래퍼가
>   빠져 있는데, 백엔드 컨트롤러는 `DataResponseBody`로 감싼다. 다른 차량 엔드포인트와 같다.
> - **`fullRangeKm`은 non-null이다.** 표본이 없는 달은 배열에서 빠지므로 옵셔널일 자리가 없다.
>   `capacityKwh`만 null이 온다.
> - **「만충 환산」·「용량 추정」·「중앙값」을 앱에 두지 않았다.** 아래 「계산」 절이 이 셋을
>   `VehicleMath`에 두라고 적었지만, 같은 문서의 「서버 API」 절이 「표본 규칙과 월별 중앙값은
>   서버가 끝낸다」고 확정했고 백엔드도 그렇다. 앱에 두면 아무도 부르지 않는 죽은 코드가 된다.
>   **앱이 실제로 하는 나눗셈은 「잔존율 = 최근 값 ÷ 기준선」 하나이며**, 그것과 열화·줄어든
>   거리·공기압 판정만 `VehicleMath`에 있다.
>
> 화면에서도 한 곳 벗어났다 — 건강 화면 스케치는 에어컨·위치를 그림에서 뺐지만, 그 둘을
> 지우자는 논의가 문서 어디에도 없어 **온도 타일 아래 작은 두 줄로 남겼다.**
```

- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/specs/2026-08-17-vehicle-health-dashboard-design.md
git commit -m "docs: 1단계 구현 완료와 문서에서 갈라진 곳을 적는다"
```

---

## 이 계획이 다루지 않는 것

- **2단계(주행 인사이트)·3단계(곁가지)·보류(`positions`).** 각 단계는 그 자체로 쓸 만한 화면이 하나씩 완성되므로 계획도 따로 쓴다. 백엔드는 `/tesla/drive-insights`까지 이미 구현돼 있다(확인, 2026-08-17) — 2단계 계획을 쓸 때 `TeslaVehicleDtos.kt`에서 계약을 그대로 옮겨 적으면 된다.
- **금액 입력 기능.** 큐 화면과 상세 「금액 수정」 코드는 한 줄도 손대지 않는다.
- **여러 대 차량.** 기준선이 앱 상수 한 곳(`VehicleBaseline`)에 있다. 차를 바꾸면 그 두 줄을 고친다.
