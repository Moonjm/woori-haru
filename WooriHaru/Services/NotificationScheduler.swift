import SwiftUI
import UserNotifications

private let maxScheduledAlarms = 20

@MainActor
@Observable
final class NotificationScheduler {
    private var lastAlarmSeconds: Int = 0

    var alarmIntervalMinutes: Int {
        get { UserDefaults.standard.integer(forKey: "alarmIntervalMinutes") }
        set { UserDefaults.standard.set(newValue, forKey: "alarmIntervalMinutes") }
    }

    var alarmIntervalText: String = {
        let saved = UserDefaults.standard.integer(forKey: "alarmIntervalMinutes")
        return saved > 0 ? "\(saved)" : ""
    }()

    // MARK: - Public

    func resetAlarmTracking() {
        lastAlarmSeconds = 0
    }

    func restoreAlarmTracking(elapsedSeconds: Int) {
        let intervalSeconds = alarmIntervalMinutes * 60
        if intervalSeconds > 0 {
            lastAlarmSeconds = (elapsedSeconds / intervalSeconds) * intervalSeconds
        }
    }

    func saveAlarmInterval() {
        let filtered = alarmIntervalText.filter { $0.isNumber }
        if alarmIntervalText != filtered {
            alarmIntervalText = filtered
        }
        alarmIntervalMinutes = max(0, Int(filtered) ?? 0)
    }

    /// 매 초 호출 — 알림 시점이면 알림 발송
    func checkAlarm(elapsedSeconds: Int, subjectName: String, isRunning: @escaping () -> Bool) {
        let intervalSeconds = alarmIntervalMinutes * 60
        guard intervalSeconds > 0 else { return }
        let nextAlarmAt = lastAlarmSeconds + intervalSeconds
        if elapsedSeconds >= nextAlarmAt {
            lastAlarmSeconds = (elapsedSeconds / intervalSeconds) * intervalSeconds
            scheduleAlarmNotifications(subjectName: subjectName, elapsedSeconds: elapsedSeconds)
            sendAlarmNotification(identifier: "study-alarm", subjectName: subjectName, elapsedSeconds: elapsedSeconds)
            let isForeground = UIApplication.shared.applicationState == .active
            if !isForeground {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, isRunning() else { return }
                    self.sendAlarmNotification(identifier: "study-alarm-2", subjectName: subjectName, elapsedSeconds: elapsedSeconds)
                }
            }
        }
    }

    func scheduleAlarmNotifications(subjectName: String, elapsedSeconds: Int) {
        removeScheduledAlarms()
        let intervalSeconds = alarmIntervalMinutes * 60
        guard intervalSeconds > 0 else { return }

        let center = UNUserNotificationCenter.current()

        for i in 1...maxScheduledAlarms {
            let targetElapsed = lastAlarmSeconds + intervalSeconds * i
            let delayFromNow = targetElapsed - elapsedSeconds
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

    func removeScheduledAlarms() {
        let center = UNUserNotificationCenter.current()
        let ids = (1...maxScheduledAlarms).map { "study-scheduled-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func removeAllAlarmNotifications() {
        removeScheduledAlarms()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["study-alarm", "study-alarm-2"])
    }

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Private

    private func sendAlarmNotification(identifier: String, subjectName: String, elapsedSeconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["study-alarm", "study-alarm-2"])

        let content = UNMutableNotificationContent()
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        content.title = subjectName
        content.body = "\(h)시간 \(m)분 경과"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
