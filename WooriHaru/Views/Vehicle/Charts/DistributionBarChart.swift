import SwiftUI

/// 버킷 분포 세로 막대. **카드가 아니라 막대만 그린다** — 껍데기는 `ChartCard`가 얹는다.
///
/// `MonthlyBarChart`와 가르는 이유: 월별 막대는 「기록 없는 달」 때문에 값이 옵셔널이고
/// 라벨이 월 숫자 두 자리다. 분포는 **모든 칸에 값이 있고**(0은 「그 칸에 아무것도 없었다」는
/// 사실이다) 라벨이 「0~20」처럼 길다 — 라벨을 눕혀야 하는 자리가 여기뿐이다.
///
/// **탭은 콜아웃만 바꾼다.**
struct DistributionBarChart: View {
    let points: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var barHeight: CGFloat = 84

    var body: some View {
        let maxValue = ChartScale.maxValue(points)
        let spacing = ChartScale.slotSpacing(count: points.count)
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(points) { point in
                bar(point, maxValue: maxValue)
            }
        }
        .frame(height: barHeight + 22)
    }

    private func bar(_ point: ChartPoint, maxValue: Decimal) -> some View {
        // 인라인으로 두면 SourceKit이 타입 검사를 포기한다 — 1단계 5번 태스크에서 겪었다.
        let isSelected = point.id == selectedID
        let ratio = ChartScale.ratio(point.value, max: maxValue)
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                // 값이 0이면 막대를 남기지 않는다 — 분포에서 0은 「없었다」이고,
                // 최소 높이를 주면 「조금 있었다」로 읽힌다.
                .frame(height: ratio > 0 ? max(3, ratio * barHeight) : 0)
            Text(point.label)
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(point.id) }
    }
}
