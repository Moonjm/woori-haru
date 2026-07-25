import Foundation

/// 쉬는 구간으로 나뉜 수영 세트. 피트니스 앱의 "자동 세트"와 같은 개념이다.
struct SwimSet: Identifiable, Hashable {
    /// 1-based 세트 번호
    let id: Int
    let distanceMeters: Double
    /// 세트 첫 랩 시작부터 마지막 랩 종료까지. 벽에서 턴한 시간이 포함된다.
    let duration: TimeInterval
    /// 다음 세트가 시작될 때까지 쉰 시간. 마지막 세트는 nil.
    let restDuration: TimeInterval?
    let strokeStyle: SwimStrokeStyle

    var pacePer100m: TimeInterval {
        guard distanceMeters > 0 else { return 0 }
        return duration / distanceMeters * 100
    }

    var distanceText: String { "\(Int(distanceMeters.rounded()))m" }
    var durationText: String { SwimSplit.clockText(duration) }
    var paceText: String { "\(SwimSplit.clockText(pacePer100m))/100m" }
    var restText: String? { restDuration.map { SwimSplit.clockText($0) } }
}

// MARK: - Set Detection

extension SwimWorkout {
    /// 랩 사이 공백이 이보다 길면 쉰 것으로 본다.
    ///
    /// 실측에서 벽 찍고 턴하는 공백은 1~7초, 세트 사이 휴식은 1분 이상으로
    /// 뚜렷하게 갈렸다. 그 사이 값이라면 어디를 잡아도 같은 결과가 나온다.
    static let restThreshold: TimeInterval = 20

    /// 랩을 쉬는 구간 기준으로 묶어 세트를 만든다.
    /// 구간(`splits`)이 순수 수영 시간을 보는 것과 달리, 세트는 턴 시간을 포함한
    /// 실제 기록을 보여준다.
    var sets: [SwimSet] {
        guard !laps.isEmpty else { return [] }

        // 먼저 랩을 세트 단위로 끊는다
        var groups: [[SwimLap]] = []
        var current: [SwimLap] = []
        for lap in laps {
            if let previous = current.last,
               lap.startDate.timeIntervalSince(previous.endDate) > Self.restThreshold {
                groups.append(current)
                current = []
            }
            current.append(lap)
        }
        if !current.isEmpty { groups.append(current) }

        return groups.indices.map { index in
            let group = groups[index]
            let start = group[0].startDate
            let end = group[group.count - 1].endDate
            let nextStart = index + 1 < groups.count ? groups[index + 1][0].startDate : nil

            return SwimSet(
                id: index + 1,
                distanceMeters: group.reduce(0) { $0 + $1.distanceMeters },
                duration: end.timeIntervalSince(start),
                restDuration: nextStart.map { $0.timeIntervalSince(end) },
                strokeStyle: Self.dominantStroke(group.map(\.strokeStyle))
            )
        }
    }
}

extension SwimLap {
    var endDate: Date { startDate.addingTimeInterval(duration) }
}
