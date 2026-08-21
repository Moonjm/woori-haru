import Foundation
import Observation

/// 개요 탭 — 서버 DB에 쌓인 마지막 값을 그대로 본다. 자동 폴링도, 차를 깨우는 일도 없다.
@MainActor
@Observable
final class VehicleStatusViewModel {
    /// 이만큼 지난 값은 「지금」으로 읽히면 안 된다. 주차 중에는 몇 시간 전 값이 정상이다.
    static let staleMinutes = 30

    private(set) var status: VehicleStatus?
    private(set) var isLoading = false
    var errorMessage: String?

    /// 최근 48시간 배터리 추이(`/tesla/battery-window`). **`status`와 독립이다** — 하나가
    /// 실패해도 다른 카드는 그린다는 이 저장소의 규칙(`fetchBatteryHealth`가
    /// `/tesla/status`와 독립인 것과 같다)을 여기서는 같은 뷰모델 안의 두 프로퍼티로 지킨다.
    private(set) var batteryWindow: BatteryWindowResponse?
    var batteryWindowErrorMessage: String?

    private let service: VehicleService
    private let now: @Sendable () -> Date

    init(service: VehicleService = VehicleService(), now: @escaping @Sendable () -> Date = { .now }) {
        self.service = service
        self.now = now
    }

    /// 위치 기록 자체가 있는지 — 없는 것과 못 받은 것은 다르다.
    var hasRecord: Bool { status?.asOfDate != nil }

    /// **화면은 이쪽을 쓴다.** 계산 속성은 `now()`를 부르는데 그 호출은 관찰 대상이 아니라,
    /// 탭을 열어 둔 채 시간이 흘러도 뷰가 다시 그려지지 않는다 — 29분에 연 값이 30분을 넘겨도
    /// 「29분 전」에 멈춘다. 시각을 밖에서 받아 1분마다 다시 계산하게 한다.
    func minutesAgo(at date: Date) -> Int? {
        guard let asOf = status?.asOfDate else { return nil }
        return VehicleMath.minutesAgo(from: asOf, now: date)
    }

    func isStale(at date: Date) -> Bool { (minutesAgo(at: date) ?? 0) > Self.staleMinutes }

    var minutesAgo: Int? { minutesAgo(at: now()) }

    var isStale: Bool { isStale(at: now()) }

    private var generation = 0

    func load() async {
        await reload()
    }

    /// 상태와 배터리 추이를 **함께 병렬로** 받는다. `async let` 둘을 각각 자기 오류만
    /// 다루게 해서, 하나가 실패해도 다른 쪽 값은 그대로 반영된다 — 여기서 던지고 밖에서
    /// 한 번에 잡으면 먼저 실패한 쪽이 나중에 도착한 성공까지 함께 삼킨다.
    ///
    /// **`isLoading`은 상태(`reloadStatus`) 전용이다.** 배터리 추이는 원래부터 「실패하면
    /// 조용히 자리를 비운다」는 자기만의 표시 규칙이 있고 로딩 스피너를 갖지 않는다
    /// (`isBatteryWindowLoading`을 죽은 코드로 지운 적이 있다 — 되살리지 않는다). 예전에는
    /// `isLoading`을 둘 다 끝난 뒤에야 내렸는데, `/tesla/status`가 먼저 실패하고
    /// `/tesla/battery-window`가 오래 걸리면 `errorMessage`는 채워졌는데 `isLoading`만 참으로
    /// 남아 `VehicleOverviewTab`이 (로딩이 오류보다 먼저인 그 화면의 규칙 때문에) 이미 끝난
    /// 실패를 가리고 배터리 요청이 끝날 때까지 「불러오는 중」만 계속 보여줬다.
    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        async let statusOutcome: Void = reloadStatus(generation: current)
        async let windowOutcome: Void = reloadBatteryWindow(generation: current)
        _ = await (statusOutcome, windowOutcome)
    }

    private func reloadStatus(generation current: Int) async {
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

    private func reloadBatteryWindow(generation current: Int) async {
        do {
            let loaded = try await service.fetchBatteryWindow()
            guard current == generation else { return }
            batteryWindow = loaded
            batteryWindowErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            batteryWindowErrorMessage = "배터리 추이를 불러오지 못했습니다."
        }
    }
}
