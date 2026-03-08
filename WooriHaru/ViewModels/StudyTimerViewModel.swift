import Foundation
import Observation
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
    var alarmIntervalMinutes: Int = 60

    // MARK: - Private
    private let service = StudyService()
    private var activeSessionId: Int?
    private var timer: Timer?
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
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Alarm

    private func checkAlarm() {
        let intervalSeconds = alarmIntervalMinutes * 60
        guard intervalSeconds > 0 else { return }
        let cumulativeTotal = todayTotalSeconds + elapsedSeconds
        let nextAlarmAt = lastAlarmSeconds + intervalSeconds
        if cumulativeTotal >= nextAlarmAt {
            lastAlarmSeconds = (cumulativeTotal / intervalSeconds) * intervalSeconds
            sendAlarmNotification()
        }
    }

    private func sendAlarmNotification() {
        let content = UNMutableNotificationContent()
        let totalMinutes = (todayTotalSeconds + elapsedSeconds) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        content.title = "공부 타이머"
        content.body = "누적 공부시간 \(h)시간 \(m)분 경과"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "study-alarm-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func removeAlarmNotifications() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: []
        )
    }

    private func requestNotificationPermission() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

private extension Date {
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}
