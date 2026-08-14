import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleSummaryViewModelTests {
    private nonisolated static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    private nonisolated static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        seoulCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private nonisolated static func charge(id: Int, startedAt: String) -> ChargeItem {
        ChargeItem(
            id: id, startedAt: startedAt, endedAt: "2026-08-12T02:31:00", durationMin: 257,
            locationName: "집", energyAddedKwh: Decimal(string: "48.2"),
            energyUsedKwh: Decimal(string: "51.8"), startBatteryLevel: 18, endBatteryLevel: 90,
            cost: 14100
        )
    }

    private nonisolated static func stub(_ mock: MockAPIClient, charges: [ChargeItem] = []) {
        let month = VehiclePeriod(
            yearMonth: "2026-08", distanceKm: 842, drivingMin: 1043, driveCount: 61,
            energyAddedKwh: 186, energyUsedKwh: 201, cost: 52300, chargeCount: charges.count
        )
        mock.stubGet("/tesla/summary", result: DataResponse<VehicleSummaryResponse>(
            data: VehicleSummaryResponse(month: month, previous: nil, trend: [month], charges: charges)
        ))
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: 12, items: [])
        ))
    }

    private func makeViewModel(mock: MockAPIClient) -> VehicleSummaryViewModel {
        VehicleSummaryViewModel(
            service: VehicleService(api: mock),
            now: { Self.date(2026, 8, 13) },
            calendar: Self.seoulCalendar
        )
    }

    @Test func 진입하면_이번_달_요약과_미등록_수를_받는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, charges: [Self.charge(id: 1, startedAt: "2026-08-11T22:14:00")])
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(mock.getCalls.contains { $0.path == "/tesla/summary" && $0.query == ["yearMonth": "2026-08"] })
        #expect(viewModel.summary?.month.distanceKm == 842)
        #expect(viewModel.missingCostCount == 12)
        #expect(viewModel.isMonthLoaded)
    }

    /// 미등록 수는 월과 무관하다 — 달을 옮길 때마다 다시 받지 않는다.
    @Test func 달을_옮겨도_미등록_수는_다시_받지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.shiftMonth(-1)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 7))
        #expect(mock.getCalls.filter { $0.path == "/tesla/charges/missing-cost" }.count == 1)
    }

    @Test func 이번_달_다음으로는_이동하지_않는다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()
        let calls = mock.getCalls.count

        await viewModel.shiftMonth(1)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 8))
        #expect(mock.getCalls.count == calls)
        #expect(viewModel.isAtCurrentMonth)
    }

    @Test func 피커가_미래_달을_주면_이번_달로_되돌린다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        let viewModel = makeViewModel(mock: mock)

        await viewModel.selectMonth(year: 2027, month: 3)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 8))
    }

    /// 실패를 빈 달로 눙치지 않는다 — 「안 탔다」와 구분되지 않는다.
    @Test func 실패하면_에러를_드러내고_로드되지_않은_상태다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/summary")
        mock.stubGet("/tesla/charges/missing-cost", result: DataResponse<MissingCostResponse>(
            data: MissingCostResponse(totalCount: 0, items: [])
        ))
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.summary == nil)
        #expect(!viewModel.isMonthLoaded)
    }

    /// 미등록 수를 못 받아도 요약은 그대로 보여준다 — 배지 하나 때문에 화면을 죽이지 않는다.
    @Test func 미등록_수만_실패하면_요약은_남는다() async {
        let mock = MockAPIClient()
        Self.stub(mock)
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges/missing-cost")
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.summary != nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.missingCostCount == 0)
    }

    @Test func 충전을_하루_단위로_묶는다() async {
        let mock = MockAPIClient()
        Self.stub(mock, charges: [
            Self.charge(id: 1, startedAt: "2026-08-11T22:14:00"),
            Self.charge(id: 2, startedAt: "2026-08-10T22:14:00"),
            Self.charge(id: 3, startedAt: "2026-08-10T09:00:00"),
        ])
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.sections.map(\.items.count) == [1, 2]) // 최신 날짜 먼저
    }
}
