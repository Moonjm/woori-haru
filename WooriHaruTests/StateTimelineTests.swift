import Foundation
import Testing
@testable import WooriHaru

struct StateTimelineTests {

    /// 창은 KST 자정에서 시작한다 — 서버가 그렇게 잘라 준다.
    /// 마지막 행(오늘)만 정오에서 끝난다.
    private func response(states: [StateSegment] = [],
                          drives: [TimeSegment] = [],
                          charges: [TimeSegment] = []) -> StateTimelineResponse {
        StateTimelineResponse(days: 7,
                              from: "2026-08-13T00:00:00",
                              to: "2026-08-19T12:00:00",
                              states: states, drives: drives, charges: charges)
    }

    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 1e-9 }

    @Test func 하루_안에_든_구간이_그_행의_비율로_나온다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "offline", from: "2026-08-13T06:00:00", to: "2026-08-13T12:00:00")
        ]))
        #expect(bars.count == 1)
        #expect(bars[0].dayIndex == 0)
        #expect(bars[0].kind == .offline)
        #expect(isClose(bars[0].start, 0.25))
        #expect(isClose(bars[0].end, 0.5))
    }

    @Test func 자정을_넘는_구간이_두_행으로_쪼개진다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "offline", from: "2026-08-13T22:00:00", to: "2026-08-14T06:00:00")
        ]))
        #expect(bars.count == 2)
        #expect(bars[0].dayIndex == 0)
        #expect(isClose(bars[0].start, 22.0 / 24))
        #expect(isClose(bars[0].end, 1.0))
        #expect(bars[1].dayIndex == 1)
        #expect(isClose(bars[1].start, 0.0))
        #expect(isClose(bars[1].end, 6.0 / 24))
    }

    @Test func 이틀을_통째로_덮는_구간이_세_행이_된다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "asleep", from: "2026-08-13T18:00:00", to: "2026-08-15T06:00:00")
        ]))
        #expect(bars.map(\.dayIndex) == [0, 1, 2])
        #expect(isClose(bars[0].start, 0.75))
        #expect(isClose(bars[1].start, 0.0))
        #expect(isClose(bars[1].end, 1.0))
        #expect(isClose(bars[2].end, 0.25))
    }

    @Test func 창_앞뒤로_삐져나온_구간이_잘린다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-12T20:00:00", to: "2026-08-13T02:00:00")],
            drives: [TimeSegment(from: "2026-08-19T11:00:00", to: "2026-08-19T23:00:00")]))
        let online = bars.filter { $0.kind == .online }
        #expect(online.count == 1)
        #expect(online[0].dayIndex == 0)
        #expect(isClose(online[0].start, 0.0))
        #expect(isClose(online[0].end, 2.0 / 24))

        let driving = bars.filter { $0.kind == .driving }
        #expect(driving.count == 1)
        #expect(driving[0].dayIndex == 6)
        #expect(isClose(driving[0].end, 12.0 / 24)) // to에서 끊긴다
    }

    @Test func 모르는_상태는_버린다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "teleporting", from: "2026-08-13T06:00:00", to: "2026-08-13T07:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 길이가_0인_구간은_막대를_만들지_않는다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "online", from: "2026-08-13T06:00:00", to: "2026-08-13T06:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 상태_주행_충전_순으로_정렬된다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-13T06:00:00", to: "2026-08-13T08:00:00")],
            drives: [TimeSegment(from: "2026-08-13T06:30:00", to: "2026-08-13T07:00:00")],
            charges: [TimeSegment(from: "2026-08-13T07:10:00", to: "2026-08-13T07:40:00")]))
        #expect(bars.map(\.kind) == [.online, .driving, .charging])
    }

    @Test func 빈_응답은_빈_배열을_낸다() {
        #expect(StateTimelineMath.bars(response()).isEmpty)
    }

    @Test func 읽을_수_없는_창은_빈_배열을_낸다() {
        let broken = StateTimelineResponse(days: 7, from: "어제", to: "오늘",
                                           states: [], drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }
}
