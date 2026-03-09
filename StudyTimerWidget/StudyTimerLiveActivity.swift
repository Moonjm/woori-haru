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
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.subjectName, systemImage: "book.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(context: context)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        if context.state.timerState == "running" {
                            Link(destination: URL(string: "wooriharu://study/pause")!) {
                                Label("일시정지", systemImage: "pause.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.orange.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        } else {
                            Link(destination: URL(string: "wooriharu://study/resume")!) {
                                Label("재개", systemImage: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.green.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        Link(destination: URL(string: "wooriharu://study/end")!) {
                            Label("종료", systemImage: "stop.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(.red.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } compactLeading: {
                // MARK: - Compact Leading
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                // MARK: - Compact Trailing
                timerText(context: context)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                // MARK: - Minimal
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Lock Screen View

    private func lockScreenView(context: ActivityViewContext<StudyTimerAttributes>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.subjectName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if context.state.timerState == "paused" {
                    Text("일시정지")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            timerText(context: context)
                .font(.title.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.7))
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: - Timer Text

    @ViewBuilder
    private func timerText(context: ActivityViewContext<StudyTimerAttributes>) -> some View {
        if context.state.timerState == "running" {
            Text(context.state.startDate, style: .timer)
        } else {
            let h = context.state.pausedElapsed / 3600
            let m = (context.state.pausedElapsed % 3600) / 60
            let s = context.state.pausedElapsed % 60
            Text(String(format: "%02d:%02d:%02d", h, m, s))
        }
    }
}
