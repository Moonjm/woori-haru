import Foundation
import Testing
@testable import WooriHaru

/// `ChargeItem` 픽스처 — 여러 테스트 타입이 함께 쓴다.
enum ChargeFixtures {
    nonisolated static func item(
        id: Int,
        startedAt: String,
        cost: Decimal? = 14100,
        energyUsedKwh: Decimal? = Decimal(string: "51.8")
    ) -> ChargeItem {
        ChargeItem(
            id: id,
            startedAt: startedAt,
            endedAt: "2026-08-12T02:31:00",
            durationMin: 257,
            locationName: "집",
            energyAddedKwh: Decimal(string: "48.2"),
            energyUsedKwh: energyUsedKwh,
            startBatteryLevel: 18,
            endBatteryLevel: 90,
            cost: cost
        )
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

    /// 파라미터가 없다. 전 기간이다.
    @Test func 누적은_파라미터_없이_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/totals", result: DataResponse<ChargeTotalsResponse>(
            data: ChargeTotalsResponse(
                chargeCount: 474, energyAddedKwh: nil, energyUsedKwh: nil, cost: nil,
                costMissingCount: 35, costMissingEnergyUsedKwh: nil, firstChargedAt: "2021-09-03",
                fast: ChargeTotalsBreakdown(chargeCount: 42, energyAddedKwh: nil, energyUsedKwh: nil,
                                            cost: nil, costMissingCount: 24,
                                            costMissingEnergyUsedKwh: nil),
                slow: ChargeTotalsBreakdown(chargeCount: 432, energyAddedKwh: nil, energyUsedKwh: nil,
                                            cost: nil, costMissingCount: 11,
                                            costMissingEnergyUsedKwh: nil)
            )
        ))
        let service = ChargeService(api: mock)

        let totals = try await service.fetchTotals()

        #expect(totals.chargeCount == 474)
        #expect(mock.getCalls.map(\.path) == ["/tesla/charges/totals"])
        #expect(mock.getCalls.first?.query == [:])
    }

    @Test func 곡선은_id를_경로에_넣어_부른다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/402/curve", result: DataResponse<ChargeCurveResponse>(
            data: ChargeCurveResponse(samples: [
                ChargeCurveSample(at: "2025-09-10T13:02:11", powerKw: 166, batteryLevel: 11),
            ])
        ))
        let service = ChargeService(api: mock)

        let curve = try await service.fetchCurve(id: 402)

        #expect(curve.samples.count == 1)
        #expect(mock.getCalls.map(\.path) == ["/tesla/charges/402/curve"])
    }

    /// **샘플이 없는 세션은 빈 배열이다** — 없는 id·진행 중(404)과 다르게 그려야 한다.
    @Test func 샘플이_없어도_에러가_아니다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/charges/9/curve",
                     result: DataResponse<ChargeCurveResponse>(data: ChargeCurveResponse(samples: [])))
        let service = ChargeService(api: mock)

        #expect(try await service.fetchCurve(id: 9).samples.isEmpty)
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

    /// 단가의 분모는 차에 들어간 양이 아니라 벽에서 뽑아쓴 양이다 — 요금을 그쪽으로 매기기 때문이다.
    /// 14100 ÷ 51.8 = 272.2…이지 14100 ÷ 48.2 = 292.5…가 아니다.
    @Test func 단가는_사용_전력으로_나눈다() {
        let detail = ChargeDetailTests.detail()
        #expect(ChargeFormat.unitPrice(detail.costPerKwh) == "₩272/kWh")
    }

    @Test func 효율을_계산한다() {
        #expect(ChargeFormat.percent(ChargeDetailTests.detail().efficiency) == "93%")
    }

    @Test func 금액이_없으면_단가도_없다() {
        #expect(ChargeDetailTests.detail(cost: nil).costPerKwh == nil)
    }

    /// 사용 전력이 없는 구버전 데이터에서 충전량으로 갈음하지 않는다 —
    /// 기준이 다른 값을 같은 자리에 섞으면 두 건을 비교할 수 없다.
    @Test func 사용_전력이_없으면_단가도_없다() {
        #expect(ChargeDetailTests.detail(energyUsedKwh: nil).costPerKwh == nil)
        #expect(ChargeDetailTests.detail(energyUsedKwh: 0).costPerKwh == nil)
    }

    /// 목록과 상세가 같은 기준으로 같은 값을 내야 한다.
    @Test func 목록_단가도_같은_기준이다() {
        let item = ChargeFixtures.item(id: 3312, startedAt: "2026-08-11T22:14:00")
        #expect(item.costPerKwh == ChargeDetailTests.detail().costPerKwh)
        #expect(ChargeFixtures.item(
            id: 1, startedAt: "2026-08-11T22:14:00", energyUsedKwh: nil
        ).costPerKwh == nil)
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

    /// 채워 넣은 값을 그대로 다시 읽어야 한다. 서식이 기기 로케일을 따르면 소수 구분자가
    /// 쉼표인 지역에서 "14100,5"가 채워지고, 그 쉼표를 자리구분으로 지워 141005가 된다 —
    /// 열어서 저장만 눌러도 금액이 10배가 되는 경로다.
    @Test func 채워_넣은_값을_그대로_다시_읽는다() {
        for raw in ["14100.00", "14100.50", "4587.36", "0"] {
            let value = Decimal(string: raw)!
            #expect(ChargeFormat.parseCost(ChargeFormat.plainNumber(value)) == value)
        }
    }

    @Test func 자리구분_쉼표와_공백은_받아_준다() {
        #expect(ChargeFormat.parseCost(" 14,100 ") == 14100)
    }

    /// 서버가 400으로 돌려줄 값은 저장 버튼을 살려 두지 않는다.
    @Test func 서버가_거절할_값은_읽지_않는다() {
        #expect(ChargeFormat.parseCost("") == nil)
        #expect(ChargeFormat.parseCost("   ") == nil)
        #expect(ChargeFormat.parseCost("만원") == nil)
        #expect(ChargeFormat.parseCost("-100") == nil)
        // 소수 셋째 자리 — 서버 `@Digits(fraction = 2)`
        #expect(ChargeFormat.parseCost("1.234") == nil)
        #expect(ChargeFormat.parseCost("14100.99") == Decimal(string: "14100.99"))
        // 상한 99,999,999.99 — 서버 `@Digits(integer = 8)`
        #expect(ChargeFormat.parseCost("100000000") == nil)
        #expect(ChargeFormat.parseCost("99999999") == 99_999_999)
    }
}
