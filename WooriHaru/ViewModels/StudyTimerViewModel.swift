import SwiftUI
import UserNotifications

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

    // MARK: - Alarm
    var alarmIntervalMinutes: Int {
        get { UserDefaults.standard.integer(forKey: "alarmIntervalMinutes") }
        set { UserDefaults.standard.set(newValue, forKey: "alarmIntervalMinutes") }
    }
    var alarmIntervalText: String = {
        let saved = UserDefaults.standard.integer(forKey: "alarmIntervalMinutes")
        return saved > 0 ? "\(saved)" : ""
    }()

    // MARK: - Private
    private let service = StudyService()
    private var activeSessionId: Int?
    nonisolated(unsafe) private var timer: Timer? {
        willSet { timer?.invalidate() }
    }
    private var lastAlarmSeconds: Int = 0

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

    var todayTotalFormatted: String {
        let total = todayTotalSeconds + (timerState != .idle ? elapsedSeconds : 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d시간 %d분", h, m)
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
            } else {
                timerState = .running
                startTimer()
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: string)
    }

    func loadSubjects() async {
        do {
            subjects = try await service.fetchSubjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTodaySessions() async {
        let today = Date().dateString
        do {
            todaySessions = try await service.fetchSessions(from: today, to: today)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Timer Actions

    func start() async {
        guard let subject = selectedSubject else { return }
        do {
            let sessionId = try await service.startSession(subjectId: subject.id)
            activeSessionId = sessionId
            timerState = .running
            elapsedSeconds = 0
            lastAlarmSeconds = 0
            startTimer()
            await requestNotificationPermission()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() async {
        guard let id = activeSessionId else { return }
        do {
            try await service.pauseSession(id: id)
            timerState = .paused
            stopTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume() async {
        guard let id = activeSessionId else { return }
        do {
            try await service.resumeSession(id: id)
            timerState = .running
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func end() async {
        guard let id = activeSessionId else { return }
        do {
            _ = try await service.endSession(id: id)
            timerState = .idle
            activeSessionId = nil
            elapsedSeconds = 0
            stopTimer()
            removeAlarmNotifications()
            await loadTodaySessions()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                guard let self else { return }
                self.elapsedSeconds += 1
                self.checkAlarm()
            }
        }
    }

    private func stopTimer() {
        timer = nil
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
            sendAlarmNotification()
        }
    }

    private func sendAlarmNotification() {
        let content = UNMutableNotificationContent()
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let subjectName = selectedSubject?.name ?? "공부"
        content.title = subjectName
        content.body = "\(h)시간 \(m)분 경과"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "study-alarm-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func removeAlarmNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .filter { $0.request.identifier.hasPrefix("study-alarm-") }
                .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    private func requestNotificationPermission() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

