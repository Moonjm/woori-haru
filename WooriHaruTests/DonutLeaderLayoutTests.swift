import Foundation
import Testing
@testable import WooriHaru

@Suite("도넛 지시선 배치")
struct DonutLeaderLayoutTests {
    private typealias Slice = DonutLeaderLayout.Slice

    /// 참고 이미지가 겹치는 시나리오다 — 큰 조각 둘(50%, 24%) 다음에 작은 조각 셋(15%, 8%, 3%).
    /// 누적 각도로 보면 처음 하나만 오른쪽(12시~6시)에 서고 나머지 넷이 전부 왼쪽에 몰린다.
    private func crowdedSlices() -> [Slice] {
        [Slice(label: "0~5km", fraction: 0.50),
         Slice(label: "5~20km", fraction: 0.24),
         Slice(label: "20~50km", fraction: 0.15),
         Slice(label: "50~100km", fraction: 0.08),
         Slice(label: "100km 이상", fraction: 0.03)]
    }

    @Test func 같은_쪽_라벨은_최소_간격_이상_떨어진다() {
        let placements = DonutLeaderLayout.place(crowdedSlices(), radius: 100, bendX: 120, labelX: 140)
        for side in [DonutLeaderLayout.Side.left, .right] {
            let ys = placements.filter { $0.side == side }.map(\.labelPoint.y).sorted()
            guard ys.count > 1 else { continue }
            for i in 1..<ys.count {
                #expect(ys[i] - ys[i - 1] >= DonutLeaderLayout.minGap - 0.001,
                        "\(side) 라벨 간격이 최소값보다 좁다: \(ys)")
            }
        }
    }

    @Test func 오른쪽_반원_조각은_오른쪽에_왼쪽_반원_조각은_왼쪽에_선다() {
        let placements = DonutLeaderLayout.place(crowdedSlices(), radius: 100, bendX: 120, labelX: 140)
        // 누적 각도(12시부터 시계 방향): 0~5km은 중앙각 90도(오른쪽), 나머지 넷은 180도를 넘는다(왼쪽).
        #expect(placements[0].side == .right)
        #expect(placements[1...].allSatisfy { $0.side == .left })
    }

    @Test func 오른쪽_라벨은_양수_x_왼쪽_라벨은_음수_x다() {
        let placements = DonutLeaderLayout.place(crowdedSlices(), radius: 100, bendX: 120, labelX: 140)
        for placement in placements {
            let expectedSign: CGFloat = placement.side == .right ? 1 : -1
            #expect(placement.labelPoint.x * expectedSign > 0)
            #expect(placement.bendPoint.x * expectedSign > 0)
        }
    }

    @Test func 조각_순서와_개수를_그대로_지킨다() {
        let slices = crowdedSlices()
        let placements = DonutLeaderLayout.place(slices, radius: 100, bendX: 120, labelX: 140)
        #expect(placements.count == slices.count)
        #expect(placements.map(\.label) == slices.map(\.label))
    }

    @Test func 조각이_하나면_안_터지고_하나를_돌려준다() {
        let placements = DonutLeaderLayout.place([Slice(label: "전체", fraction: 1.0)],
                                                   radius: 100, bendX: 120, labelX: 140)
        #expect(placements.count == 1)
        #expect(placements[0].label == "전체")
    }

    @Test func 조각이_0개면_빈_배열이고_안_터진다() {
        let placements = DonutLeaderLayout.place([], radius: 100, bendX: 120, labelX: 140)
        #expect(placements.isEmpty)
    }
}
