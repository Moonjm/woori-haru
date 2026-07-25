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
    /// 레인 길이(m). 수영장 기록에만 들어온다.
    let laneLengthMeters: Double?
    /// 레인 한 바퀴 단위 기록. 개방 수역이거나 워치가 랩을 남기지 않았으면 비어 있다.
    let laps: [SwimLap]
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

    /// "수영장 · 25m" 처럼 장소와 레인 길이를 합친 부제
    var locationText: String {
        guard let laneLengthMeters, laneLengthMeters > 0 else { return location.label }
        return "\(location.label) · \(Self.decimalText(laneLengthMeters.rounded()))m 레인"
    }
}
