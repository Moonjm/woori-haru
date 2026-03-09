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
                            if context.state.timerState == .running {
                                Link(destination: URL(string: "wooriharu://study/pause")!) {
                                    Image(systemName: "pause.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .frame(width: 32, height: 32)
                                        .background(.orange.opacity(0.2))
                                        .clipShape(Circle())
                                }
                            } else {
                                Link(destination: URL(string: "wooriharu://study/resume")!) {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .frame(width: 32, height: 32)
                                        .background(.green.opacity(0.2))
                                        .clipShape(Circle())
                                }
                            }
                            Link(destination: URL(string: "wooriharu://study/end")!) {
                                Image(systemName: "stop.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(width: 32, height: 32)
                                    .background(.red.opacity(0.2))
                                    .clipShape(Circle())
                            }
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
                    .frame(width: 45)
            } minimal: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            }
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
