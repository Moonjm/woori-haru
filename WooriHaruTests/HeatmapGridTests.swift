import Testing
@testable import WooriHaru

@Suite("히트맵 격자")
struct HeatmapGridTests {
    @Test func 최대가_0이면_모든_칸이_빈칸이다() {
        #expect(HeatmapGrid.intensity(count: 0, maxCount: 0) == 0)
        #expect(HeatmapGrid.intensity(count: 3, maxCount: 0) == 0)
    }

    @Test func 가장_진한_칸이_1이다() {
        #expect(HeatmapGrid.intensity(count: 12, maxCount: 12) == 1)
    }

    /// 0에 최소 진하기를 주면 「조금 탔다」로 읽힌다.
    @Test func 히트맵의_0인_칸은_빈칸이다() {
        // 0에 최소 진하기를 주면 「조금 탔다」로 읽힌다.
        #expect(HeatmapGrid.intensity(count: 0, maxCount: 12) == 0)
    }
}
