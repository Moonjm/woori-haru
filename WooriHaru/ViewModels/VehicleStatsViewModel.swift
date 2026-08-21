import Foundation
import Observation

/// 통계 탭 — `/tesla/insights` **하나만** 본다. 화면의 카드가 전부 한 응답에서 나오므로
/// **기간 칩이 바뀌면 월별 차트까지 함께 바뀐다.**
///
/// **배터리 열화(`VehicleHealthViewModel`)와 급속/완속 도넛(`ChargeTotalsViewModel`)은
/// 여전히 다른 응답이다** — 둘 다 전 기간 집계라 기간 칩과 무관하다.
@MainActor
@Observable
final class VehicleStatsViewModel {

    private(set) var insights: InsightsResponse? {
        didSet { rebuildHeatMap() }
    }
    private(set) var isLoading = false
    private(set) var period: DrivePeriod = .twelveMonths
    var errorMessage: String?

    private let service: VehicleService
    /// 겹친 요청 중 최신 것만 결과를 반영한다.
    private var generation = 0

    init(service: VehicleService = VehicleService()) {
        self.service = service
    }

    // MARK: - 파생 값

    /// 오래된 달부터 이번 달까지. **기록이 없는 달도 자리를 지킨다** — 건너뛰면 x축이 어긋난다.
    /// **기간 칩을 따른다.**
    var monthly: [InsightsMonth] { insights?.monthly ?? [] }

    /// 거리 버킷 기준이다 — 시간대 카드와 같은 모수를 쓴다.
    var hasDrives: Bool { distanceDriveCount > 0 }

    /// `cars.efficiency`가 없으면 전비를 낼 수 없다. 카드를 감춘다.
    ///
    /// **계수가 있어도 행이 전부 비면 마찬가지로 감춘다.** 온도 버킷마다
    /// `ratedRangeUsedKm`이 0이면(아주 짧은 주행만 있는 기간 등) `temperatureRows`가
    /// 다섯 줄 다 「—」로 나온다 — 값이 하나도 없는 카드는 자리만 차지한다.
    var showsEfficiency: Bool {
        insights?.efficiencyKwhPerKm != nil && temperatureRows.contains { $0.kmPerKwh != nil }
    }

    /// #8 속도별 전비 카드 게이트. **`showsEfficiency`를 그대로 쓰지 않는다** — 그것은 온도
    /// 전용 판정(#9)이라 재료가 다르다. 모양은 같으니(계수 + 값 하나) 재료만
    /// `speedEfficiencyPoints`로 바꿔 쓴다.
    ///
    /// 게이트 없이 그리면 `cars.efficiency` 결측일 때 #9는 감춰지는데 #8만 빈 막대로
    /// 남아 두 카드가 다르게 반응한다.
    var showsSpeedEfficiency: Bool {
        insights?.efficiencyKwhPerKm != nil && speedEfficiencyPoints.contains { $0.value != nil }
    }

    /// #24 자주 가는 곳. **막대 길이는 건수다** — 서버가 건수 내림차순(`drive_count DESC,
    /// distance_km DESC, name`)으로 주므로, 거리로 길이를 정하면 짧은 막대가 위에 온다.
    var placeRows: [RankBarList.Row] {
        (insights?.places ?? []).map { place in
            RankBarList.Row(id: place.id, label: place.name,
                            value: Decimal(place.driveCount),
                            primary: DriveFormat.count(place.driveCount),
                            secondary: VehicleFormat.distance(place.distanceKm))
        }
    }

    /// #25 충전소별 비용 TOP. **막대 길이는 충전 횟수다**(서버 정렬 기준과 같다,
    /// `charge_count DESC, energy_added_kwh DESC, name`) — 금액으로 정하면 금액 미입력이
    /// 섞인 곳이 실제보다 짧게 나와 순위와 어긋난다. 금액은 `primary`에 문자열로만 싣는다.
    var chargerRows: [RankBarList.Row] {
        (insights?.chargers ?? []).map { charger in
            RankBarList.Row(
                id: charger.id, label: charger.name,
                value: Decimal(charger.chargeCount),
                primary: ChargeFormat.cost(charger.cost),
                secondary: ChargeFormat.energy(charger.energyAddedKwh),
                // 미입력이 섞이면 위 금액이 실제보다 적다 — 그 사실을 적어 순위가
                // 조용히 뒤집히지 않게 한다.
                note: charger.costMissingCount > 0
                      ? "\(charger.costMissingCount)건 금액 없음" : nil)
        }
    }

    /// 위치 섹션 게이트. 셋(`places`·`chargers`·`regions`)이 다 비면 헤더까지 감춘다.
    ///
    /// 서버는 지오펜스가 없으면 주소로 이름을 지어 채우므로, `places`가 비는 것은 「그 기간에
    /// 주행·충전이 없었다」뿐이다. **`regions`는 `cities`만 보지 않는다** — 역지오코딩이
    /// 시골길에서 `city`만 NULL이고 `state`·`country`는 채우는 행이 실제로 나온다.
    var showsPlaceSection: Bool {
        guard let insights else { return false }
        let regions = insights.regions
        return !insights.places.isEmpty || !insights.chargers.isEmpty
            || regions.cities > 0 || regions.states > 0 || regions.countries > 0
    }

    /// **뷰가 아니라 여기서 나눈다.** 뷰에서 다시 계산하면 테스트하는 값과 화면에 나오는 값이
    /// 서로 다른 코드가 된다.
    ///
    /// **`recordedMonths`는 0으로 올 수 있다**(주행이 하나도 없는 계정) — non-null이라고
    /// 「0이 안 온다」는 뜻은 아니므로, 0 분모 방어는 `VehicleMath` 쪽에 그대로 남는다.
    var avgMonthlyKm: Decimal? {
        VehicleMath.avgMonthlyDistanceKm(totalKm: insights?.totalDistanceKm,
                                         months: insights?.recordedMonths)
    }

    var avgYearlyKm: Decimal? {
        VehicleMath.avgYearlyDistanceKm(totalKm: insights?.totalDistanceKm,
                                        months: insights?.recordedMonths)
    }

    struct TemperatureRow: Identifiable {
        let bucket: TemperatureBucket
        /// 서버는 합만 낸다. 이 나눗셈이 앱 몫이다.
        let kmPerKwh: Decimal?

        var id: String { bucket.id }
    }

    var temperatureRows: [TemperatureRow] {
        let efficiency = insights?.efficiencyKwhPerKm
        return (insights?.temperatureBuckets ?? []).map { bucket in
            TemperatureRow(
                bucket: bucket,
                kmPerKwh: VehicleMath.kmPerKwh(
                    distanceKm: bucket.distanceKm,
                    ratedRangeUsedKm: bucket.ratedRangeUsedKm,
                    efficiencyKwhPerKm: efficiency
                )
            )
        }
    }

    /// **두 수가 다르다.** 온도 쪽은 주행가능거리 소모가 0 이하인 주행을 뺀 뒤 센다
    /// (실측 최근 12개월: 939 대 959). 한 곳에서 뽑아 두 카드에 쓰면 어긋난다.
    var temperatureDriveCount: Int {
        (insights?.temperatureBuckets ?? []).reduce(0) { $0 + $1.driveCount }
    }

    var distanceDriveCount: Int {
        (insights?.distanceBuckets ?? []).reduce(0) { $0 + $1.driveCount }
    }

    /// #22 거리 분포 도넛. **버킷 + 전체 대비 퍼센트**를 한 짝으로 묶는다 — 조각이 다섯
    /// 개라 각도만으로는 크기를 못 견주므로(`DonutChart` doc), 조각마다 글자로 퍼센트를
    /// 적어야 한다. 나눗셈은 `VehicleMath.ratio`로 여기서 낸다.
    struct DistanceSlice: Identifiable {
        let bucket: DistanceBucket
        /// 총 건수가 0이면 nil이다 — 화면은 그때 도넛 자체를 안 그린다(`hasDrives` 게이트).
        let percent: Decimal?

        var id: String { bucket.id }
    }

    var distanceSlices: [DistanceSlice] {
        let total = distanceDriveCount
        return (insights?.distanceBuckets ?? []).map { bucket in
            DistanceSlice(bucket: bucket,
                          percent: VehicleMath.ratio(Decimal(bucket.driveCount), Decimal(total)))
        }
    }

    /// 요일×시각 조회표. **응답을 받을 때 한 번만 편다.**
    ///
    /// 계산 속성으로 두면 히트맵이 한 번 그려질 때마다 168칸이 각자 딕셔너리를 새로 만든다 —
    /// 표본이 100칸만 돼도 draw 한 번에 1만 7천 번 도는 셈이다. 응답은 성기게 오므로
    /// (0인 칸은 빠진다) 저장 시점에 펴 두고 조회만 한다.
    private var heatMap: [Int: Int] = [:]
    private(set) var maxHeatCount = 0

    private func rebuildHeatMap() {
        let times = insights?.driveTimes ?? []
        // **`uniqueKeysWithValues`를 쓰지 않는다** — 서버가 같은 칸을 두 번 보내면 크래시한다.
        // 지금 SQL은 그러지 않지만, 서버 데이터로 앱이 죽는 길을 열어 둘 이유가 없다.
        heatMap = Dictionary(times.map { ($0.id, $0.count) }, uniquingKeysWith: +)
        maxHeatCount = heatMap.values.max() ?? 0
    }

    /// 없는 칸은 **0이다.** 「기록이 없다」가 아니라 「그 시각에 안 탔다」다.
    func heatCount(weekday: Int, hour: Int) -> Int { heatMap[weekday * 24 + hour] ?? 0 }

    // MARK: - 파생 값(월별)

    /// 주행 섹션 게이트. **행의 존재가 아니라 값의 존재를 본다** — 서버는 기록이 없는
    /// 달도 값이 전부 nil인 행으로 자리를 채워 보내므로(`InsightsMonth` 참고)
    /// `!monthly.isEmpty`는 「그 기간에 하나도 안 탔다」일 때도 참이다. 그것으로 게이트를
    /// 삼으면 「이 기간에 주행 기록이 없어요」 안내문 위아래로 빈 차트가 헤더까지 달고 선다.
    var hasDriveMonths: Bool {
        monthly.contains { $0.distanceKm != nil || $0.drivingMin != nil || $0.driveCount != nil }
    }

    /// 「🚗 주행」 헤더 게이트. **두 카드 묶음 중 하나라도 있으면 선다.**
    ///
    /// 월별 카드 넷은 `hasDriveMonths` 하나만 보고, `content`(온도별 전비·시간대 히트맵·
    /// 거리 분포)는 이 프로퍼티와 같은 OR을 본다 — 그래서 헤더와 `content`는 늘 함께 서고
    /// 빠진다. **`hasDrives`(`end_date`)와 `hasDriveMonths`(`start_date`)는 합치지 않는다**
    /// — 기간 경계를 걸친 주행 하나만 있으면 `hasDrives=true`·`hasDriveMonths=false`가
    /// 나오는데, 헤더를 `hasDriveMonths` 하나로만 걸면 `content`가 헤더 없이 뜬다.
    var showsDriveSection: Bool { hasDrives || hasDriveMonths }

    /// 충전 섹션 게이트. **주행과 따로 본다** — 충전은 주행 없이도 한다. 하나로 묶으면
    /// 안 타고 충전만 한 기간에 충전 카드까지 사라진다.
    var hasChargeMonths: Bool {
        monthly.contains { $0.cost != nil || $0.energyAddedKwh != nil || $0.chargeCount != nil }
    }

    /// 「응답을 받았는가」 하나만 말한다. **내용 게이트 둘과 다르다** — 값이 하나도 없는
    /// 응답도 받은 것은 받은 것이다.
    var hasLoadedInsights: Bool { insights != nil }

    /// 주차 섹션 게이트. **행의 존재를 그대로 쓴다** — `idleMin`이 애초에 non-null이라
    /// 행이 있으면 값도 있다(위 둘처럼 필드값을 따로 볼 필요가 없다). `hasLoadedInsights`를
    /// 쓰지 않는 것은, `monthly`가 정말 빈 배열일 때 그것까지 참이면 내용 없는 헤더만
    /// 서기 때문이다.
    var hasParkMonths: Bool { !monthly.isEmpty }

    private func points(_ value: (InsightsMonth) -> Decimal?) -> [ChartPoint] {
        monthly.map {
            ChartPoint(id: $0.yearMonth, label: MonthLabel.axis($0.yearMonth), value: value($0))
        }
    }

    var distancePoints: [ChartPoint] { points(\.distanceKm) }
    var driveCountPoints: [ChartPoint] { points { $0.driveCount.map { Decimal($0) } } }
    var drivingMinPoints: [ChartPoint] { points { $0.drivingMin.map { Decimal($0) } } }
    var energyPoints: [ChartPoint] { points(\.energyAddedKwh) }
    var costPoints: [ChartPoint] { points(\.cost) }
    var chargeCountPoints: [ChartPoint] { points { $0.chargeCount.map { Decimal($0) } } }

    /// #12 월별 충전 시간(분). **막대 값은 분 그대로 둔다** — `drivingMinPoints`와 같은 이유다.
    /// 막대 높이는 비율이라 단위가 무엇이든 그림이 같아, 60으로 나눠 시간 단위로 바꿔도
    /// 얻는 것이 없다. 시·분 표기는 콜아웃에서 `ChargeFormat.duration(_:)`이 맡는다.
    var chargingMinPoints: [ChartPoint] { points { $0.chargingMin.map { Decimal($0) } } }

    /// 전비(km/kWh). `InsightsMonth`에 계산 속성이 없어 여기서 낸다. 분모는
    /// 충전량(`energyAddedKwh`)이다.
    ///
    /// **선의 공식은 고정이다** — 정격거리 기반으로 바꾸지 않는다(`vehicle-insights-tabs-design.md:190`).
    /// 정격 대비 비율은 `overallEfficiencyRatio`로 카드 머리에 한 줄만 얹는다.
    var efficiencyPoints: [ChartPoint] {
        points { VehicleMath.kmPerKwh(energyAddedKwh: $0.energyAddedKwh, distanceKm: $0.distanceKm) }
    }

    /// 기간 전체의 정격 대비 실주행. **합끼리 나눈다** — 월별 비율의 평균은 짧은 달을
    /// 과대평가한다(주행이 사흘뿐인 달의 100% 비율이 꽉 찬 달과 같은 무게를 갖는다).
    /// 개요 누적 타일에서 옮겨온 자리다.
    var overallEfficiencyRatio: Decimal? {
        let distance = monthly.compactMap(\.distanceKm).reduce(0, +)
        let rated = monthly.compactMap(\.ratedRangeUsedKm).reduce(0, +)
        guard distance > 0, rated > 0 else { return nil }
        return distance / rated
    }

    /// **누적은 뷰가 아니라 여기서 낸다.** 뷰에서 다시 더하면 테스트하는 값과 화면 값이 갈린다.
    var cumulativeDistancePoints: [ChartPoint] {
        let totals = VehicleMath.runningTotals(monthly.map(\.distanceKm))
        return zip(monthly, totals).map { month, total in
            ChartPoint(id: month.yearMonth, label: MonthLabel.axis(month.yearMonth), value: total)
        }
    }

    var cumulativeCostPoints: [ChartPoint] {
        let totals = VehicleMath.runningTotals(monthly.map(\.cost))
        return zip(monthly, totals).map { month, total in
            ChartPoint(id: month.yearMonth, label: MonthLabel.axis(month.yearMonth), value: total)
        }
    }

    /// #19 월별 정지 시간(분). **`idleMin`은 non-null이다** — 다른 월별 계열(거리·비용·
    /// 횟수…)과 반대로 기록이 없는 달일수록 값이 크다. 기록이 없다는 것 자체가 「그 달
    /// 내내 서 있었다」는 뜻이라, 빈 달은 44640분(31일)까지도 나온다. 여기서 nil로
    /// 바꾸거나 0으로 뭉개면 이 계약이 사라진다.
    var idleMinPoints: [ChartPoint] {
        monthly.map {
            ChartPoint(id: $0.yearMonth, label: MonthLabel.axis($0.yearMonth), value: Decimal($0.idleMin))
        }
    }

    /// #21 월별 대기 중 소모(팬텀 드레인, rated km). **표본이 0이면 nil이다** —
    /// `parkDrainSamples == 0`은 「안 샜다」가 아니라 「그 달에 잴 구간이 없었다」다.
    ///
    /// **음수를 0으로 자르지 않는다** — 충전 기록 없이 정격거리가 늘어난 구간이 부호 그대로
    /// 섞여 있다(BMS 재보정 등, 실측 3,960:628). 스펙이 음수 구간을 명시하므로, 이 카드는
    /// `ChartScale.ratio`(음수를 0으로 자르는)를 쓰는 `MonthlyBarChart` 대신 부호를 보존하는
    /// `DivergingMonthlyBarChart`로 그린다.
    var parkDrainPoints: [ChartPoint] {
        monthly.map { month in
            ChartPoint(id: month.yearMonth, label: MonthLabel.axis(month.yearMonth),
                       value: month.parkDrainSamples > 0 ? month.parkDrainRatedKm : nil)
        }
    }

    // MARK: - 파생 값(분포)

    /// #4 요일별 평균 주행거리. **`isoWeekdayLabel`을 쓴다** — 이 배열만 1=월요일이고
    /// 같은 응답의 `driveTimes`·`chargeTimes`는 0=일요일이다. 섞으면 차트가 하루씩 밀린다.
    var weekdayDistancePoints: [ChartPoint] {
        (insights?.weekday ?? []).map { day in
            ChartPoint(id: "wd\(day.weekday)",
                       label: DriveFormat.isoWeekdayLabel(day.weekday),
                       value: VehicleMath.avgPerOccurrence(total: day.distanceKm,
                                                            occurrences: day.occurrences))
        }
    }

    /// #20 요일별 정지 시간(분). **`isoWeekdayLabel`을 쓴다**(1=월요일) — 이 응답의
    /// `weekday` 배열 전용 규약이고, 같은 응답의 `driveTimes`·`chargeTimes`(0=일요일)와
    /// 반대다. `weekdayDistancePoints`(#4)와 같은 쪽이니 헷갈리면 그쪽을 본다.
    var weekdayIdlePoints: [ChartPoint] {
        (insights?.weekday ?? []).map { day in
            ChartPoint(id: "wi\(day.weekday)", label: DriveFormat.isoWeekdayLabel(day.weekday),
                       value: Decimal(day.idleMin))
        }
    }

    /// #7 최고속도 분포. 주행 **한 건의 최고** 속도라 #8과 모집단이 다르다.
    var speedPoints: [ChartPoint] {
        (insights?.speedBuckets ?? []).map {
            ChartPoint(id: "sp\($0.fromKmh)", label: $0.label, value: Decimal($0.driveCount))
        }
    }

    /// #8 속도별 전비. **`driveCount`가 없는 배열이다** — `ΔratedRange > 0`인 주행만 들어
    /// #7과 모집단이 다르므로, 카드 콜아웃에 「N회 기준」을 적지 않는다.
    var speedEfficiencyPoints: [ChartPoint] {
        (insights?.speedEnergyBuckets ?? []).map { bucket in
            ChartPoint(id: "se\(bucket.fromKmh)", label: bucket.label,
                       value: VehicleMath.kmPerKwh(distanceKm: bucket.distanceKm,
                                                    ratedRangeUsedKm: bucket.ratedRangeUsedKm,
                                                    efficiencyKwhPerKm: insights?.efficiencyKwhPerKm))
        }
    }

    /// #15 충전 히트맵. **`chargeTimes`는 0=일요일이다** — `driveTimes`와 같고 `weekday`
    /// 배열(1=월요일, ISO)과 다르다. `HeatmapGrid`는 `weekdayLabel`(0=일요일)을 쓰므로
    /// `isoWeekdayLabel`로 바꾸면 안 된다.
    ///
    /// 없는 칸이 서버에서 아예 빠지므로 매번 선형 탐색한다 — `driveTimes`용 `heatMap` 사전을
    /// 따로 둘 만큼 크지 않다(충전은 주행보다 훨씬 드물다).
    func chargeHeatCount(weekday: Int, hour: Int) -> Int {
        insights?.chargeTimes.first { $0.weekday == weekday && $0.hour == hour }?.count ?? 0
    }

    var maxChargeHeatCount: Int { insights?.chargeTimes.map(\.count).max() ?? 0 }

    /// 충전 히트맵 콜아웃의 총합. **뷰가 아니라 여기서 더한다** — 주행 쪽
    /// (`distanceDriveCount`)과 같은 관례다. 뷰에서 다시 더하면 두 히트맵이 서로 다른
    /// 방식으로 같은 일을 하게 된다.
    var totalChargeHeatCount: Int { (insights?.chargeTimes ?? []).reduce(0) { $0 + $1.count } }

    /// #16 충전 시작 SoC 분포. 열 칸이 늘 오고 0인 칸도 자리를 지킨다.
    var chargeStartLevelPoints: [ChartPoint] {
        (insights?.chargeStartLevels ?? []).map {
            ChartPoint(id: "cs\($0.fromPct)", label: $0.label, value: Decimal($0.count))
        }
    }

    /// #17 충전 종료 SoC 분포. **마지막 칸만 양끝이 닫혀 있다**(90 이상 100 이하) —
    /// 정확히 100%로 끝난 충전이 실측 71건이라 「미만」이면 가장 흔한 값이 어느 칸에도
    /// 안 든다. 그 칸만 라벨을 「90~100」으로 적어 다른 칸(「미만」)과 다름을 글자로 드러낸다.
    var chargeEndLevelPoints: [ChartPoint] {
        let buckets = insights?.chargeEndLevels ?? []
        return buckets.enumerated().map { index, bucket in
            let isLast = index == buckets.count - 1
            return ChartPoint(id: "ce\(bucket.fromPct)",
                              label: isLast ? "\(bucket.fromPct)~\(bucket.toPct)" : bucket.label,
                              value: Decimal(bucket.count))
        }
    }

    // MARK: - 로드

    /// 탭에 들어올 때마다 부른다. **단, 지난번이 오류로 끝났다면 다시 받는다** —
    /// 그러지 않으면 실패한 채로 탭을 나갔다 돌아와도 빨간 배너가 영영 그대로 남는다.
    /// (`VehicleHealthViewModel.load()`와 같은 규칙이다.)
    func load() async {
        guard insights == nil || errorMessage != nil else { return }
        await fetch(period, isPeriodChange: false)
    }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다** — `VehicleHealthViewModel`과 같은 규칙이다.
    func reload() async {
        await fetch(period, isPeriodChange: false)
    }

    /// 기간 칩. **성공이든 실패든 옛 기간의 값을 곧장 지운다** — 칩은 3개월인데 화면이
    /// 12개월 값이면 그 순간만이라도 거짓말이 된다. 새로고침과 다르게 다뤄야 하는 유일한 자리다.
    ///
    /// **`.all`의 rawValue 0을 그대로 보낸다** — 「전체」라고 파라미터를 빼면 서버가 기본값
    /// 12로 답해 조용히 12개월만 나온다.
    func select(_ next: DrivePeriod) async {
        guard next != period else { return }
        period = next
        await fetch(next, isPeriodChange: true)
    }

    /// `isPeriodChange`는 「기간이 바뀌어 옛 값을 이 요청 결과로 완전히 갈아치운다」는 뜻이다 —
    /// 「실패하면 지운다」가 아니다. 그래서 지우는 지점은 아래 한 곳, 응답을 기다리기 전뿐이다.
    private func fetch(_ months: DrivePeriod, isPeriodChange: Bool) async {
        generation += 1
        let current = generation
        // 기간이 바뀌면 결과를 기다리지 않고 바로 옛 값을 지운다 — 칩과 화면이 한순간도
        // 어긋나면 안 되기 때문이다.
        if isPeriodChange { insights = nil }
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }

        var loaded: InsightsResponse?
        var failure: (any Error)?
        do { loaded = try await service.fetchInsights(months: months.rawValue) }
        catch { failure = error }

        if failure is CancellationError { return }
        guard current == generation else { return }

        if let loaded {
            insights = loaded
            errorMessage = nil
        } else {
            errorMessage = "주행 인사이트를 불러오지 못했습니다."
        }
    }
}
