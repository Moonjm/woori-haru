import SwiftUI

/// 요일 × 시각 7 × 24 히트맵 격자. 손으로 그린다(Swift Charts 아님).
///
/// `DriveTimeHeatmap`(#6 주행 시간대×요일)에서 뽑아낸 원형이다 — #15 충전 시간대×요일도
/// 이것을 쓴다. **`weekday`는 0이 일요일**(PostgreSQL `dow` 그대로)이어야 하는 `DriveTime`
/// 배열 전용이고, 같은 응답의 `weekday` 배열(1=월요일, ISO)과 섞으면 격자가 하루씩 밀린다.
///
/// **행 하나가 접근성 요소 하나다** — 셀마다 달면 168정거장이 되어 되레 못 쓴다. 셀은
/// `.accessibilityHidden`으로 접근성에서 지우고, 행 전체를 합쳐(`.combine`) 요약 한 줄로
/// 대신한다. 그 요약 문구는 호출부마다 말(「주행」·「충전」)이 달라 `accessibilityLabel`
/// 클로저로 받는다 — 격자는 렌더링만 하고 문구는 도메인에 남긴다.
struct HeatmapGrid: View {
    let count: (Int, Int) -> Int
    let maxCount: Int
    let accessibilityLabel: (Int) -> String

    /// 눈금을 다는 시각. 24개를 다 적으면 읽을 수 없다.
    private static let markedHours = [0, 6, 12, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<7, id: \.self) { weekday in
                row(weekday)
            }
            hourAxis
        }
    }

    private func row(_ weekday: Int) -> some View {
        HStack(spacing: 2) {
            Text(DriveFormat.weekdayLabel(weekday))
                .font(.system(size: 10))
                // 주말을 조금 다르게 둔다 — 출퇴근 패턴이 주중에 몰리는지 보는 자리다.
                .foregroundStyle(weekday == 0 || weekday == 6 ? VehicleTheme.warning : VehicleTheme.textSecondary)
                .frame(width: 16, alignment: .leading)
            ForEach(0..<24, id: \.self) { hour in
                cell(weekday: weekday, hour: hour)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(weekday))
    }

    private func cell(weekday: Int, hour: Int) -> some View {
        let value = count(weekday, hour)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color(for: value))
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// 0은 **빈칸**이다 — 옅은 색으로 칠하면 「조금 탔다」로 읽힌다.
    private func color(for value: Int) -> Color {
        guard value > 0, maxCount > 0 else { return VehicleTheme.tileFill }
        return VehicleTheme.accent.opacity(0.15 + 0.85 * Self.intensity(count: value, maxCount: maxCount))
    }

    /// 그 칸의 진하기 비율(0~1) — `count / maxCount`.
    ///
    /// **`maxCount`가 0이면 나누지 않고 0을 돌려준다** — 표본이 아예 없다는 뜻이다.
    /// 「0에 최소 진하기를 주지 않는다」는 판단은 이 함수가 아니라 `color(for:)`의
    /// `value > 0` 가드가 맡는다. 테스트가 바로 닿을 수 있도록 `static`으로 둔다.
    static func intensity(count: Int, maxCount: Int) -> Double {
        guard maxCount > 0 else { return 0 }
        return Double(count) / Double(maxCount)
    }

    private var hourAxis: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: 16)
            ForEach(0..<24, id: \.self) { hour in
                Text(Self.markedHours.contains(hour) ? "\(hour)" : "")
                    .font(.system(size: 8))
                    .foregroundStyle(VehicleTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
