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
    ///
    /// **정수 psi로 반올림한 뒤 비교한다.** bar→psi 변환 계수(14.5038)가 근사값이라
    /// 경계값(예: 38psi에 해당하는 2.62bar)을 그대로 곱하면 37.999956처럼 경계를 살짝
    /// 벗어난다 — 화면은 반올림한 정수만 보여주므로 판정도 그 값을 봐야 「38psi로 보이는데
    /// 왜 경고인가」가 생기지 않는다.
    static func tireStatus(bar: Decimal?) -> TireStatus {
        guard let raw = psi(fromBar: bar) else { return .unknown }
        let psi = rounded(raw)
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
