import SwiftUI

/// 주행 통계 타일 셋 — 역대 최고 속도 / 월 평균 / 연 평균.
///
/// **다섯째 차트를 더하지 않는다.** 이 탭에는 이미 카드가 넷 있고, 여기 들어갈 값 셋은
/// 추세가 아니라 지금의 숫자다.
///
/// **평균으로 바꾼 이유:** 「이번 달·올해」는 시점에 끌려다닌다 — 매달 1일에 0으로 떨어지고
/// 12월에 가장 커진다. 그 숫자로는 「내가 얼마나 타는 사람인가」를 알 수 없다.
///
/// **세 칸 모두 기간 칩을 따르지 않는다** — 역대 최고는 전 기간이고, 평균 둘은 전 기간을
/// 달 수로 나눈 값이다. 그래서 이 카드는 기간 분기 위에 그린다.
///
/// **뷰모델이 낸 값을 그대로 받는다.** 여기서 다시 나누면 화면에 나오는 값과 테스트하는 값이
/// 서로 다른 코드가 된다.
struct DriveStatsCard: View {
    let maxSpeedKmh: Int?
    let avgMonthlyKm: Decimal?
    let avgYearlyKm: Decimal?

    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                tile(VehicleFormat.speed(maxSpeedKmh), "역대 최고")
                tile(VehicleFormat.distance(avgMonthlyKm), "월 평균")
                tile(VehicleFormat.distance(avgYearlyKm), "연 평균")
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

#Preview("주행 통계") {
    VStack(spacing: 12) {
        DriveStatsCard(maxSpeedKmh: 138,
                       avgMonthlyKm: Decimal(string: "1787.63"),
                       avgYearlyKm: Decimal(string: "21451.56"))
        DriveStatsCard(maxSpeedKmh: nil, avgMonthlyKm: nil, avgYearlyKm: nil)
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
