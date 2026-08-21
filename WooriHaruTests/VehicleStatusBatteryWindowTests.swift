import Foundation
import Testing
@testable import WooriHaru

// MARK: - 뷰모델(병렬·독립 로딩)

@MainActor
struct VehicleStatusViewModelBatteryWindowTests {
    private nonisolated static func status() -> VehicleStatus {
        VehicleStatus(
            asOf: "2026-08-18T13:00:00", state: "asleep", stateSince: nil,
            batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: 312, estRangeKm: nil,
            odometerKm: 41203, insideTempC: nil, outsideTempC: nil, climateOn: false,
            locationName: "집", tpmsBar: nil)
    }

    private nonisolated static func window() -> BatteryWindowResponse {
        BatteryWindowResponse(
            hours: 48, from: "2026-08-18T13:00:00", to: "2026-08-20T13:00:00",
            samples: [BatterySample(at: "2026-08-18T13:00:00", batteryLevel: 62, usableBatteryLevel: nil)],
            charges: [], parkDrain: ParkDrain(ratedKm: 4.2, hours: 96.4, samples: 6))
    }

    /// 둘 다 성공하면 둘 다 값이 채워진다 — 개요 로딩과 함께 병렬로 받는다.
    @Test func 상태와_배터리_추이를_함께_받는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.status == Self.status())
        #expect(viewModel.batteryWindow == Self.window())
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.batteryWindowErrorMessage == nil)
    }

    /// **하나가 실패해도 다른 카드는 그린다** — 상태가 실패해도 배터리 추이는 받은 값을 지닌다.
    @Test func 상태가_실패해도_배터리_추이는_남는다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/status")
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.status == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.batteryWindow == Self.window())
        #expect(viewModel.batteryWindowErrorMessage == nil)
    }

    /// 반대 방향도 같다 — 배터리 추이가 실패해도 상태는 받은 값을 지닌다.
    @Test func 배터리_추이가_실패해도_상태는_남는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/battery-window")
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.status == Self.status())
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.batteryWindow == nil)
        #expect(viewModel.batteryWindowErrorMessage != nil)
    }

    /// 「최근 48시간」은 창이 계속 움직인다 — 캐시하지 않고 매번 서버를 부른다.
    @Test func 다시_부르면_매번_서버를_부른다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()
        await viewModel.reload()

        #expect(mock.getCalls.filter { $0.path == "/tesla/battery-window" }.count == 2)
    }

    /// **회귀 테스트.** `isLoading`이 예전에는 상태·배터리 추이가 "둘 다" 끝나야 내려갔다 —
    /// `/tesla/status`가 먼저 실패하고 `/tesla/battery-window`가 오래 걸리면, `errorMessage`는
    /// 채워졌는데 `isLoading`만 참으로 남아 `VehicleOverviewTab`이 (로딩이 오류보다 먼저인
    /// 그 화면의 규칙 때문에) 이미 끝난 실패를 가리고 배터리 요청이 끝날 때까지 「불러오는 중」만
    /// 계속 보여줬다. `isLoading`은 상태 전용이어야 한다.
    ///
    /// 배터리 추이 쪽을 게이트로 영원히 막아 둔 채(이 테스트 안에서는 다시 열지 않는다) 상태
    /// 실패만 관찰한다 — 상태와 배터리 추이가 `async let`으로 진짜 동시에 도는 두 자식 작업이라
    /// 어느 쪽이 먼저 MainActor로 돌아올지는 언어 차원에서 보장되지 않는다. `waitUntilBlocked()`
    /// 하나만 걸면 "배터리가 막혔다"는 확인은 되지만 "상태의 MainActor 반영이 이미 끝났다"는
    /// 확인은 안 된다 — 그래서 배터리를 절대 풀리지 않게 막아 두고, 상태 실패를 막을 경합
    /// 상대가 없는 상태에서 `Task.yield()`로 그 반영이 실제로 도착할 때까지만 기다린다(둘 다
    /// 게이트로 잠깐 세워 확인 후 상태만 열어도 결과는 같다 — 여기서는 배터리를 아예 안 여는
    /// 쪽이 더 단순하다).
    @Test func 상태만_끝나도_배터리_추이가_남아있어도_로딩이_내려간다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/status")
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let windowGate = AsyncGate()
        mock.setGate(windowGate, for: "GET /tesla/battery-window")
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        let task = Task { await viewModel.reload() }

        // 배터리 추이 호출이 게이트 안에서 멈췄다 — 이 테스트가 끝날 때까지 다시 열지 않으므로
        // 이 호출은 스스로 끝날 길이 없다. 즉 이 시점 이후로 `isLoading`을 내릴 수 있는 것은
        // 상태 쪽뿐이다.
        await windowGate.waitUntilBlocked()

        // 상태 호출은 게이트가 없어 이미 끝났거나 곧 끝난다. 배터리가 영원히 막혀 있는 이상
        // 경합 상대가 없으므로, MainActor가 그 완료를 실제로 반영할 때까지 양보만 하면 된다
        // (sleep으로 시간을 흉내 내지 않는다 — 몇 번 양보하든 결국 반영되고, 그 반영을 막을
        // 다른 작업이 없다는 것이 이 테스트의 핵심 보장이다).
        for _ in 0..<1000 where viewModel.isLoading {
            await Task.yield()
        }

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.status == nil)
        // 배터리 추이는 여전히 진행 중이다 — 아직 값도 오류도 없어야 이 테스트가 재현하려던
        // 「배터리가 안 끝났는데 상태 실패가 로딩에 가려진다」는 상황이 실제로 성립한 것이다.
        #expect(viewModel.batteryWindow == nil)
        #expect(viewModel.batteryWindowErrorMessage == nil)

        // 뒷정리 — 막아 둔 호출을 풀어 작업을 끝낸다.
        await windowGate.open()
        await task.value
    }

    // MARK: - 낡음(값은 있는데 새로고침이 실패한 상태)

    /// 한 번 성공해 값을 얻은 뒤 다음 새로고침이 실패하면, 값은 그대로 남고
    /// `batteryWindowIsStale`이 참이 된다 — 카드가 낡은 값을 「최근 48시간」이라고
    /// 계속 우기지 않도록 뷰가 이 접근자로 물어볼 수 있어야 한다.
    @Test func 성공한_뒤_실패하면_값은_남고_낡음이_참이_된다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.batteryWindowIsStale == false)

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/battery-window")
        await viewModel.reload()

        #expect(viewModel.batteryWindow == Self.window())
        #expect(viewModel.batteryWindowIsStale == true)
    }

    /// 낡은 뒤 다시 성공하면 낡음이 다시 거짓으로 돌아간다 — 「낡음」이 한 번 참이 되면
    /// 영영 참으로 눌어붙지 않는다.
    @Test func 낡은_뒤_다시_성공하면_낡음이_거짓이_된다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/battery-window")
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        #expect(viewModel.batteryWindowIsStale == true)

        // 이전 실패를 지워야 한다 — `MockAPIClient.get`은 `errors`에 값이 남아 있으면
        // `getResults` 스텁을 무시하고 계속 던진다.
        mock.setError(nil, for: "GET /tesla/battery-window")
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        await viewModel.reload()

        #expect(viewModel.batteryWindow == Self.window())
        #expect(viewModel.batteryWindowIsStale == false)
    }

    /// 한 번도 받은 적이 없으면(값이 nil) 「낡음」 여부와 무관하게 `batteryWindow`는 nil로
    /// 남는다 — `VehicleOverviewTab.batteryWindowSection`이 `if let window = ...`로만
    /// 카드를 세우므로, 이 전제가 그대로여야 「기록 없음」과 「못 받음」을 뭉개지 않는
    /// 기존 동작(카드가 아예 안 뜬다)이 유지된다.
    @Test func 한번도_못_받으면_값이_nil로_남아_카드가_설_전제가_없다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/status", result: DataResponse(data: Self.status()))
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/battery-window")
        let viewModel = VehicleStatusViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.batteryWindow == nil)
        #expect(viewModel.batteryWindowErrorMessage != nil)
    }
}
