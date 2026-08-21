import Foundation
import Testing
@testable import WooriHaru

@Suite("분포 막대")
struct DistributionBarChartTests {
    @Test func 분포에서_0인_칸도_자리를_지킨다() {
        let points = [ChartPoint(id: "a", label: "0~5", value: 10),
                      ChartPoint(id: "b", label: "5~10", value: 0),
                      ChartPoint(id: "c", label: "10+", value: 4)]
        // 0은 「없었다」는 사실이라 비율 0이고, 칸은 남는다.
        #expect(ChartScale.ratio(points[1].value, max: 10) == 0)
        #expect(points.count == 3)
    }

    @Test func 최대가_0이면_모든_비율이_0이다() {
        let points = [ChartPoint(id: "a", label: "0~5", value: 0),
                      ChartPoint(id: "b", label: "5~10", value: 0)]
        let max = ChartScale.maxValue(points)
        #expect(max == 0)
        #expect(ChartScale.ratio(points[0].value, max: max) == 0)
    }
}
