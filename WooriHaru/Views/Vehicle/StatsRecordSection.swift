import SwiftUI

/// 통계 탭 「기록」 섹션 — #26 명예의 전당. 최장거리 · 최장시간 · 최고효율 타일 셋.
///
/// **셋이 각각 nil일 수 있다.** 주행이 하나도 없으면 셋 다 nil이고, `bestEfficiency`만
/// 따로 nil인 길이 있다 — **거리 하한 20km를 넘은 주행이 없을 때다**(하한이 없으면
/// 실측으로 0.2km 주행이 8.2배 효율로 1등을 먹어 서버가 하한을 걸었다).
///
/// **하나라도 있으면 섹션을 그린다.** 개별 타일은 자기 레코드가 nil이면 「—」만 보이고
/// 다른 두 타일은 그대로 값을 낸다 — `DriveStatsCard`가 역대 최고·평균 중 없는 값만
/// 「—」로 두는 것과 같다. **셋 다 없을 때만 헤더까지 감춘다**(`showsRecords`).
///
/// **`driveId`는 화면에 쓰지 않는다.** 지금 앱에 주행 상세 화면이 없다 — 서버가
/// 나중을 위해 실어 둔 값이다.
struct StatsRecordSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.showsRecords {
                header
                GlassCard {
                    HStack(spacing: 10) {
                        distanceTile
                        durationTile
                        efficiencyTile
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("🏆 기록")
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(VehicleTheme.textPrimary)
            Spacer(minLength: 8)
            // **`records`는 `months`를 안 따른다** — 서버가 파라미터 없이 전 기간을
            // 조회한다(범위마다 1등이 바뀌면 기록이 아니다). 급속/완속 도넛
            // (`StatsChargeSection.fastSlowCard`)과 같은 이유로 글자로 범위를 드러낸다 —
            // 안 그러면 주행 없는 기간을 골랐을 때 「기록 없음」 안내 바로 아래에
            // 몇 년 전 기록 타일이 떠서 어느 기간 이야기인지 헷갈린다.
            Text("전 기간")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textTertiary)
        }
        .padding(.top, 4)
    }

    // MARK: - 타일

    private var distanceTile: some View {
        let record = viewModel.insights?.records.longestDistance
        return tile(VehicleFormat.distance(record?.distanceKm), "최장거리",
                   date: dateLabel(record?.startDate))
    }

    private var durationTile: some View {
        let record = viewModel.insights?.records.longestDuration
        return tile(ChargeFormat.duration(record?.durationMin), "최장시간",
                   date: dateLabel(record?.startDate))
    }

    /// **비율은 서버가 안 낸다.** `VehicleMath.ratio(_:_:)`로 앱이 낸다 —
    /// `distanceKm ÷ ratedRangeUsedKm`.
    private var efficiencyTile: some View {
        let record = viewModel.insights?.records.bestEfficiency
        let ratio = record.flatMap { VehicleMath.ratio($0.distanceKm, $0.ratedRangeUsedKm) }
        return tile(ratioText(ratio), "최고효율", date: dateLabel(record?.startDate))
    }

    /// 1.745… → "1.7배". 브리프의 예(0.2km 주행이 8.2배로 1등)와 같은 말투다 —
    /// 「정격 대비 174%」보다 「1.7배」가 「1등을 먹었다」는 느낌에 더 가깝다.
    private func ratioText(_ ratio: Decimal?) -> String {
        guard let ratio else { return ChargeFormat.placeholder }
        return "\(VehicleFormat.number(ratio, fraction: 1, minFraction: 1))배"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.dateFormat = "yyyy.M.d"
        return formatter
    }()

    private func dateLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private func tile(_ value: String, _ label: String, date: String?) -> some View {
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
            // 기록이 없으면 날짜도 없다 — 「—」 옆에 빈 날짜 줄을 남기지 않는다.
            if let date {
                Text(date)
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(date.map { "\(label) \(value), \($0)" } ?? "\(label) \(value)")
    }
}
