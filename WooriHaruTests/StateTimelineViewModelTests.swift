import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct StateTimelineViewModelTests {

    private nonisolated static func timeline(states: [StateSegment]) -> StateTimelineResponse {
        StateTimelineResponse(hours: 24,
                              from: "2026-08-18T13:00:00",
                              to: "2026-08-19T13:00:00",
                              states: states, drives: [], charges: [])
    }

    private nonisolated static var sample: StateTimelineResponse {
        timeline(states: [StateSegment(state: "online",
                                       from: "2026-08-18T18:00:00",
                                       to: "2026-08-18T20:00:00")])
    }

    private func makeViewModel(_ mock: MockAPIClient) -> StateTimelineViewModel {
        StateTimelineViewModel(service: VehicleService(api: mock))
    }

    @Test func 받은_구간이_막대로_바뀐다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.timeline == Self.sample)
        #expect(viewModel.bars.count == 1)
        #expect(viewModel.bars[0].kind == .online)
        #expect(viewModel.hasSegments)
    }

    @Test func 매번_서버를_부른다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.load()

        // 누적(ChargeTotalsViewModel)과 반대다 — 「최근 7일」은 창이 계속 움직인다.
        #expect(mock.getCalls.filter { $0.path == "/tesla/state-timeline" }.count == 2)
    }

    @Test func hours를_질의로_보낸다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let call = mock.getCalls.first { $0.path == "/tesla/state-timeline" }
        #expect(call?.query["hours"] == String(StateTimelineViewModel.hours))
        #expect(call?.query["days"] == nil)
    }

    @Test func 새로고침에_실패해도_있던_값을_지우지_않는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/state-timeline")
        await viewModel.reload()

        #expect(viewModel.timeline == Self.sample)
        #expect(viewModel.bars.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func 값이_한_번도_없으면_실패가_오류로만_남는다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/state-timeline")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.timeline == nil)
        #expect(viewModel.bars.isEmpty)
        #expect(viewModel.hasSegments == false)
        #expect(viewModel.errorMessage != nil)
    }

    /// **404는 「못 받았다」가 아니라 「아직 없다」다.** `/tesla/state-timeline`은 다른 저장소가
    /// 나중에 내는 경로라, 그때까지 이것을 실패로 세우면 미니앱을 열자마자 뜨는 첫 화면에
    /// 「불러오지 못했습니다 [다시 시도]」가 상주하고 눌러 봐야 또 404다. 주행 통계가 새 필드가
    /// 없을 때 카드째 감추는 것과 같은 처리를 경로에도 한다.
    @Test func 아직_없는_엔드포인트의_404는_오류로_세우지_않는다() async {
        let mock = MockAPIClient()
        mock.setError(APIError.serverError(statusCode: 404, message: "Not Found"),
                      for: "GET /tesla/state-timeline")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.timeline == nil)
        #expect(viewModel.hasSegments == false)
    }

    /// **한 번 붙은 오류가 안 떨어지던 것을 막는다.** 오프라인에서 앱을 한 번 열면 비404
    /// 실패가 오류를 세우는데, 서버가 나오기 전에는 이후 모든 응답이 404라 오류를 지우는
    /// 유일한 경로(성공)에 닿지 못한다 — 오류 카드가 배포 때까지 첫 화면에 못 박힌다.
    @Test func 비404_실패_뒤에_온_404는_낡은_오류를_지운다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/state-timeline")
        let viewModel = makeViewModel(mock)
        await viewModel.load()
        #expect(viewModel.errorMessage != nil)

        mock.setError(APIError.serverError(statusCode: 404, message: nil),
                      for: "GET /tesla/state-timeline")
        await viewModel.reload()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.timeline == nil)
        #expect(viewModel.hasSegments == false)
    }

    /// 서버가 나온 뒤 잠깐 경로가 사라지는 배포 창이 있어도 **있던 띠를 지우지 않는다** —
    /// 404를 조용히 넘기는 갈래가 「값을 비운다」는 뜻이 되면 안 된다.
    @Test func 성공한_뒤에_온_404가_있던_값을_지우지_않는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(APIError.serverError(statusCode: 404, message: nil),
                      for: "GET /tesla/state-timeline")
        await viewModel.reload()

        #expect(viewModel.timeline == Self.sample)
        #expect(viewModel.bars.count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    /// **`generation` 가드를 실제로 겹치게 만들어 검증한다.** 매 호출을 끝까지 기다렸다 다음을
    /// 시작하면 `guard current == generation` 줄을 전부 지워도 통과한다 — 응답이 뒤바뀌어
    /// 도착하는 경우를 재현해야 가드의 존재 이유가 드러난다. 첫 호출을 게이트로 붙잡아 둔 채
    /// 두 번째 새로고침을 끝까지 굴리고, 그다음에야 첫 응답을 흘려보낸다.
    @Test func 늦게_도착한_옛_응답이_새_값을_덮어쓰지_않는다() async {
        let stale = Self.sample
        let fresh = Self.timeline(states: [
            StateSegment(state: "offline", from: "2026-08-18T14:00:00", to: "2026-08-18T20:00:00"),
            StateSegment(state: "online", from: "2026-08-18T20:00:00", to: "2026-08-18T23:00:00")
        ])
        let mock = MockAPIClient()
        let gate = AsyncGate()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: stale))
        mock.setGate(gate, for: "GET /tesla/state-timeline")
        let viewModel = makeViewModel(mock)

        let first = Task { await viewModel.reload() } // generation 1 — 게이트 안에서 멈춘다.
        await gate.waitUntilBlocked()

        mock.setGate(nil, for: "GET /tesla/state-timeline")
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: fresh))
        await viewModel.reload() // generation 2 — 게이트가 없어 곧바로 끝난다.
        #expect(viewModel.timeline == fresh)

        await gate.open() // 이제야 첫 호출의 옛 응답을 흘려보낸다.
        await first.value

        // generation 토큰이 없었다면 여기서 옛 응답이 새 값을 덮어썼을 것이다.
        #expect(viewModel.timeline == fresh)
        #expect(viewModel.bars.count == 2)
    }

    @Test func 구간이_비어_있어도_오류가_아니다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.timeline(states: [])))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.timeline != nil)
        #expect(viewModel.hasSegments == false)
        #expect(viewModel.errorMessage == nil)
    }
}
