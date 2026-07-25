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

extension SwimLap {
    /// 랩 이벤트 하나의 원본 값. HealthKit 타입에 묶이지 않게 떼어 둔다.
    struct Event {
        let start: Date
        let duration: TimeInterval
        let stroke: SwimStrokeStyle
    }

    /// 랩 이벤트를 SwimLap 배열로 만든다.
    ///
    /// 길이 0인 마커가 하나라도 섞여 있으면 아무것도 만들지 않는다. 마커만으로는
    /// 헤엄친 시간과 벽에서 쉰 시간을 나눌 수 없고, 다음 마커까지를 소요 시간으로
    /// 메우면 랩 사이 공백이 전부 0이 되어 세트가 하나로 뭉개진다.
    /// 틀린 기록을 보여주느니 세트를 접는 편이 낫다.
    static func build(from events: [Event], lapLength: Double) -> [SwimLap] {
        guard lapLength > 0, !events.isEmpty else { return [] }
        guard events.allSatisfy({ $0.duration > 0 }) else { return [] }

        return events.indices.map { index in
            SwimLap(
                id: index,
                startDate: events[index].start,
                duration: events[index].duration,
                distanceMeters: lapLength,
                strokeStyle: events[index].stroke
            )
        }
    }
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

/// 영법별 거리 집계 결과
struct StrokeBreakdown: Identifiable, Hashable {
    var id: SwimStrokeStyle { style }
    let style: SwimStrokeStyle
    let meters: Double
    let duration: TimeInterval
    /// 가장 많이 한 영법 대비 비율 (0~1). 막대 길이에 쓴다.
    let ratio: Double

    var metersText: String { "\(Int(meters.rounded()))m" }

    /// 100m 환산 페이스
    var paceText: String {
        guard meters > 0 else { return "-" }
        return "\((duration / meters * 100).clockText)/100m"
    }
}

// MARK: - Aggregation

extension SwimWorkout {
    var hasLapData: Bool { !laps.isEmpty }

    /// 영법별 거리·시간 집계. 많이 한 순서로 정렬하고, 비율은 최대값 대비로 낸다.
    var strokeBreakdown: [StrokeBreakdown] {
        var totals: [SwimStrokeStyle: (meters: Double, duration: TimeInterval)] = [:]
        for lap in laps {
            let existing = totals[lap.strokeStyle] ?? (0, 0)
            totals[lap.strokeStyle] = (
                existing.meters + lap.distanceMeters,
                existing.duration + lap.duration
            )
        }
        let maxMeters = max(totals.values.map(\.meters).max() ?? 0, 1)
        return totals
            .map { style, value in
                StrokeBreakdown(
                    style: style,
                    meters: value.meters,
                    duration: value.duration,
                    ratio: value.meters / maxMeters
                )
            }
            .sorted { $0.meters > $1.meters }
    }

    /// 세트 안에서 가장 많이 쓰인 영법. 종류가 섞이면 혼영으로 본다.
    static func dominantStroke(_ strokes: [SwimStrokeStyle]) -> SwimStrokeStyle {
        let meaningful = strokes.filter { $0 != .unknown }
        guard let first = meaningful.first else { return .unknown }
        guard meaningful.allSatisfy({ $0 == first }) else { return .mixed }
        return first
    }
}
