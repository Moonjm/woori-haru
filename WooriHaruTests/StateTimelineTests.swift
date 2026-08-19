import Foundation
import Testing
@testable import WooriHaru

struct StateTimelineTests {

    /// 범위는 **자정에 맞춰지지 않는다** — 지금부터 거꾸로 24시간이다.
    /// 13:00 ~ 다음날 13:00으로 잡아 비율 계산이 눈으로 검산된다.
    private func response(states: [StateSegment] = [],
                          drives: [TimeSegment] = [],
                          charges: [TimeSegment] = []) -> StateTimelineResponse {
        StateTimelineResponse(hours: 24,
                              from: "2026-08-18T13:00:00",
                              to: "2026-08-19T13:00:00",
                              states: states, drives: drives, charges: charges)
    }

    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 1e-9 }

    @Test func 범위_한가운데_구간이_비율로_나온다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "offline", from: "2026-08-18T19:00:00", to: "2026-08-19T01:00:00")
        ]))
        #expect(bars.count == 1)
        #expect(bars[0].kind == .offline)
        #expect(isClose(bars[0].start, 6.0 / 24))   // 13시 → 19시
        #expect(isClose(bars[0].end, 12.0 / 24))    // 13시 → 다음날 1시
    }

    @Test func 자정을_넘어도_막대가_쪼개지지_않는다() {
        // 4단계에서는 두 행으로 갈렸다. 한 줄이 되면서 하나로 이어진다.
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "asleep", from: "2026-08-18T22:00:00", to: "2026-08-19T06:00:00")
        ]))
        #expect(bars.count == 1)
        #expect(isClose(bars[0].start, 9.0 / 24))
        #expect(isClose(bars[0].end, 17.0 / 24))
    }

    @Test func 범위_앞뒤로_삐져나온_구간이_잘린다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-18T11:00:00", to: "2026-08-18T15:00:00")],
            drives: [TimeSegment(from: "2026-08-19T12:00:00", to: "2026-08-19T18:00:00")]))

        let online = bars.filter { $0.kind == .online }
        #expect(online.count == 1)
        #expect(isClose(online[0].start, 0.0))
        #expect(isClose(online[0].end, 2.0 / 24))

        let driving = bars.filter { $0.kind == .driving }
        #expect(driving.count == 1)
        #expect(isClose(driving[0].start, 23.0 / 24))
        #expect(isClose(driving[0].end, 1.0))       // 오른쪽 끝 = 지금
    }

    @Test func 모르는_상태는_버린다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "teleporting", from: "2026-08-18T14:00:00", to: "2026-08-18T15:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 길이가_0인_구간은_막대를_만들지_않는다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "online", from: "2026-08-18T14:00:00", to: "2026-08-18T14:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 상태_주행_충전_순으로_정렬된다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-18T14:00:00", to: "2026-08-18T16:00:00")],
            drives: [TimeSegment(from: "2026-08-18T14:30:00", to: "2026-08-18T15:00:00")],
            charges: [TimeSegment(from: "2026-08-18T15:10:00", to: "2026-08-18T15:40:00")]))
        #expect(bars.map(\.kind) == [.online, .driving, .charging])
    }

    @Test func 빈_응답은_빈_배열을_낸다() {
        #expect(StateTimelineMath.bars(response()).isEmpty)
    }

    @Test func 읽을_수_없는_범위는_빈_배열을_낸다() {
        let broken = StateTimelineResponse(hours: 24, from: "어제", to: "오늘",
                                           states: [], drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }

    @Test func 뒤집힌_범위는_빈_배열을_낸다() {
        let broken = StateTimelineResponse(hours: 24,
                                           from: "2026-08-19T13:00:00",
                                           to: "2026-08-18T13:00:00",
                                           states: [StateSegment(state: "online",
                                                                 from: "2026-08-18T14:00:00",
                                                                 to: "2026-08-18T15:00:00")],
                                           drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }
}
