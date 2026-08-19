import Foundation

// MARK: - 응답

/// 최근 몇 시간의 차량 상태 — **세 배열이 겹친 채로 온다.**
///
/// 서버가 하나의 띠로 합치지 않는 이유는 TeslaMate `states`에 `driving`·`charging`이 없어서다
/// (`CREATE TYPE states_status AS ENUM ('online', 'offline', 'asleep')`). 합치려면 구간 산술이
/// 필요한데, 세 겹을 그대로 받아 화면이 덧칠하면 그 로직이 사라진다.
struct StateTimelineResponse: Codable, Equatable {
    let hours: Int
    /// KST 벽시계. **자정에 맞춰지지 않는다** — `to`가 요청 시각이고 `from`은 그보다 `hours`시간 앞이다.
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

/// 한 막대 = 범위 안의 한 조각. `start`·`end`는 **범위 전체에 대한 비율**(0.0 = `from`, 1.0 = `to`)이다.
///
/// **4단계의 `dayIndex`가 사라졌다.** 7일을 하루 한 행씩 그릴 때는 막대가 어느 행에 속하는지
/// 알아야 했지만, 24시간을 한 줄로 그리면 행이 하나뿐이라 그 값이 가리킬 곳이 없다.
struct TimelineBar: Equatable {
    let start: Double
    let end: Double
    let kind: TimelineKind
}

// MARK: - 계산

/// 화면이 하는 유일한 계산이다.
///
/// **4단계에서 하던 세 가지 중 하나가 사라졌다** — 자정을 넘는 구간을 날짜 행으로 쪼개는 일이다.
/// 행이 하나뿐이면 쪼갤 곳이 없다. 남은 것은 범위 밖 자르기와 정렬 둘이다.
enum StateTimelineMath {
    static func bars(_ response: StateTimelineResponse) -> [TimelineBar] {
        guard let windowStart = VehicleFormat.parseKST(response.from),
              let windowEnd = VehicleFormat.parseKST(response.to) else { return [] }
        let span = windowEnd.timeIntervalSince(windowStart)
        guard span > 0 else { return [] }

        var bars: [TimelineBar] = []
        for segment in response.states {
            guard let kind = TimelineKind.state(segment.state) else { continue }
            if let bar = clip(segment.from, segment.to, kind: kind, from: windowStart, span: span) {
                bars.append(bar)
            }
        }
        for segment in response.drives {
            if let bar = clip(segment.from, segment.to, kind: .driving, from: windowStart, span: span) {
                bars.append(bar)
            }
        }
        for segment in response.charges {
            if let bar = clip(segment.from, segment.to, kind: .charging, from: windowStart, span: span) {
                bars.append(bar)
            }
        }

        // **정렬 기준을 둘 다 준다.** Swift의 `sorted`는 안정 정렬을 보장하지 않아
        // 레이어만으로 비교하면 같은 레이어 안의 순서가 실행마다 달라질 수 있다.
        return bars.sorted {
            if $0.kind.layer != $1.kind.layer { return $0.kind.layer < $1.kind.layer }
            return $0.start < $1.start
        }
    }

    /// 구간 하나를 범위 안의 비율로 바꾼다. **범위 밖은 자른다** — 서버가 이미 잘라 주지만,
    /// 계약이 깨져도 화면이 무너지지 않게 한 번 더 막는다.
    private static func clip(_ rawFrom: String, _ rawTo: String, kind: TimelineKind,
                             from windowStart: Date, span: TimeInterval) -> TimelineBar? {
        guard let segmentStart = VehicleFormat.parseKST(rawFrom),
              let segmentEnd = VehicleFormat.parseKST(rawTo) else { return nil }
        let windowEnd = windowStart.addingTimeInterval(span)
        let start = max(segmentStart, windowStart)
        let end = min(segmentEnd, windowEnd)
        guard end > start else { return nil }
        return TimelineBar(start: start.timeIntervalSince(windowStart) / span,
                           end: end.timeIntervalSince(windowStart) / span,
                           kind: kind)
    }
}
