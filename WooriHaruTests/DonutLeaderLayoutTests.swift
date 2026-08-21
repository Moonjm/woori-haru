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
        let placements = DonutLeaderLayout.place(crowdedSlices(), radius: 100, stubLength: 14, bendX: 120, labelX: 140)
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
        let placements = DonutLeaderLayout.place(crowdedSlices(), radius: 100, stubLength: 14, bendX: 120, labelX: 140)
        // 누적 각도(12시부터 시계 방향): 0~5km은 중앙각 90도(오른쪽), 나머지 넷은 180도를 넘는다(왼쪽).
        #expect(placements[0].side == .right)
        #expect(placements[1...].allSatisfy { $0.side == .left })
    }

    @Test func 오른쪽_라벨은_양수_x_왼쪽_라벨은_음수_x다() {
        let placements = DonutLeaderLayout.place(crowdedSlices(), radius: 100, stubLength: 14, bendX: 120, labelX: 140)
        for placement in placements {
            let expectedSign: CGFloat = placement.side == .right ? 1 : -1
            #expect(placement.labelPoint.x * expectedSign > 0)
            #expect(placement.bendPoint.x * expectedSign > 0)
        }
    }

    @Test func 조각_순서와_개수를_그대로_지킨다() {
        let slices = crowdedSlices()
        let placements = DonutLeaderLayout.place(slices, radius: 100, stubLength: 14, bendX: 120, labelX: 140)
        #expect(placements.count == slices.count)
        #expect(placements.map(\.label) == slices.map(\.label))
    }

    @Test func 조각이_하나면_안_터지고_하나를_돌려준다() {
        let placements = DonutLeaderLayout.place([Slice(label: "전체", fraction: 1.0)],
                                                   radius: 100, stubLength: 14, bendX: 120, labelX: 140)
        #expect(placements.count == 1)
        #expect(placements[0].label == "전체")
    }

    @Test func 조각이_0개면_빈_배열이고_안_터진다() {
        let placements = DonutLeaderLayout.place([], radius: 100, stubLength: 14, bendX: 120, labelX: 140)
        #expect(placements.isEmpty)
    }

    /// 방사형 토막(`stubPoint`)이 실제로 각도를 유지하는지 못박는다 — `edgePoint`와 같은
    /// 방향(원점 기준 벡터가 평행·같은 부호)이면서 원점에서 더 멀어야 한다.
    @Test func 방사형_토막은_가장자리_점과_같은_각도로_더_멀리_뻗는다() {
        let placements = DonutLeaderLayout.place(crowdedSlices(), radius: 100, stubLength: 14, bendX: 120, labelX: 140)
        for placement in placements {
            let edge = placement.edgePoint
            let stub = placement.stubPoint
            // 원점·edge·stub이 한 직선 위에 있는지 — 외적(cross product)이 0에 가까운지로 본다.
            let cross = edge.x * stub.y - edge.y * stub.x
            #expect(abs(cross) < 0.001, "\(placement.label): edge와 stub가 같은 각도가 아니다")
            // 반대 방향(180도 돌아간 점)이 아니라 같은 방향으로 더 멀리 뻗었는지 — 내적이 양수인지로 본다.
            let dot = edge.x * stub.x + edge.y * stub.y
            #expect(dot > 0, "\(placement.label): stub가 edge 반대 방향이다")
            let edgeMagnitude = (edge.x * edge.x + edge.y * edge.y).squareRoot()
            let stubMagnitude = (stub.x * stub.x + stub.y * stub.y).squareRoot()
            #expect(stubMagnitude > edgeMagnitude, "\(placement.label): stub가 edge보다 원점에서 안 멀다")
        }
    }
}
