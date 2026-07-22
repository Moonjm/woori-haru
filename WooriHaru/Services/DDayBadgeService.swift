import Foundation
import UserNotifications

/// 기념일 D-Day 앱 아이콘 뱃지 관리.
/// 선택 상태는 UserDefaults에만 저장하는 stateless 서비스.
/// 자정마다 뱃지 숫자만 조용히 바꾸는 로컬 알림을 30일치 예약해두고,
/// 앱이 열릴 때마다 버퍼를 다시 채운다.
enum DDayBadgeService {
    private static let eventIdKey = "ddayBadgeEventId"
    private static let eventDateKey = "ddayBadgeEventDate"
    private static let identifierPrefix = "dday-badge-"
    private static let scheduledDays = 30

    static var selectedEventId: Int? {
        UserDefaults.standard.object(forKey: eventIdKey) as? Int
    }

    /// 선택일을 1일째로 세는 D+ 카운트. 미래 날짜면 0(뱃지 숨김).
    static func badgeCount(eventDate: Date, on day: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: eventDate)
        let target = calendar.startOfDay(for: day)
        guard let days = calendar.dateComponents([.day], from: start, to: target).day,
              days >= 0 else { return 0 }
        return days + 1
    }

    /// D-Day 갱신 알림인지 식별 (포그라운드 표시 옵션 분기용)
    static func isDDayNotification(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    /// 뱃지 대상 기념일 선택. 알림 권한 또는 배지 설정이 꺼져 있으면 false.
    static func select(event: PairEvent) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        // 알림 자체는 허용돼도 배지만 꺼져 있을 수 있음
        // (설정에서 배지 off, 또는 과거 .badge 없이 권한을 받은 기존 사용자)
        guard await center.notificationSettings().badgeSetting == .enabled else { return false }
        UserDefaults.standard.set(event.id, forKey: eventIdKey)
        UserDefaults.standard.set(event.eventDate, forKey: eventDateKey)
        await refresh()
        return true
    }

    static func deselect() async {
        UserDefaults.standard.removeObject(forKey: eventIdKey)
        UserDefaults.standard.removeObject(forKey: eventDateKey)
        await clearBadge()
    }

    /// 기념일 목록 로드 후 호출 — 선택된 기념일이 삭제됐으면 자동 해제,
    /// 날짜가 수정됐으면 저장값을 갱신한 뒤 재예약한다.
    static func sync(with events: [PairEvent]) async {
        guard let id = selectedEventId else { return }
        guard let event = events.first(where: { $0.id == id }) else {
            await deselect()
            return
        }
        if event.eventDate != UserDefaults.standard.string(forKey: eventDateKey) {
            UserDefaults.standard.set(event.eventDate, forKey: eventDateKey)
        }
        await refresh()
    }

    /// 오늘 숫자 즉시 반영 + 앞으로 30일치 자정 갱신 알림 재예약.
    static func refresh() async {
        guard let dateString = UserDefaults.standard.string(forKey: eventDateKey),
              let eventDate = Date.from(dateString) else { return }

        let center = UNUserNotificationCenter.current()
        removePendingBadgeNotifications(center: center)

        let today = Date()
        try? await center.setBadgeCount(badgeCount(eventDate: eventDate, on: today))

        let calendar = Calendar.current
        for i in 1...scheduledDays {
            guard let day = calendar.date(byAdding: .day, value: i, to: today) else { continue }
            // 제목·본문·소리 없이 badge만 설정 → 배너 없이 뱃지만 조용히 갱신됨
            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: badgeCount(eventDate: eventDate, on: day))
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = 0
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(i)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    // MARK: - Private

    private static func clearBadge() async {
        let center = UNUserNotificationCenter.current()
        removePendingBadgeNotifications(center: center)
        try? await center.setBadgeCount(0)
    }

    private static func removePendingBadgeNotifications(center: UNUserNotificationCenter) {
        let ids = (1...scheduledDays).map { "\(identifierPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
