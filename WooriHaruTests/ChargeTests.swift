import Foundation
import Testing
@testable import WooriHaru

/// 충전 내역 — 월 조회와 금액 수정. 고치는 것은 금액 한 값뿐이다.
@MainActor
struct ChargeListViewModelTests {
    // 기본 인자에서 부르므로 `nonisolated`여야 한다 — 기본 인자는 액터 밖에서 평가된다.
    private nonisolated static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    private nonisolated static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        seoulCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeViewModel(
        mock: MockAPIClient,
        now: Date = ChargeListViewModelTests.date(2026, 8, 13)
    ) -> ChargeListViewModel {
        ChargeListViewModel(
            service: ChargeService(api: mock),
            now: { now },
            calendar: Self.seoulCalendar
        )
    }

    private nonisolated static func item(
        id: Int,
        startedAt: String,
        cost: Decimal? = 14100
    ) -> ChargeItem {
        ChargeItem(
            id: id,
            startedAt: startedAt,
            endedAt: "2026-08-12T02:31:00",
            durationMin: 257,
            locationName: "집",
            energyAddedKwh: Decimal(string: "48.2"),
            startBatteryLevel: 18,
            endBatteryLevel: 90,
            cost: cost
        )
    }

    private nonisolated static func stubList(
        _ mock: MockAPIClient,
        summary: ChargeSummary = ChargeSummary(count: 1, totalEnergyAddedKwh: Decimal(string: "48.2"), totalCost: 14100),
        items: [ChargeItem] = [item(id: 3312, startedAt: "2026-08-11T22:14:00")]
    ) {
        mock.stubGet(
            "/tesla/charges",
            result: DataResponse<ChargeListResponse>(data: ChargeListResponse(summary: summary, items: items))
        )
    }

    @Test func 진입하면_이번_달을_조회한다() async {
        let mock = MockAPIClient()
        Self.stubList(mock)
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(mock.getCalls.map(\.path) == ["/tesla/charges"])
        #expect(mock.getCalls.first?.query == ["yearMonth": "2026-08"])
        #expect(viewModel.items.count == 1)
    }

    /// 합계는 서버 SQL 집계다 — 목록을 순회해 다시 더하면 페이지네이션이 붙는 순간 조용히 틀린다.
    @Test func 합계는_서버_값을_그대로_싣는다() async {
        let mock = MockAPIClient()
        Self.stubList(
            mock,
            summary: ChargeSummary(count: 12, totalEnergyAddedKwh: Decimal(string: "412.5"), totalCost: 98400),
            items: [Self.item(id: 1, startedAt: "2026-08-11T22:14:00", cost: 100)]
        )
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.summary.count == 12)
        #expect(viewModel.summary.totalCost == 98400)
        #expect(viewModel.summary.totalEnergyAddedKwh == Decimal(string: "412.5"))
    }

    @Test func 이전_달로_이동하면_그_달을_조회한다() async {
        let mock = MockAPIClient()
        Self.stubList(mock)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.shiftMonth(-1)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 7))
        #expect(mock.getCalls.last?.query == ["yearMonth": "2026-07"])
    }

    /// 미래 달 충전 기록은 있을 수 없다 — 요청 자체를 보내지 않는다.
    @Test func 이번_달_다음으로는_이동하지_않는다() async {
        let mock = MockAPIClient()
        Self.stubList(mock)
        let viewModel = makeViewModel(mock: mock)
        await viewModel.load()

        await viewModel.shiftMonth(1)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 8))
        #expect(mock.getCalls.count == 1)
        #expect(viewModel.isAtCurrentMonth)
    }

    /// 피커로 미래 달을 골라도 오늘이 속한 달로 되돌린다.
    @Test func 피커가_미래_달을_주면_이번_달로_되돌린다() async {
        let mock = MockAPIClient()
        Self.stubList(mock)
        let viewModel = makeViewModel(mock: mock)

        await viewModel.selectMonth(year: 2027, month: 3)

        #expect(viewModel.month == LedgerYearMonth(year: 2026, month: 8))
        #expect(mock.getCalls.last?.query == ["yearMonth": "2026-08"])
    }

    /// 연결 실패를 빈 목록으로 눙치면 「충전한 적 없음」과 구분되지 않는다.
    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges")
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.summary == .empty)
        // 화면이 「기록 없음」·「0원」으로 그리지 않도록 못 받았다는 사실이 남아야 한다.
        #expect(!viewModel.isMonthLoaded)
    }

    @Test func 응답을_받아야_로드된_달이다() async {
        let mock = MockAPIClient()
        Self.stubList(mock)
        let viewModel = makeViewModel(mock: mock)
        #expect(!viewModel.isMonthLoaded)

        await viewModel.load()
        #expect(viewModel.isMonthLoaded)

        // 달을 옮기면 그 달의 응답을 받기 전까지는 다시 「모르는 상태」다.
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/charges")
        await viewModel.shiftMonth(-1)
        #expect(!viewModel.isMonthLoaded)
    }

    @Test func 금액이_빈_건수를_센다() async {
        let mock = MockAPIClient()
        Self.stubList(mock, items: [
            Self.item(id: 1, startedAt: "2026-08-11T22:14:00", cost: nil),
            Self.item(id: 2, startedAt: "2026-08-10T22:14:00", cost: 14100),
            Self.item(id: 3, startedAt: "2026-08-10T09:00:00", cost: nil),
        ])
        let viewModel = makeViewModel(mock: mock)

        await viewModel.load()

        #expect(viewModel.missingCostCount == 2)
        // 같은 날 두 건은 한 섹션으로 묶이고, 최신 날짜가 먼저다.
        #expect(viewModel.sections.map(\.items.count) == [1, 2])
    }
}

@MainActor
struct ChargeServiceTests {
    @Test func 금액_수정은_전용_경로로_보낸다() async throws {
        let mock = MockAPIClient()
        let service = ChargeService(api: mock)

        try await service.updateCost(id: 3312, cost: 15000)

        #expect(mock.putVoidCalls.map(\.path) == ["/tesla/charges/3312/cost"])
        let body = try #require(mock.putVoidCalls.first?.body as? ChargeCostRequest)
        #expect(body.cost == 15000)
    }

    @Test func 상세는_id_경로로_조회한다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/3312", result: DataResponse<ChargeDetail>(data: ChargeDetailTests.detail()))
        let service = ChargeService(api: mock)

        let detail = try await service.fetchDetail(id: 3312)

        #expect(detail.id == 3312)
        #expect(mock.getCalls.map(\.path) == ["/tesla/charges/3312"])
    }
}

struct ChargeDetailTests {
    static func detail(
        energyAddedKwh: Decimal? = Decimal(string: "48.2"),
        energyUsedKwh: Decimal? = Decimal(string: "51.8"),
        cost: Decimal? = 14100,
        maxPowerKw: Int? = 48,
        fastCharger: Bool? = false
    ) -> ChargeDetail {
        ChargeDetail(
            id: 3312,
            startedAt: "2026-08-11T22:14:00",
            endedAt: "2026-08-12T02:31:00",
            durationMin: 257,
            energyAddedKwh: energyAddedKwh,
            energyUsedKwh: energyUsedKwh,
            startBatteryLevel: 18,
            endBatteryLevel: 90,
            startRatedRangeKm: Decimal(string: "80.5"),
            endRatedRangeKm: Decimal(string: "402.5"),
            outsideTempAvg: Decimal(string: "26.5"),
            geofenceName: "집",
            address: "서울시 어딘가",
            cost: cost,
            maxPowerKw: maxPowerKw,
            avgPowerKw: Decimal(string: "11.2"),
            fastCharger: fastCharger,
            fastChargerBrand: nil,
            fastChargerType: nil
        )
    }

    /// 효율·단가는 서버가 아니라 앱이 나눈다 — 분모가 없으면 계산하지 않는다.
    @Test func 사용_전력이_없으면_효율은_없다() {
        #expect(ChargeDetailTests.detail(energyUsedKwh: nil).efficiency == nil)
        #expect(ChargeDetailTests.detail(energyUsedKwh: 0).efficiency == nil)
    }

    @Test func 효율과_단가를_계산한다() {
        let detail = ChargeDetailTests.detail()
        #expect(ChargeFormat.percent(detail.efficiency) == "93%")
        #expect(ChargeFormat.unitPrice(detail.costPerKwh) == "₩293/kWh")
    }

    @Test func 금액이_없으면_단가도_없다() {
        #expect(ChargeDetailTests.detail(cost: nil).costPerKwh == nil)
    }

    @Test func 주행가능거리_증가분을_낸다() {
        #expect(ChargeFormat.distance(ChargeDetailTests.detail().ratedRangeGainKm) == "322km")
    }
}

struct ChargeFormatTests {
    /// 없는 값은 0이 아니라 「—」다. 0kW는 「출력 0으로 충전했다」는 뜻이 되어 없는 데이터와 구분되지 않는다.
    @Test func 없는_값은_대시로_낸다() {
        #expect(ChargeFormat.power(nil) == "—")
        #expect(ChargeFormat.energy(nil) == "—")
        #expect(ChargeFormat.batteryRange(18, nil) == "—")
        #expect(ChargeFormat.duration(nil) == "—")
    }

    /// 건별 금액만 「미입력」이다 — 채우러 오는 화면이라 빈 값이 눈에 띄어야 한다.
    @Test func 금액이_없으면_미입력이다() {
        #expect(ChargeFormat.cost(nil) == "미입력")
        #expect(ChargeFormat.cost(14100) == "₩14,100")
    }

    /// 합계 자리에는 「미입력」을 쓰지 않는다 — 못 받았다·충전이 없다와 구분되지 않는다.
    @Test func 합계는_모르는_것과_없는_것을_구분한다() {
        // 아직 못 받았다
        #expect(ChargeFormat.summaryTotal(nil, count: 0, loaded: false) == "—")
        #expect(ChargeFormat.summaryTotal(98400, count: 12, loaded: false) == "—")
        // 충전이 한 건도 없는 달
        #expect(ChargeFormat.summaryTotal(nil, count: 0, loaded: true) == "₩0")
        // 충전은 있는데 금액이 전부 비었다
        #expect(ChargeFormat.summaryTotal(nil, count: 3, loaded: true) == "금액 없음")
        #expect(ChargeFormat.summaryTotal(98400, count: 12, loaded: true) == "₩98,400")
    }

    @Test func 소요시간을_시간과_분으로_쓴다() {
        #expect(ChargeFormat.duration(257) == "4시간 17분")
        #expect(ChargeFormat.duration(45) == "45분")
        #expect(ChargeFormat.duration(120) == "2시간")
    }

    /// 서버가 `numeric(10,2)`로 내려 준 "14100.00"을 그대로 두면 숫자 키패드로 고칠 수 없다.
    @Test func 입력칸_초기값은_소수부_0을_떼어_낸다() {
        #expect(ChargeFormat.plainNumber(Decimal(string: "14100.00")!) == "14100")
        #expect(ChargeFormat.plainNumber(Decimal(string: "14100.50")!) == "14100.5")
    }
}
