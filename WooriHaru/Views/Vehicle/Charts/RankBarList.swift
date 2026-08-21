import SwiftUI

/// 이름 있는 것들의 순위를 가로 막대로 낸다. **자주 가는 곳(#24)과 충전소별 비용(#25) 둘이 쓴다.**
///
/// **막대는 0에서 시작한다.** `TemperatureEfficiencyCard`는 밑동을 잘라 그리는데(전비 6.0과
/// 7.6의 26% 차이를 보이려면 그래야 한다), 순위표는 「1등이 2등의 몇 배인가」가 질문이라
/// 밑동을 자르면 그 배수가 거짓이 된다.
///
/// **`id`는 서버가 유일성을 보장한다.** `places`·`chargers` 모두 표시 이름으로 묶여 오므로
/// 이름이 목록 안에서 유일하다.
struct RankBarList: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        /// 막대 길이를 정하는 값. **순위 기준과 같아야 한다** — 다르면 짧은 막대가 위에 온다.
        let value: Decimal
        /// 오른쪽 첫 줄. 순위 기준을 그대로 적는다.
        let primary: String
        /// 오른쪽 둘째 줄. 없으면 「—」다.
        let secondary: String
        /// 그 행에 붙는 한 줄 단서(예: 「4건 금액 없음」). 없으면 nil.
        var note: String?

        var chartPoint: ChartPoint { ChartPoint(id: id, label: label, value: value) }
    }

    let rows: [Row]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxValue = ChartScale.maxValue(rows.map(\.chartPoint))
        VStack(spacing: 8) {
            ForEach(rows) { row in
                bar(row, maxValue: maxValue)
            }
        }
    }

    private func bar(_ row: Row, maxValue: Decimal) -> some View {
        let isSelected = row.id == selectedID
        let ratio = ChartScale.ratio(row.value, max: maxValue)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.primary)
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textSecondary)
                Text(row.secondary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textTertiary)
                    .frame(width: 72, alignment: .trailing)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(VehicleTheme.trackFill)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                        // 값이 0이면 막대를 안 그린다 — 순위표의 0은 「없었다」다.
                        .frame(width: ratio > 0 ? max(3, proxy.size.width * ratio) : 0)
                }
            }
            .frame(height: 8)
            if let note = row.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.warning)
            }
        }
        .contentShape(.rect)
        .onTapGesture { onSelect(row.id) }
    }
}
