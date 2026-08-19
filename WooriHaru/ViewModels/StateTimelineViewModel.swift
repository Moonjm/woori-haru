import Foundation
import Observation

/// 최근 7일 상태 타임라인 — `/tesla/state-timeline` 하나만 본다.
///
/// **캐시하지 않는다.** 「최근 7일」은 창이 계속 움직이므로 탭에 들어올 때마다 새로 받아야 한다.
/// 전 기간 집계라 한 번만 받는 `ChargeTotalsViewModel`과 정확히 반대다.
@MainActor
@Observable
final class StateTimelineViewModel {
    /// 며칠을 그릴지는 화면이 정한다. 서버는 1~30을 받는다.
    static let days = 7

    /// **`bars`를 저장 속성으로 둔다.** 계산 속성으로 두면 스크롤 한 프레임마다 구간 168개를
    /// 다시 쪼갠다 — 2단계 히트맵이 같은 이유로 `heatMap`을 저장 속성으로 만들었다.
    private(set) var timeline: StateTimelineResponse? {
        didSet { bars = timeline.map(StateTimelineMath.bars) ?? [] }
    }
    private(set) var bars: [TimelineBar] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: VehicleService
    private var generation = 0

    init(service: VehicleService = VehicleService()) { self.service = service }

    /// 구간이 **하나도 없는 것**과 **못 받은 것**은 다르다. 화면이 그 둘을 갈라 그린다.
    var hasSegments: Bool { !bars.isEmpty }

    /// 탭에 들어올 때마다 부른다 — 가드가 없다.
    func load() async { await reload() }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다.**
    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let loaded = try await service.fetchStateTimeline(days: Self.days)
            guard current == generation else { return }
            timeline = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            errorMessage = "상태 타임라인을 불러오지 못했습니다."
        }
    }
}
