import SwiftUI

/// 애플워치 운동 앱으로 기록한 수영을 건강 앱에서 읽어와 목록으로 보여준다. 읽기 전용.
struct SwimRecordListView: View {
    @State private var vm = SwimRecordViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !vm.workouts.isEmpty {
                    summaryCard
                }

                ForEach(vm.workouts) { workout in
                    NavigationLink(value: workout) {
                        SwimWorkoutRow(workout: workout)
                    }
                    .buttonStyle(.plain)
                    .task { await vm.loadMoreIfNeeded(currentItem: workout) }
                }

                if vm.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 12)
                }

                if vm.showsEmptyState {
                    emptyState
                }

                if vm.showsFailureState {
                    failureState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .glassScreenBackground()
        .navigationTitle("수영 기록")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SwimWorkout.self) {
            SwimWorkoutDetailView(workout: $0, service: vm.service)
        }
        .overlay {
            if vm.isLoading && vm.workouts.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.loadIfNeeded() }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    summaryItem(label: "횟수", value: "\(vm.totalCount)회")
                    Divider().frame(height: 32)
                    summaryItem(label: "총 거리", value: vm.totalDistanceText ?? "-")
                    Divider().frame(height: 32)
                    summaryItem(label: "총 시간", value: vm.totalDurationText)
                }

                // 스크롤할수록 숫자가 커지므로 어디까지의 합인지 밝혀 둔다.
                if vm.canLoadMore {
                    Text("지금까지 불러온 기록 기준")
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate900)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Failure State

    /// 조회 자체가 실패한 경우. 알림을 닫아도 "기록 없음"으로 오인되지 않게 따로 띄운다.
    private var failureState: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(Color.slate400)

                Text("기록을 불러오지 못했습니다")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                Button("다시 시도") {
                    Task { await vm.load() }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.blue500)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 12) {
                Image(systemName: "figure.pool.swim")
                    .font(.largeTitle)
                    .foregroundStyle(Color.slate400)

                Text(vm.isHealthDataAvailable ? "표시할 수영 기록이 없습니다" : "건강 데이터를 쓸 수 없는 기기입니다")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                if vm.isHealthDataAvailable {
                    // 읽기 권한 거부 여부는 앱이 알 수 없어(HealthKit 정책) 두 경우를 함께 안내한다.
                    Text("애플워치 운동 앱의 수영 기록이 건강 앱에 동기화됐는지, 설정에서 '우리 하루'의 건강 읽기 권한이 켜져 있는지 확인해 주세요.")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .multilineTextAlignment(.center)

                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.blue500)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Row

private struct SwimWorkoutRow: View {
    let workout: SwimWorkout

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: workout.location.iconName)
                        .font(.subheadline)
                        .foregroundStyle(Color.blue500)

                    Text(workout.dayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate900)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    Text(workout.timeRangeText)
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .lineLimit(1)
                        .fixedSize()
                }

                HStack(spacing: 16) {
                    metric(icon: "ruler", text: workout.distanceText ?? "-")
                    metric(icon: "clock", text: workout.durationText)
                    if let energyText = workout.energyText {
                        metric(icon: "flame", text: energyText)
                    }
                    if let strokeText = workout.strokeText {
                        metric(icon: "arrow.trianglehead.2.clockwise", text: strokeText)
                    }
                }

                Text(workout.locationText)
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Color.slate400)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.slate700)
        }
    }
}
