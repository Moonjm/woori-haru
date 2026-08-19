import Foundation
import Observation

/// 주행 탭 — `/tesla/drive-insights` 하나만 본다. 네 카드가 한 응답에서 나오므로
/// 호출도 하나이고, **기간 칩이 바뀌면 넷이 함께 바뀐다.**
@MainActor
@Observable
final class VehicleDriveViewModel {

    private(set) var insights: DriveInsightsResponse? {
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

    /// 거리 버킷 기준이다 — 시간대 카드와 같은 모수를 쓴다.
    var hasDrives: Bool { distanceDriveCount > 0 }

    /// `cars.efficiency`가 없으면 전비를 낼 수 없다. 카드를 감춘다.
    var showsEfficiency: Bool { insights?.efficiencyKwhPerKm != nil }

    /// **지오펜스가 하나도 없는 것이 이 차량의 기본 상태다**(`geofences` 0행).
    /// 「가끔 비는 경우」로 다루면 안 되고, 등록하기 전까지 이 카드는 늘 감춰진다.
    var showsPlaces: Bool { !(insights?.places.isEmpty ?? true) }

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

    // MARK: - 로드

    func load() async {
        guard insights == nil else { return }
        await fetch(period, clearingOnFailure: false)
    }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다** — 1단계 건강 화면과 같은 규칙이다.
    func reload() async {
        await fetch(period, clearingOnFailure: false)
    }

    /// 기간 칩. **실패하면 옛 기간의 값을 지운다** — 칩은 3개월인데 화면이 12개월 값이면
    /// 거짓말이 된다. 새로고침 실패와 다르게 다뤄야 하는 유일한 자리다.
    func select(_ next: DrivePeriod) async {
        guard next != period else { return }
        period = next
        await fetch(next, clearingOnFailure: true)
    }

    private func fetch(_ months: DrivePeriod, clearingOnFailure: Bool) async {
        generation += 1
        let current = generation
        if clearingOnFailure { insights = nil }
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let loaded = try await service.fetchDriveInsights(months: months.rawValue)
            guard current == generation else { return }
            insights = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            if clearingOnFailure { insights = nil }
            errorMessage = "주행 인사이트를 불러오지 못했습니다."
        }
    }
}
