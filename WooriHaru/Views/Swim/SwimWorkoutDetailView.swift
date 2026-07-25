import SwiftUI

/// 수영 기록 1건의 상세. 전체 요약과 50m·100m 구간 기록을 보여준다.
struct SwimWorkoutDetailView: View {
    let workout: SwimWorkout
    @State private var splitUnit: Double = 100

    private var splits: [SwimSplit] { workout.splits(every: splitUnit) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard

                if workout.hasLapData {
                    splitUnitPicker
                    splitsCard
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
