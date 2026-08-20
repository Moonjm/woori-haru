import Foundation
import Observation

/// 통계 탭 — `/tesla/drive-insights` 하나만 본다. 네 카드가 한 응답에서 나오므로
/// 호출도 하나이고, **기간 칩이 바뀌면 넷이 함께 바뀐다.**
@MainActor
@Observable
final class VehicleStatsViewModel {

    private(set) var insights: DriveInsightsResponse? {
        didSet { rebuildHeatMap() }
    }
    private(set) var isLoading = false
    private(set) var period: DrivePeriod = .twelveMonths
    var errorMessage: String?

    /// **기간 칩을 따르지 않는다** — 늘 이번 달 기준 12개월이다.
    /// 충전 탭의 `VehicleSummaryViewModel`과 같은 엔드포인트를 보지만 창이 달라 따로 받는다.
    private(set) var trend: [VehiclePeriod] = []

    private let service: VehicleService
    /// 겹친 요청 중 최신 것만 결과를 반영한다.
    private var generation = 0

    init(service: VehicleService = VehicleService()) {
        self.service = service
    }

    // MARK: - 파생 값

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

    /// **지오펜스가 하나도 없는 것이 이 차량의 기본 상태다**(`geofences` 0행).
    /// 「가끔 비는 경우」로 다루면 안 되고, 등록하기 전까지 이 카드는 늘 감춰진다.
    var showsPlaces: Bool { !(insights?.places.isEmpty ?? true) }

    /// 셋 다 없으면 서버가 아직 이 필드를 내지 않는 것이다. 하나라도 있으면 그린다 —
    /// 「총거리 0km」는 값이 없는 것이 아니라 **안 탔다는 사실**이다.
    var showsStats: Bool {
        guard let insights else { return false }
        return insights.maxSpeedKmh != nil
            || insights.totalDistanceKm != nil
            || insights.recordedMonths != nil
    }

    /// **뷰가 아니라 여기서 나눈다.** 뷰에서 다시 계산하면 테스트하는 값과 화면에 나오는 값이
    /// 서로 다른 코드가 된다 — 3단계에서 같은 함정을 두 번 밟았다.
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

    // MARK: - 파생 값(추이)

    var hasTrend: Bool { !trend.isEmpty }

    private func points(_ value: (VehiclePeriod) -> Decimal?) -> [ChartPoint] {
        trend.map { ChartPoint(id: $0.yearMonth, label: "\($0.monthNumber)", value: value($0)) }
    }

    var distancePoints: [ChartPoint] { points(\.distanceKm) }
    var driveCountPoints: [ChartPoint] { points { $0.driveCount.map { Decimal($0) } } }
    var drivingMinPoints: [ChartPoint] { points { $0.drivingMin.map { Decimal($0) } } }
    var energyPoints: [ChartPoint] { points(\.energyAddedKwh) }
    var costPoints: [ChartPoint] { points(\.cost) }
    var chargeCountPoints: [ChartPoint] { points { $0.chargeCount.map { Decimal($0) } } }
    var efficiencyPoints: [ChartPoint] { points(\.efficiency) }

    /// **누적은 뷰가 아니라 여기서 낸다.** 뷰에서 다시 더하면 테스트하는 값과 화면 값이 갈린다.
    var cumulativeDistancePoints: [ChartPoint] {
        let totals = VehicleMath.runningTotals(trend.map(\.distanceKm))
        return zip(trend, totals).map { period, total in
            ChartPoint(id: period.yearMonth, label: "\(period.monthNumber)", value: total)
        }
    }

    var cumulativeCostPoints: [ChartPoint] {
        let totals = VehicleMath.runningTotals(trend.map(\.cost))
        return zip(trend, totals).map { period, total in
            ChartPoint(id: period.yearMonth, label: "\(period.monthNumber)", value: total)
        }
    }

    // MARK: - 로드

    /// 탭에 들어올 때마다 부른다. **단, 지난번이 오류로 끝났다면 다시 받는다** —
    /// 그러지 않으면 실패한 채로 탭을 나갔다 돌아와도 빨간 배너가 영영 그대로 남는다.
    /// (`VehicleHealthViewModel.load()`와 같은 규칙이다.)
    func load() async {
        guard insights == nil || errorMessage != nil else { return }
        await fetch(period, isPeriodChange: false, fetchTrend: true)
    }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다** — 1단계 건강 화면과 같은 규칙이다.
    func reload() async {
        await fetch(period, isPeriodChange: false, fetchTrend: true)
    }

    /// 기간 칩. **성공이든 실패든 옛 기간의 값을 곧장 지운다** — 칩은 3개월인데 화면이
    /// 12개월 값이면 그 순간만이라도 거짓말이 된다. 새로고침과 다르게 다뤄야 하는 유일한 자리다.
    ///
    /// **추이는 다시 받지 않는다** — 「이번 달 기준 12개월」은 기간 칩과 무관해 이미 있는
    /// 값 그대로다. 다시 받으면 칩을 누를 때마다 `/tesla/summary`를 불필요하게 또 부른다.
    func select(_ next: DrivePeriod) async {
        guard next != period else { return }
        period = next
        await fetch(next, isPeriodChange: true, fetchTrend: false)
    }

    /// `isPeriodChange`는 「기간이 바뀌어 옛 값을 이 요청 결과로 완전히 갈아치운다」는 뜻이다 —
    /// 「실패하면 지운다」가 아니다. 그래서 지우는 지점은 아래 한 곳, 응답을 기다리기 전뿐이다.
    ///
    /// `fetchTrend`가 참이면 주행 인사이트와 12개월 추이를 **병렬로** 받는다. 하나가 던져도
    /// 다른 하나는 산다 — 추이는 이번 달 기준으로 고정이라 기간 칩 변경(`select`)에는 딸려
    /// 보내지 않는다.
    private func fetch(_ months: DrivePeriod, isPeriodChange: Bool, fetchTrend: Bool) async {
        generation += 1
        let current = generation
        // 기간이 바뀌면 결과를 기다리지 않고 바로 옛 값을 지운다 — 칩과 화면이 한순간도
        // 어긋나면 안 되기 때문이다.
        if isPeriodChange { insights = nil }
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }

        async let insightsTask = service.fetchDriveInsights(months: months.rawValue)
        async let summaryTask: VehicleSummaryResponse? = fetchTrend
            ? (try? await service.fetchSummary(yearMonth: LedgerYearMonth.current().apiValue))
            : nil

        // **둘을 따로 잡는다** — 하나가 던져도 다른 하나는 산다.
        var loadedInsights: DriveInsightsResponse?
        var insightsError: (any Error)?
        do { loadedInsights = try await insightsTask } catch { insightsError = error }

        // 추이는 실패해도 배너를 세우지 않는다 — 주행 카드가 살아 있는데 빨간 줄이 서면
        // 「전부 못 받았다」로 읽힌다. 섹션이 조용히 빠질 뿐이다.
        // **실패해도 있던 값을 지우지 않는다**(당겨서 새로고침 관례).
        let loadedSummary = await summaryTask

        if insightsError is CancellationError { return }
        guard current == generation else { return }

        if let loadedInsights {
            insights = loadedInsights
            errorMessage = nil
        } else if insightsError != nil {
            errorMessage = "주행 인사이트를 불러오지 못했습니다."
        }
        if fetchTrend {
            trend = loadedSummary?.trend ?? trend
        }
    }
}
