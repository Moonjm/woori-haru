import Foundation

/// 건강 앱(애플워치 운동)에서 읽어온 수영 기록 1건.
/// HealthKit 타입과 분리해 뷰·테스트가 HealthKit 없이도 동작하게 한다.
struct SwimWorkout: Identifiable, Hashable {
    enum Location: Hashable {
        case pool
        case openWater
        case unknown

        var label: String {
            switch self {
            case .pool: "수영장"
            case .openWater: "개방 수역"
            case .unknown: "수영"
            }
        }

        var iconName: String {
            switch self {
            case .pool: "figure.pool.swim"
            case .openWater: "figure.open.water.swim"
            case .unknown: "figure.pool.swim"
            }
        }
    }

    let id: UUID
    let startDate: Date
    let endDate: Date
    /// 일시정지를 제외한 실제 운동 시간(초)
    let duration: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let strokeCount: Int?
    let location: Location
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    /// 레인 길이(m). 수영장 기록에만 들어온다.
    let laneLengthMeters: Double?
    /// 레인 한 바퀴 단위 기록. 개방 수역이거나 워치가 랩을 남기지 않았으면 비어 있다.
    let laps: [SwimLap]
}

/// 워크아웃에 딸린 심박수 통계. **`HKWorkout.statistics(for:)`로는 못 얻는 기록이 있어**
/// 상세 화면이 별도 질의로 읽는다 — 심박수는 워크아웃 집계 통계가 아니라 워크아웃에 묶인
/// 샘플로 저장되는 경우가 있고, 그때 목록 매핑에서는 `nil`로 온다.
struct SwimHeartRate: Equatable, Sendable {
    let averageBpm: Double?
    let maxBpm: Double?

    var isEmpty: Bool { averageBpm == nil && maxBpm == nil }
}

// MARK: - Display Text

extension SwimWorkout {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 (E)"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm"
        return f
    }()

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static func decimalText(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    var dayText: String { Self.dayFormatter.string(from: startDate) }

    var timeRangeText: String {
        "\(Self.timeFormatter.string(from: startDate)) ~ \(Self.timeFormatter.string(from: endDate))"
    }

    var durationText: String { Int(duration).durationText }

    /// 1km 이상은 km, 미만은 m로 보여준다. 거리가 없으면 nil.
    var distanceText: String? {
        guard let distanceMeters, distanceMeters > 0 else { return nil }
        if distanceMeters >= 1000 {
            return String(format: "%.2fkm", distanceMeters / 1000)
        }
        return "\(Self.decimalText(distanceMeters.rounded()))m"
    }

    var energyText: String? {
        guard let activeEnergyKcal, activeEnergyKcal > 0 else { return nil }
        return "\(Self.decimalText(activeEnergyKcal.rounded()))kcal"
    }

    var strokeText: String? {
        guard let strokeCount, strokeCount > 0 else { return nil }
        return "\(Self.decimalText(Double(strokeCount)))회"
    }

    static func bpmText(_ bpm: Double?) -> String? {
        guard let bpm, bpm > 0 else { return nil }
        return "\(Int(bpm.rounded()))bpm"
    }

    var averageHeartRateText: String? { Self.bpmText(averageHeartRate) }
    var maxHeartRateText: String? { Self.bpmText(maxHeartRate) }

    /// 상세 화면이 보여줄 심박수. **워크아웃 자체 통계가 우선이고**, 비어 있을 때만 따로
    /// 읽어 온 값을 쓴다 — `HKWorkout.statistics(for:)`가 심박수를 안 담고 오는 기록이 있어
    /// 상세 화면이 별도 질의로 메운다(`SwimWorkoutFetching.fetchHeartRate`).
    func heartRateTexts(fallback: SwimHeartRate?) -> (average: String?, maximum: String?) {
        (
            averageHeartRateText ?? Self.bpmText(fallback?.averageBpm),
            maxHeartRateText ?? Self.bpmText(fallback?.maxBpm)
        )
    }

    /// "수영장 · 25m" 처럼 장소와 레인 길이를 합친 부제
    var locationText: String {
        guard let laneLengthMeters, laneLengthMeters > 0 else { return location.label }
        return "\(location.label) · \(Self.decimalText(laneLengthMeters.rounded()))m 레인"
    }

    /// 잘못 시작한 기록. 거리도 스트로크도 없을 때만 해당한다 — 헤엄친 흔적이 하나도
    /// 안 남은 것이라 카드에 채울 것이 「-」뿐이다.
    ///
    /// **둘 다 없기를 요구해야** 정상 기록이 안 사라진다. 거리를 못 잡은 개방 수역
    /// 기록에도 스트로크는 남고, 짧은 스프린트 한 판에도 거리가 남는다.
    ///
    /// 시간과 칼로리는 보지 않는다. 잘못 시작한 것을 몇 분 뒤에 끄기도 하고, 그 몇 분에
    /// 워치가 몇 kcal를 적어 넣기 때문에 둘 다 「실제로 헤엄쳤는가」를 못 가른다.
    var isEmptyRecord: Bool {
        (distanceMeters ?? 0) <= 0 && (strokeCount ?? 0) <= 0
    }
}
