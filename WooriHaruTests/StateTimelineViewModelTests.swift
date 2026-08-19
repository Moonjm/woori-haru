import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct StateTimelineViewModelTests {

    private nonisolated static func timeline(states: [StateSegment]) -> StateTimelineResponse {
        StateTimelineResponse(days: 7,
                              from: "2026-08-13T00:00:00",
                              to: "2026-08-19T12:00:00",
                              states: states, drives: [], charges: [])
    }

    private nonisolated static var sample: StateTimelineResponse {
        timeline(states: [StateSegment(state: "online",
                                       from: "2026-08-13T06:00:00",
                                       to: "2026-08-13T08:00:00")])
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

    @Test func days를_질의로_보낸다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let call = mock.getCalls.first { $0.path == "/tesla/state-timeline" }
        #expect(call?.query["days"] == String(StateTimelineViewModel.days))
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
