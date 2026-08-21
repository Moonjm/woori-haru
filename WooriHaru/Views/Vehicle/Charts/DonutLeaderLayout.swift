import SwiftUI

/// 지시선(leader line) 라벨 배치. `DistanceDistributionCard` 전용이다 — 급속/완속처럼
/// 조각 둘인 도넛(`DonutChart`)은 지시선이 필요 없어 원형에는 넣지 않는다.
///
/// SwiftUI 렌더링 없이 겹침·좌우 배치를 테스트하려고 뷰 밖으로 뺐다(`ChartScale`과 같은 이유).
enum DonutLeaderLayout {
    enum Side: Equatable { case left, right }

    struct Slice: Equatable {
        let label: String
        /// 0...1, 전체 각도에 대한 비율. 도넛의 조각 각도와 같은 값을 넣는다.
        let fraction: CGFloat
    }

    /// 도넛 중심을 원점으로 하는 세 점 — 조각 바깥 가장자리 → 꺾임점 → 라벨.
    struct Placement: Identifiable, Equatable {
        let label: String
        let side: Side
        let edgePoint: CGPoint
        let bendPoint: CGPoint
        let labelPoint: CGPoint

        var id: String { label }
    }

    /// 같은 쪽 라벨끼리 지켜야 할 최소 세로 간격.
    static let minGap: CGFloat = 16

    /// - Parameters:
    ///   - slices: 라벨 + 비율. 순서는 누적 각도 순(12시부터 시계 방향)이어야 한다.
    ///   - radius: 지시선이 시작하는 가장자리 반지름.
    ///   - bendX: 꺾임점의 중심에서 가로 거리(오른쪽/왼쪽은 함수가 부호를 맞춘다).
    ///   - labelX: 라벨이 앉는 점의 중심에서 가로 거리.
    /// - Returns: `slices`와 같은 개수·순서의 배치. 조각이 없으면 빈 배열.
    static func place(_ slices: [Slice], radius: CGFloat, bendX: CGFloat, labelX: CGFloat) -> [Placement] {
        guard !slices.isEmpty else { return [] }

        var cursor: CGFloat = 0
        let edged: [(index: Int, slice: Slice, side: Side, edge: CGPoint)] = slices.enumerated().map { index, slice in
            let midFraction = cursor + slice.fraction / 2
            cursor += slice.fraction
            let midDeg = midFraction * 360
            // 12시가 0도, 시계 방향(`DonutChart`와 같은 방향). 12시~6시(0..<180)가 오른쪽 반원이다.
            let side: Side = midDeg < 180 ? .right : .left
            let standardRad = (90 - midDeg) * .pi / 180
            let edge = CGPoint(x: radius * cos(standardRad), y: -radius * sin(standardRad))
            return (index, slice, side, edge)
        }

        var results = [Placement?](repeating: nil, count: slices.count)
        for side in [Side.right, Side.left] {
            // **세로 위치로 정렬한다** — 오른쪽은 각도 순과 같고, 왼쪽은 각도가 아래(180도)에서
            // 위(360도)로 갈수록 화면에서도 아래→위로 움직여 결과가 같다.
            let group = edged.filter { $0.side == side }.sorted { $0.edge.y < $1.edge.y }
            var previousY: CGFloat?
            for item in group {
                var y = item.edge.y
                if let previousY, y < previousY + minGap {
                    y = previousY + minGap
                }
                previousY = y
                let signedBendX = side == .right ? bendX : -bendX
                let signedLabelX = side == .right ? labelX : -labelX
                results[item.index] = Placement(label: item.slice.label, side: side,
                                                 edgePoint: item.edge,
                                                 bendPoint: CGPoint(x: signedBendX, y: y),
                                                 labelPoint: CGPoint(x: signedLabelX, y: y))
            }
        }
        // 모든 인덱스가 좌/우 어느 한쪽에서 정확히 한 번씩 채워진다.
        return results.compactMap { $0 }
    }
}
