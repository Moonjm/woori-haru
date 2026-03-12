import ActivityKit
import OSLog
import SwiftUI
import UserNotifications

private let alarmIntervalKey = "alarmIntervalMinutes"
private let maxScheduledAlarms = 20

enum TimerState {
    case idle
    case running
    case paused
}

@MainActor
@Observable
final class StudyTimerViewModel {
    // MARK: - State
    var subjects: [StudySubject] = []
    var selectedSubject: StudySubject?
    var timerState: TimerState = .idle
    var elapsedSeconds: Int = 0
    var todaySessions: [StudySession] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Subject Management
    var showAddSubject = false
    var newSubjectName = ""
    var editingSubject: StudySubject?
    var editSubjectName = ""

    // MARK: - Daily Goal
    var dailyGoalMinutes: Int = 0
    var dailyGoalText: String = ""

    // MARK: - Weekly Summary
    var weeklyGoalMinutes: Int = 0
    var weeklyActualMinutes: Int = 0

    // MARK: - Pause Types
    var pauseTypes: [PauseType] = []
    var selectedPauseType: String = "REST"

    // MARK: - Alarm
    var alarmIntervalMinutes: Int {
        get { UserDefaults.standard.integer(forKey: alarmIntervalKey) }
        set { UserDefaults.standard.set(newValue, forKey: alarmIntervalKey) }
    }
    var alarmIntervalText: String = {
        let saved = UserDefaults.standard.integer(forKey: alarmIntervalKey)
        return saved > 0 ? "\(saved)" : ""
    }()

    // MARK: - Private
    private let logger = Logger(subsystem: "com.wooriharu", category: "StudyTimer")
    private let service = StudyService()
    private var activeSessionId: Int?
    nonisolated(unsafe) private var timer: Timer? {
        willSet { timer?.invalidate() }
    }
    private var lastAlarmSeconds: Int = 0
    private var liveActivity: Activity<StudyTimerAttributes>?
    private var timerStartDate: Date?

    // MARK: - Computed

    var elapsedFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var todayTotalSeconds: Int {
        todaySessions.reduce(0) { $0 + $1.totalSeconds }
    }

    var todayTotalWithCurrentSeconds: Int {
        todayTotalSeconds + (timerState != .idle ? elapsedSeconds : 0)
    }

    var todayTotalFormatted: String {
        let total = todayTotalWithCurrentSeconds
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d시간 %d분", h, m)
    }

    var todaySessionCount: Int {
        todaySessions.count + (timerState != .idle ? 1 : 0)
    }

    var goalProgress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return Double(todayTotalWithCurrentSeconds) / Double(dailyGoalMinutes * 60)
    }

    var goalProgressClamped: Double {
        min(goalProgress, 1.0)
    }

    var goalPercentText: String {
        "\(Int(goalProgress * 100))%"
    }

    var dailyGoalFormatted: String? {
        guard dailyGoalMinutes > 0 else { return nil }
        let h = dailyGoalMinutes / 60
        let m = dailyGoalMinutes % 60
        if h > 0 {
            return m > 0 ? "목표 \(h)시간 \(m)분" : "목표 \(h)시간"
        }
        return "목표 \(m)분"
    }

    // MARK: - Weekly Computed

    /// 주간 목표 = API(월~어제) + 오늘 목표
    var weeklyTotalGoalMinutes: Int {
        weeklyGoalMinutes + dailyGoalMinutes
    }

    /// 주간 실제 = API(월~어제) + 오늘 실제(세션 + 진행중)
    var weeklyTotalActualSeconds: Int {
        weeklyActualMinutes * 60 + todayTotalWithCurrentSeconds
    }

    var weeklyTotalActualFormatted: String {
        let total = weeklyTotalActualSeconds
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d시간 %d분", h, m)
    }

    var weeklyGoalFormatted: String? {
        let total = weeklyTotalGoalMinutes
        guard total > 0 else { return nil }
        let h = total / 60
        let m = total % 60
        if h > 0 {
            return m > 0 ? "목표 \(h)시간 \(m)분" : "목표 \(h)시간"
        }
        return "목표 \(m)분"
    }

    var weeklyGoalProgress: Double {
        let goalSeconds = weeklyTotalGoalMinutes * 60
        guard goalSeconds > 0 else { return 0 }
        return Double(weeklyTotalActualSeconds) / Double(goalSeconds)
    }

    var weeklyGoalProgressClamped: Double {
        min(weeklyGoalProgress, 1.0)
    }

    var weeklyGoalPercentText: String {
        "\(Int(weeklyGoalProgress * 100))%"
    }

    // MARK: - Load

    func restoreActiveSession() async {
        do {
            guard let session = try await service.fetchActiveSession() else { return }
            activeSessionId = session.id
            selectedSubject = subjects.first { $0.id == session.subject.id }

            let isPaused = session.pauses.contains { $0.resumedAt == nil }
            let elapsed = calculateElapsed(session: session)
            elapsedSeconds = elapsed

            let intervalSeconds = alarmIntervalMinutes * 60
            if intervalSeconds > 0 {
                lastAlarmSeconds = (elapsed / intervalSeconds) * intervalSeconds
            }

            if isPaused {
                timerState = .paused
                if let lastPause = session.pauses.last(where: { $0.resumedAt == nil }),
                   let type = lastPause.type {
                    selectedPauseType = type
                }
            } else {
                timerState = .running
                timerStartDate = Date().addingTimeInterval(TimeInterval(-elapsed))
                startTimer()
                scheduleAlarmNotifications()
            }

            // Live Activity 복원
            if let subjectName = selectedSubject?.name {
                await startLiveActivity(subjectName: subjectName)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func calculateElapsed(session: StudySession) -> Int {
        guard let startDate = parseISO(session.startedAt) else { return 0 }
        let now = Date()
        let totalDuration = Int(now.timeIntervalSince(startDate))
        let pausedDuration = session.pauses.reduce(0) { total, pause in
            guard let pauseStart = parseISO(pause.pausedAt) else { return total }
            let pauseEnd = pause.resumedAt.flatMap { parseISO($0) } ?? now
            return total + Int(pauseEnd.timeIntervalSince(pauseStart))
        }
        return max(0, totalDuration - pausedDuration)
    }

    private func parseISO(_ string: String) -> Date? {
        Date.fromISO(string)
    }

    // MARK: - Daily Goal

    func loadDailyGoal(silent: Bool = false) async {
        do {
            if let goal = try await service.fetchDailyGoal(),
               let minutes = goal.goalMinutes {
                dailyGoalMinutes = minutes
                dailyGoalText = goalMinutesToHoursText(minutes)
            }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func saveDailyGoal() async {
        let hours = Double(dailyGoalText) ?? 0
        let minutes = Int((hours * 60).rounded())
        guard minutes > 0 else {
            errorMessage = "올바른 시간을 입력해 주세요"
            return
        }
        do {
            try await service.setDailyGoal(goalMinutes: minutes)
            dailyGoalMinutes = minutes
            dailyGoalText = goalMinutesToHoursText(minutes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goalMinutesToHoursText(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            return "\(minutes / 60)"
        }
        return String(format: "%.1f", Double(minutes) / 60.0)
    }

    func loadWeeklySummary(silent: Bool = false) async {
        do {
            let summary = try await service.fetchWeeklySummary()
            weeklyGoalMinutes = summary.totalGoalMinutes
            weeklyActualMinutes = summary.totalActualMinutes
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func loadPauseTypes() async {
        do {
            pauseTypes = try await service.fetchPauseTypes()
        } catch {
            // 실패해도 기본 동작에 영향 없음
        }
    }

    func selectPauseType(_ type: String) {
        let previous = selectedPauseType
        selectedPauseType = type
        guard let id = activeSessionId else { return }
        Task {
            do {
                try await service.setPauseType(sessionId: id, pauseType: type)
            } catch {
                selectedPauseType = previous
                errorMessage = "일시정지 타입 변경에 실패했습니다"
            }
        }
    }

    func loadSubjects() async {
        do {
            subjects = try await service.fetchSubjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTodaySessions(silent: Bool = false) async {
        let today = Date().dateString
        do {
            todaySessions = try await service.fetchSessions(from: today, to: today)
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Timer Actions

    func start() async {
        guard !isLoading, let subject = selectedSubject else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let sessionId = try await service.startSession(subjectId: subject.id)
            activeSessionId = sessionId
            timerState = .running
            elapsedSeconds = 0
            lastAlarmSeconds = 0
            timerStartDate = Date()
            startTimer()
            await startLiveActivity(subjectName: subject.name)
            await requestNotificationPermission()
            scheduleAlarmNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() async {
        guard !isLoading, let id = activeSessionId else { return }
        isLoading = true
        defer { isLoading = false }
        // API 결과와 관계없이 즉시 타이머/알림 정리
        stopTimer()
        removeScheduledAlarms()
        timerState = .paused
        selectedPauseType = "REST"
        do {
            try await service.pauseSession(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
        await updateLiveActivity()
    }

    func resume() async {
        guard !isLoading, let id = activeSessionId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.resumeSession(id: id)
            timerState = .running
            timerStartDate = Date().addingTimeInterval(TimeInterval(-elapsedSeconds))
            startTimer()
            scheduleAlarmNotifications()
            await updateLiveActivity()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func end() async {
        guard !isLoading, let id = activeSessionId else { return }
        isLoading = true
        defer { isLoading = false }
        // API 결과와 관계없이 즉시 타이머/알림 정리
        stopTimer()
        removeAlarmNotifications()
        do {
            try await service.endSession(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
        timerState = .idle
        activeSessionId = nil
        elapsedSeconds = 0
        timerStartDate = nil
        await endLiveActivity()
        await loadTodaySessions()
        await loadWeeklySummary()
    }

    // MARK: - Subject CRUD

    func addSubject() async {
        let name = newSubjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            _ = try await service.createSubject(name: name)
            newSubjectName = ""
            showAddSubject = false
            await loadSubjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSubject() async {
        guard let subject = editingSubject else { return }
        let name = editSubjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await service.updateSubject(id: subject.id, name: name)
            editingSubject = nil
            editSubjectName = ""
            await loadSubjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSubject(_ subject: StudySubject) async {
        do {
            try await service.deleteSubject(id: subject.id)
            if selectedSubject?.id == subject.id {
                selectedSubject = nil
            }
            await loadSubjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.timerStartDate else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(start))
                self.checkAlarm()
            }
        }
    }

    private func stopTimer() {
        timer = nil
    }

    /// 포그라운드 복귀 시 경과 시간 및 Live Activity 동기화
    func syncOnForeground() {
        Task {
            async let sessions: () = loadTodaySessions(silent: true)
            async let goal: () = loadDailyGoal(silent: true)
            async let weekly: () = loadWeeklySummary(silent: true)
            _ = await (sessions, goal, weekly)
        }
        guard timerState != .idle else { return }
        if timerState == .running, let start = timerStartDate {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }
        // Live Activity 참조가 사라진 경우 기존 활동 복원 또는 재생성
        restoreLiveActivityIfNeeded()
    }

    private func restoreLiveActivityIfNeeded() {
        guard liveActivity == nil, activeSessionId != nil,
              let subjectName = selectedSubject?.name else { return }
        // iOS가 아직 관리 중인 기존 Live Activity 중 현재 과목과 일치하는 것 복원
        if let existing = Activity<StudyTimerAttributes>.activities.first(where: {
            $0.attributes.subjectName == subjectName
        }) {
            liveActivity = existing
            Task { await updateLiveActivity() }
        } else {
            Task { await startLiveActivity(subjectName: subjectName) }
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity(subjectName: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // 기존 Live Activity 모두 종료 (고아 포함)
        await cleanupLiveActivities()

        let attributes = StudyTimerAttributes(subjectName: subjectName)
        let state = makeContentState()

        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            logger.error("Live Activity 시작 실패: \(error)")
        }
    }

    private func updateLiveActivity() async {
        guard let activity = liveActivity else { return }
        let state = makeContentState()
        await activity.update(.init(state: state, staleDate: nil))
    }

    private func endLiveActivity() async {
        guard let activity = liveActivity else { return }
        let state = makeContentState()
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        liveActivity = nil
    }

    private func cleanupLiveActivities() async {
        for activity in Activity<StudyTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }

    private func makeContentState() -> StudyTimerAttributes.ContentState {
        switch timerState {
        case .running:
            return .init(
                timerState: .running,
                startDate: timerStartDate ?? Date(),
                pausedElapsed: 0
            )
        case .paused, .idle:
            return .init(
                timerState: .paused,
                startDate: Date(),
                pausedElapsed: elapsedSeconds
            )
        }
    }

    // MARK: - Alarm

    func saveAlarmInterval() {
        let filtered = alarmIntervalText.filter { $0.isNumber }
        if alarmIntervalText != filtered {
            alarmIntervalText = filtered
        }
        let value = Int(filtered) ?? 0
        alarmIntervalMinutes = max(0, value)
    }

    private func checkAlarm() {
        let intervalSeconds = alarmIntervalMinutes * 60
        guard intervalSeconds > 0 else { return }
        let cumulativeTotal = elapsedSeconds
        let nextAlarmAt = lastAlarmSeconds + intervalSeconds
        if cumulativeTotal >= nextAlarmAt {
            lastAlarmSeconds = (cumulativeTotal / intervalSeconds) * intervalSeconds
            // 예약 알림 갱신 후 즉시 알림 (예약과 중복 방지)
            scheduleAlarmNotifications()
            // 알림 2회 발송 (진동 2번) — 노티는 1개만 유지
            sendAlarmNotification(elapsedSeconds: elapsedSeconds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                guard timerState == .running else { return }
                sendAlarmNotification(elapsedSeconds: elapsedSeconds)
            }
        }
    }

    private func sendAlarmNotification(elapsedSeconds: Int) {
        let center = UNUserNotificationCenter.current()
        // 이전 알림 제거 → 알림센터에 항상 최신 1개만 유지
        center.removeDeliveredNotifications(withIdentifiers: ["study-alarm"])

        let content = UNMutableNotificationContent()
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let subjectName = selectedSubject?.name ?? "공부"
        content.title = subjectName
        content.body = "\(h)시간 \(m)분 경과"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "study-alarm",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    /// 백그라운드에서도 알림이 오도록 미래 시간에 예약
    private func scheduleAlarmNotifications() {
        removeScheduledAlarms()
        let intervalSeconds = alarmIntervalMinutes * 60
        guard intervalSeconds > 0 else { return }

        let center = UNUserNotificationCenter.current()
        let subjectName = selectedSubject?.name ?? "공부"
        let maxSchedule = maxScheduledAlarms
        let baseElapsed = elapsedSeconds

        for i in 1...maxSchedule {
            let targetElapsed = lastAlarmSeconds + intervalSeconds * i
            let delayFromNow = targetElapsed - baseElapsed
            guard delayFromNow > 0 else { continue }

            let content = UNMutableNotificationContent()
            let h = targetElapsed / 3600
            let m = (targetElapsed % 3600) / 60
            content.title = subjectName
            content.body = "\(h)시간 \(m)분 경과"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(delayFromNow), repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "study-scheduled-\(i)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func removeScheduledAlarms() {
        let center = UNUserNotificationCenter.current()
        let ids = (1...maxScheduledAlarms).map { "study-scheduled-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func removeAlarmNotifications() {
        removeScheduledAlarms()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["study-alarm"])
    }

    private func requestNotificationPermission() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

