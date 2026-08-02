import SwiftUI

/// 수영 기록 1건의 상세. 요약·운동 강도·영법별 거리와 자동 세트를 보여준다.
struct SwimWorkoutDetailView: View {
    let workout: SwimWorkout
    let service: SwimWorkoutFetching
    @State private var effortScore: Double?
    /// 목록 매핑이 심박수를 못 채운 기록을 여기서 메운다. 채워져 있으면 조회하지 않는다.
    @State private var fetchedHeartRate: SwimHeartRate?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard
                intensityCard

                if workout.hasLapData {
                    strokeBreakdownCard
                    autoSetsCard
                } else {
                    noLapDataCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .glassScreenBackground()
        .navigationTitle(workout.dayText)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 강도가 없는 기록도 많다. 실패하면 그냥 섹션을 숨긴다.
            effortScore = try? await service.fetchEffortScore(workoutID: workout.id)

            // **하나라도 비어 있으면 묻는다.** 평균만 있고 최대가 없는 기록이 있는데, 둘 다
            // 없을 때만 조회하면 그런 기록은 빈 쪽이 영영 안 채워진다
            // (`heartRateTexts(fallback:)`는 필드별로 메운다).
            if workout.averageHeartRateText == nil || workout.maxHeartRateText == nil {
                fetchedHeartRate = try? await service.fetchHeartRate(workoutID: workout.id)
            }
        }
    }

    // MARK: - Intensity

    /// 심박수와 운동 강도. 셋 다 없으면 섹션을 통째로 숨긴다.
    @ViewBuilder
    private var intensityCard: some View {
        let heartRate = workout.heartRateTexts(fallback: fetchedHeartRate)
        let hasAny = heartRate.average != nil || heartRate.maximum != nil || effortScore != nil

        if hasAny {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("운동 강도")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.slate500)

                    HStack(spacing: 0) {
                        if let effortScore {
                            summaryItem(
                                label: Self.effortLabel(effortScore),
                                value: "\(Int(effortScore.rounded()))"
                            )
                        }
                        if let average = heartRate.average {
                            summaryItem(label: "평균 심박", value: average)
                        }
                        if let maximum = heartRate.maximum {
                            summaryItem(label: "최대 심박", value: maximum)
                        }
                    }
                }
            }
        }
    }

    /// 애플의 1~10 강도 척도를 말로 옮긴 것
    private static func effortLabel(_ score: Double) -> String {
        switch Int(score.rounded()) {
        case ...3: "가벼움"
        case 4...6: "보통"
        case 7...9: "힘듦"
        default: "최대"
        }
    }

    // MARK: - Stroke Breakdown

    @ViewBuilder
    private var strokeBreakdownCard: some View {
        let breakdown = workout.strokeBreakdown

        if breakdown.count > 1 || breakdown.first?.style != .unknown {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("영법별 거리")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.slate500)

                    ForEach(breakdown) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.style.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.slate700)
                                Spacer()
                                Text(item.metersText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.slate900)
                                Text(item.paceText)
                                    .font(.caption2)
                                    .foregroundStyle(Color.slate400)
                            }

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue400)
                                    .frame(width: max(geo.size.width * item.ratio, 2))
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: workout.location.iconName)
                        .foregroundStyle(Color.blue500)
                    Text(workout.locationText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate900)
                    Spacer()
                    Text(workout.timeRangeText)
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                }

                Divider()

                HStack(spacing: 0) {
                    summaryItem(label: "거리", value: workout.distanceText ?? "-")
                    summaryItem(label: "시간", value: workout.durationText)
                    summaryItem(label: "칼로리", value: workout.energyText ?? "-")
                    summaryItem(label: "스트로크", value: workout.strokeText ?? "-")
                }
            }
        }
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Auto Sets

    /// 쉬는 구간으로 나눈 세트. 턴 시간이 포함된 실제 기록이라 피트니스 앱 표기와 같은 기준이다.
    private var autoSetsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("자동 세트", note: "턴 포함")

                ForEach(workout.sets) { set in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("\(set.id)")
                                .font(.caption2)
                                .foregroundStyle(Color.slate400)
                                .frame(width: 16, alignment: .leading)
                            Text(set.strokeStyle.label)
                                .font(.caption)
                                .foregroundStyle(Color.slate600)
                            Spacer()
                            Text(set.distanceText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.slate900)
                            Text(set.paceText)
                                .font(.caption2)
                                .foregroundStyle(Color.slate400)
                                .frame(width: 76, alignment: .trailing)
                        }

                        HStack(spacing: 10) {
                            Text("수영 \(set.durationText)")
                                .foregroundStyle(Color.slate700)
                            if let restText = set.restText {
                                Text("휴식 \(restText)")
                                    .foregroundStyle(Color.slate400)
                            }
                        }
                        .font(.caption2.monospacedDigit())
                        .padding(.leading, 24)
                    }
                    .padding(.vertical, 4)

                    if set.id != workout.sets.count {
                        Divider()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate500)
            Text(note)
                .font(.caption2)
                .foregroundStyle(Color.slate400)
        }
    }

    // MARK: - No Lap Data

    private var noLapDataCard: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 8) {
                Text("세트 기록이 없습니다")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                // 개방 수역은 턴이 없어 랩이 남지 않고, 수영장이어도 레인 길이가 없으면 거리를 못 나눈다.
                Text("개방 수역에서 기록했거나 레인 길이 정보가 없으면 세트를 나눌 수 없습니다.")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
        }
    }
}
