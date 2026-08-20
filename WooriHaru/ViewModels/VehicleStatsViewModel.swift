import Foundation
import Observation

/// 통계 탭 — `/tesla/insights` **하나만** 본다. 화면의 카드가 전부 한 응답에서 나오므로
/// **기간 칩이 바뀌면 월별 차트까지 함께 바뀐다.**
///
/// 1단계에서는 `/tesla/drive-insights`와 `/tesla/summary`를 병렬로 받았다 — 후자는 오직
/// 「이번 달 기준 12개월」 추이 때문이었고, 그래서 기간 칩이 월별 차트에 먹지 않았다.
/// 이제 `monthly`가 그 자리를 채운다.
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
    ///
    /// **기간 칩을 따른다.** 1단계의 `trend`가 12개월 고정이었던 것과 다른 점이고,
    /// 이 화면에서 칩이 실제로 먹는다는 사실이 여기서 나온다.
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

    /// **지오펜스가 하나도 없는 것이 이 차량의 기본 상태다**(`geofences` 0행).
    /// 「가끔 비는 경우」로 다루면 안 되고, 등록하기 전까지 이 카드는 늘 감춰진다.
    var showsPlaces: Bool { !(insights?.places.isEmpty ?? true) }

    /// **뷰가 아니라 여기서 나눈다.** 뷰에서 다시 계산하면 테스트하는 값과 화면에 나오는 값이
    /// 서로 다른 코드가 된다 — 3단계에서 같은 함정을 두 번 밟았다.
    ///
    /// **`recordedMonths`가 0으로 올 수 있다**(주행이 하나도 없는 계정). 새 계약에서
    /// non-null이 된 것은 「없음」이 사라졌다는 뜻이지 「0이 안 온다」가 아니므로,
    /// 0 분모 방어는 `VehicleMath` 쪽에 그대로 남는다.
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

    // MARK: - 파생 값(월별)

    /// 월별 차트를 그릴 수 있는가. **`insights != nil`과 다르다** — 응답은 받았는데
    /// 기록이 하나도 없어 `monthly`가 빈 배열로 오는 길이 따로 있다.
    var hasMonthly: Bool { !monthly.isEmpty }

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

    /// 전비(km/kWh). **`VehiclePeriod.efficiency`가 하던 계산을 여기로 옮겼다** —
    /// `InsightsMonth`에는 그 계산 속성이 없다. 분모는 1단계와 같은 충전량이다.
    var efficiencyPoints: [ChartPoint] {
        points { VehicleMath.kmPerKwh(energyAddedKwh: $0.energyAddedKwh, distanceKm: $0.distanceKm) }
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

    // MARK: - 로드

    /// 탭에 들어올 때마다 부른다. **단, 지난번이 오류로 끝났다면 다시 받는다** —
    /// 그러지 않으면 실패한 채로 탭을 나갔다 돌아와도 빨간 배너가 영영 그대로 남는다.
    /// (`VehicleHealthViewModel.load()`와 같은 규칙이다.)
    func load() async {
        guard insights == nil || errorMessage != nil else { return }
        await fetch(period, isPeriodChange: false)
    }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다** — 1단계 건강 화면과 같은 규칙이다.
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
