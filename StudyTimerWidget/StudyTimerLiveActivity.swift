import ActivityKit
import SwiftUI
import WidgetKit

struct StudyTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyTimerAttributes.self) { context in
            // MARK: - Lock Screen
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded
                DynamicIslandExpandedRegion(.center) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.subjectName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            timerText(context: context)
                                .font(.title3.monospacedDigit().weight(.semibold))
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            toggleButton(isRunning: context.state.timerState == .running)
                            circleButton(deepLink: .end, icon: "stop.fill", color: .red)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                timerText(context: context)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
            } minimal: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private func toggleButton(isRunning: Bool) -> some View {
        if isRunning {
            circleButton(deepLink: .pause, icon: "pause.fill", color: .orange)
        } else {
            circleButton(deepLink: .resume, icon: "play.fill", color: .green)
        }
    }

    private func circleButton(deepLink: StudyDeepLink, icon: String, color: Color) -> some View {
        Link(destination: deepLink.url) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.2))
                .clipShape(Circle())
        }
    }

    private func pillButton(deepLink: StudyDeepLink, title: String, icon: String, color: Color) -> some View {
        Link(destination: deepLink.url) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(color.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Lock Screen View

    private func lockScreenView(context: ActivityViewContext<StudyTimerAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.subjectName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if context.state.timerState == .paused {
                        Text("일시정지")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                timerText(context: context)
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 12) {
                if context.state.timerState == .running {
                    pillButton(deepLink: .pause, title: "일시정지", icon: "pause.fill", color: .orange)
                } else {
                    pillButton(deepLink: .resume, title: "재개", icon: "play.fill", color: .green)
                }
                pillButton(deepLink: .end, title: "종료", icon: "stop.fill", color: .red)
            }
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.8))
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: - Timer Text

    @ViewBuilder
    private func timerText(context: ActivityViewContext<StudyTimerAttributes>) -> some View {
        if context.state.timerState == .running {
            Text(context.state.startDate, style: .timer)
        } else {
            let h = context.state.pausedElapsed / 3600
            let m = (context.state.pausedElapsed % 3600) / 60
            let s = context.state.pausedElapsed % 60
            Text(String(format: "%02d:%02d:%02d", h, m, s))
        }
    }

}
