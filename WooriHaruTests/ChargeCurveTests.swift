import Foundation
import Testing
@testable import WooriHaru

struct ChargeCurveTests {

    private static func sample(_ minute: Int, _ kw: Int?) -> ChargeCurveSample {
        let base = 60 * 13 + minute // 13:00 + minute
        return ChargeCurveSample(
            at: String(format: "2025-09-10T%02d:%02d:00", base / 60, base % 60),
            powerKw: kw, batteryLevel: nil
        )
    }

    /// 폰 차트 폭이 ~340pt라 1,980개는 어차피 못 그린다. **줄이되 봉우리를 잃지 않는다.**
    /// 알고리즘은 이 입력에서 정확히 150개를 낸다 — 덜 나오는 회귀를 느슨한 `<=`로는 못 잡는다.
    @Test func 상한보다_많으면_줄인다() {
        let many = (0..<510).map { Self.sample($0, 100) }
        #expect(ChargeCurveMath.downsample(many, to: 150).count == 150)
    }

    /// **상한 이하면 손대지 않는다.** 줄일 이유가 없는데 줄이면 없던 왜곡이 생긴다.
    @Test func 상한_이하면_그대로_둔다() {
        let few = (0..<80).map { Self.sample($0, 50) }
        #expect(ChargeCurveMath.downsample(few, to: 150).count == 80)
    }

    /// **최고점을 잃지 않는 것이 이 함수의 존재 이유다.** 균등 간격으로 솎으면 166kW 봉우리가
    /// 통째로 빠져 「최고 100kW였네」가 된다 — 곡선을 여는 이유가 그 봉우리인데.
    @Test func 줄여도_최고점은_남는다() {
        var samples = (0..<400).map { Self.sample($0, 60) }
        samples[137] = Self.sample(137, 166)
        let reduced = ChargeCurveMath.downsample(samples, to: 100)
        #expect(reduced.compactMap(\.powerKw).max() == 166)
    }

    /// 첫 점과 끝 점은 늘 남는다 — 곡선의 시작과 끝이 잘리면 소요 시간이 틀려 보인다.
    @Test func 양_끝은_늘_남는다() {
        let samples = (0..<300).map { Self.sample($0, 70) }
        let reduced = ChargeCurveMath.downsample(samples, to: 50)
        #expect(reduced.first?.at == samples.first?.at)
        #expect(reduced.last?.at == samples.last?.at)
    }

    /// **경과 분은 앱이 낸다** — 서버는 KST 시각만 준다.
    @Test func 첫_샘플에서_빼서_경과_분을_낸다() {
        let points = ChargeCurveMath.elapsedMinutes([
            Self.sample(0, 166), Self.sample(16, 100), Self.sample(33, 66),
        ])
        #expect(points.map(\.minutes) == [0, 16, 33])
        #expect(points.map(\.powerKw) == [166, 100, 66])
    }

    /// **`powerKw`가 null인 샘플은 버린다.** 0으로 읽으면 곡선이 바닥까지 떨어졌다 올라온
    /// 것처럼 보인다 — null은 「모른다」이지 「안 들어갔다」가 아니다.
    @Test func 전력이_없는_샘플은_빼고_그린다() {
        let points = ChargeCurveMath.elapsedMinutes([
            Self.sample(0, 166), Self.sample(5, nil), Self.sample(10, 120),
        ])
        #expect(points.map(\.minutes) == [0, 10])
    }

    /// 시각을 못 읽는 샘플도 빠진다. 그리고 남은 것이 없으면 빈 배열이다.
    @Test func 읽을_수_없으면_빈_배열이다() {
        #expect(ChargeCurveMath.elapsedMinutes([]).isEmpty)
        let broken = [ChargeCurveSample(at: "not-a-date", powerKw: 10, batteryLevel: nil)]
        #expect(ChargeCurveMath.elapsedMinutes(broken).isEmpty)
    }
}
