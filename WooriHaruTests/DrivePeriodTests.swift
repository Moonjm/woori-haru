import Testing
@testable import WooriHaru

@Suite("기간 칩")
struct DrivePeriodTests {
    @Test func 칩이_넷이고_전체는_0이다() {
        #expect(DrivePeriod.allCases.map(\.rawValue) == [3, 6, 12, 0])
        #expect(DrivePeriod.all.rawValue == 0)
    }

    @Test func 전체만_라벨이_개월수가_아니다() {
        #expect(DrivePeriod.threeMonths.label == "3개월")
        #expect(DrivePeriod.sixMonths.label == "6개월")
        #expect(DrivePeriod.twelveMonths.label == "12개월")
        #expect(DrivePeriod.all.label == "전체")
    }
}
