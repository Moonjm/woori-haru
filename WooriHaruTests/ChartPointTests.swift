import Foundation
import Testing
@testable import WooriHaru

struct ChartPointTests {
    /// 최댓값이 0이면 나누지 않는다 — 값이 전부 0인 기간에 0으로 나누는 길을 막는다.
    @Test func 최댓값이_0이면_비율도_0이다() {
        #expect(ChartScale.ratio(0, max: 0) == 0)
        #expect(ChartScale.ratio(5, max: 0) == 0)
    }

    /// nil은 「기록이 없다」라 막대를 그리지 않는다. 0은 「안 탔다」라 0 높이로 그린다.
    /// 둘 다 비율은 0이지만 그리는 쪽이 `value == nil`로 갈라 색을 다르게 준다.
    @Test func 기록이_없으면_비율이_0이다() {
        #expect(ChartScale.ratio(nil, max: 100) == 0)
        #expect(ChartScale.ratio(0, max: 100) == 0)
    }

    @Test func 값을_최댓값에_대한_비율로_바꾼다() {
        #expect(ChartScale.ratio(50, max: 100) == 0.5)
        #expect(ChartScale.ratio(100, max: 100) == 1.0)
    }

    /// 음수는 0으로 자른다 — 막대가 축 아래로 뻗으면 다른 막대와 높이를 견줄 수 없다.
    @Test func 음수는_0으로_자른다() {
        #expect(ChartScale.ratio(-10, max: 100) == 0)
    }

    /// 배열에서 최댓값을 뽑을 때 nil은 건너뛴다.
    @Test func 최댓값은_기록이_있는_달에서만_고른다() {
        let points = [
            ChartPoint(id: "2026-06", label: "6", value: nil),
            ChartPoint(id: "2026-07", label: "7", value: 42),
            ChartPoint(id: "2026-08", label: "8", value: 17),
        ]
        #expect(ChartScale.maxValue(points) == 42)
        #expect(ChartScale.maxValue([]) == 0)
    }
}
