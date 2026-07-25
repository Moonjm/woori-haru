import SwiftUI

/// 월별 추이 막대 그래프 카드 — 원화 위에 외화 환산을 쌓는 스택 막대.
/// 막대를 탭하면 콜아웃(선택 월 금액)이 바뀐다.
struct LedgerStatsChartCard: View {
    let trend: [LedgerStatistics.MonthlyTotal]
    /// 월별 스코프면 막대 간격이 넓고 라벨에 "월"이 붙는다. 연별(12개)은 숫자만.
    let isMonthlyScope: Bool
    let selectedKey: String?
    let onSelectMonth: (String) -> Void

    var body: some View {
        let maxTotal = trend.map(\.combinedTotal).max() ?? 0
        let selected = trend.first { $0.yearMonth == selectedKey }
        GlassCard {
            VStack(spacing: 12) {
                // 선택한 월의 금액 콜아웃 — 막대를 탭하면 바뀐다.
                if let selected {
                    HStack(spacing: 6) {
                        Text("\(selected.monthNumber)월")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(Color.blue600)
                        Text(LedgerFormat.amount(selected.combinedTotal, currency: "KRW"))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if let fx = selected.fxKrwTotal, fx != 0 {
                            Text("외화 \(LedgerFormat.amount(fx, currency: "KRW"))")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(Color.purple500)
                        }
                        Spacer()
                    }
                    .animation(.snappy, value: selected.yearMonth)
                }

                HStack(alignment: .bottom, spacing: isMonthlyScope ? 10 : 5) {
                    ForEach(trend) { item in
                        let isSelected = item.yearMonth == selectedKey
                        let fx = item.fxKrwTotal ?? 0
                        VStack(spacing: 5) {
                            VStack(spacing: 0) {
                                // 외화 환산분을 원화 위에 쌓는다 (음수 순액은 표시 생략)
                                if fx > 0 {
                                    Rectangle()
                                        .fill(isSelected ? AnyShapeStyle(Color.purple500)
                                            : AnyShapeStyle(Color.purple500.opacity(0.3)))
                                        .frame(height: segmentHeight(fx, max: maxTotal))
                                }
                                Rectangle()
                                    .fill(
                                        isSelected
                                            ? AnyShapeStyle(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                                           startPoint: .top, endPoint: .bottom))
                                            : AnyShapeStyle(Color.blue500.opacity(0.25))
                                    )
                                    .frame(height: barHeight(item.krwTotal, max: maxTotal))
                            }
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                            // 12개 막대(연별)는 폭이 좁아 "월" 없이 숫자만 표시
                            Text(isMonthlyScope ? "\(item.monthNumber)월" : "\(item.monthNumber)")
                                .font(.system(size: 9, weight: isSelected ? .heavy : .bold))
                                .foregroundStyle(isSelected ? Color.blue600 : Color.slate400)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect) // 막대가 낮아도 열 전체가 탭되게
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) { onSelectMonth(item.yearMonth) }
                        }
                    }
                }
                .frame(height: 130, alignment: .bottom)
            }
        }
    }

    /// 원화(바닥) 세그먼트 — 빈 달도 최소 높이로 탭 대상이 되게 한다.
    private func barHeight(_ total: Decimal, max maxTotal: Decimal) -> CGFloat {
        guard maxTotal > 0 else { return 4 }
        let ratio = (total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
        return Swift.max(4, CGFloat(ratio) * 105)
    }

    /// 외화(위) 세그먼트 — 없으면 0, 최소 높이 없이 비율 그대로.
    private func segmentHeight(_ total: Decimal, max maxTotal: Decimal) -> CGFloat {
        guard maxTotal > 0, total > 0 else { return 0 }
        let ratio = (total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
        return CGFloat(ratio) * 105
    }
}

/// 차트 범례 — 외화 환산 지출이 있을 때만 섹션 헤더 옆에 표시.
struct LedgerStatsChartLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(color: Color.blue600, label: "원화")
            legendItem(color: Color.purple500, label: "외화")
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.slate500)
        }
    }
}
