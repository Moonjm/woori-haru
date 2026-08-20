import CoreGraphics
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
        // 이 테스트가 직접 쓴 payload는 from~to가 정확히 7×24시간이라 168이 나온다 — 실제
        // 개정 전 서버는 KST 자정에 맞춰 시작하므로 요청 시각에 따라 145~168시간을 낸다.
        // 여기서는 24시간인 척하지 않는다는 것만 확인한다.
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

    // MARK: - 눈금 솎아내기

    @Test func 짧은_범위는_솎아내도_눈금이_그대로_남는다() {
        // `from`을 정각(12시)으로 잡는다 — 13:00으로 잡으면 마지막 눈금(비율 0.9583)이
        // 320pt에서 원래도 「지금」과 겹쳐 빠지므로(그 경계는 f > 0.86), 이웃 겹침 판정을
        // 추가해도 결과가 그대로인지를 못 본다. 12시 시작은 눈금이 5개뿐이고 마지막이
        // 0.833이라 「지금」과도, 이웃과도 안 겹친다.
        let from = VehicleFormat.parseKST("2026-08-18T12:00:00")!
        let to = VehicleFormat.parseKST("2026-08-19T12:00:00")!
        let ticks = StateTimelineMath.ticks(from: from, to: to)
        let visible = StateTimelineMath.visibleTicks(ticks, width: 320, labelWidth: 30)
        #expect(visible == ticks)
    }

    /// 서버가 자정에 맞춘 범위(145~168시간)를 주면 4시간 간격 눈금이 서른 몇 개가 된다.
    /// **앞 눈금과 겹치지 않아야 한다** — 이웃 간격을 안 보면 30pt짜리 글자가 10.7pt 간격으로 포개진다.
    @Test func 긴_범위에서_남은_눈금끼리_겹치지_않는다() {
        let from = VehicleFormat.parseKST("2026-08-12T00:00:00")!
        let to = VehicleFormat.parseKST("2026-08-19T13:00:00")!  // 157시간
        let ticks = StateTimelineMath.ticks(from: from, to: to)
        #expect(ticks.count > 6)  // 24시간 범위보다 훨씬 많다는 전제 확인

        let width: CGFloat = 343
        let labelWidth: CGFloat = 30
        let visible = StateTimelineMath.visibleTicks(ticks, width: width, labelWidth: labelWidth)
        #expect(visible.count > 1)

        for (prev, next) in zip(visible, visible.dropFirst()) {
            let prevX = width * CGFloat(prev.fraction)
            let nextX = width * CGFloat(next.fraction)
            #expect(nextX - prevX >= labelWidth)
        }
    }

    @Test func 폭이_0이면_눈금이_모두_빠진다() {
        let from = VehicleFormat.parseKST("2026-08-18T13:00:00")!
        let to = VehicleFormat.parseKST("2026-08-19T13:00:00")!
        let ticks = StateTimelineMath.ticks(from: from, to: to)
        #expect(StateTimelineMath.visibleTicks(ticks, width: 0, labelWidth: 30).isEmpty)
    }

    @Test func 지금_자리와_겹치는_눈금은_빠진다() {
        // 13:42 다음의 4시간 정각들 중 마지막(12시, 비율 0.9292)은 320pt에서
        // 「지금」 칸([290, 320])과 겹친다 — 눈금 칸이 [304.3−15, 304.3+15]이기 때문이다.
        let from = VehicleFormat.parseKST("2026-08-18T13:42:00")!
        let to = VehicleFormat.parseKST("2026-08-19T13:42:00")!
        let ticks = StateTimelineMath.ticks(from: from, to: to)
        let visible = StateTimelineMath.visibleTicks(ticks, width: 320, labelWidth: 30)
        #expect(visible.count == ticks.count - 1)
        #expect(!visible.contains { isClose($0.fraction, ticks.last!.fraction) })
    }

    // MARK: - 짚은 자리의 막대

    /// 겹친 자리에서는 **맨 위 것**을 고른다. 상태 위에 주행이, 그 위에 충전이 덧칠되므로
    /// 눈에 보이는 색과 짚어서 나오는 이름이 갈리면 안 된다.
    @Test func 겹친_자리에서는_맨_위_막대를_고른다() {
        let bars = [
            TimelineBar(start: 0.0, end: 1.0, kind: .online),
            TimelineBar(start: 0.2, end: 0.4, kind: .driving),
            TimelineBar(start: 0.3, end: 0.35, kind: .charging)
        ]
        #expect(StateTimelineMath.bar(atFraction: 0.10, in: bars)?.kind == .online)
        #expect(StateTimelineMath.bar(atFraction: 0.25, in: bars)?.kind == .driving)
        #expect(StateTimelineMath.bar(atFraction: 0.32, in: bars)?.kind == .charging)
    }

    /// 막대가 없는 자리는 **아무것도 아니다.** 가장 가까운 것을 끌어다 붙이면
    /// 기록이 없는 시간대에 없는 상태가 찍힌다.
    @Test func 막대가_없는_자리는_아무것도_고르지_않는다() {
        let bars = [TimelineBar(start: 0.2, end: 0.4, kind: .online)]
        #expect(StateTimelineMath.bar(atFraction: 0.1, in: bars) == nil)
        #expect(StateTimelineMath.bar(atFraction: 0.5, in: bars) == nil)
        #expect(StateTimelineMath.bar(atFraction: 0.3, in: bars)?.kind == .online)
    }

    /// 경계는 **시작을 품고 끝을 뱉는다.** 붙어 있는 두 구간의 이음매에서 둘 다 잡히면
    /// 같은 자리를 짚었는데 나오는 값이 실행마다 달라진다.
    @Test func 경계는_시작을_품고_끝을_뱉는다() {
        let bars = [
            TimelineBar(start: 0.0, end: 0.5, kind: .offline),
            TimelineBar(start: 0.5, end: 1.0, kind: .online)
        ]
        #expect(StateTimelineMath.bar(atFraction: 0.5, in: bars)?.kind == .online)
        #expect(StateTimelineMath.bar(atFraction: 0.499, in: bars)?.kind == .offline)
    }

    /// 띠 밖을 짚는 일은 없어야 하지만, 제스처가 손가락을 따라 폭 밖으로 나가면 생긴다.
    @Test func 범위_밖을_짚으면_아무것도_고르지_않는다() {
        let bars = [TimelineBar(start: 0.0, end: 1.0, kind: .online)]
        #expect(StateTimelineMath.bar(atFraction: -0.1, in: bars) == nil)
        #expect(StateTimelineMath.bar(atFraction: 1.5, in: bars) == nil)
    }

    @Test func 막대가_하나도_없으면_아무것도_고르지_않는다() {
        #expect(StateTimelineMath.bar(atFraction: 0.5, in: []) == nil)
    }
}
