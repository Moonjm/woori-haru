import ActivityKit
import OSLog

@MainActor
final class LiveActivityCoordinator {
    private let logger = Logger(subsystem: "com.wooriharu", category: "LiveActivity")
    private var activity: Activity<StudyTimerAttributes>?

    func start(subjectName: String, timerStartDate: Date, elapsedSeconds: Int, timerState: TimerState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await cleanupAll()

        let attributes = StudyTimerAttributes(subjectName: subjectName)
        let state = makeContentState(timerState: timerState, timerStartDate: timerStartDate, elapsedSeconds: elapsedSeconds)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            logger.error("Live Activity 시작 실패: \(error)")
        }
    }

    func update(timerState: TimerState, timerStartDate: Date, elapsedSeconds: Int) async {
        guard let activity else { return }
        let state = makeContentState(timerState: timerState, timerStartDate: timerStartDate, elapsedSeconds: elapsedSeconds)
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end(timerState: TimerState, timerStartDate: Date, elapsedSeconds: Int) async {
        guard let activity else { return }
        let state = makeContentState(timerState: timerState, timerStartDate: timerStartDate, elapsedSeconds: elapsedSeconds)
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        self.activity = nil
    }

    func restoreIfNeeded(subjectName: String, timerState: TimerState, timerStartDate: Date?, elapsedSeconds: Int) {
        guard activity == nil else { return }
        if let existing = Activity<StudyTimerAttributes>.activities.first(where: {
            $0.attributes.subjectName == subjectName
        }) {
            activity = existing
            Task { await update(timerState: timerState, timerStartDate: timerStartDate ?? Date(), elapsedSeconds: elapsedSeconds) }
        } else {
            Task { await start(subjectName: subjectName, timerStartDate: timerStartDate ?? Date(), elapsedSeconds: elapsedSeconds, timerState: timerState) }
        }
    }

    // MARK: - Private

    private func cleanupAll() async {
        for activity in Activity<StudyTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }

    private func makeContentState(timerState: TimerState, timerStartDate: Date, elapsedSeconds: Int) -> StudyTimerAttributes.ContentState {
        switch timerState {
        case .running:
            return .init(timerState: .running, startDate: timerStartDate, pausedElapsed: 0)
        case .paused, .idle:
            return .init(timerState: .paused, startDate: Date(), pausedElapsed: elapsedSeconds)
        }
    }
}
