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
