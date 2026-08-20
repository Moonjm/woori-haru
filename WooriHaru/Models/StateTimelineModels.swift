import CoreGraphics
import Foundation

// MARK: - 응답

/// 최근 얼마간의 차량 상태 — **세 배열이 겹친 채로 온다.**
///
/// 서버가 하나의 띠로 합치지 않는 이유는 TeslaMate `states`에 `driving`·`charging`이 없어서다
/// (`CREATE TYPE states_status AS ENUM ('online', 'offline', 'asleep')`). 합치려면 구간 산술이
/// 필요한데, 세 겹을 그대로 받아 화면이 덧칠하면 그 로직이 사라진다.
///
/// **서버가 싣는 범위 길이(`hours`)를 받지 않는다.** 화면이 필요한 것은 「이 띠가 몇 시간인가」이고
/// 그건 `to − from`에 이미 있다. 필드로 받으면 둘이 어긋날 때 그린 것과 말하는 것이 갈리고,
/// 그 값을 아직 안 내는 서버에서는 디코딩이 통째로 실패해 첫 화면에 오류 카드가 상주한다.
struct StateTimelineResponse: Codable, Equatable {
    /// KST 벽시계. **자정에 맞춰지지 않는다** — `to`가 요청 시각이고 `from`은 그보다 앞이다.
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

/// 눈금 하나. `fraction`은 범위 안의 위치(0.0 = from, 1.0 = to)다.
struct TimelineTick: Equatable {
    let fraction: Double
    let date: Date
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

    /// 손가락이 짚은 자리의 막대. 없으면 `nil`이다.
    ///
    /// **겹친 자리에서는 맨 위 것을 고른다.** `bars`는 이미 상태 → 주행 → 충전 순으로
    /// 정렬돼 있고 그리는 순서가 곧 덧칠 순서이므로, 뒤에서부터 찾으면 눈에 보이는 색과
    /// 짚어서 나오는 이름이 언제나 같다.
    ///
    /// **가장 가까운 것을 끌어다 붙이지 않는다.** 막대가 없는 자리는 기록이 없는 시간대이고,
    /// 거기에 옆 구간의 이름을 찍으면 화면이 없는 사실을 말하게 된다.
    ///
    /// **경계는 시작을 품고 끝을 뱉는다** — 붙어 있는 두 구간의 이음매에서 둘 다 잡히면
    /// 같은 자리를 짚었는데 나오는 값이 실행마다 달라진다.
    ///
    /// **오른쪽 맨 끝만 예외다.** 띠의 오른쪽 끝(「지금」)에서는 비율이 정확히 `1.0`이 되는데,
    /// 반열린 규칙만 쓰면 `end == 1.0`인 마지막 막대까지 걸러져 **눈에는 색이 칠해져 있는
    /// 자리에서 제목이 「최근 N시간」으로 되돌아간다.** 안쪽 이음매의 규칙은 그대로 두고
    /// 끝점만 마지막 막대에 붙인다.
    static func bar(atFraction fraction: Double, in bars: [TimelineBar]) -> TimelineBar? {
        guard (0...1).contains(fraction) else { return nil }
        if let hit = bars.last(where: { fraction >= $0.start && fraction < $0.end }) { return hit }
        guard fraction == 1 else { return nil }
        return bars.last { $0.end == 1 && $0.start < 1 }
    }

    /// 범위 길이를 시간으로. 화면의 「최근 N시간」이 이것으로 만들어진다.
    /// **`to − from`에서 낸다** — 그려진 범위와 말하는 길이가 갈릴 자리를 두지 않는다.
    static func hours(from: Date, to: Date) -> Int {
        max(0, Int((to.timeIntervalSince(from) / 3600).rounded()))
    }

    /// 범위 안에 드는 **4시간 정각**들. 범위가 자정에 맞춰져 있지 않으므로 `from` 다음의
    /// 4시간 정각에서 시작한다.
    ///
    /// **폭과 무관한 부분만 낸다** — 화면 밖으로 나가거나 「지금」과 겹치는 눈금을 버리는 일은
    /// 폭을 아는 뷰가 한다. 그래야 이 산술에 테스트가 닿는다.
    static func ticks(from: Date, to: Date) -> [TimelineTick] {
        let span = to.timeIntervalSince(from)
        guard span > 0 else { return [] }
        var result: [TimelineTick] = []
        var cursor = firstTick(after: from)
        while cursor < to {
            result.append(TimelineTick(fraction: cursor.timeIntervalSince(from) / span, date: cursor))
            cursor = cursor.addingTimeInterval(4 * 3600)
        }
        return result
    }

    /// `date` 다음의 4시간 정각. **KST로 읽는다** — `from`·`to`가 KST 벽시계라
    /// 기기 시간대로 끊으면 정각이 시차만큼 어긋난다.
    private static func firstTick(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kst
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let hourStart = calendar.date(from: parts), let hour = parts.hour else { return date }
        // 지금 시(hour)의 정각에서 다음 4의 배수까지 나아간다. 1~4시간이 더해진다.
        return hourStart.addingTimeInterval(Double(4 - (hour % 4)) * 3600)
    }

    private static let kst = TimeZone(identifier: "Asia/Seoul") ?? .current

    /// 실제로 그릴 눈금만 남긴다. 셋을 한 번에 판정한다 — 왼쪽으로 삐져나오는 것,
    /// **앞 눈금과 겹치는 것**, 오른쪽 끝 「지금」과 겹치는 것.
    ///
    /// **이웃 간격을 보지 않으면 범위가 길어질 때 축이 뭉개진다.** 24시간에서는 눈금이 여섯
    /// 개뿐이라 드러나지 않지만, 서버가 자정에 맞춘 범위(약 145~168시간)를 주면 눈금이 서른
    /// 몇 개가 되어 30pt짜리 글자가 10pt 간격으로 포개진다.
    ///
    /// 폭을 받아야 하므로 순수 함수로 두고 뷰가 부른다 — 그래야 이 판정에 테스트가 닿는다.
    static func visibleTicks(_ ticks: [TimelineTick],
                             width: CGFloat,
                             labelWidth: CGFloat) -> [TimelineTick] {
        guard width > 0, labelWidth > 0 else { return [] }
        var kept: [TimelineTick] = []
        // 앞 눈금이 차지한 오른쪽 끝. 0에서 시작하므로 첫 눈금은 왼쪽으로 못 삐져나온다.
        var lastTrailing: CGFloat = 0
        for tick in ticks {
            let leading = width * CGFloat(tick.fraction) - labelWidth / 2
            guard leading >= lastTrailing else { continue }
            guard leading + labelWidth <= width - labelWidth else { continue }
            kept.append(tick)
            lastTrailing = leading + labelWidth
        }
        return kept
    }
}
