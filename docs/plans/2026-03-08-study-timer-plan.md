# 공부 타이머 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 세무사 시험 과목별 공부 시간을 기록하는 타이머 기능 (백엔드 + iOS)

**Architecture:** 백엔드에 StudySubject enum + StudySession/StudyPause 엔티티 + REST API. iOS에 StudyTimerView + StudyTimerViewModel + StudyService + 로컬 알림.

**Tech Stack:** Kotlin/Spring Boot/JPA (백엔드), SwiftUI/Observation (iOS), UNUserNotificationCenter (알림)

---

## Task 1: 백엔드 — StudySubject enum + 조회 API

**Files:**
- Create: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudySubject.kt`
- Create: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudyController.kt`

**Step 1: StudySubject enum 작성**

```kotlin
package com.toy.backend.study

enum class StudySubject(
    val emoji: String,
    val displayName: String,
) {
    FISCAL("🏛️", "재정학"),
    TAX_LAW_INTRO("📜", "세법학개론"),
    ACCOUNTING_INTRO("📊", "회계학개론"),
    COMMERCIAL_LAW("⚖️", "상법/민법/행정소송법"),
    TAX_LAW_1("📕", "세법학 1부"),
    TAX_LAW_2("📗", "세법학 2부"),
    FINANCIAL_ACCOUNTING("🧮", "회계학 1부"),
    COST_ACCOUNTING("💰", "회계학 2부"),
}

data class StudySubjectResponse(
    val name: String,
    val emoji: String,
    val displayName: String,
)

fun StudySubject.toResponse(): StudySubjectResponse =
    StudySubjectResponse(name = name, emoji = emoji, displayName = displayName)
```

**Step 2: 조회 컨트롤러 작성**

```kotlin
package com.toy.backend.study

import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@Tag(name = "공부", description = "공부 타이머 API")
@RestController
@RequestMapping("/study")
class StudyController(
    private val service: StudySessionService,
) {
    @GetMapping("/subjects")
    @Operation(summary = "과목 목록 조회")
    fun subjects(): ResponseEntity<List<StudySubjectResponse>> =
        ResponseEntity.ok(StudySubject.entries.map { it.toResponse() })
}
```

**Step 3: 커밋**

```bash
git add -A && git commit -m "feat: StudySubject enum + 과목 조회 API"
```

---

## Task 2: 백엔드 — StudySession, StudyPause 엔티티

**Files:**
- Create: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudySession.kt`
- Create: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudyPause.kt`

**Step 1: StudySession 엔티티**

```kotlin
package com.toy.backend.study

import com.toy.backend.common.entity.BaseEntity
import com.toy.backend.user.User
import jakarta.persistence.*
import java.time.LocalDateTime

@Entity
@Table(
    name = "study_sessions",
    indexes = [
        Index(name = "idx_study_sessions_user", columnList = "user_id"),
        Index(name = "idx_study_sessions_started", columnList = "started_at"),
    ],
)
class StudySession(
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    var user: User,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    var subject: StudySubject,

    @Column(nullable = false)
    var startedAt: LocalDateTime,

    @Column(nullable = true)
    var endedAt: LocalDateTime? = null,

    @Column(nullable = false)
    var totalSeconds: Long = 0,

    @OneToMany(mappedBy = "session", cascade = [CascadeType.ALL], orphanRemoval = true)
    var pauses: MutableList<StudyPause> = mutableListOf(),
) : BaseEntity() {

    fun pause(at: LocalDateTime): StudyPause {
        val pause = StudyPause(session = this, pausedAt = at)
        pauses.add(pause)
        return pause
    }

    fun resume(at: LocalDateTime) {
        val activePause = pauses.lastOrNull { it.resumedAt == null }
            ?: error("No active pause to resume")
        activePause.resumedAt = at
    }

    fun end(at: LocalDateTime) {
        endedAt = at
        totalSeconds = calculateTotalSeconds(at)
    }

    private fun calculateTotalSeconds(endTime: LocalDateTime): Long {
        val totalDuration = java.time.Duration.between(startedAt, endTime)
        val pausedDuration = pauses.sumOf { pause ->
            val resumeTime = pause.resumedAt ?: endTime
            java.time.Duration.between(pause.pausedAt, resumeTime).seconds
        }
        return totalDuration.seconds - pausedDuration
    }
}
```

**Step 2: StudyPause 엔티티**

```kotlin
package com.toy.backend.study

import com.toy.backend.common.entity.BaseEntity
import jakarta.persistence.*
import java.time.LocalDateTime

@Entity
@Table(name = "study_pauses")
class StudyPause(
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "session_id", nullable = false)
    var session: StudySession,

    @Column(nullable = false)
    var pausedAt: LocalDateTime,

    @Column(nullable = true)
    var resumedAt: LocalDateTime? = null,
) : BaseEntity()
```

**Step 3: 커밋**

```bash
git add -A && git commit -m "feat: StudySession, StudyPause JPA 엔티티"
```

---

## Task 3: 백엔드 — Repository + Service + DTO

**Files:**
- Create: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudySessionRepository.kt`
- Create: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudySessionService.kt`
- Create: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudyDtos.kt`

**Step 1: Repository**

```kotlin
package com.toy.backend.study

import com.toy.backend.user.User
import org.springframework.data.jpa.repository.JpaRepository

interface StudySessionRepository : JpaRepository<StudySession, Long> {
    fun findByIdAndUser(id: Long, user: User): StudySession?
    fun findAllByUserAndStartedAtBetweenOrderByStartedAtDesc(
        user: User,
        from: java.time.LocalDateTime,
        to: java.time.LocalDateTime,
    ): List<StudySession>
}
```

**Step 2: DTO**

```kotlin
package com.toy.backend.study

import io.swagger.v3.oas.annotations.media.Schema
import java.time.LocalDateTime

@Schema(description = "세션 시작 요청")
data class StudySessionStartRequest(
    @field:Schema(description = "과목", example = "FISCAL")
    val subject: StudySubject,
)

@Schema(description = "세션 응답")
data class StudySessionResponse(
    val id: Long,
    val subject: StudySubjectResponse,
    val startedAt: LocalDateTime,
    val endedAt: LocalDateTime?,
    val totalSeconds: Long,
    val pauses: List<StudyPauseResponse>,
)

@Schema(description = "일시정지 응답")
data class StudyPauseResponse(
    val id: Long,
    val pausedAt: LocalDateTime,
    val resumedAt: LocalDateTime?,
)

fun StudySession.toResponse(): StudySessionResponse =
    StudySessionResponse(
        id = requiredId,
        subject = subject.toResponse(),
        startedAt = startedAt,
        endedAt = endedAt,
        totalSeconds = totalSeconds,
        pauses = pauses.map { it.toResponse() },
    )

fun StudyPause.toResponse(): StudyPauseResponse =
    StudyPauseResponse(
        id = requiredId,
        pausedAt = pausedAt,
        resumedAt = resumedAt,
    )
```

**Step 3: Service**

```kotlin
package com.toy.backend.study

import com.toy.backend.common.constant.ErrorCode
import com.toy.backend.common.exception.CustomException
import com.toy.backend.user.UserRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

@Service
@Transactional(readOnly = true)
class StudySessionService(
    private val repository: StudySessionRepository,
    private val userRepository: UserRepository,
) {
    fun list(
        username: String,
        date: LocalDate?,
        from: LocalDate?,
        to: LocalDate?,
    ): List<StudySessionResponse> {
        val user = findUser(username)
        val start = (from ?: date ?: LocalDate.now()).atStartOfDay()
        val end = (to ?: date ?: LocalDate.now()).atTime(LocalTime.MAX)
        return repository
            .findAllByUserAndStartedAtBetweenOrderByStartedAtDesc(user, start, end)
            .map { it.toResponse() }
    }

    @Transactional
    fun start(username: String, request: StudySessionStartRequest): Long {
        val session = StudySession(
            user = findUser(username),
            subject = request.subject,
            startedAt = LocalDateTime.now(),
        )
        return repository.save(session).requiredId
    }

    @Transactional
    fun pause(username: String, id: Long) {
        val session = findSession(username, id)
        session.pause(at = LocalDateTime.now())
    }

    @Transactional
    fun resume(username: String, id: Long) {
        val session = findSession(username, id)
        session.resume(at = LocalDateTime.now())
    }

    @Transactional
    fun end(username: String, id: Long): StudySessionResponse {
        val session = findSession(username, id)
        session.end(at = LocalDateTime.now())
        return session.toResponse()
    }

    private fun findSession(username: String, id: Long): StudySession {
        val user = findUser(username)
        return repository.findByIdAndUser(id, user)
            ?: throw CustomException(ErrorCode.RESOURCE_NOT_FOUND, id)
    }

    private fun findUser(username: String) =
        userRepository.findByUsername(username)
            ?: throw CustomException(ErrorCode.RESOURCE_NOT_FOUND, username)
}
```

**Step 4: 커밋**

```bash
git add -A && git commit -m "feat: StudySession repository, service, DTO"
```

---

## Task 4: 백엔드 — Controller 엔드포인트 추가

**Files:**
- Modify: `pf-backend/apps/daily-record/src/main/kotlin/com/toy/backend/study/StudyController.kt`

**Step 1: 세션 CRUD 엔드포인트 추가**

StudyController에 다음 메서드를 추가:

```kotlin
@GetMapping("/sessions")
@Operation(summary = "세션 목록 조회")
fun listSessions(
    @RequestParam(required = false)
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
    date: LocalDate?,
    @RequestParam(required = false)
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
    from: LocalDate?,
    @RequestParam(required = false)
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
    to: LocalDate?,
    authentication: Authentication,
): ResponseEntity<DataResponseBody<List<StudySessionResponse>>> =
    ResponseEntity.ok(DataResponseBody(service.list(authentication.name, date, from, to)))

@PostMapping("/sessions")
@Operation(summary = "세션 시작")
fun startSession(
    @Valid @RequestBody request: StudySessionStartRequest,
    authentication: Authentication,
): ResponseEntity<Long> =
    ResponseEntity.ok(service.start(authentication.name, request))

@PatchMapping("/sessions/{id}/pause")
@Operation(summary = "세션 일시정지")
fun pauseSession(
    @PathVariable id: Long,
    authentication: Authentication,
): ResponseEntity<Void> {
    service.pause(authentication.name, id)
    return ResponseEntity.noContent().build()
}

@PatchMapping("/sessions/{id}/resume")
@Operation(summary = "세션 재개")
fun resumeSession(
    @PathVariable id: Long,
    authentication: Authentication,
): ResponseEntity<Void> {
    service.resume(authentication.name, id)
    return ResponseEntity.noContent().build()
}

@PatchMapping("/sessions/{id}/end")
@Operation(summary = "세션 종료")
fun endSession(
    @PathVariable id: Long,
    authentication: Authentication,
): ResponseEntity<StudySessionResponse> =
    ResponseEntity.ok(service.end(authentication.name, id))
```

필요한 import 추가: `Authentication`, `Valid`, `RequestBody`, `PathVariable`, `RequestParam`, `DateTimeFormat`, `DataResponseBody`, `LocalDate`.

**Step 2: 커밋**

```bash
git add -A && git commit -m "feat: StudySession REST 엔드포인트"
```

---

## Task 5: iOS — StudySubject 모델 + StudyService

**Files:**
- Create: `WooriHaru/Models/StudySubject.swift`
- Create: `WooriHaru/Models/StudySession.swift`
- Create: `WooriHaru/Services/StudyService.swift`

**Step 1: 모델 정의**

```swift
// StudySubject.swift
import Foundation

struct StudySubject: Codable, Identifiable {
    let name: String
    let emoji: String
    let displayName: String

    var id: String { name }
}
```

```swift
// StudySession.swift
import Foundation

struct StudySession: Codable, Identifiable {
    let id: Int
    let subject: StudySubject
    let startedAt: String
    let endedAt: String?
    let totalSeconds: Int
    let pauses: [StudyPause]
}

struct StudyPause: Codable, Identifiable {
    let id: Int
    let pausedAt: String
    let resumedAt: String?
}
```

**Step 2: Service 작성**

```swift
// StudyService.swift
import Foundation

struct StudySessionStartRequest: Encodable {
    let subject: String
}

struct StudyService {
    private let api = APIClient.shared

    func fetchSubjects() async throws -> [StudySubject] {
        try await api.get("/study/subjects")
    }

    func fetchSessions(date: String? = nil, from: String? = nil, to: String? = nil) async throws -> [StudySession] {
        var query: [String: String] = [:]
        if let date { query["date"] = date }
        if let from { query["from"] = from }
        if let to { query["to"] = to }
        let response: DataResponse<[StudySession]> = try await api.get("/study/sessions", query: query)
        return response.data ?? []
    }

    func startSession(subject: String) async throws -> Int {
        try await api.post("/study/sessions", body: StudySessionStartRequest(subject: subject))
    }

    func pauseSession(id: Int) async throws {
        try await api.patchVoid("/study/sessions/\(id)/pause")
    }

    func resumeSession(id: Int) async throws {
        try await api.patchVoid("/study/sessions/\(id)/resume")
    }

    func endSession(id: Int) async throws -> StudySession {
        try await api.patch("/study/sessions/\(id)/end")
    }
}
```

참고: `APIClient`에 `patchVoid` 메서드가 없으면 추가 필요:
```swift
func patchVoid(_ path: String, body: (any Encodable)? = nil) async throws {
    try await requestVoid("PATCH", path: path, body: body)
}
```

**Step 3: Xcode 프로젝트에 파일 추가 + 커밋**

```bash
git add -A && git commit -m "feat: iOS StudySubject/StudySession 모델 + StudyService"
```

---

## Task 6: iOS — StudyTimerViewModel

**Files:**
- Create: `WooriHaru/ViewModels/StudyTimerViewModel.swift`

**Step 1: ViewModel 작성**

```swift
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class StudyTimerViewModel {
    // MARK: - State
    var subjects: [StudySubject] = []
    var selectedSubject: StudySubject?
    var timerState: TimerState = .idle
    var elapsedSeconds: Int = 0
    var errorMessage: String?
    var isLoading = false

    enum TimerState {
        case idle
        case running
        case paused
    }

    // MARK: - Private
    private let studyService = StudyService()
    private var sessionId: Int?
    private var timer: Timer?
    private var remainingSecondsToNextAlarm: Int = 3600

    private static let alarmInterval = 3600 // 1시간 (초)
    private static let notificationId = "studyTimerAlarm"

    // MARK: - Data Loading
    func loadSubjects() async {
        do {
            subjects = try await studyService.fetchSubjects()
        } catch {
            errorMessage = "과목을 불러올 수 없습니다."
        }
    }

    // MARK: - Timer Actions
    func start() async {
        guard let subject = selectedSubject else { return }
        do {
            sessionId = try await studyService.startSession(subject: subject.name)
            timerState = .running
            elapsedSeconds = 0
            remainingSecondsToNextAlarm = Self.alarmInterval
            startTimer()
            scheduleNotification(afterSeconds: remainingSecondsToNextAlarm)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "세션 시작에 실패했습니다."
        }
    }

    func pause() async {
        guard let id = sessionId else { return }
        do {
            try await studyService.pauseSession(id: id)
            timerState = .paused
            stopTimer()
            cancelNotification()
        } catch {
            errorMessage = "일시정지에 실패했습니다."
        }
    }

    func resume() async {
        guard let id = sessionId else { return }
        do {
            try await studyService.resumeSession(id: id)
            timerState = .running
            startTimer()
            scheduleNotification(afterSeconds: remainingSecondsToNextAlarm)
        } catch {
            errorMessage = "재개에 실패했습니다."
        }
    }

    func end() async {
        guard let id = sessionId else { return }
        do {
            _ = try await studyService.endSession(id: id)
            timerState = .idle
            stopTimer()
            cancelNotification()
            sessionId = nil
            selectedSubject = nil
            elapsedSeconds = 0
        } catch {
            errorMessage = "종료에 실패했습니다."
        }
    }

    // MARK: - Timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.timerState == .running else { return }
                self.elapsedSeconds += 1
                self.remainingSecondsToNextAlarm -= 1
                if self.remainingSecondsToNextAlarm <= 0 {
                    self.remainingSecondsToNextAlarm = Self.alarmInterval
                    self.scheduleNotification(afterSeconds: Self.alarmInterval)
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Notification
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(afterSeconds: Int) {
        cancelNotification()
        let content = UNMutableNotificationContent()
        content.title = "공부 타이머"
        content.body = "\(selectedSubject?.emoji ?? "") \(elapsedSeconds / 3600 + 1)시간째 공부 중!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(afterSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    }

    // MARK: - Formatted Time
    var formattedTime: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
```

**Step 2: 커밋**

```bash
git add -A && git commit -m "feat: StudyTimerViewModel — 타이머, 알림, API 연동"
```

---

## Task 7: iOS — StudyTimerView UI

**Files:**
- Create: `WooriHaru/Views/Study/StudyTimerView.swift`

**Step 1: 타이머 화면 작성**

```swift
import SwiftUI

struct StudyTimerView: View {
    @State private var viewModel = StudyTimerViewModel()

    var body: some View {
        VStack(spacing: 32) {
            // 과목 선택
            if viewModel.timerState == .idle {
                subjectSelector
            } else if let subject = viewModel.selectedSubject {
                HStack(spacing: 8) {
                    Text(subject.emoji)
                        .font(.title)
                    Text(subject.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.slate900)
                }
            }

            // 타이머
            Text(viewModel.formattedTime)
                .font(.system(size: 64, weight: .light, design: .monospaced))
                .foregroundStyle(Color.slate900)

            // 버튼
            actionButtons

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red500)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.slate50)
        .navigationTitle("공부 타이머")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadSubjects()
            viewModel.requestNotificationPermission()
        }
    }

    // MARK: - Subject Selector
    private var subjectSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.subjects) { subject in
                    Button {
                        viewModel.selectedSubject = subject
                    } label: {
                        VStack(spacing: 4) {
                            Text(subject.emoji)
                                .font(.title2)
                            Text(subject.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(width: 72, height: 72)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.selectedSubject?.name == subject.name ? Color.blue50 : .white)
                                .stroke(
                                    viewModel.selectedSubject?.name == subject.name ? Color.blue300 : Color.slate200,
                                    lineWidth: 1
                                )
                        }
                        .foregroundStyle(
                            viewModel.selectedSubject?.name == subject.name ? Color.blue700 : Color.slate700
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 16) {
            switch viewModel.timerState {
            case .idle:
                Button {
                    Task { await viewModel.start() }
                } label: {
                    Text("시작")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.selectedSubject != nil ? Color.blue500 : Color.slate400)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.selectedSubject == nil)

            case .running:
                Button {
                    Task { await viewModel.pause() }
                } label: {
                    Text("일시정지")
                        .font(.headline)
                        .foregroundStyle(Color.slate700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.slate200)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    Task { await viewModel.end() }
                } label: {
                    Text("종료")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red500)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

            case .paused:
                Button {
                    Task { await viewModel.resume() }
                } label: {
                    Text("재개")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    Task { await viewModel.end() }
                } label: {
                    Text("종료")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red500)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}
```

**Step 2: 커밋**

```bash
git add -A && git commit -m "feat: StudyTimerView UI"
```

---

## Task 8: iOS — 사이드 드로어 메뉴 + 네비게이션 연결

**Files:**
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift` — 메뉴 항목 추가
- Modify: `WooriHaru/Views/ContentView.swift` — AppDestination에 `.studyTimer` 추가 + navigationDestination 연결

**Step 1: AppDestination에 케이스 추가**

```swift
case studyTimer
```

**Step 2: SideDrawerView에 메뉴 항목 추가**

기존 메뉴 항목들 사이에 추가:
```swift
drawerItem(icon: "timer", label: "공부 타이머") {
    navPath.append(AppDestination.studyTimer)
    isOpen = false
}
```

**Step 3: ContentView에 navigationDestination 추가**

```swift
case .studyTimer:
    StudyTimerView()
```

**Step 4: Xcode 프로젝트에 새 파일들 등록 + 커밋**

```bash
git add -A && git commit -m "feat: 사이드 드로어에 공부 타이머 메뉴 추가"
```

---

## Task 9: iOS — APIClient에 patchVoid 추가 (필요 시)

**Files:**
- Modify: `WooriHaru/Services/APIClient.swift`

**Step 1: patchVoid 메서드 확인 및 추가**

기존 `patch<T>` 메서드 아래에:

```swift
func patchVoid(_ path: String, body: (any Encodable)? = nil) async throws {
    try await requestVoid("PATCH", path: path, body: body)
}
```

**Step 2: 커밋**

```bash
git add -A && git commit -m "feat: APIClient에 patchVoid 메서드 추가"
```
