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
    ///
    /// `525.4`·`485.64`는 568 기준선에서 각각 정확히 92.5%·85.5%가 되는 값이다 — `.5` 경계다.
    /// `VehicleFormat.percent`가 `NumberFormatter`의 기본 반올림(은행가 반올림, `.halfEven`)을
    /// 그대로 쓰면 92.5%가 "92%"로, `degradationPercent`는 `VehicleMath.rounded`(`.plain`)로
    /// 93을 만들어 "7%"를 내면서 92+7=99가 된다. `percent`도 같은 반올림을 쓰도록 고쳤는지
    /// 이 경계값들이 가른다.
    @Test func 잔존율과_열화를_더하면_늘_100이다() {
        for value in [Decimal(string: "525.3")!, 520, Decimal(string: "512.5")!, 559,
                      Decimal(string: "525.4")!, Decimal(string: "485.64")!] {
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

    /// **이 테스트가 실제로 고정하는 것:** 표기된 정수(`pressurePsi`)와 판정(`tireStatus`)이
    /// 같은 경계 규칙(`TirePressureSpec.normalRangePsi`)을 쓴다는 것 — 어느 쪽 정수가 나오든
    /// 둘이 어긋나지 않아야 한다는 관계만 본다.
    ///
    /// **`.5` 정확한 동점은 이 경로로 못 만든다.** psi = bar × 145038 / 10⁴이므로 정확히
    /// `.5`가 되려면 `bar ≡ 2500 (mod 5000)`이어야 하는데 그런 bar 값은 없다. `.plain`과
    /// `.halfEven`은 정확한 `.5` 동점에서만 갈리므로, 3.2061bar(원값 46.50063…psi)로는 고쳐진
    /// 구현과 깨진 구현이 똑같이 통과한다 — 즉 이 테스트는 그 결함을 가려내지 못한다. 실제
    /// 결함(반올림 없이 원값으로 판정)을 가르는 것은 `공기압을_범위로_판정한다`의 `2.62bar`
    /// 케이스다(원값 37.999956 → 반올림 안 하면 `.low`).
    @Test func 공기압_표기와_판정은_경계에서_같은_이야기를_한다() {
        let bar = Decimal(string: "3.2061")!
        let displayed = VehicleFormat.pressurePsi(bar)
        guard let displayedPsi = Int(displayed.dropLast(3)) else {
            Issue.record("psi 표기를 정수로 읽지 못했다: \(displayed)")
            return
        }
        let expected: TireStatus
        if Decimal(displayedPsi) < TirePressureSpec.normalRangePsi.lowerBound {
            expected = .low
        } else if Decimal(displayedPsi) > TirePressureSpec.normalRangePsi.upperBound {
            expected = .high
        } else {
            expected = .normal
        }
        #expect(VehicleMath.tireStatus(bar: bar) == expected)
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

    // MARK: - 색 구간

    @Test func 잔존율_색은_반올림한_값으로_판정한다() {
        // [89.5, 90)은 "90%"로 찍힌다 — 색도 90% 구간이어야 표기와 판정이 갈리지 않는다.
        #expect(HealthBand.of(Decimal(string: "89.5")) == .good)
        #expect(HealthBand.of(Decimal(string: "89.4")) == .fair)
        #expect(HealthBand.of(Decimal(string: "79.5")) == .fair)
        #expect(HealthBand.of(Decimal(string: "79.4")) == .low)
        #expect(HealthBand.of(90) == .good)
        #expect(HealthBand.of(nil) == nil)
    }

    @Test func 잔량_색은_정수_경계로_갈린다() {
        #expect(BatteryBand.of(50) == .high)
        #expect(BatteryBand.of(49) == .mid)
        #expect(BatteryBand.of(20) == .mid)
        #expect(BatteryBand.of(19) == .low)
        #expect(BatteryBand.of(nil) == nil)
    }
}
