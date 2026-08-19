import SwiftUI

/// 언제 타나 — 요일 × 시각 7 × 24 히트맵. 손으로 그린다.
///
/// **조회를 클로저로 받는다.** 서버가 0인 칸을 빼고 성기게 주므로 168칸을 배열로 펴서
/// 넘기면 뷰가 그 펴는 일을 알아야 한다. 뷰모델이 편 뒤 여기는 「이 칸 몇 회」만 묻는다.
///
/// **`weekday`는 0이 일요일이다**(PostgreSQL `dow` 그대로). 여기서 어긋나면 히트맵 전체가
/// 하루씩 밀리는데, 밀린 채로도 그럴듯해 보여서 눈으로는 잡히지 않는다.
struct DriveTimeHeatmap: View {
    let count: (Int, Int) -> Int
    let maxCount: Int

    /// 눈금을 다는 시각. 24개를 다 적으면 읽을 수 없다.
    private static let markedHours = [0, 6, 12, 18]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("언제 타나")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                ForEach(0..<7, id: \.self) { weekday in
                    row(weekday)
                }
                hourAxis
            }
        }
    }

    /// **행 하나가 접근성 요소 하나다** — 셀마다 달면 168정거장이 되어 되레 못 쓴다.
    /// 셀은 `.accessibilityHidden`으로 접근성에서 지우고, 행 전체를 합쳐(`.combine`)
    /// 요약 한 줄로 대신한다(`rowAccessibilityLabel(_:)`). `DriveBucketCards.swift`와
    /// 같은 방식이다.
    private func row(_ weekday: Int) -> some View {
        HStack(spacing: 2) {
            Text(DriveFormat.weekdayLabel(weekday))
                .font(.system(size: 10))
                // 주말을 조금 다르게 둔다 — 출퇴근 패턴이 주중에 몰리는지 보는 자리다.
                .foregroundStyle(weekday == 0 || weekday == 6 ? Color.orange700 : Color.slate500)
                .frame(width: 16, alignment: .leading)
            ForEach(0..<24, id: \.self) { hour in
                cell(weekday: weekday, hour: hour)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(weekday))
    }

    private func cell(weekday: Int, hour: Int) -> some View {
        let value = count(weekday, hour)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color(for: value))
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// 한 요일의 총합과 가장 많은 시각을 `count` 클로저로 직접 구한다 — 24번
    /// 부르는 것은 라벨 한 줄에 드는 값싼 비용이다(행마다 한 번, 168칸을 다시 펴지 않는다).
    /// 표본이 아예 없는 요일은 「0시 0회」 같은 거짓 피크 대신 그렇게 말한다.
    private func rowAccessibilityLabel(_ weekday: Int) -> String {
        var total = 0
        var peakHour = 0
        var peakCount = 0
        for hour in 0..<24 {
            let value = count(weekday, hour)
            total += value
            if value > peakCount {
                peakCount = value
                peakHour = hour
            }
        }
        let weekdayName = "\(DriveFormat.weekdayLabel(weekday))요일"
        guard total > 0 else { return "\(weekdayName) 주행 없음" }
        return "\(weekdayName) 총 \(DriveFormat.count(total)), 가장 많은 시각 "
            + "\(DriveFormat.hourLabel(peakHour)) \(DriveFormat.count(peakCount))"
    }

    /// 0은 **빈칸**이다 — 옅은 색으로 칠하면 「조금 탔다」로 읽힌다.
    private func color(for value: Int) -> Color {
        guard value > 0, maxCount > 0 else { return Color.slate100 }
        let ratio = Double(value) / Double(maxCount)
        return Color.blue600.opacity(0.15 + 0.85 * ratio)
    }

    private var hourAxis: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: 16)
            ForEach(0..<24, id: \.self) { hour in
                Text(Self.markedHours.contains(hour) ? "\(hour)" : "")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview("히트맵") {
    // 출퇴근이 보이는 모양 — 월~금 08시·17시가 진하다.
    let sample: [Int: Int] = {
        var map: [Int: Int] = [:]
        for weekday in 1...5 {
            map[weekday * 24 + 8] = 35 + weekday
            map[weekday * 24 + 17] = 30 + weekday
            map[weekday * 24 + 12] = 8
        }
        map[0 * 24 + 14] = 12
        map[6 * 24 + 11] = 15
        return map
    }()
    return VStack(spacing: 12) {
        DriveTimeHeatmap(count: { sample[$0 * 24 + $1] ?? 0 }, maxCount: 40)
        // 표본이 없을 때
        DriveTimeHeatmap(count: { _, _ in 0 }, maxCount: 0)
    }
    .padding(16)
    .background(Color.slate50)
}
