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

    /// `load()`를 한 번이라도 끝냈는지. 첫 로드가 끝나기 전에는 `items`가 비어 있어도
    /// 「다 채웠다」로 보이면 안 된다 — 그렇지 않으면 등록 화면이 열리자마자
    /// 「채울 게 없어요」를 한 번 깜빡이고 나서야 진짜 목록이 뜬다.
    private(set) var hasLoaded = false

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
    var isFinished: Bool { hasLoaded && !isLoading && current == nil }

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
            // 성공했을 때만 세운다 — 취소·실패까지 세우면 화면이 「채울 게 없어요」로
            // 잘못 그려진다(실패는 재시도가 있는 상태다).
            hasLoaded = true
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
