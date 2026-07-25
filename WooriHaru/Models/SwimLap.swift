import Foundation

/// 수영장 레인 한 바퀴(lap) 기록. 애플워치가 턴할 때마다 남긴다.
struct SwimLap: Identifiable, Hashable {
    /// 워크아웃 내 0-based 순번
    let id: Int
    let startDate: Date
    let duration: TimeInterval
    /// 레인 길이. 워크아웃 metadata의 lap length를 그대로 쓴다.
    let distanceMeters: Double
    let strokeStyle: SwimStrokeStyle
}

enum SwimStrokeStyle: Int, Hashable {
    case unknown = 0
    case mixed = 1
    case freestyle = 2
    case backstroke = 3
    case breaststroke = 4
    case butterfly = 5
    case kickboard = 6

    var label: String {
        switch self {
        case .unknown: "기타"
        case .mixed: "혼영"
        case .freestyle: "자유형"
        case .backstroke: "배영"
        case .breaststroke: "평영"
        case .butterfly: "접영"
        case .kickboard: "킥판"
        }
    }
}

/// 50m·100m처럼 일정 거리 단위로 묶은 구간 기록
struct SwimSplit: Identifiable, Hashable {
    let id: Int
    /// 구간이 끝나는 시점의 누적 거리
    let cumulativeMeters: Double
    /// 이 구간의 실제 거리. 마지막 구간은 단위 거리보다 짧을 수 있다.
    let distanceMeters: Double
    let duration: TimeInterval
    let strokeStyle: SwimStrokeStyle

    /// 100m 환산 페이스(초)
    var pacePer100m: TimeInterval {
        guard distanceMeters > 0 else { return 0 }
        return duration / distanceMeters * 100
    }
}

// MARK: - Splitting

extension SwimWorkout {
    /// 사용 가능한 구간 단위. 레인 길이로 나누어떨어지는 것만 노출한다.
    /// (25m 레인이면 50·100 모두, 33m 레인이면 어느 쪽도 딱 떨어지지 않아 빈 배열)
    static let splitOptions: [Double] = [50, 100]

    var hasLapData: Bool { !laps.isEmpty }

    /// `unit` 미터마다 랩을 묶어 구간 기록을 만든다.
    /// 랩 거리가 단위에 딱 떨어지지 않으면 단위를 넘어서는 순간 구간을 끊는다.
    func splits(every unit: Double) -> [SwimSplit] {
        guard unit > 0, !laps.isEmpty else { return [] }

        var result: [SwimSplit] = []
        var cumulative: Double = 0
        var bucketDistance: Double = 0
        var bucketDuration: TimeInterval = 0
        var bucketStrokes: [SwimStrokeStyle] = []

        func flush() {
            guard bucketDistance > 0 else { return }
            result.append(SwimSplit(
                id: result.count,
                cumulativeMeters: cumulative,
                distanceMeters: bucketDistance,
                duration: bucketDuration,
                strokeStyle: Self.dominantStroke(bucketStrokes)
            ))
            bucketDistance = 0
            bucketDuration = 0
            bucketStrokes = []
        }

        for lap in laps {
            cumulative += lap.distanceMeters
            bucketDistance += lap.distanceMeters
            bucketDuration += lap.duration
            bucketStrokes.append(lap.strokeStyle)
            if bucketDistance >= unit { flush() }
        }
        flush() // 단위에 못 미치고 남은 마지막 구간

        return result
    }

    /// 구간 안에서 가장 많이 쓰인 영법. 종류가 섞이면 혼영으로 본다.
    private static func dominantStroke(_ strokes: [SwimStrokeStyle]) -> SwimStrokeStyle {
        let meaningful = strokes.filter { $0 != .unknown }
        guard let first = meaningful.first else { return .unknown }
        guard meaningful.allSatisfy({ $0 == first }) else { return .mixed }
        return first
    }
}

// MARK: - Display Text

extension SwimSplit {
    /// "1:52" 형태. 1시간을 넘으면 "1:02:03"
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var distanceText: String { "\(Int(cumulativeMeters.rounded()))m" }
    var durationText: String { Self.clockText(duration) }
    var paceText: String { "\(Self.clockText(pacePer100m))/100m" }
}
