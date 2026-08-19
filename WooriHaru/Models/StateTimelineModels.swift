import Foundation

// MARK: - 응답

/// 최근 며칠의 차량 상태 — **세 배열이 겹친 채로 온다.**
///
/// 서버가 하나의 띠로 합치지 않는 이유는 TeslaMate `states`에 `driving`·`charging`이 없어서다
/// (`CREATE TYPE states_status AS ENUM ('online', 'offline', 'asleep')`). 합치려면 구간 산술이
/// 필요한데, 세 겹을 그대로 받아 화면이 덧칠하면 그 로직이 사라진다.
struct StateTimelineResponse: Codable, Equatable {
    let days: Int
    /// KST 벽시계. **서버가 KST 자정에 맞춰 잘라 준다** — `days=7`이면 온전한 6일 + 오늘 부분이다.
    let from: String
    let to: String
    let states: [StateSegment]
    let drives: [TimeSegment]
    let charges: [TimeSegment]
}

struct StateSegment: Codable, Equatable {
    /// TeslaMate 원문(`online`·`asleep`·`offline`).
    let state: String
    let from: String
    let to: String
}

/// 주행·충전은 상태 이름이 없다 — 존재 자체가 뜻이다.
struct TimeSegment: Codable, Equatable {
    let from: String
    let to: String
}

// MARK: - 그리는 단위

enum TimelineKind: Equatable {
    case asleep, offline, online, driving, charging

    /// **상태를 깔고 주행, 그 위에 충전을 덧칠한다.** 주행과 충전이 동시에 열리는 일은 없다.
    var layer: Int {
        switch self {
        case .asleep, .offline, .online: 0
        case .driving: 1
        case .charging: 2
        }
    }

    /// **모르는 상태는 버린다.** 글자로 내는 `VehicleFormat.stateLabel`은 원문을 그대로 보여주지만
    /// (상류가 늘렸다는 사실을 숨기지 않으려고), 띠는 색을 골라야 한다 — 임의의 색으로 칠하면
    /// 다섯 색의 뜻이 무너진다. 안 그리는 편이 낫다.
    static func state(_ raw: String) -> TimelineKind? {
        switch raw {
        case "online": .online
        case "asleep": .asleep
        case "offline": .offline
        default: nil
        }
    }
}

/// 한 막대 = 하루 안의 한 조각. `start`·`end`는 그 행에서의 비율(0.0~1.0)이다.
struct TimelineBar: Equatable {
    let dayIndex: Int
    let start: Double
    let end: Double
    let kind: TimelineKind
}

// MARK: - 계산

/// 화면이 하는 유일한 계산이다. **한국은 서머타임이 없어** 하루를 86,400초 고정으로 잡아도
/// 자정 경계가 어긋나지 않는다.
enum StateTimelineMath {
    static let secondsPerDay: Double = 86_400

    static func bars(_ response: StateTimelineResponse) -> [TimelineBar] {
        guard let windowStart = VehicleFormat.parseKST(response.from),
              let windowEnd = VehicleFormat.parseKST(response.to),
              windowEnd > windowStart else { return [] }

        var bars: [TimelineBar] = []
        for segment in response.states {
            guard let kind = TimelineKind.state(segment.state) else { continue }
            bars += split(segment.from, segment.to, kind: kind, from: windowStart, to: windowEnd)
        }
        for segment in response.drives {
            bars += split(segment.from, segment.to, kind: .driving, from: windowStart, to: windowEnd)
        }
        for segment in response.charges {
            bars += split(segment.from, segment.to, kind: .charging, from: windowStart, to: windowEnd)
        }

        // **정렬 기준을 셋 다 준다.** Swift의 `sorted`는 안정 정렬을 보장하지 않아
        // 레이어만으로 비교하면 같은 레이어 안의 순서가 실행마다 달라질 수 있다.
        return bars.sorted {
            if $0.kind.layer != $1.kind.layer { return $0.kind.layer < $1.kind.layer }
            if $0.dayIndex != $1.dayIndex { return $0.dayIndex < $1.dayIndex }
            return $0.start < $1.start
        }
    }

    /// 구간 하나를 날짜 행으로 쪼갠다. **창 밖은 자른다** — 서버가 이미 잘라 주지만,
    /// 계약이 깨져도 화면이 무너지지 않게 한 번 더 막는다.
    private static func split(_ rawFrom: String, _ rawTo: String, kind: TimelineKind,
                              from windowStart: Date, to windowEnd: Date) -> [TimelineBar] {
        guard let segmentStart = VehicleFormat.parseKST(rawFrom),
              let segmentEnd = VehicleFormat.parseKST(rawTo) else { return [] }
        let start = max(segmentStart, windowStart)
        let end = min(segmentEnd, windowEnd)
        guard end > start else { return [] }

        var bars: [TimelineBar] = []
        var cursor = start
        while cursor < end {
            let dayIndex = Int(floor(cursor.timeIntervalSince(windowStart) / secondsPerDay))
            let dayStart = windowStart.addingTimeInterval(Double(dayIndex) * secondsPerDay)
            let sliceEnd = min(end, dayStart.addingTimeInterval(secondsPerDay))
            bars.append(TimelineBar(
                dayIndex: dayIndex,
                start: cursor.timeIntervalSince(dayStart) / secondsPerDay,
                end: sliceEnd.timeIntervalSince(dayStart) / secondsPerDay,
                kind: kind))
            cursor = sliceEnd
        }
        return bars
    }
}
