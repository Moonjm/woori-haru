# 기념일 D-Day 앱 뱃지 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기념일 관리에서 선택한 기념일을 1일째로 세는 D+ 카운트를 앱 아이콘 뱃지에 표시하고, 자정마다 자동 갱신되게 한다.

**Architecture:** 상태를 UserDefaults에만 두는 stateless `DDayBadgeService`(enum + static 함수)가 뱃지 계산·즉시 반영·30일치 자정 예약 알림(뱃지만 조용히 갱신)을 담당한다. `PairEventsView`의 각 행에 선택 토글 버튼을 추가하고, 앱 포그라운드 진입 시 예약 버퍼를 리필한다.

**Tech Stack:** SwiftUI, UserNotifications(`UNCalendarNotificationTrigger`, `setBadgeCount`), UserDefaults. 스펙: `docs/superpowers/specs/2026-07-22-dday-badge-design.md`

## Global Constraints

- 예약 알림은 **30일치**, 식별자 접두사 `dday-badge-` (공부 타이머 알림 `study-*`와 절대 겹치지 않게).
- 카운트: 선택일이 1일째. 표시 숫자 = 경과일 + 1. 미래 날짜면 0(뱃지 숨김).
- 선택 저장은 UserDefaults 키 `ddayBadgeEventId`(Int), `ddayBadgeEventDate`(String, `yyyy-MM-dd`).
- 프로젝트에 테스트 타깃이 없음 — 각 태스크는 빌드 통과로 검증: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS Simulator' build`
- 커밋 메시지는 한국어 `feat:` 관례. UI 코드는 기존 Glass 디자인 시스템/색상(`Color.blue600`, `Color.slate500`) 사용.
- iOS 17+ / Observation 프레임워크(`@Observable`) 사용 프로젝트.

---

### Task 1: DDayBadgeService + 알림 권한에 .badge 추가

**Files:**
- Create: `WooriHaru/Services/DDayBadgeService.swift`
- Modify: `WooriHaru/Services/NotificationScheduler.swift:105` (권한 옵션에 `.badge` 추가)

**Interfaces:**
- Consumes: `PairEvent`(`WooriHaru/Models/PairEvent.swift` — `id: Int`, `eventDate: String`), `Date.from(_:)`(`WooriHaru/Extensions/Date+Extensions.swift:65` — `yyyy-MM-dd` 파싱)
- Produces (Task 2·3이 사용):
  - `DDayBadgeService.selectedEventId: Int?` (get)
  - `DDayBadgeService.badgeCount(eventDate: Date, on: Date, calendar: Calendar = .current) -> Int`
  - `DDayBadgeService.select(event: PairEvent) async -> Bool` (권한 거부 시 false)
  - `DDayBadgeService.deselect() async`
  - `DDayBadgeService.sync(with: [PairEvent]) async`
  - `DDayBadgeService.refresh() async`

- [ ] **Step 1: DDayBadgeService.swift 작성**

```swift
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

    /// 뱃지 대상 기념일 선택. 알림 권한이 거부되면 false.
    static func select(event: PairEvent) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
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
```

- [ ] **Step 2: NotificationScheduler 권한 옵션에 .badge 추가**

`WooriHaru/Services/NotificationScheduler.swift:105`:

```swift
// 변경 전
_ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
// 변경 후
_ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
```

- [ ] **Step 3: 빌드 검증**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add WooriHaru/Services/DDayBadgeService.swift WooriHaru/Services/NotificationScheduler.swift
git commit -m "feat: 기념일 D-Day 뱃지 서비스 추가 (30일치 자정 예약알림)"
```

※ 새 파일이 Xcode 프로젝트에 자동 포함되는지 확인: `WooriHaru.xcodeproj/project.pbxproj`에 `PBXFileSystemSynchronizedRootGroup`이 있으면 폴더 기반이라 자동 포함. 없으면 pbxproj에 파일 참조를 수동 추가해야 한다 (`grep -n "FileSystemSynchronized" WooriHaru.xcodeproj/project.pbxproj`로 확인).

---

### Task 2: PairEventsView 선택 UI + 권한 안내 얼럿

**Files:**
- Modify: `WooriHaru/ViewModels/PairEventsViewModel.swift`
- Modify: `WooriHaru/Views/Pair/PairEventsView.swift`

**Interfaces:**
- Consumes: Task 1의 `DDayBadgeService.selectedEventId`, `.select(event:) async -> Bool`, `.deselect() async`, `.sync(with:) async`
- Produces: `PairEventsViewModel.badgeEventId: Int?`, `PairEventsViewModel.showBadgePermissionAlert: Bool`, `PairEventsViewModel.toggleBadge(for: PairEvent) async`

- [ ] **Step 1: PairEventsViewModel에 뱃지 상태·액션 추가**

`WooriHaru/ViewModels/PairEventsViewModel.swift` — State 섹션에 추가:

```swift
var badgeEventId: Int? = DDayBadgeService.selectedEventId
var showBadgePermissionAlert = false
```

`loadEvents()` 성공 경로(`events = try await ...` 다음 줄)에 추가:

```swift
await DDayBadgeService.sync(with: events)
badgeEventId = DDayBadgeService.selectedEventId
```

Actions 섹션에 메서드 추가:

```swift
func toggleBadge(for event: PairEvent) async {
    if badgeEventId == event.id {
        await DDayBadgeService.deselect()
        badgeEventId = nil
    } else if await DDayBadgeService.select(event: event) {
        badgeEventId = event.id
    } else {
        showBadgePermissionAlert = true
    }
}
```

- [ ] **Step 2: PairEventsView 행에 뱃지 토글 버튼 추가**

`WooriHaru/Views/Pair/PairEventsView.swift` 리스트 행의 `Spacer()`와 `if event.recurring` 사이에 추가:

```swift
Button {
    Task { await viewModel.toggleBadge(for: event) }
} label: {
    Image(systemName: viewModel.badgeEventId == event.id
          ? "app.badge.checkmark.fill" : "app.badge")
        .font(.body)
        .foregroundStyle(viewModel.badgeEventId == event.id
                         ? Color.blue600 : Color.slate500)
}
.buttonStyle(.plain)
```

- [ ] **Step 3: 권한 안내 얼럿 추가**

같은 파일, 기존 `.alert("기념일 삭제", ...)` 아래에 추가:

```swift
.alert("알림 권한 필요", isPresented: $viewModel.showBadgePermissionAlert) {
    Button("설정으로 이동") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    Button("취소", role: .cancel) {}
} message: {
    Text("D-Day 뱃지를 표시하려면 설정에서 알림을 허용해주세요.")
}
```

(이 프로젝트는 `import SwiftUI`만으로 `UIApplication` 접근 가능 — `NotificationScheduler.swift:51` 선례 있음.)

- [ ] **Step 4: 빌드 검증**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add WooriHaru/ViewModels/PairEventsViewModel.swift WooriHaru/Views/Pair/PairEventsView.swift
git commit -m "feat: 기념일 관리에 D-Day 뱃지 선택 토글 추가"
```

---

### Task 3: 앱 포그라운드 진입 시 뱃지 버퍼 리필

**Files:**
- Modify: `WooriHaru/WooriHaruApp.swift`

**Interfaces:**
- Consumes: Task 1의 `DDayBadgeService.refresh() async`

- [ ] **Step 1: scenePhase 감지 후 refresh 호출**

`WooriHaru/WooriHaruApp.swift`의 `WooriHaruApp` struct에 프로퍼티 추가:

```swift
@Environment(\.scenePhase) private var scenePhase
```

`WindowGroup` 내부 `Group`의 모디파이어 체인(예: `.onOpenURL` 아래)에 추가:

```swift
.onChange(of: scenePhase) {
    if scenePhase == .active {
        Task { await DDayBadgeService.refresh() }
    }
}
```

- [ ] **Step 2: 빌드 검증**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 시뮬레이터 수동 검증**

시뮬레이터에서 앱 실행 후:
1. 기념일 관리 → 기념일 하나의 뱃지 아이콘 탭 → 권한 허용 → 홈 화면에서 앱 아이콘 뱃지에 D+숫자 표시 확인.
2. 다시 탭(해제) → 뱃지 사라짐 확인.
3. (선택) Xcode 콘솔에서 `UNUserNotificationCenter.current().pendingNotificationRequests()` 덤프로 `dday-badge-1...30` 예약 확인.

- [ ] **Step 4: Commit**

```bash
git add WooriHaru/WooriHaruApp.swift
git commit -m "feat: 앱 포그라운드 진입 시 D-Day 뱃지 예약 리필"
```
