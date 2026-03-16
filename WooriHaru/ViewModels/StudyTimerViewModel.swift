import SwiftUI

enum TimerState {
    case idle
    case running
    case paused
}

@MainActor
@Observable
final class StudyTimerViewModel {
    /// 시작 직후 실수 방지 확인 팝업 기준(초)
    static let earlyConfirmSeconds = 60


    // MARK: - State
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

    // MARK: - Pause
    var selectedPauseType: String = "REST"

    // MARK: - Stores
    private(set) var subjectStore: SubjectStore!
    private(set) var pauseTypeStore: PauseTypeStore!

    func configure(subjectStore: SubjectStore, pauseTypeStore: PauseTypeStore) {
        self.subjectStore = subjectStore
        self.pauseTypeStore = pauseTypeStore
    }

    // MARK: - Dependencies
    let notificationScheduler = NotificationScheduler()
    private let liveActivity = LiveActivityCoordinator()
    private let service = StudyService()
    private var activeSessionId: Int?
    private var timer: Timer? {
        willSet { timer?.invalidate() }
    }
    private var timerStartDate: Date?
    /// 가장 최근 running 전환 시점 (start / resume)
    private(set) var lastRunStartDate: Date?

    // MARK: - Computed

    /// 마지막 시작/재개로부터 earlyConfirmSeconds 이내인지
    /// 앱 재시작 시 lastRunStartDate는 nil이므로 false — 의도적 동작
    var isWithinEarlyConfirm: Bool {
        guard let date = lastRunStartDate else { return false }
        return Date().timeIntervalSince(date) < TimeInterval(Self.earlyConfirmSeconds)
    }

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

    var weeklyTotalGoalMinutes: Int {
        weeklyGoalMinutes + dailyGoalMinutes
    }

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
            selectedSubject = subjectStore.subjects.first { $0.id == session.subject.id }

            let isPaused = session.pauses.contains { $0.resumedAt == nil }
            let elapsed = calculateElapsed(session: session)
            elapsedSeconds = elapsed
            notificationScheduler.restoreAlarmTracking(elapsedSeconds: elapsed)

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
                notificationScheduler.scheduleAlarmNotifications(
                    subjectName: selectedSubject?.name ?? "공부",
                    elapsedSeconds: elapsedSeconds
                )
            }

            if let subjectName = selectedSubject?.name {
                await liveActivity.start(
                    subjectName: subjectName,
                    timerStartDate: timerStartDate ?? Date(),
                    elapsedSeconds: elapsedSeconds,
                    timerState: timerState
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func calculateElapsed(session: StudySession) -> Int {
        guard let startDate = Date.fromISO(session.startedAt) else { return 0 }
        let now = Date()
        let totalDuration = Int(now.timeIntervalSince(startDate))
        let pausedDuration = session.pauses.reduce(0) { total, pause in
            guard let pauseStart = Date.fromISO(pause.pausedAt) else { return total }
            let pauseEnd = pause.resumedAt.flatMap { Date.fromISO($0) } ?? now
            return total + Int(pauseEnd.timeIntervalSince(pauseStart))
        }
        return max(0, totalDuration - pausedDuration)
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
            try await pauseTypeStore.load()
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
            try await subjectStore.load()
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
            let startDate = Date()
            timerStartDate = startDate
            lastRunStartDate = startDate
            notificationScheduler.resetAlarmTracking()
            startTimer()
            await liveActivity.start(
                subjectName: subject.name,
                timerStartDate: startDate,
                elapsedSeconds: 0,
                timerState: .running
            )
            await notificationScheduler.requestPermission()
            notificationScheduler.scheduleAlarmNotifications(
                subjectName: subject.name,
                elapsedSeconds: elapsedSeconds
            )
        } catch {
            errorMessage = error.localizedDescription
            await resyncWithServer()
        }
    }

    func pause() async {
        guard !isLoading, let id = activeSessionId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.pauseSession(id: id)
            stopTimer()
            notificationScheduler.removeScheduledAlarms()
            timerState = .paused
            selectedPauseType = "REST"
            await liveActivity.update(
                timerState: timerState,
                timerStartDate: timerStartDate ?? Date(),
                elapsedSeconds: elapsedSeconds
            )
        } catch {
            errorMessage = error.localizedDescription
            await resyncWithServer()
        }
    }

    func resume() async {
        guard !isLoading, let id = activeSessionId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.resumeSession(id: id)
            timerState = .running
            lastRunStartDate = Date()
            timerStartDate = Date().addingTimeInterval(TimeInterval(-elapsedSeconds))
            startTimer()
            notificationScheduler.scheduleAlarmNotifications(
                subjectName: selectedSubject?.name ?? "공부",
                elapsedSeconds: elapsedSeconds
            )
            await liveActivity.update(
                timerState: timerState,
                timerStartDate: timerStartDate ?? Date(),
                elapsedSeconds: elapsedSeconds
            )
        } catch {
            errorMessage = error.localizedDescription
            await resyncWithServer()
        }
    }

    func end() async {
        guard !isLoading, let id = activeSessionId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.endSession(id: id)
            stopTimer()
            notificationScheduler.removeAllAlarmNotifications()
            timerState = .idle
            activeSessionId = nil
            elapsedSeconds = 0
            timerStartDate = nil
            lastRunStartDate = nil
            await liveActivity.end(timerState: .idle, timerStartDate: Date(), elapsedSeconds: 0)
            await loadTodaySessions()
            await loadWeeklySummary()
        } catch {
            errorMessage = error.localizedDescription
            await resyncWithServer()
        }
    }

    // MARK: - Subject CRUD

    func addSubject() async {
        let name = newSubjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await subjectStore.create(name: name)
            newSubjectName = ""
            showAddSubject = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSubjectById(_ id: Int, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await subjectStore.update(id: id, name: trimmed)
            editingSubject = nil
            editSubjectName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSubject(_ subject: StudySubject) async {
        do {
            try await subjectStore.delete(id: subject.id)
            if selectedSubject?.id == subject.id {
                selectedSubject = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 에러 발생 시 서버 상태로 UI 동기화
    private func resyncWithServer() async {
        stopTimer()
        notificationScheduler.removeAllAlarmNotifications()
        timerState = .idle
        activeSessionId = nil
        elapsedSeconds = 0
        timerStartDate = nil
        lastRunStartDate = nil
        await liveActivity.end(timerState: .idle, timerStartDate: Date(), elapsedSeconds: 0)
        await restoreActiveSession()
    }

    // MARK: - Timer Engine

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.timerStartDate else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(start))
                self.notificationScheduler.checkAlarm(
                    elapsedSeconds: self.elapsedSeconds,
                    subjectName: self.selectedSubject?.name ?? "공부",
                    isRunning: { [weak self] in self?.timerState == .running }
                )
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
        if let subjectName = selectedSubject?.name, activeSessionId != nil {
            liveActivity.restoreIfNeeded(
                subjectName: subjectName,
                timerState: timerState,
                timerStartDate: timerStartDate,
                elapsedSeconds: elapsedSeconds
            )
        }
    }
}
