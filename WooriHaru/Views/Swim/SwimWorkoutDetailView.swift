import SwiftUI

/// 수영 기록 1건의 상세. 전체 요약과 50m·100m 구간 기록을 보여준다.
struct SwimWorkoutDetailView: View {
    let workout: SwimWorkout
    let service: SwimWorkoutFetching
    @State private var splitUnit: Double = 100
    @State private var effortScore: Double?

    private var splits: [SwimSplit] { workout.splits(every: splitUnit) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard
                intensityCard

                if workout.hasLapData {
                    strokeBreakdownCard
                    splitUnitPicker
                    splitsCard
                    rawLapCard
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
        }
    }

    // MARK: - Intensity

    /// 심박수와 운동 강도. 셋 다 없으면 섹션을 통째로 숨긴다.
    @ViewBuilder
    private var intensityCard: some View {
        let hasAny = workout.averageHeartRateText != nil
            || workout.maxHeartRateText != nil
            || effortScore != nil

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
                        if let average = workout.averageHeartRateText {
                            summaryItem(label: "평균 심박", value: average)
                        }
                        if let maximum = workout.maxHeartRateText {
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

    // MARK: - Splits

    private var splitUnitPicker: some View {
        Picker("구간 단위", selection: $splitUnit) {
            ForEach(SwimWorkout.splitOptions, id: \.self) { unit in
                Text("\(Int(unit))m").tag(unit)
            }
        }
        .pickerStyle(.segmented)
    }

    private var splitsCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                splitHeader

                ForEach(splits) { split in
                    Divider().padding(.vertical, 2)
                    splitRow(split)
                }
            }
        }
    }

    private var splitHeader: some View {
        HStack {
            Text("구간")
                .frame(width: 64, alignment: .leading)
            Text("기록")
                .frame(width: 64, alignment: .trailing)
            Spacer()
            Text("페이스")
        }
        .font(.caption2)
        .foregroundStyle(Color.slate400)
        .padding(.bottom, 4)
    }

    private func splitRow(_ split: SwimSplit) -> some View {
        HStack {
            Text(split.distanceText)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate700)
                .frame(width: 64, alignment: .leading)

            Text(split.durationText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate900)
                .frame(width: 64, alignment: .trailing)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(split.paceText)
                    .font(.caption)
                    .foregroundStyle(Color.slate600)
                if split.strokeStyle != .unknown {
                    Text(split.strokeStyle.label)
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Raw Laps (진단용)

    /// 워치가 준 랩 데이터를 가공 없이 보여준다. 피트니스 앱 자동 세트와 시간이
    /// 어긋나는 원인을 찾기 위한 임시 섹션 — 원인 확인 후 걷어낸다.
    private var rawLapCard: some View {
        GlassCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticRow("랩 개수", "\(workout.laps.count)개")
                    diagnosticRow("랩 거리 합", "\(Int(workout.lapsTotalDistance.rounded()))m")
                    diagnosticRow("워크아웃 총 거리", workout.distanceText ?? "-")
                    diagnosticRow("랩 시간 합", SwimSplit.clockText(workout.lapsTotalDuration))
                    diagnosticRow("워크아웃 총 시간", SwimSplit.clockText(workout.duration))
                    diagnosticRow(
                        "시작~종료 경과",
                        SwimSplit.clockText(workout.endDate.timeIntervalSince(workout.startDate))
                    )

                    Divider().padding(.vertical, 4)

                    ForEach(workout.laps) { lap in
                        HStack {
                            Text("#\(lap.id + 1)")
                                .frame(width: 40, alignment: .leading)
                            Text("+\(SwimSplit.clockText(lap.startDate.timeIntervalSince(workout.startDate)))")
                                .frame(width: 64, alignment: .leading)
                            Text(SwimSplit.clockText(lap.duration))
                                .frame(width: 56, alignment: .trailing)
                            Spacer()
                            Text(lap.strokeStyle.label)
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.slate600)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("랩 원본 (진단용)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.slate500)
            }
        }
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.slate500)
            Spacer()
            Text(value)
                .foregroundStyle(Color.slate900)
        }
        .font(.caption.monospacedDigit())
    }

    // MARK: - No Lap Data

    private var noLapDataCard: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 8) {
                Text("구간 기록이 없습니다")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                // 개방 수역은 턴이 없어 랩이 남지 않고, 수영장이어도 레인 길이가 없으면 거리를 못 나눈다.
                Text("개방 수역에서 기록했거나 레인 길이 정보가 없으면 구간을 나눌 수 없습니다.")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
        }
    }
}
