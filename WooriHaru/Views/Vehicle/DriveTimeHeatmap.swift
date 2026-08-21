import SwiftUI

/// 언제 타나 — 카드 껍데기와 「N회 기준」 콜아웃. 격자 자체는 `HeatmapGrid`(#6·#15가
/// 함께 쓰는 원형)에 맡긴다.
///
/// **조회를 클로저로 받는다.** 서버가 0인 칸을 빼고 성기게 주므로 168칸을 배열로 펴서
/// 넘기면 뷰가 그 펴는 일을 알아야 한다. 뷰모델이 편 뒤 여기는 「이 칸 몇 회」만 묻는다.
///
/// **`weekday`는 0이 일요일이다**(PostgreSQL `dow` 그대로). 여기서 어긋나면 히트맵 전체가
/// 하루씩 밀리는데, 밀린 채로도 그럴듯해 보여서 눈으로는 잡히지 않는다.
struct DriveTimeHeatmap: View {
    let count: (Int, Int) -> Int
    let maxCount: Int
    /// **거리 카드와 같은 수다** — 온도 카드는 주행가능거리 소모가 0 이하인 주행을
    /// 걸러 내 939로 다르게 나오므로, 여기는 거리·시간대가 서는 959를 그대로 쓴다.
    let driveCount: Int

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                // `DriveBucketCards.swift`의 `header(_:_:)`와 같은 모양(제목 왼쪽, 모수
                // 오른쪽)을 그대로 맞춘다. 그 헬퍼는 그 파일에 `private`이라 여기서
                // 재사용할 수 없어 모양만 따라 그린다.
                HStack(alignment: .firstTextBaseline) {
                    Text("언제 타나")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer(minLength: 8)
                    Text("\(driveCount)회 기준")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(VehicleTheme.textTertiary)
                }

                HeatmapGrid(count: count, maxCount: maxCount, accessibilityLabel: rowAccessibilityLabel)
            }
        }
    }

    /// 한 요일의 총합과 가장 많은 시각을 `count` 클로저로 직접 구한다 — 24번
    /// 부르는 것은 라벨 한 줄에 드는 값싼 비용이다(행마다 한 번, 168칸을 다시 펴지 않는다).
    /// 표본이 아예 없는 요일은 「0시 0회」 같은 거짓 피크 대신 그렇게 말한다.
    ///
    /// 「주행 없음」처럼 말이 도메인(주행)에 매인 문구라 `HeatmapGrid`가 아니라 여기 남는다 —
    /// #15 충전 히트맵은 같은 격자를 쓰되 이 함수 대신 자기 말로 된 문구를 넘긴다.
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
        DriveTimeHeatmap(count: { sample[$0 * 24 + $1] ?? 0 }, maxCount: 40, driveCount: 959)
        // 표본이 없을 때
        DriveTimeHeatmap(count: { _, _ in 0 }, maxCount: 0, driveCount: 0)
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
