import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleHealthViewModelTests {

    private nonisolated static func sample(
        _ yearMonth: String, _ fullRangeKm: String, capacity: String? = nil, count: Int = 1
    ) -> BatteryHealthSample {
        BatteryHealthSample(
            yearMonth: yearMonth, fullRangeKm: Decimal(string: fullRangeKm)!,
            capacityKwh: capacity.flatMap { Decimal(string: $0) },
            sampleCount: count, capacitySampleCount: capacity == nil ? 0 : 1
        )
    }

    private func makeViewModel(_ mock: MockAPIClient) -> VehicleHealthViewModel {
        VehicleHealthViewModel(service: VehicleService(api: mock))
    }

    private func stub(_ mock: MockAPIClient, _ samples: [BatteryHealthSample], missing: Int = 0) {
        mock.stubGet("/tesla/battery-health",
                     result: DataResponse<BatteryHealthResponse>(data: BatteryHealthResponse(samples: samples)))
        mock.stubGet("/tesla/charges/missing-cost",
                     result: DataResponse<MissingCostResponse>(data: MissingCostResponse(totalCount: missing, items: [])))
    }

    /// 서버가 오래된 것부터 주므로 **마지막**이 최근이다.
    @Test func 최근_표본으로_잔존율을_낸다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-07", "527.1"), Self.sample("2026-08", "525.3", capacity: "71.6", count: 3)])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.latest?.yearMonth == "2026-08")
        #expect(VehicleFormat.percent(viewModel.remainingPercent) == "92%")
        #expect(VehicleFormat.percent(viewModel.degradationPercent) == "8%")
        #expect(VehicleFormat.distance(viewModel.rangeLostKm) == "43km")
        #expect(viewModel.latestCapacityKwh == Decimal(string: "71.6"))
    }

    /// 용량 표본은 주행거리 표본보다 드물다 — 최근 달에 없으면 **값이 있는 마지막 달**에서 온다.
    @Test func 용량은_값이_있는_마지막_달에서_온다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-06", "530.0", capacity: "72.4"),
                    Self.sample("2026-07", "527.1"),
                    Self.sample("2026-08", "525.3")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.latest?.yearMonth == "2026-08")
        #expect(viewModel.latestCapacityKwh == Decimal(string: "72.4"))
    }

    /// 5년 치를 다 그리면 최근 1년의 움직임이 뭉갠다. 24개월만 그린다.
    @Test func 최근_24개월만_그린다() async {
        let mock = MockAPIClient()
        let samples = (0..<30).map { index -> BatteryHealthSample in
            let ordinal = 2024 * 12 + 3 + index
            let year = (ordinal - 1) / 12
            let month = (ordinal - 1) % 12 + 1
            return Self.sample(String(format: "%04d-%02d", year, month), "540.0")
        }
        stub(mock, samples)
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.samples.count == 30)
        #expect(viewModel.trendSamples.count == 24)
        #expect(viewModel.trendSamples.last?.yearMonth == samples.last?.yearMonth)
    }

    /// **빠진 달에서 선을 끊는다.** 없는 값을 직선으로 메우면 그 달에도 잰 것처럼 보인다.
    @Test func 표본이_빠진_달에서_선이_갈린다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-03", "532.0"), Self.sample("2026-04", "530.5"),
                    // 2026-05가 없다
                    Self.sample("2026-06", "528.0"), Self.sample("2026-07", "527.1")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.trendSegments.map(\.count) == [2, 2])
        #expect(viewModel.trendSegments[0].map(\.yearMonth) == ["2026-03", "2026-04"])
        #expect(viewModel.trendSegments[1].map(\.yearMonth) == ["2026-06", "2026-07"])
    }

    @Test func 표본이_하나면_선분도_하나에_점_하나다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.hasSamples)
        #expect(viewModel.trendSegments.map(\.count) == [1])
    }

    /// 표본이 없는 것은 에러가 아니다 — 「아직 잴 만한 충전이 없다」다.
    @Test func 표본이_없어도_에러가_아니다() async {
        let mock = MockAPIClient()
        stub(mock, [])
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.hasSamples)
        #expect(viewModel.isLoaded)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.remainingPercent == nil)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        stub(mock, [])
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/battery-health")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.hasSamples)
        #expect(!viewModel.isLoaded)
    }

    /// 배지 하나 때문에 화면을 죽이지 않는다. 요약 탭과 같은 규칙이다.
    @Test func 배지가_실패해도_건강_카드는_산다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")])
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/missing-cost")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.missingCostCount == 0)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.hasSamples)
    }

    @Test func 미등록_건수를_받는다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")], missing: 3)
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.missingCostCount == 3)
    }

    /// 탭을 오갈 때마다 전 기간 집계를 다시 부르지 않는다. 배지 수만 매번 맞춘다 —
    /// 큐에서 금액을 채우고 돌아오면 그 수가 달라져 있어야 한다.
    @Test func 다시_열어도_집계는_한_번만_부른다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")], missing: 3)
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.load()

        #expect(mock.getCalls.filter { $0.path == "/tesla/battery-health" }.count == 1)
        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/missing-cost" }.count == 2)
    }

    /// 당겨서 새로고침은 캐시를 무시한다.
    @Test func 새로고침은_다시_부른다() async {
        let mock = MockAPIClient()
        stub(mock, [Self.sample("2026-08", "525.3")])
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.reload()

        #expect(mock.getCalls.filter { $0.path == "/tesla/battery-health" }.count == 2)
    }
}
