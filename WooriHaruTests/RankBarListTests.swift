import Foundation
import Testing
@testable import WooriHaru

@Suite("순위 막대")
struct RankBarListTests {
    private let rows = [
        RankBarList.Row(id: "집", label: "집", value: 302, primary: "302회", secondary: "4,120km"),
        RankBarList.Row(id: "회사", label: "회사", value: 151, primary: "151회", secondary: "2,010km"),
    ]

    /// 밑동을 자르면 「1등이 2등의 몇 배인가」가 거짓이 된다.
    @Test func 순위_막대는_0에서_시작한다() {
        let max = ChartScale.maxValue(rows.map(\.chartPoint))
        #expect(max == 302)
        #expect(ChartScale.ratio(rows[0].value, max: max) == 1)
        // 151/302 = 정확히 0.5
        #expect(abs(ChartScale.ratio(rows[1].value, max: max) - 0.5) < 0.0001)
    }

    @Test func 값이_0인_행도_이름은_남는다() {
        let row = RankBarList.Row(id: "미상", label: "미상", value: 0,
                                  primary: "0회", secondary: "—")
        #expect(ChartScale.ratio(row.value, max: 302) == 0)
        #expect(row.label == "미상")
    }

    @Test func 순위가_모두_0이면_0으로_나누지_않는다() {
        let zeros = [RankBarList.Row(id: "a", label: "a", value: 0, primary: "0", secondary: "—")]
        let max = ChartScale.maxValue(zeros.map(\.chartPoint))
        #expect(ChartScale.ratio(zeros[0].value, max: max) == 0)
    }
}
