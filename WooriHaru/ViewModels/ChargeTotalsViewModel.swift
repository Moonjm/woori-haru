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
