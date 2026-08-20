import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VehicleStatsViewModelTests {

    /// 버킷·장소를 갈아 끼울 수 있는 응답. **`InsightsStub`을 안 쓰는 이유**는 이 파일의
    /// 카드 테스트들이 실측 버킷(온도 939건·거리 959건)을 그대로 단언하기 때문이다 —
    /// 공용 스텁은 그 노브를 열지 않고, 여는 순간 열한 태스크가 함께 쓰는 스텁이 커진다.
    /// 월별 계열만 보는 테스트는 `InsightsStub`을 그대로 쓴다.
    private nonisolated static func response(
        months: Int = 12,
        monthly: [InsightsMonth] = [],
        efficiency: String? = "0.1367",
        temperatureBuckets: [TemperatureBucket] = [],
        driveTimes: [DriveTime] = [],
        distanceBuckets: [DistanceBucket] = [],
        places: [DrivePlace] = [],
        maxSpeedKmh: Int? = 138,
        totalDistanceKm: Decimal = Decimal(string: "107257.8")!,
        recordedMonths: Int = 60
    ) -> InsightsResponse {
        InsightsResponse(
            months: months,
            monthly: monthly,
            efficiencyKwhPerKm: efficiency.flatMap { Decimal(string: $0) },
            temperatureBuckets: temperatureBuckets,
            driveTimes: driveTimes,
            distanceBuckets: distanceBuckets,
            places: places,
            maxSpeedKmh: maxSpeedKmh,
            totalDistanceKm: totalDistanceKm,
            recordedMonths: recordedMonths,
            weekday: [],
            chargeTimes: [],
            speedBuckets: [],
            speedEnergyBuckets: [],
            chargeStartLevels: [],
            chargeEndLevels: [],
            chargers: [],
            regions: Regions(cities: 0, states: 0, countries: 0),
            records: InsightsRecords(longestDistance: nil, longestDuration: nil,
                                     bestEfficiency: nil)
        )
    }

    /// 실측(2026-08-17 최근 12개월) 그대로다 — 온도 939건, 거리 959건.
    private nonisolated static func insights(
        months: Int = 12, efficiency: String? = "0.1367", places: [DrivePlace] = []
    ) -> InsightsResponse {
        response(
            months: months,
            efficiency: efficiency,
            temperatureBuckets: [
                TemperatureBucket(fromC: nil, toC: 0, driveCount: 82,
                                  distanceKm: Decimal(string: "2424.8")!,
                                  ratedRangeUsedKm: Decimal(string: "2939.2")!),
                TemperatureBucket(fromC: 0, toC: 10, driveCount: 229,
                                  distanceKm: Decimal(string: "6507.3")!,
                                  ratedRangeUsedKm: Decimal(string: "7097.1")!),
                TemperatureBucket(fromC: 10, toC: 20, driveCount: 244,
                                  distanceKm: Decimal(string: "5990.4")!,
                                  ratedRangeUsedKm: Decimal(string: "5723.9")!),
                TemperatureBucket(fromC: 20, toC: 30, driveCount: 266,
                                  distanceKm: Decimal(string: "5748.4")!,
                                  ratedRangeUsedKm: Decimal(string: "5798.5")!),
                TemperatureBucket(fromC: 30, toC: nil, driveCount: 118,
                                  distanceKm: Decimal(string: "2494.6")!,
                                  ratedRangeUsedKm: Decimal(string: "2551.5")!),
            ],
            driveTimes: [
                DriveTime(weekday: 1, hour: 8, count: 43),
                DriveTime(weekday: 2, hour: 17, count: 41),
                DriveTime(weekday: 0, hour: 14, count: 12),
            ],
            distanceBuckets: [
                DistanceBucket(fromKm: 0, toKm: 5, driveCount: 620, distanceKm: 1802),
                DistanceBucket(fromKm: 5, toKm: 20, driveCount: 210, distanceKm: 2400),
                DistanceBucket(fromKm: 20, toKm: 50, driveCount: 90, distanceKm: 2700),
                DistanceBucket(fromKm: 50, toKm: 100, driveCount: 36, distanceKm: 2500),
                DistanceBucket(fromKm: 100, toKm: nil, driveCount: 3, distanceKm: 412),
            ],
            places: places
        )
    }

    private nonisolated static func empty(months: Int = 3) -> InsightsResponse {
        response(months: months)
    }

    /// 한 달치. 기록이 없는 달은 값 자리가 전부 nil이다 — 셋(`idleMin`·팬텀 드레인 둘)만
    /// 그때도 값이 온다.
    ///
    /// **그 셋을 0으로 못박지 않는다.** 계약은 오히려 반대다 — 빈 달일수록 `idleMin`이
    /// 크다(내내 서 있었으므로). 전부 0으로 두면 뒤 태스크가 `idleMin`·팬텀 드레인
    /// 접근자를 더할 때 「상수 0을 돌려주는 접근자」가 조용히 통과한다. 값은 공용
    /// `InsightsStub`과 맞추고, 노브로 덮어쓸 수 있게 연다.
    private nonisolated static func month(
        _ yearMonth: String, distanceKm: Decimal? = nil, drivingMin: Int? = nil,
        driveCount: Int? = nil, energyAddedKwh: Decimal? = nil, energyUsedKwh: Decimal? = nil,
        cost: Decimal? = nil, chargeCount: Int? = nil, chargingMin: Int? = nil,
        ratedRangeUsedKm: Decimal? = nil,
        idleMin: Int? = nil, parkDrainRatedKm: Decimal? = nil, parkDrainSamples: Int? = nil
    ) -> InsightsMonth {
        // 주행도 충전도 없는 달이면 「내내 서 있었다」 — 31일 = 44640분.
        let isEmpty = distanceKm == nil && drivingMin == nil && driveCount == nil
            && energyAddedKwh == nil && cost == nil && chargeCount == nil
        return InsightsMonth(
            yearMonth: yearMonth, distanceKm: distanceKm, driveCount: driveCount,
            drivingMin: drivingMin, energyAddedKwh: energyAddedKwh,
            energyUsedKwh: energyUsedKwh, cost: cost, chargeCount: chargeCount,
            chargingMin: chargingMin, ratedRangeUsedKm: ratedRangeUsedKm,
            idleMin: idleMin ?? (isEmpty ? 44640 : 42800),
            parkDrainRatedKm: parkDrainRatedKm ?? (isEmpty ? 0 : Decimal(string: "18.4")!),
            parkDrainSamples: parkDrainSamples ?? (isEmpty ? 0 : 34))
    }

    private func makeViewModel(_ mock: MockAPIClient) -> VehicleStatsViewModel {
        VehicleStatsViewModel(service: VehicleService(api: mock))
    }

    private func stub(_ mock: MockAPIClient, _ response: InsightsResponse) {
        InsightsStub.stub(mock, response)
    }

    /// 이제 이 화면이 부르는 경로는 하나다 — 그래도 걸러 보는 것은, 다른 뷰모델이 같은
    /// 목을 쓰는 테스트가 생겨도 이 단언이 그 호출을 세지 않게 하기 위해서다.
    private func insightsCalls(_ mock: MockAPIClient) -> [(path: String, query: [String: String])] {
        mock.getCalls.filter { $0.path == "/tesla/insights" }
    }

    /// 기본은 12개월이다.
    @Test func 기본_기간은_12개월이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.period == .twelveMonths)
        #expect(insightsCalls(mock).first?.query == ["months": "12"])
        #expect(viewModel.hasDrives)
    }

    /// 기간을 바꾸면 다시 받는다 — 카드가 전부 같은 기간을 봐야 한다.
    @Test func 기간을_바꾸면_다시_받는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        await viewModel.select(.threeMonths)

        #expect(viewModel.period == .threeMonths)
        #expect(insightsCalls(mock).map { $0.query["months"] } == ["12", "3"])
    }

    /// 1단계에서는 `trend`가 12개월 고정이라 칩이 월별 차트에 안 먹었다.
    @Test func 기간을_바꾸면_월별_계열도_함께_바뀐다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(months: 12, monthlyCount: 12))
        let viewModel = makeViewModel(mock)
        await viewModel.load()
        #expect(viewModel.distancePoints.count == 12)

        InsightsStub.stub(mock, InsightsStub.response(months: 3, monthlyCount: 3))
        await viewModel.select(.threeMonths)

        #expect(viewModel.distancePoints.count == 3)
    }

    /// **0이 전체 기간이다.** 칩 라벨이 「전체」라고 해서 파라미터를 빼면 서버가 기본값
    /// 12로 답해 조용히 12개월만 나온다.
    @Test func 전체를_고르면_개월수_0으로_부른다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(months: 0, monthlyCount: 60))
        let viewModel = makeViewModel(mock)

        await viewModel.select(.all)

        let call = insightsCalls(mock).last
        #expect(call?.query["months"] == "0")
        #expect(viewModel.distancePoints.count == 60)
    }

    /// 같은 기간을 다시 누르면 부르지 않는다.
    @Test func 같은_기간은_다시_부르지_않는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        await viewModel.select(.twelveMonths)

        #expect(insightsCalls(mock).count == 1)
    }

    /// 버킷별 전비를 앱이 낸다. 영하가 가장 나쁘고 10~20℃가 가장 좋다 — 실측 그대로다.
    @Test func 버킷마다_전비를_낸다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let rows = viewModel.temperatureRows
        #expect(rows.count == 5)
        #expect(rows[0].bucket.label == "영하")
        let cold = rows[0].kmPerKwh!
        let mild = rows[2].kmPerKwh!
        #expect(mild > cold)
        #expect(rows.allSatisfy { $0.kmPerKwh != nil })
    }

    /// **두 카드의 총합이 다르다.** 온도 쪽은 주행가능거리 소모가 0 이하인 주행을 뺀 뒤 센다.
    /// 한 곳에서 뽑아 「N건」으로 쓰면 어긋난다.
    @Test func 온도와_거리의_건수가_다르다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.temperatureDriveCount == 939)
        #expect(viewModel.distanceDriveCount == 959)
    }

    /// TeslaMate가 `cars.efficiency`를 아직 못 채운 경우다 — 전비 카드를 감춘다.
    /// 나머지 카드는 그대로 그린다.
    @Test func 효율_계수가_없으면_전비_카드를_감춘다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights(efficiency: nil))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.showsEfficiency)
        #expect(viewModel.hasDrives)
        #expect(viewModel.temperatureRows.allSatisfy { $0.kmPerKwh == nil })
    }

    /// **지오펜스가 하나도 없는 것이 이 차량의 기본 상태다.** 「가끔 비는 경우」가 아니다.
    @Test func 지오펜스가_없으면_자주_가는_곳을_감춘다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.showsPlaces)
    }

    /// **계수는 있는데 모든 온도 버킷의 `ratedRangeUsedKm`이 0인 경우다** — 아주 짧은
    /// 주행만 있는 기간(실측: 447건 중 431건이 델타 정확히 0). 거리 버킷 쪽엔 주행이
    /// 있어 `hasDrives`는 참이지만, 전비 카드는 다섯 줄 다 「—」가 되어 감춰야 한다.
    @Test func 전비_행이_전부_비면_카드를_감춘다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(
            temperatureBuckets: [
                TemperatureBucket(fromC: nil, toC: 0, driveCount: 3,
                                  distanceKm: Decimal(string: "12.4")!, ratedRangeUsedKm: 0),
                TemperatureBucket(fromC: 0, toC: 10, driveCount: 5,
                                  distanceKm: Decimal(string: "20.1")!, ratedRangeUsedKm: 0),
            ],
            distanceBuckets: [
                DistanceBucket(fromKm: 0, toKm: 5, driveCount: 8,
                               distanceKm: Decimal(string: "32.5")!),
            ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.hasDrives)
        #expect(!viewModel.showsEfficiency)
    }

    @Test func 지오펜스가_있으면_자주_가는_곳을_낸다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights(places: [DrivePlace(name: "집", driveCount: 124, distanceKm: 812)]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.showsPlaces)
    }

    /// **`recordedMonths`가 non-null이 된 것은 「0이 안 온다」가 아니다.** 주행이 하나도
    /// 없는 계정은 총거리 0·기록된 달 0으로 오는데, 그걸로 나누면 안 된다 —
    /// 「월 평균 0km」가 아니라 「낼 수 없다」다.
    @Test func 기록된_달이_0이면_평균을_내지_않는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(totalDistanceKm: 0, recordedMonths: 0))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.insights?.totalDistanceKm == 0)
        #expect(viewModel.avgMonthlyKm == nil)
        #expect(viewModel.avgYearlyKm == nil)
    }

    /// **총거리 0은 값이다.** 기록된 달이 있는데 그 기간에 안 탔으면 평균 0km가 옳다 —
    /// 위 테스트의 nil과 갈리는 자리다.
    @Test func 총거리가_0이어도_기록된_달이_있으면_평균은_0이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(totalDistanceKm: 0, recordedMonths: 12))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.avgMonthlyKm == 0)
        #expect(viewModel.avgYearlyKm == 0)
    }

    /// 아직 응답을 못 받은 상태에서는 통계 카드도 섹션도 없다 —
    /// 로딩 스피너 위에 「—」 셋짜리 카드나 빈 섹션 헤더가 먼저 서면 안 된다.
    @Test func 응답을_아직_못_받으면_카드도_섹션도_없다() {
        let viewModel = makeViewModel(MockAPIClient())

        #expect(!viewModel.hasLoadedInsights)
        #expect(!viewModel.hasDriveMonths)
        #expect(!viewModel.hasChargeMonths)
        #expect(viewModel.distancePoints.isEmpty)
        #expect(viewModel.cumulativeDistancePoints.isEmpty)
    }

    /// **「받았다」와 「내용이 있다」는 다르다.** 값이 하나도 없는 응답도 받은 것은 받은
    /// 것이라 통계 카드는 선다 — 감추는 것은 응답 전뿐이다.
    @Test func 응답을_받으면_내용이_비어도_통계_카드는_선다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: []))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.hasLoadedInsights)
        #expect(!viewModel.hasDriveMonths)
        #expect(!viewModel.hasChargeMonths)
    }

    /// **서버는 기록이 없는 달도 값이 전부 nil인 행으로 자리를 채워 보낸다.**
    /// 행의 존재(`!monthly.isEmpty`)로 게이트를 삼으면 「이 기간에 주행 기록이 없어요」
    /// 안내문 위아래로 빈 차트 일곱 장이 헤더까지 달고 선다.
    @Test func 월이_전부_비면_주행도_충전도_섹션이_없다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-06"), Self.month("2026-07"), Self.month("2026-08"),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        // 행은 셋이다 — 자리를 지키는 것과 내용이 있는 것은 다르다.
        #expect(viewModel.monthly.count == 3)
        #expect(viewModel.distancePoints.count == 3)
        #expect(!viewModel.hasDriveMonths)
        #expect(!viewModel.hasChargeMonths)
    }

    /// **게이트를 둘로 나눈 이유가 여기다.** 충전은 주행 없이도 한다 — 하나로 묶으면
    /// 안 타고 충전만 한 기간에 충전 카드까지 사라진다.
    @Test func 충전만_있는_달은_충전_섹션만_세운다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-08", energyAddedKwh: 153, cost: 32700, chargeCount: 7),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.hasChargeMonths)
        #expect(!viewModel.hasDriveMonths)
    }

    /// 반대 방향도 못박는다 — 주행만 있고 충전이 없는 달(집 충전 금액 미입력 등)에
    /// 주행 섹션이 함께 사라지면 안 된다.
    @Test func 주행만_있는_달은_주행_섹션만_세운다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-08", distanceKm: 780, drivingMin: 1120, driveCount: 41),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.hasDriveMonths)
        #expect(!viewModel.hasChargeMonths)
    }

    /// 히트맵은 성기게 온다 — 없는 칸은 0이다. `weekday` 0이 일요일이다.
    @Test func 히트맵의_없는_칸은_0이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.heatCount(weekday: 1, hour: 8) == 43)
        #expect(viewModel.heatCount(weekday: 0, hour: 14) == 12)
        #expect(viewModel.heatCount(weekday: 3, hour: 3) == 0)
        #expect(viewModel.maxHeatCount == 43)
    }

    /// **서버가 같은 칸(요일·시각)을 두 번 보내도 죽지 않고 합쳐야 한다** —
    /// `rebuildHeatMap()`이 `uniqueKeysWithValues` 대신 `uniquingKeysWith: +`를
    /// 쓰는 이유다. 지금 SQL은 이러지 않지만, 서버 데이터로 앱이 죽는 길을 열어 둘
    /// 이유가 없다.
    @Test func 같은_칸이_두_번_와도_합쳐서_센다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(driveTimes: [
            DriveTime(weekday: 1, hour: 8, count: 20),
            DriveTime(weekday: 1, hour: 8, count: 15),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.heatCount(weekday: 1, hour: 8) == 35)
        #expect(viewModel.maxHeatCount == 35)
    }

    /// 그 기간에 주행이 없는 것은 에러가 아니다. 카드마다 비우지 않고 화면 하나로 말한다.
    @Test func 주행이_없어도_에러가_아니다() async {
        let mock = MockAPIClient()
        stub(mock, Self.empty())
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(!viewModel.hasDrives)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.maxHeatCount == 0)
    }

    @Test func 실패하면_에러를_드러낸다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/insights")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.insights == nil)
    }

    /// **있던 값을 새로고침 실패로 지우지 않는다** — 1단계 건강 화면과 같은 규칙이다.
    @Test func 새로고침이_실패해도_있던_값은_남는다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/insights")
        await viewModel.reload()

        #expect(viewModel.hasDrives)
        #expect(viewModel.errorMessage != nil)
    }

    /// **지난번이 오류로 끝났으면 탭에 다시 들어와도 다시 받는다** — 그러지 않으면
    /// 빨간 배너가 영영 남는다. `VehicleHealthViewModel.load()`와 같은 규칙이다.
    @Test func 에러_상태에서_다시_들어오면_재시도한다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/insights")
        await viewModel.reload()
        #expect(insightsCalls(mock).count == 2)

        await viewModel.load()

        #expect(insightsCalls(mock).count == 3)
    }

    /// **기간을 바꾸다 실패하면 옛 기간의 값을 남기지 않는다** — 칩은 3개월인데 화면이
    /// 12개월 값이면 거짓말이 된다. 새로고침 실패와 다르게 다뤄야 한다.
    @Test func 기간_변경이_실패하면_옛_기간_값을_지운다() async {
        let mock = MockAPIClient()
        stub(mock, Self.insights())
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/insights")
        await viewModel.select(.threeMonths)

        #expect(viewModel.period == .threeMonths)
        #expect(viewModel.insights == nil)
        #expect(viewModel.errorMessage != nil)
    }

    /// 세 달 — 가운데가 기록 없는 달이다. **자리는 지키되 막대를 안 그리고, 누적은
    /// 끊기지 않는다.**
    @Test func 월별_점은_기록_없는_달도_자리를_지킨다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-06", distanceKm: 620, drivingMin: 880, driveCount: 34,
                       energyAddedKwh: 115, energyUsedKwh: 126, cost: 22770, chargeCount: 5),
            Self.month("2026-07"),
            Self.month("2026-08", distanceKm: 780, drivingMin: 1120, driveCount: 41,
                       energyAddedKwh: 153, energyUsedKwh: 161, cost: 32700, chargeCount: 7),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.hasDriveMonths)
        #expect(viewModel.distancePoints.count == 3)
        #expect(viewModel.distancePoints[0].label == "6")
        #expect(viewModel.distancePoints[1].value == nil)      // 기록 없는 달은 nil로 남는다
        // 누적은 기록 없는 달을 건너뛰고 이어 간다.
        let cumulative = viewModel.cumulativeDistancePoints
        let expectedCumulativeAugust: Decimal = 620 + 780
        #expect(cumulative[2].value == expectedCumulativeAugust)
        #expect(cumulative[1].value == nil)
    }

    /// **전비는 응답에 없다** — 1단계에서 `VehiclePeriod.efficiency`가 하던 나눗셈이
    /// 뷰모델로 옮겨왔다. 분모는 충전량이라 620÷115 = 5.39km/kWh다.
    @Test func 월별_전비는_충전량으로_나눈다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-06", distanceKm: 620, energyAddedKwh: 115),
            Self.month("2026-07"),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let june = try! #require(viewModel.efficiencyPoints.first?.value)
        #expect(abs(june - Decimal(string: "5.3913")!) < Decimal(string: "0.001")!)
        // **0이 아니라 nil이다** — 기록이 없는 달은 「전비 0」이 아니라 「모른다」다.
        #expect(viewModel.efficiencyPoints[1].value == nil)
    }

    /// #12 월별 충전 시간. **막대 값은 분 그대로 둔다** — `drivingMinPoints`와 같다.
    /// 시·분 표기(`ChargeFormat.duration`)는 콜아웃에서만 쓴다.
    @Test func 월별_충전_시간은_분_그대로_점으로_옮긴다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-06", chargingMin: 257),
            Self.month("2026-07"),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.chargingMinPoints[0].value == 257)
        // 기록 없는 달은 0분이 아니라 nil이다.
        #expect(viewModel.chargingMinPoints[1].value == nil)
    }

    // MARK: - 종합 효율(정격 대비)

    /// 100km를 정격 50km로, 10km를 정격 100km로 갔다면 월별 비율은 2.0과 0.1이지만
    /// **합끼리 나눠야** 110÷150 ≈ 0.733이다. 월별 평균(1.05)과 다른 값이어야
    /// 「합끼리 나눈다」는 계약이 실제로 지켜지는지 가른다.
    @Test func 종합_효율은_거리와_정격_합끼리_나눈다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-06", distanceKm: 100, ratedRangeUsedKm: 50),
            Self.month("2026-07", distanceKm: 10, ratedRangeUsedKm: 100),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let ratio = try! #require(viewModel.overallEfficiencyRatio)
        let expected = Decimal(110) / Decimal(150)
        #expect(abs(ratio - expected) < Decimal(string: "0.0001")!)
    }

    /// 정격거리 소모가 한 달도 없으면(분모 0) nil이다 — 0으로 나누지 않는다.
    @Test func 정격_소모가_없으면_종합_효율도_nil이다() async {
        let mock = MockAPIClient()
        stub(mock, Self.response(monthly: [
            Self.month("2026-06", distanceKm: 100),
        ]))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.overallEfficiencyRatio == nil)
    }

    // MARK: - 분포(요일·속도)

    /// 월요일 52번에 612km면 11.77km.
    @Test func 요일별_평균은_그_요일이_몇_번_있었나로_나눈다() {
        let value = VehicleMath.avgPerOccurrence(total: 612, occurrences: 52)
        let unwrapped = try! #require(value)
        #expect(abs(unwrapped - Decimal(string: "11.769")!) < Decimal(string: "0.01")!)
    }

    @Test func 그_요일이_한_번도_없으면_nil이다() {
        #expect(VehicleMath.avgPerOccurrence(total: 0, occurrences: 0) == nil)
    }

    /// **이 차트가 하루 밀리는 것이 이 태스크의 가장 큰 위험이다.** 같은 응답의
    /// `driveTimes`는 0=일요일인데 `weekday`는 1=월요일이다.
    @Test func 요일_라벨이_ISO_규약을_따른다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        // 스텁의 weekday는 1...7이 월~일 순서다.
        #expect(viewModel.weekdayDistancePoints.map(\.label)
                == ["월", "화", "수", "목", "금", "토", "일"])
    }

    /// #7은 버킷 건수를 그대로 점으로 옮긴다 — 나눗셈이 없다.
    @Test func 최고속도_분포는_버킷_건수를_그대로_점으로_옮긴다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        let point = try! #require(viewModel.speedPoints.first)
        #expect(point.id == "sp120")
        #expect(point.label == "120+")
        #expect(point.value == 3)
    }

    /// #8은 정격거리 소모를 kWh로 환산해 나눈다 — `VehicleMath.kmPerKwh`와 같은 식이다.
    /// 스텁: 302km, 정격 소모 410km, 계수 0.168kWh/km → 소비 68.88kWh →
    /// 302÷68.88 = 4.384436...km/kWh(직접 검산).
    @Test func 속도별_전비는_정격거리_소모를_kWh로_환산해_나눈다() async {
        let mock = MockAPIClient()
        InsightsStub.stub(mock, InsightsStub.response(monthlyCount: 1))
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))
        await viewModel.load()
        let point = try! #require(viewModel.speedEfficiencyPoints.first)
        #expect(point.id == "se0")
        let value = try! #require(point.value)
        #expect(abs(value - Decimal(string: "4.3844")!) < Decimal(string: "0.001")!)
    }
}
