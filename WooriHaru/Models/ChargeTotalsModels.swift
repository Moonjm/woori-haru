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
        return "\(LedgerFormat.amount(VehicleMath.rounded(value), currency: "KRW"))/kWh"
    }
}
