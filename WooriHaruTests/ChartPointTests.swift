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

    // MARK: - 슬롯 기하

    /// **그리는 식과 탭을 받는 식이 서로의 역이어야 한다.** 점을 찍은 바로 그 자리를 눌렀는데
    /// 옆 점이 잡히면 화면만 봐서는 원인을 못 찾는다 — 카드 폭(≈329pt)과 12개월에서
    /// 실제로 그랬다(끝맞춤 `width / (count - 1)`로 받던 시절).
    @Test func 슬롯_중심을_누르면_그_슬롯이_잡힌다() {
        let width: CGFloat = 329
        for count in [1, 2, 3, 12] {
            for index in 0..<count {
                let x = ChartScale.slotCenterX(index: index, count: count, width: width)
                #expect(ChartScale.slotIndex(atX: x, count: count, width: width) == index,
                        "count \(count), index \(index), x \(x)")
            }
        }
    }

    /// 슬롯 중심은 왼쪽부터 오른쪽으로 늘어서고 카드 안에 있다.
    @Test func 슬롯_중심은_순서대로_카드_안에_있다() {
        let width: CGFloat = 329
        let count = 12
        let xs = (0..<count).map { ChartScale.slotCenterX(index: $0, count: count, width: width) }
        #expect(xs == xs.sorted())
        #expect(xs.first! > 0)
        #expect(xs.last! < width)
    }

    /// 점이 하나면 왼쪽 끝이 아니라 가운데에 찍는다 — 기록이 한 달뿐인 사람이
    /// 카드 구석에 붙은 점을 보게 두지 않는다.
    @Test func 점이_하나면_가운데다() {
        #expect(ChartScale.slotCenterX(index: 0, count: 1, width: 300) == 150)
        #expect(ChartScale.slotIndex(atX: 0, count: 1, width: 300) == 0)
        #expect(ChartScale.slotIndex(atX: 300, count: 1, width: 300) == 0)
    }

    /// 첫 점보다 왼쪽, 마지막 점보다 오른쪽을 눌러도 양 끝이 받는다 —
    /// 카드 여백을 스치듯 누른 탭이 아무 일도 안 하면 「안 눌린다」로 읽힌다.
    @Test func 양_끝_바깥을_눌러도_양_끝이_잡힌다() {
        let width: CGFloat = 329
        let count = 12
        let first = ChartScale.slotCenterX(index: 0, count: count, width: width)
        let last = ChartScale.slotCenterX(index: count - 1, count: count, width: width)
        #expect(ChartScale.slotIndex(atX: first - 8, count: count, width: width) == 0)
        #expect(ChartScale.slotIndex(atX: 0, count: count, width: width) == 0)
        #expect(ChartScale.slotIndex(atX: last + 8, count: count, width: width) == count - 1)
        #expect(ChartScale.slotIndex(atX: width, count: count, width: width) == count - 1)
    }

    /// 첫 슬롯 중심에 가까운 x는 첫 슬롯이 받는다. 예전 끝맞춤 계산은 x=20에서
    /// 둘째 점을 골랐다 — 첫 점(≈13pt)이 더 가까운데도.
    @Test func 첫_점에_가까운_탭은_첫_점이_받는다() {
        let width: CGFloat = 329
        let count = 12
        #expect(ChartScale.slotIndex(atX: 15, count: count, width: width) == 0)
        #expect(ChartScale.slotIndex(atX: 20, count: count, width: width) == 0)
    }

    /// 폭이 0인 첫 프레임에서도 나누다 죽지 않고 첫 슬롯을 준다.
    @Test func 폭이_없어도_인덱스가_범위_안이다() {
        #expect(ChartScale.slotIndex(atX: 10, count: 12, width: 0) == 0)
        #expect(ChartScale.slotIndex(atX: 10, count: 0, width: 329) == 0)
    }

    @Test func 칸이_많아지면_간격이_좁아진다() {
        #expect(ChartScale.slotSpacing(count: 12) == 5)
        // 60칸에서도 막대가 남아야 한다.
        let spacing = ChartScale.slotSpacing(count: 60)
        #expect(spacing < 5)
        let width: CGFloat = 320
        let barWidth = (width - spacing * 59) / 60
        #expect(barWidth > 0)
    }

    @Test func 칸이_많으면_x축_라벨을_솎는다() {
        // 12칸이면 전부 적는다.
        #expect(MonthLabel.shows(index: 5, count: 12))
        // 60칸이면 여섯 달에 하나만 적는다 — 다 적으면 글자가 겹친다.
        #expect(MonthLabel.shows(index: 0, count: 60))
        #expect(!MonthLabel.shows(index: 1, count: 60))
        #expect(MonthLabel.shows(index: 6, count: 60))
    }

    // MARK: - ChartAnchor

    /// 선택된 id가 지금 배열에 있으면 그것을 쓴다 — 기본값 계산(`fallback`)까지
    /// 가지 않는다.
    @Test func 선택된_id가_배열에_있으면_그것을_쓴다() {
        let anchor = ChartAnchor.resolve(selected: "2026-08", in: ["2026-06", "2026-07", "2026-08"]) {
            Issue.record("배열에 있는데 기본값으로 떨어졌다")
            return "fallback"
        }
        #expect(anchor == "2026-08")
    }

    /// **기간을 바꿔 옛 선택이 새 배열에서 빠지면 기본값으로 떨어진다.** `StatsDriveSection`이
    /// 12개월에서 `"2025-09"`를 고른 채 3개월로 바꾸는 시나리오가 바로 이것이다 — 존재
    /// 검사가 없으면 강조·콜아웃이 실재하지 않는 id를 가리키게 된다.
    @Test func 선택된_id가_배열에_없으면_기본값으로_떨어진다() {
        let anchor = ChartAnchor.resolve(selected: "2025-09", in: ["2026-06", "2026-07", "2026-08"]) {
            "2026-08"
        }
        #expect(anchor == "2026-08")
    }

    /// 아무것도 선택하지 않았으면(`nil`) 곧장 기본값이다.
    @Test func 아무것도_선택_안했으면_기본값을_쓴다() {
        let anchor = ChartAnchor.resolve(selected: nil, in: ["2026-06", "2026-07", "2026-08"]) {
            "2026-08"
        }
        #expect(anchor == "2026-08")
    }

    /// 기본값 계산 자체가 nil을 낼 수 있다(빈 배열 등) — 그대로 nil을 돌려준다.
    @Test func 기본값도_없으면_nil이다() {
        let anchor = ChartAnchor.resolve(selected: nil, in: []) { nil }
        #expect(anchor == nil)
    }
}
