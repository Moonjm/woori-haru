import SwiftUI

private let narrowProgressThreshold = 0.11
private let progressBarHeight: CGFloat = 28
private let progressBarCornerRadius: CGFloat = 12

/// 오늘 공부 시간·세션 수 요약 카드.
struct StudyTodaySummaryCard: View {
    @Environment(StudyTimerViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("오늘 공부")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.slate400)
                Text(vm.todayTotalFormatted)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.slate900)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 4) {
                Text("세션")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.slate400)
                Text("\(vm.todaySessionCount)회")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.slate900)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 이번 주 목표 카드 — 목표/일평균 표기와 진행 바, 누적·잔여 시간.
struct StudyWeeklyGoalCard: View {
    @Environment(StudyTimerViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("이번 주 목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Text(vm.weeklyGoalFormatted)
                    .font(.subheadline)
                    .foregroundStyle(Color.slate400)
                Text("· \(vm.weeklyDailyAverageFormatted)")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate400)
                Spacer()
            }

            goalProgressBar(
                progress: vm.weeklyGoalProgress,
                progressClamped: vm.weeklyGoalProgressClamped,
                percentText: vm.weeklyGoalPercentText
            )

            HStack {
                Text(vm.weeklyTotalActualFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                Text(vm.weeklyRemainingFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func goalProgressBar(progress: Double, progressClamped: Double, percentText: String) -> some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * progressClamped
            let isNarrow = progressClamped < narrowProgressThreshold
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.slate100)
                if barWidth > 0 {
                    Rectangle()
                        .fill(progress >= 1.0 ? Color.green300 : Color.blue400)
                        .frame(width: barWidth)
                        .overlay {
                            if !isNarrow {
                                Text(percentText)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: progressClamped)
                }
                if isNarrow {
                    Text(percentText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.slate400)
                        .offset(x: barWidth + 8)
                }
            }
            .frame(height: progressBarHeight)
            .clipShape(RoundedRectangle(cornerRadius: progressBarCornerRadius))
        }
        .frame(height: progressBarHeight)
    }
}
