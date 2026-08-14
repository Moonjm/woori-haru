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
