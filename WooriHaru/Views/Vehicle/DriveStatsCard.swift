import SwiftUI

/// 주행 통계 타일 셋 — 역대 최고 속도 / 이번 달 / 올해.
///
/// **다섯째 차트를 더하지 않는다.** 이 탭에는 이미 카드가 넷 있고, 여기 들어갈 값 셋은
/// 추세가 아니라 지금의 숫자다. 연도별 막대는 저울질했지만 두지 않았다.
///
/// **라벨이 「최고 속도」가 아니라 「역대 최고」인 이유**는 이 칸만 기간 칩을 따르지 않아서다.
/// 옆 두 칸은 이번 달·올해이고 이 칸은 전 기간이다 — 범위 차이를 글자가 말해야 한다.
struct DriveStatsCard: View {
    let maxSpeedKmh: Int?
    let monthDistanceKm: Decimal?
    let yearDistanceKm: Decimal?

    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                tile(VehicleFormat.speed(maxSpeedKmh), "역대 최고")
                tile(VehicleFormat.distance(monthDistanceKm), "이번 달")
                tile(VehicleFormat.distance(yearDistanceKm), "올해")
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

#Preview("주행 통계") {
    VStack(spacing: 12) {
        DriveStatsCard(maxSpeedKmh: 138,
                       monthDistanceKm: Decimal(string: "1331.3"),
                       yearDistanceKm: Decimal(string: "13440.4"))
        DriveStatsCard(maxSpeedKmh: nil, monthDistanceKm: 0, yearDistanceKm: 0)
    }
    .padding(16)
    .background(Color.slate50)
}
