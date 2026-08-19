import Foundation
import Testing
@testable import WooriHaru

struct StateTimelineTests {

    /// 범위는 **자정에 맞춰지지 않는다** — 지금부터 거꾸로 24시간이다.
    /// 13:00 ~ 다음날 13:00으로 잡아 비율 계산이 눈으로 검산된다.
    private func response(states: [StateSegment] = [],
                          drives: [TimeSegment] = [],
                          charges: [TimeSegment] = []) -> StateTimelineResponse {
        StateTimelineResponse(from: "2026-08-18T13:00:00",
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
        let broken = StateTimelineResponse(from: "어제", to: "오늘",
                                           states: [], drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }

    @Test func 뒤집힌_범위는_빈_배열을_낸다() {
        let broken = StateTimelineResponse(from: "2026-08-19T13:00:00",
                                           to: "2026-08-18T13:00:00",
                                           states: [StateSegment(state: "online",
                                                                 from: "2026-08-18T14:00:00",
                                                                 to: "2026-08-18T15:00:00")],
                                           drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }

    @Test func 범위_밖에_통째로_있는_구간은_막대를_만들지_않는다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "online", from: "2026-08-18T08:00:00", to: "2026-08-18T11:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 뒤집힌_구간은_막대를_만들지_않는다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "online", from: "2026-08-18T18:00:00", to: "2026-08-18T16:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    // MARK: - 범위 길이

    @Test func 범위_길이를_시간으로_낸다() {
        let from = VehicleFormat.parseKST("2026-08-18T13:00:00")!
        #expect(StateTimelineMath.hours(from: from, to: VehicleFormat.parseKST("2026-08-19T13:00:00")!) == 24)
        #expect(StateTimelineMath.hours(from: from, to: VehicleFormat.parseKST("2026-08-25T13:00:00")!) == 168)
        // 분 단위로 어긋난 범위는 가장 가까운 시간으로 읽는다.
        #expect(StateTimelineMath.hours(from: from, to: VehicleFormat.parseKST("2026-08-19T12:50:00")!) == 24)
        // 뒤집힌 범위는 0이다 — 음수 시간을 말하지 않는다.
        #expect(StateTimelineMath.hours(from: from, to: VehicleFormat.parseKST("2026-08-18T09:00:00")!) == 0)
    }

    /// **범위 길이를 필드로 받지 않는다.** 개정 전 서버는 `hours` 없이 `days`를 싣는데,
    /// 그 키를 모델이 요구하면 디코딩이 통째로 실패해 첫 화면에 오류 카드가 상주한다.
    @Test func 개정_전_서버_응답도_디코딩된다() throws {
        let json = Data("""
        {"days": 7, "from": "2026-08-12T13:00:00", "to": "2026-08-19T13:00:00",
         "states": [{"state": "online", "from": "2026-08-19T09:00:00", "to": "2026-08-19T13:00:00"}],
         "drives": [], "charges": []}
        """.utf8)
        let decoded = try JSONDecoder().decode(StateTimelineResponse.self, from: json)
        #expect(decoded.from == "2026-08-12T13:00:00")
        #expect(decoded.states.count == 1)
        // 7일치가 「최근 168시간」으로 정직하게 읽힌다 — 24시간인 척하지 않는다.
        #expect(StateTimelineMath.hours(from: VehicleFormat.parseKST(decoded.from)!,
                                        to: VehicleFormat.parseKST(decoded.to)!) == 168)
    }

    // MARK: - 눈금

    /// 범위 안 눈금의 시(hour)를 KST로 읽는다.
    private func kstHour(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar.component(.hour, from: date)
    }

    @Test func 정각에서_시작한_범위는_네_시간_뒤부터_눈금이_선다() {
        // 12시는 이미 4의 배수지만 첫 눈금은 16시다 — `from` 자리(비율 0)의 글자는
        // 왼쪽으로 삐져나가 어차피 그려지지 않는다.
        let from = VehicleFormat.parseKST("2026-08-18T12:00:00")!
        let ticks = StateTimelineMath.ticks(from: from, to: VehicleFormat.parseKST("2026-08-19T12:00:00")!)
        #expect(ticks.map { kstHour($0.date) } == [16, 20, 0, 4, 8])
        #expect(isClose(ticks[0].fraction, 4.0 / 24))
        // 범위 끝(비율 1.0)은 「지금」이 차지하므로 눈금이 서지 않는다.
        #expect(ticks.last.map { isClose($0.fraction, 20.0 / 24) } == true)
    }

    @Test func 시간_중간에서_시작한_범위도_4시간_정각에_눈금이_선다() {
        // 13:42 다음의 4시간 정각은 16:00 — 2시간 18분 뒤다.
        let from = VehicleFormat.parseKST("2026-08-18T13:42:00")!
        let ticks = StateTimelineMath.ticks(from: from, to: VehicleFormat.parseKST("2026-08-19T13:42:00")!)
        #expect(ticks.first.map { kstHour($0.date) } == 16)
        #expect(isClose(ticks[0].fraction, (2 * 60 + 18) / (24 * 60.0)))
        #expect(ticks.map { kstHour($0.date) } == [16, 20, 0, 4, 8, 12])
    }

    @Test func 눈금은_모두_범위_안쪽에_있다() {
        let from = VehicleFormat.parseKST("2026-08-18T13:42:00")!
        let ticks = StateTimelineMath.ticks(from: from, to: VehicleFormat.parseKST("2026-08-19T13:42:00")!)
        #expect(!ticks.isEmpty)
        // 양 끝은 눈금이 아니다 — 0은 잘려 나가고 1.0은 「지금」의 자리다.
        #expect(ticks.allSatisfy { $0.fraction > 0 && $0.fraction < 1 })
    }

    @Test func 뒤집히거나_길이가_0인_범위는_눈금이_없다() {
        let from = VehicleFormat.parseKST("2026-08-18T13:00:00")!
        #expect(StateTimelineMath.ticks(from: from, to: from).isEmpty)
        #expect(StateTimelineMath.ticks(from: from, to: VehicleFormat.parseKST("2026-08-17T13:00:00")!).isEmpty)
    }
}
