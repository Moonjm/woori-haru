import SwiftUI

/// 발산형 막대의 폭. **부호를 담지 않는다** — 방향은 그리는 쪽이 정렬로 정하고
/// 여기서는 크기만 낸다. `ChartScale.divergingRatio`에 최소 폭 규칙만 얹은 것이다.
enum DivergingRankGeometry {
    /// 0이 아닌데 안 보이는 막대를 없앤다 — 「0이다」와 갈려야 한다.
    private static let minimumWidth: CGFloat = 2

    /// `trackWidth`는 기준선 양쪽을 합친 전체 폭이다. 한쪽이 쓸 수 있는 것은 그 절반이다.
    static func halfWidth(_ value: Decimal, maxAbs: Decimal, trackWidth: CGFloat) -> CGFloat {
        let ratio = ChartScale.divergingRatio(value, max: maxAbs)
        guard ratio > 0 else { return 0 }
        return max(minimumWidth, trackWidth / 2 * ratio)
    }
}

/// 이름 있는 것들의 **증감**을 세로 리스트로 낸다. 가운데가 0이고 **오른쪽이 증가, 왼쪽이 감소**다.
///
/// **원형을 새로 둔 이유.** `DivergingMonthlyBarChart`는 부호를 그리지만 9pt 가로축 라벨이라
/// 「일반관리비」가 안 들어가고(달 이름 `8`에 맞춘 원형이다), `RankBarList`는 이름이 들어가지만
/// 막대가 늘 한 방향이라 부호를 못 그린다. 기하 계산은 이미 있는 `ChartScale`을 쓴다.
///
/// **카드가 아니라 리스트만 그린다** — 제목·콜아웃·`GlassCard`는 부르는 쪽이 얹는다.
/// **탭은 콜아웃만 바꾼다**(`onSelect`) — 다른 차트들과 같은 규칙이다.
struct DivergingRankList: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        /// 부호가 뜻을 갖는다. 양수면 올랐다.
        let value: Decimal
        /// 오른쪽에 적는 한 줄. 부호까지 포함한 표기를 부르는 쪽이 만든다.
        let detail: String
    }

    let rows: [Row]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxAbs = ChartScale.maxAbsValue(
            rows.map { ChartPoint(id: $0.id, label: $0.label, value: $0.value) }
        )
        VStack(spacing: 8) {
            ForEach(rows) { row in
                bar(row, maxAbs: maxAbs)
            }
        }
    }

    private func bar(_ row: Row, maxAbs: Decimal) -> some View {
        let isSelected = row.id == selectedID
        // 오른 항목은 경고색이다 — 「더 냈다」가 이 리스트가 답하는 질문이다.
        let up = row.value > 0
        let fill = up ? VehicleTheme.warning : VehicleTheme.accent
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.detail)
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? fill : VehicleTheme.textSecondary)
            }
            GeometryReader { proxy in
                let width = DivergingRankGeometry.halfWidth(row.value, maxAbs: maxAbs,
                                                            trackWidth: proxy.size.width)
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 3).fill(VehicleTheme.trackFill)
                    // 기준선(0)은 늘 그린다 — 「여기가 0이다」를 눈으로 준다.
                    Rectangle()
                        .fill(VehicleTheme.cardStroke)
                        .frame(width: 1)
                    HStack(spacing: 0) {
                        // 감소는 기준선 왼쪽으로, 증가는 오른쪽으로 뻗는다. 빈 쪽을 `Spacer`로
                        // 밀어 두 막대가 늘 가운데에서 시작하게 한다.
                        if up { Spacer(minLength: 0) }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? fill : fill.opacity(0.45))
                            .frame(width: width)
                        if !up { Spacer(minLength: 0) }
                    }
                    .padding(up ? .leading : .trailing, proxy.size.width / 2)
                }
            }
            .frame(height: 10)
        }
        .contentShape(.rect)
        .onTapGesture { onSelect(row.id) }
    }
}

#Preview("발산형 순위 — 전년 동월 대비") {
    let rows = [
        DivergingRankList.Row(id: "난방비", label: "난방비", value: 30_000, detail: "+30,000원"),
        DivergingRankList.Row(id: "일반관리비", label: "일반관리비", value: 5_000, detail: "+5,000원"),
        DivergingRankList.Row(id: "세대전기료", label: "세대전기료", value: -12_400, detail: "-12,400원"),
    ]
    return DivergingRankList(rows: rows, selectedID: "난방비") { _ in }
        .padding()
        .background(VehicleTheme.background)
}
