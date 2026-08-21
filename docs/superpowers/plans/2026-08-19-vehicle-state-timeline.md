# 차량 상태 타임라인·주행 통계 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 건강 탭의 주인공을 배터리 열화에서 **지금 상태**로 넘기고, 최근 7일을 가로 띠로 그리는 상태 타임라인을 더하고, 주행 탭 맨 위에 역대 최고 속도·이번 달·올해 주행거리 타일 셋을 놓는다.

**Architecture:** 서버가 상태·주행·충전 세 배열을 **겹친 채로** 주면 앱이 `StateTimelineMath.bars`로 날짜 행 좌표를 낸다. 계산은 순수 함수 하나에 모이고 뷰는 그리기만 한다. 진한 패널(`batteryPanelBackground`)과 96pt 링은 `BatteryHealthCard`에서 새 `BatteryNowCard`로 **옮겨 가고**, 열화 카드는 밝은 `GlassCard`로 내려온다 — 링이 화면에 하나만 남게 하는 것이 이 이동의 목적이다.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), `@Observable` 뷰모델, Swift Testing(`import Testing`), 손그림 차트(`GeometryReader`+`Rectangle`, Swift Charts 미사용)

**Spec:** `docs/superpowers/specs/2026-08-19-vehicle-state-timeline-design.md`

**서버 설계:** `../toy-back/docs/superpowers/specs/2026-08-19-tesla-state-timeline-drive-stats-design.md` — **아직 구현되지 않았다.** 이 계획은 계약만 보고 진행하며, **서버가 없어도 앱이 깨지지 않게** 만든다(Task 6의 옵셔널 필드 결정 참고).

**앞선 작업:** 1~3단계가 `main`에 있다(`60dc015` → `86b6695` → `5cd81c4`). 현재 브랜치는 `feat/vehicle-state-timeline`이고 스펙 커밋(`5c59c27`)이 이미 올라가 있다.

## Global Constraints

- 전체 테스트: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. 단일 스위트: 뒤에 `-only-testing:WooriHaruTests/<스위트이름>`을 붙인다.
- **Swift Charts를 쓰지 않는다.** `GeometryReader`·`Rectangle`·`Path`·`Circle().trim`으로 그린다.
- **진한 패널은 화면에서 하나뿐이다.** 이 계획이 끝난 뒤에도 하나여야 한다.
- **링은 화면에서 하나뿐이다.**
- 색은 `Color+Extensions.swift`의 기존 토큰만 쓴다. 새 토큰을 만들지 않는다.
- 시각 문자열은 **KST 벽시계**다. `VehicleFormat.parseKST`로만 읽는다(`Asia/Seoul` 고정 포매터 셋을 이미 갖고 있다).
- 「값이 있는 새로고침 실패는 있던 값을 그대로 보여주고 한 줄 배너만 띄운다.」 **오류 확인이 값 확인보다 먼저 오면 안 된다.**
- 「기록이 없음」과 「못 받음」을 한 화면으로 뭉개지 않는다.
- 뷰모델은 `@MainActor @Observable`, `generation` 토큰으로 늦은 응답을 버리고, `catch is CancellationError`는 조용히 리턴한다.
- 커밋 메시지는 한국어 평서형(`feat: ~한다`, `fix: ~을 고친다`, `docs: ~을 적는다`).

## 실측된 사실 (2026-08-19, 이 계획의 전제)

| 항목 | 값 |
|---|---|
| 최근 7일 상태 구간 | `online` 72개(36.3시간) / `offline` 73개(131.3시간) / `asleep` **0개** |
| 최근 7일 주행 / 충전 | 22건 / 1건 |
| 구간 길이 | `online` 최소 11.2분·중앙 12.2분, `offline` 최소 0.7분·중앙 120.5분 |
| 2분 미만 구간 | 145개 중 **2개** |
| 역대 최고 속도 | **138 km/h** (동률 최소 3건: 2025-09-13 · 2025-03-22 · 2024-03-09) |
| 이번 달 / 올해 주행거리 | **1,331.3 km** / **13,440.4 km** |

---

## 파일 구조

**새로 만든다**

| 파일 | 책임 |
|---|---|
| `WooriHaru/Models/StateTimelineModels.swift` | 응답 DTO 셋, `TimelineKind`, `TimelineBar`, `StateTimelineMath` |
| `WooriHaru/ViewModels/StateTimelineViewModel.swift` | `/tesla/state-timeline` 하나를 본다. 캐시하지 않는다 |
| `WooriHaru/Views/Vehicle/BatteryNowCard.swift` | 진한 패널 + 링 + 상태 배지. 패널 배경 모디파이어와 플레이스홀더가 여기로 이사 온다 |
| `WooriHaru/Views/Vehicle/StateTimelineChart.swift` | 7행 가로 띠 |
| `WooriHaru/Views/Vehicle/DriveStatsCard.swift` | 타일 셋 |
| `WooriHaruTests/StateTimelineTests.swift` | `StateTimelineMath` |
| `WooriHaruTests/StateTimelineViewModelTests.swift` | 뷰모델 |

**고친다**

| 파일 | 무엇을 |
|---|---|
| `WooriHaru/Models/VehicleHealthModels.swift` | `HealthBand`·`BatteryBand` 추가 |
| `WooriHaru/Models/VehicleModels.swift` | `VehicleFormat.speed` 추가 |
| `WooriHaru/Models/DriveInsightsModels.swift` | 필드 셋 추가 |
| `WooriHaru/Services/VehicleService.swift` | `fetchStateTimeline(days:)` 추가 |
| `WooriHaru/Views/Vehicle/BatteryHealthCard.swift` | 링 제거, 패널 배경 반출, `GlassCard`로 강등 |
| `WooriHaru/Views/Vehicle/VehicleHealthTab.swift` | 카드 순서 재배치, `batteryCard` 제거, 새로고침 다섯 갈래 |
| `WooriHaru/Views/Vehicle/VehicleView.swift` | `StateTimelineViewModel` 추가, `.task` 넷 |
| `WooriHaru/Views/Vehicle/VehicleDriveTab.swift` | `DriveStatsCard`를 카드 맨 위에 |
| `WooriHaruTests/VehicleDriveTests.swift` | `DriveInsightsResponse` 생성부 4곳 |
| `WooriHaruTests/VehicleServiceTests.swift` | `DriveInsightsResponse` 생성부 2곳 |
| `WooriHaruTests/VehicleHealthTests.swift` | `HealthBand` 테스트 추가 |
| `WooriHaruTests/VehicleMathTests.swift` | `VehicleFormat.speed` 테스트 추가 |
| `docs/superpowers/specs/2026-08-19-vehicle-state-timeline-design.md` | 「구현 완료」 블록 |

---

## Task 1: 타임라인 응답 모델과 좌표 계산

**Files:**
- Create: `WooriHaru/Models/StateTimelineModels.swift`
- Test: `WooriHaruTests/StateTimelineTests.swift`

**Interfaces:**
- Consumes: `VehicleFormat.parseKST(_ raw: String) -> Date?` (기존, `WooriHaru/Models/VehicleModels.swift`)
- Produces:
  - `struct StateTimelineResponse: Codable, Equatable { let days: Int; let from: String; let to: String; let states: [StateSegment]; let drives: [TimeSegment]; let charges: [TimeSegment] }`
  - `struct StateSegment: Codable, Equatable { let state: String; let from: String; let to: String }`
  - `struct TimeSegment: Codable, Equatable { let from: String; let to: String }`
  - `enum TimelineKind: Equatable { case asleep, offline, online, driving, charging }` — `var layer: Int`, `static func state(_ raw: String) -> TimelineKind?`
  - `struct TimelineBar: Equatable { let dayIndex: Int; let start: Double; let end: Double; let kind: TimelineKind }`
  - `enum StateTimelineMath` — `static let secondsPerDay: Double`, `static func bars(_ response: StateTimelineResponse) -> [TimelineBar]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/StateTimelineTests.swift`를 만든다.

```swift
import Foundation
import Testing
@testable import WooriHaru

struct StateTimelineTests {

    /// 창은 KST 자정에서 시작한다 — 서버가 그렇게 잘라 준다.
    /// 마지막 행(오늘)만 정오에서 끝난다.
    private func response(states: [StateSegment] = [],
                          drives: [TimeSegment] = [],
                          charges: [TimeSegment] = []) -> StateTimelineResponse {
        StateTimelineResponse(days: 7,
                              from: "2026-08-13T00:00:00",
                              to: "2026-08-19T12:00:00",
                              states: states, drives: drives, charges: charges)
    }

    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 1e-9 }

    @Test func 하루_안에_든_구간이_그_행의_비율로_나온다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "offline", from: "2026-08-13T06:00:00", to: "2026-08-13T12:00:00")
        ]))
        #expect(bars.count == 1)
        #expect(bars[0].dayIndex == 0)
        #expect(bars[0].kind == .offline)
        #expect(isClose(bars[0].start, 0.25))
        #expect(isClose(bars[0].end, 0.5))
    }

    @Test func 자정을_넘는_구간이_두_행으로_쪼개진다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "offline", from: "2026-08-13T22:00:00", to: "2026-08-14T06:00:00")
        ]))
        #expect(bars.count == 2)
        #expect(bars[0].dayIndex == 0)
        #expect(isClose(bars[0].start, 22.0 / 24))
        #expect(isClose(bars[0].end, 1.0))
        #expect(bars[1].dayIndex == 1)
        #expect(isClose(bars[1].start, 0.0))
        #expect(isClose(bars[1].end, 6.0 / 24))
    }

    @Test func 이틀을_통째로_덮는_구간이_세_행이_된다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "asleep", from: "2026-08-13T18:00:00", to: "2026-08-15T06:00:00")
        ]))
        #expect(bars.map(\.dayIndex) == [0, 1, 2])
        #expect(isClose(bars[0].start, 0.75))
        #expect(isClose(bars[1].start, 0.0))
        #expect(isClose(bars[1].end, 1.0))
        #expect(isClose(bars[2].end, 0.25))
    }

    @Test func 창_앞뒤로_삐져나온_구간이_잘린다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-12T20:00:00", to: "2026-08-13T02:00:00")],
            drives: [TimeSegment(from: "2026-08-19T11:00:00", to: "2026-08-19T23:00:00")]))
        let online = bars.filter { $0.kind == .online }
        #expect(online.count == 1)
        #expect(online[0].dayIndex == 0)
        #expect(isClose(online[0].start, 0.0))
        #expect(isClose(online[0].end, 2.0 / 24))

        let driving = bars.filter { $0.kind == .driving }
        #expect(driving.count == 1)
        #expect(driving[0].dayIndex == 6)
        #expect(isClose(driving[0].end, 12.0 / 24)) // to에서 끊긴다
    }

    @Test func 모르는_상태는_버린다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "teleporting", from: "2026-08-13T06:00:00", to: "2026-08-13T07:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 길이가_0인_구간은_막대를_만들지_않는다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "online", from: "2026-08-13T06:00:00", to: "2026-08-13T06:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 상태_주행_충전_순으로_정렬된다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-13T06:00:00", to: "2026-08-13T08:00:00")],
            drives: [TimeSegment(from: "2026-08-13T06:30:00", to: "2026-08-13T07:00:00")],
            charges: [TimeSegment(from: "2026-08-13T07:10:00", to: "2026-08-13T07:40:00")]))
        #expect(bars.map(\.kind) == [.online, .driving, .charging])
    }

    @Test func 빈_응답은_빈_배열을_낸다() {
        #expect(StateTimelineMath.bars(response()).isEmpty)
    }

    @Test func 읽을_수_없는_창은_빈_배열을_낸다() {
        let broken = StateTimelineResponse(days: 7, from: "어제", to: "오늘",
                                           states: [], drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineTests`

Expected: 컴파일 실패 — `cannot find 'StateTimelineMath' in scope`

- [ ] **Step 3: 모델과 계산을 쓴다**

`WooriHaru/Models/StateTimelineModels.swift`:

```swift
import Foundation

// MARK: - 응답

/// 최근 며칠의 차량 상태 — **세 배열이 겹친 채로 온다.**
///
/// 서버가 하나의 띠로 합치지 않는 이유는 TeslaMate `states`에 `driving`·`charging`이 없어서다
/// (`CREATE TYPE states_status AS ENUM ('online', 'offline', 'asleep')`). 합치려면 구간 산술이
/// 필요한데, 세 겹을 그대로 받아 화면이 덧칠하면 그 로직이 사라진다.
struct StateTimelineResponse: Codable, Equatable {
    let days: Int
    /// KST 벽시계. **서버가 KST 자정에 맞춰 잘라 준다** — `days=7`이면 온전한 6일 + 오늘 부분이다.
    let from: String
    let to: String
    let states: [StateSegment]
    let drives: [TimeSegment]
    let charges: [TimeSegment]
}

struct StateSegment: Codable, Equatable {
    /// TeslaMate 원문(`online`·`asleep`·`offline`).
    let state: String
    let from: String
    let to: String
}

/// 주행·충전은 상태 이름이 없다 — 존재 자체가 뜻이다.
struct TimeSegment: Codable, Equatable {
    let from: String
    let to: String
}

// MARK: - 그리는 단위

enum TimelineKind: Equatable {
    case asleep, offline, online, driving, charging

    /// **상태를 깔고 주행, 그 위에 충전을 덧칠한다.** 주행과 충전이 동시에 열리는 일은 없다.
    var layer: Int {
        switch self {
        case .asleep, .offline, .online: 0
        case .driving: 1
        case .charging: 2
        }
    }

    /// **모르는 상태는 버린다.** 글자로 내는 `VehicleFormat.stateLabel`은 원문을 그대로 보여주지만
    /// (상류가 늘렸다는 사실을 숨기지 않으려고), 띠는 색을 골라야 한다 — 임의의 색으로 칠하면
    /// 다섯 색의 뜻이 무너진다. 안 그리는 편이 낫다.
    static func state(_ raw: String) -> TimelineKind? {
        switch raw {
        case "online": .online
        case "asleep": .asleep
        case "offline": .offline
        default: nil
        }
    }
}

/// 한 막대 = 하루 안의 한 조각. `start`·`end`는 그 행에서의 비율(0.0~1.0)이다.
struct TimelineBar: Equatable {
    let dayIndex: Int
    let start: Double
    let end: Double
    let kind: TimelineKind
}

// MARK: - 계산

/// 화면이 하는 유일한 계산이다. **한국은 서머타임이 없어** 하루를 86,400초 고정으로 잡아도
/// 자정 경계가 어긋나지 않는다.
enum StateTimelineMath {
    static let secondsPerDay: Double = 86_400

    static func bars(_ response: StateTimelineResponse) -> [TimelineBar] {
        guard let windowStart = VehicleFormat.parseKST(response.from),
              let windowEnd = VehicleFormat.parseKST(response.to),
              windowEnd > windowStart else { return [] }

        var bars: [TimelineBar] = []
        for segment in response.states {
            guard let kind = TimelineKind.state(segment.state) else { continue }
            bars += split(segment.from, segment.to, kind: kind, from: windowStart, to: windowEnd)
        }
        for segment in response.drives {
            bars += split(segment.from, segment.to, kind: .driving, from: windowStart, to: windowEnd)
        }
        for segment in response.charges {
            bars += split(segment.from, segment.to, kind: .charging, from: windowStart, to: windowEnd)
        }

        // **정렬 기준을 셋 다 준다.** Swift의 `sorted`는 안정 정렬을 보장하지 않아
        // 레이어만으로 비교하면 같은 레이어 안의 순서가 실행마다 달라질 수 있다.
        return bars.sorted {
            if $0.kind.layer != $1.kind.layer { return $0.kind.layer < $1.kind.layer }
            if $0.dayIndex != $1.dayIndex { return $0.dayIndex < $1.dayIndex }
            return $0.start < $1.start
        }
    }

    /// 구간 하나를 날짜 행으로 쪼갠다. **창 밖은 자른다** — 서버가 이미 잘라 주지만,
    /// 계약이 깨져도 화면이 무너지지 않게 한 번 더 막는다.
    private static func split(_ rawFrom: String, _ rawTo: String, kind: TimelineKind,
                              from windowStart: Date, to windowEnd: Date) -> [TimelineBar] {
        guard let segmentStart = VehicleFormat.parseKST(rawFrom),
              let segmentEnd = VehicleFormat.parseKST(rawTo) else { return [] }
        let start = max(segmentStart, windowStart)
        let end = min(segmentEnd, windowEnd)
        guard end > start else { return [] }

        var bars: [TimelineBar] = []
        var cursor = start
        while cursor < end {
            let dayIndex = Int(floor(cursor.timeIntervalSince(windowStart) / secondsPerDay))
            let dayStart = windowStart.addingTimeInterval(Double(dayIndex) * secondsPerDay)
            let sliceEnd = min(end, dayStart.addingTimeInterval(secondsPerDay))
            bars.append(TimelineBar(
                dayIndex: dayIndex,
                start: cursor.timeIntervalSince(dayStart) / secondsPerDay,
                end: sliceEnd.timeIntervalSince(dayStart) / secondsPerDay,
                kind: kind))
            cursor = sliceEnd
        }
        return bars
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineTests`

Expected: PASS (9 tests)

- [ ] **Step 5: 커밋한다**

```bash
git add WooriHaru/Models/StateTimelineModels.swift WooriHaruTests/StateTimelineTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 상태 타임라인 구간을 날짜 행 좌표로 바꾼다"
```

---

## Task 2: 타임라인 서비스와 뷰모델

**Files:**
- Modify: `WooriHaru/Services/VehicleService.swift` (파일 끝, `fetchMissingCost` 뒤)
- Create: `WooriHaru/ViewModels/StateTimelineViewModel.swift`
- Test: `WooriHaruTests/StateTimelineViewModelTests.swift`

**Interfaces:**
- Consumes: `StateTimelineResponse`, `TimelineBar`, `StateTimelineMath.bars` (Task 1)
- Produces:
  - `VehicleService.fetchStateTimeline(days: Int = 7) async throws -> StateTimelineResponse`
  - `final class StateTimelineViewModel` — `static let days: Int`, `private(set) var timeline: StateTimelineResponse?`, `private(set) var bars: [TimelineBar]`, `private(set) var isLoading: Bool`, `var errorMessage: String?`, `var hasSegments: Bool`, `func load() async`, `func reload() async`, `init(service: VehicleService = VehicleService())`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/StateTimelineViewModelTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct StateTimelineViewModelTests {

    private nonisolated static func timeline(states: [StateSegment]) -> StateTimelineResponse {
        StateTimelineResponse(days: 7,
                              from: "2026-08-13T00:00:00",
                              to: "2026-08-19T12:00:00",
                              states: states, drives: [], charges: [])
    }

    private nonisolated static var sample: StateTimelineResponse {
        timeline(states: [StateSegment(state: "online",
                                       from: "2026-08-13T06:00:00",
                                       to: "2026-08-13T08:00:00")])
    }

    private func makeViewModel(_ mock: MockAPIClient) -> StateTimelineViewModel {
        StateTimelineViewModel(service: VehicleService(api: mock))
    }

    @Test func 받은_구간이_막대로_바뀐다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.timeline == Self.sample)
        #expect(viewModel.bars.count == 1)
        #expect(viewModel.bars[0].kind == .online)
        #expect(viewModel.hasSegments)
    }

    @Test func 매번_서버를_부른다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()
        await viewModel.load()

        // 누적(ChargeTotalsViewModel)과 반대다 — 「최근 7일」은 창이 계속 움직인다.
        #expect(mock.getCalls.filter { $0.path == "/tesla/state-timeline" }.count == 2)
    }

    @Test func days를_질의로_보낸다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let call = mock.getCalls.first { $0.path == "/tesla/state-timeline" }
        #expect(call?.query["days"] == String(StateTimelineViewModel.days))
    }

    @Test func 새로고침에_실패해도_있던_값을_지우지_않는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)
        await viewModel.load()

        mock.setError(MockAPIClient.MockAPIError.forced, for: "/tesla/state-timeline")
        await viewModel.reload()

        #expect(viewModel.timeline == Self.sample)
        #expect(viewModel.bars.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func 값이_한_번도_없으면_실패가_오류로만_남는다() async {
        let mock = MockAPIClient()
        mock.setError(MockAPIClient.MockAPIError.forced, for: "/tesla/state-timeline")
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.timeline == nil)
        #expect(viewModel.bars.isEmpty)
        #expect(viewModel.hasSegments == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func 구간이_비어_있어도_오류가_아니다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.timeline(states: [])))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        #expect(viewModel.timeline != nil)
        #expect(viewModel.hasSegments == false)
        #expect(viewModel.errorMessage == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineViewModelTests`

Expected: 컴파일 실패 — `cannot find 'StateTimelineViewModel' in scope`

- [ ] **Step 3: 서비스에 호출을 더한다**

`WooriHaru/Services/VehicleService.swift`의 `fetchMissingCost` 뒤에 붙인다.

```swift
    /// 최근 `days`일의 상태·주행·충전 구간. **세 배열이 겹친 채로 온다** — 서버가 합치지 않는다.
    /// 창은 서버가 KST 자정에 맞춰 잘라 주므로 `days=7`이면 온전한 6일 + 오늘 부분이 온다.
    func fetchStateTimeline(days: Int = 7) async throws -> StateTimelineResponse {
        let response: DataResponse<StateTimelineResponse> =
            try await api.get("/tesla/state-timeline", query: ["days": String(days)])
        guard let timeline = response.data else {
            throw APIError.serverError(statusCode: 200, message: "상태 타임라인 응답이 비어 있습니다")
        }
        return timeline
    }
```

- [ ] **Step 4: 뷰모델을 쓴다**

`WooriHaru/ViewModels/StateTimelineViewModel.swift`:

```swift
import Foundation
import Observation

/// 최근 7일 상태 타임라인 — `/tesla/state-timeline` 하나만 본다.
///
/// **캐시하지 않는다.** 「최근 7일」은 창이 계속 움직이므로 탭에 들어올 때마다 새로 받아야 한다.
/// 전 기간 집계라 한 번만 받는 `ChargeTotalsViewModel`과 정확히 반대다.
@MainActor
@Observable
final class StateTimelineViewModel {
    /// 며칠을 그릴지는 화면이 정한다. 서버는 1~30을 받는다.
    static let days = 7

    /// **`bars`를 저장 속성으로 둔다.** 계산 속성으로 두면 스크롤 한 프레임마다 구간 168개를
    /// 다시 쪼갠다 — 2단계 히트맵이 같은 이유로 `heatMap`을 저장 속성으로 만들었다.
    private(set) var timeline: StateTimelineResponse? {
        didSet { bars = timeline.map(StateTimelineMath.bars) ?? [] }
    }
    private(set) var bars: [TimelineBar] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: VehicleService
    private var generation = 0

    init(service: VehicleService = VehicleService()) { self.service = service }

    /// 구간이 **하나도 없는 것**과 **못 받은 것**은 다르다. 화면이 그 둘을 갈라 그린다.
    var hasSegments: Bool { !bars.isEmpty }

    /// 탭에 들어올 때마다 부른다 — 가드가 없다.
    func load() async { await reload() }

    /// 당겨서 새로고침. **실패해도 있던 값을 지우지 않는다.**
    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let loaded = try await service.fetchStateTimeline(days: Self.days)
            guard current == generation else { return }
            timeline = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            errorMessage = "상태 타임라인을 불러오지 못했습니다."
        }
    }
}
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineViewModelTests`

Expected: PASS (6 tests)

- [ ] **Step 6: 커밋한다**

```bash
git add WooriHaru/Services/VehicleService.swift WooriHaru/ViewModels/StateTimelineViewModel.swift WooriHaruTests/StateTimelineViewModelTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 상태 타임라인을 받아 온다"
```

---

## Task 3: 색 구간을 꺼내고 진한 패널을 옮긴다

이 태스크가 **링을 하나로 만든다.** `BatteryHealthCard`가 갖고 있던 진한 패널과 96pt 링이 새 `BatteryNowCard`로 이사하고, 열화 카드는 밝은 `GlassCard`가 된다.

**Files:**
- Modify: `WooriHaru/Models/VehicleHealthModels.swift` (파일 끝)
- Create: `WooriHaru/Views/Vehicle/BatteryNowCard.swift`
- Modify: `WooriHaru/Views/Vehicle/BatteryHealthCard.swift` (전면 개편)
- Test: `WooriHaruTests/VehicleHealthTests.swift` (스위트 끝에 테스트 추가)

**Interfaces:**
- Consumes: `VehicleMath.rounded(_:)`, `VehicleFormat.percent(_:)`, `VehicleFormat.distance(_:)`, `VehicleFormat.againstBaseline(_:baseline:unit:fraction:)`, `VehicleFormat.stateLabel(_:)`, `VehicleFormat.relative(minutes:)`, `VehicleStatus` (모두 기존)
- Produces:
  - `enum HealthBand { case good, fair, low; static func of(_ remainingPercent: Decimal?) -> HealthBand? }`
  - `enum BatteryBand { case high, mid, low; static func of(_ level: Int?) -> BatteryBand? }`
  - `struct BatteryNowCard: View { let status: VehicleStatus; let minutesInState: Int? }`
  - `struct BatteryNowPlaceholderCard: View { let icon: String; let title: String; let message: String; var retry: (() -> Void)? }`
  - `BatteryHealthCard`는 시그니처 그대로(`remainingPercent`·`degradationPercent`·`fullRangeKm`·`capacityKwh`·`rangeLostKm`), 링만 사라진다
  - `BatteryHealthPlaceholderCard`는 시그니처 그대로, 배경만 `GlassCard`가 된다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleHealthTests.swift`의 스위트 안, 마지막 테스트 뒤에 붙인다.

```swift
    // MARK: - 색 구간

    @Test func 잔존율_색은_반올림한_값으로_판정한다() {
        // [89.5, 90)은 "90%"로 찍힌다 — 색도 90% 구간이어야 표기와 판정이 갈리지 않는다.
        #expect(HealthBand.of(Decimal(string: "89.5")) == .good)
        #expect(HealthBand.of(Decimal(string: "89.4")) == .fair)
        #expect(HealthBand.of(Decimal(string: "79.5")) == .fair)
        #expect(HealthBand.of(Decimal(string: "79.4")) == .low)
        #expect(HealthBand.of(90) == .good)
        #expect(HealthBand.of(nil) == nil)
    }

    @Test func 잔량_색은_정수_경계로_갈린다() {
        #expect(BatteryBand.of(50) == .high)
        #expect(BatteryBand.of(49) == .mid)
        #expect(BatteryBand.of(20) == .mid)
        #expect(BatteryBand.of(19) == .low)
        #expect(BatteryBand.of(nil) == nil)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VehicleHealthTests`

Expected: 컴파일 실패 — `cannot find 'HealthBand' in scope`

- [ ] **Step 3: 색 구간을 모델로 꺼낸다**

`WooriHaru/Models/VehicleHealthModels.swift` 끝에 붙인다.

```swift
// MARK: - 색 구간

/// 잔존율 색 구간. **`VehicleMath.rounded`로 반올림한 값으로 판정한다** — 옆에 찍는 숫자
/// (`VehicleFormat.percent`)도 같은 규칙으로 반올림하므로, 원값으로 판정하면 `[89.5, 90)`이
/// "90%"로 보이면서 색만 노랑이 되는 표기/판정 불일치가 생긴다. 타이어 판정과 같은 규칙이다.
///
/// **뷰가 아니라 모델에 둔다** — 링이 사라져도 이 판정은 살아남아야 하고, 테스트가 붙어야 한다.
enum HealthBand {
    case good, fair, low

    static func of(_ remainingPercent: Decimal?) -> HealthBand? {
        guard let remainingPercent else { return nil }
        let rounded = VehicleMath.rounded(remainingPercent)
        if rounded >= 90 { return .good }
        if rounded >= 80 { return .fair }
        return .low
    }
}

/// 현재 잔량 색 구간. **`batteryLevel`이 `Int`라 반올림 불일치가 생길 길이 없다.**
/// 그래도 판정을 모델에 두는 이유는 위와 같다.
enum BatteryBand {
    case high, mid, low

    static func of(_ level: Int?) -> BatteryBand? {
        guard let level else { return nil }
        if level >= 50 { return .high }
        if level >= 20 { return .mid }
        return .low
    }
}
```

- [ ] **Step 4: 진한 패널과 링을 새 카드로 옮긴다**

`WooriHaru/Views/Vehicle/BatteryNowCard.swift`를 만든다. **`batteryPanelBackground()`와 `BatteryPanelBackground`는 `BatteryHealthCard.swift`에서 잘라내 여기로 옮긴다**(Step 5에서 원본을 지운다).

```swift
import SwiftUI

/// 지금 배터리와 지금 상태 — **화면에서 유일한 진한 패널이다.**
///
/// 이 자리는 3단계까지 `BatteryHealthCard`(열화)의 것이었다. 4단계에서 「현재 상태를 열화보다
/// 위로」 순서가 바뀌면서 강조도 함께 옮겨 왔다 — **눈이 먼저 가라고 만든 패널이 맨 아래에 있으면
/// 강조가 순서와 어긋난다.** 링도 같은 이유로 여기 하나뿐이다. 잔존율 92%와 잔량 72%가 같은
/// 모양으로 나란히 놓이면 무엇이 무엇인지 안 갈린다.
struct BatteryNowCard: View {
    let status: VehicleStatus
    /// `stateSince`로부터 흐른 분. 화면이 1분마다 다시 계산해 넘긴다.
    let minutesInState: Int?

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 96

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                stateLine.padding(.bottom, 10)
                row("사용 가능", status.usableBatteryLevel.map { "\($0)%" } ?? ChargeFormat.placeholder)
                row("위치", status.locationName ?? ChargeFormat.placeholder)
            }
            Spacer(minLength: 0)
        }
        .batteryPanelBackground()
        .accessibilityElement(children: .combine)
        // `.combine`은 자식을 묶을 뿐 그 결과를 읽지 않는다 — 라벨을 얹으면 통째로 대체되므로
        // 화면에 보이는 값을 순서대로 모두 이어 붙인다.
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - 링

    /// 잔량 링. Swift Charts를 들이지 않는 저장소 관례대로 `Circle().trim`으로 그린다.
    /// 열화 링에서 물려받은 어휘 그대로다 — 96pt, 선 굵기 9.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 9)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(status.batteryLevel.map { "\($0)%" } ?? ChargeFormat.placeholder)
                    .font(.title2)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(VehicleFormat.distance(status.ratedRangeKm))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
        }
        .frame(width: ringSize, height: ringSize)
        .animation(.snappy, value: ratio)
    }

    private var ratio: CGFloat {
        guard let level = status.batteryLevel else { return 0 }
        return min(1, max(0, CGFloat(level) / 100))
    }

    /// 50% 이상 초록, 20~50% 노랑, 20% 미만 주황. **문구는 붙이지 않는다** — 색만 바뀐다.
    private var ringColor: Color {
        switch BatteryBand.of(status.batteryLevel) {
        case .high: Color.green300
        case .mid: Color.orange300
        case .low: Color.orange500
        case nil: Color.slate500
        }
    }

    // MARK: - 상태

    /// `state`는 3단계까지 기준 시각 줄에 작은 글씨로만 붙어 있었다. 여기서 제 자리를 갖는다.
    private var stateLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.white.opacity(0.8))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(VehicleFormat.stateLabel(status.state))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                if let minutesInState {
                    Text("\(VehicleFormat.relative(minutes: minutesInState).replacingOccurrences(of: " 전", with: ""))째")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["배터리 \(status.batteryLevel.map { "\($0)퍼센트" } ?? "값 없음")",
                     "주행가능 \(VehicleFormat.distance(status.ratedRangeKm))",
                     VehicleFormat.stateLabel(status.state)]
        if let minutesInState { parts.append("\(VehicleFormat.relative(minutes: minutesInState))부터") }
        parts.append("사용 가능 \(status.usableBatteryLevel.map { "\($0)퍼센트" } ?? "값 없음")")
        parts.append("위치 \(status.locationName ?? "값 없음")")
        return parts.joined(separator: ", ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
    }
}

/// 값이 없거나 못 받았을 때 **같은 자리·같은 색**으로 서는 패널.
/// 첫 화면의 주인공이 사라지면 화면이 무너져 보인다 — 자리가 바뀌어도 같은 이유다.
struct BatteryNowPlaceholderCard: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
                // 장식 아이콘이다 — VoiceOver가 원문 심벌 이름을 읽지 않도록 숨긴다.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 제목·설명만 묶는다. 버튼까지 묶으면 눌러도 반응 없는 문구 조각으로 삼켜진다.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title). \(message)")
                if let retry {
                    Button("다시 시도", action: retry)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .batteryPanelBackground()
    }
}

// MARK: - 공용 패널 배경

extension View {
    /// 진한 패널 배경(그라디언트 + 모서리 + 그림자). `BatteryNowCard`와
    /// `BatteryNowPlaceholderCard`가 같은 자리에 번갈아 서는 같은 패널이라,
    /// 스타일이 갈라지면 화면 상태가 바뀔 때 색이 미묘하게 달라져 보인다.
    fileprivate func batteryPanelBackground() -> some View {
        modifier(BatteryPanelBackground())
    }
}

private struct BatteryPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.navy800, Color.navy900],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .shadow(color: Color.navy900.opacity(0.35), radius: 14, y: 8)
    }
}

#Preview("지금") {
    VStack(spacing: 12) {
        BatteryNowCard(status: VehicleStatus(
            asOf: "2026-08-19T12:00:00", state: "offline", stateSince: "2026-08-19T08:48:00",
            batteryLevel: 72, usableBatteryLevel: 70, ratedRangeKm: 385, estRangeKm: 370,
            odometerKm: 107_258, insideTempC: 28, outsideTempC: 31, climateOn: false,
            locationName: "집", tpmsBar: nil), minutesInState: 192)
        BatteryNowCard(status: VehicleStatus(
            asOf: "2026-08-19T12:00:00", state: "online", stateSince: "2026-08-19T11:55:00",
            batteryLevel: 14, usableBatteryLevel: 12, ratedRangeKm: 74, estRangeKm: 70,
            odometerKm: 107_258, insideTempC: 28, outsideTempC: 31, climateOn: true,
            locationName: nil, tpmsBar: nil), minutesInState: 5)
        BatteryNowPlaceholderCard(icon: "car",
                                  title: "아직 기록이 없어요",
                                  message: "차가 한 번 깨어나면 값이 쌓여요")
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 5: 열화 카드에서 링과 패널 배경을 걷어낸다**

`WooriHaru/Views/Vehicle/BatteryHealthCard.swift`를 아래로 **통째로 바꾼다.**

```swift
import SwiftUI

/// 배터리 건강 — 잔존율과 열화, 그리고 그것을 이루는 세 값.
///
/// **3단계까지 이 카드가 진한 패널과 링을 갖고 있었다.** 4단계에서 「현재 상태를 열화보다 위로」
/// 순서가 바뀌면서 그 둘을 `BatteryNowCard`에 넘기고 밝은 카드로 내려왔다 — 링이 둘이면
/// 잔존율 92%와 잔량 72%가 안 갈리고, 눈이 먼저 가라고 만든 패널이 맨 아래에 있으면
/// 강조가 순서와 어긋난다.
///
/// **경고 문구를 넣지 않는다** — 열화는 고장이 아니다. 잔존율이 낮아지면 숫자 색만 바뀐다.
struct BatteryHealthCard: View {
    let remainingPercent: Decimal?
    let degradationPercent: Decimal?
    let fullRangeKm: Decimal?
    let capacityKwh: Decimal?
    let rangeLostKm: Decimal?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("배터리 건강")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    Text("열화 \(VehicleFormat.percent(degradationPercent))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.slate400)
                }
                .padding(.bottom, 10)

                // 잔존율만 색을 갖는다. 링이 하던 일이 숫자로 옮겨 온 것이다.
                HStack(alignment: .firstTextBaseline) {
                    Text("잔존율")
                        .font(.caption2)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    Text(VehicleFormat.percent(remainingPercent))
                        .font(.title3)
                        .fontWeight(.heavy)
                        .monospacedDigit()
                        .foregroundStyle(remainingColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.vertical, 4)

                row("주행가능", VehicleFormat.againstBaseline(
                    fullRangeKm, baseline: VehicleBaseline.newRangeKm, unit: "km", fraction: 0))
                row("용량", VehicleFormat.againstBaseline(
                    capacityKwh, baseline: VehicleBaseline.newCapacityKwh, unit: "kWh", fraction: 1))
                row("줄어든 거리", VehicleFormat.distance(rangeLostKm))
            }
        }
        .accessibilityElement(children: .combine)
        // `.combine`은 자식을 묶을 뿐 그 결과를 읽지 않는다 — 라벨을 얹으면 통째로 대체되므로
        // 화면에 보이는 순서대로 값을 모두 이어 붙인다.
        .accessibilityLabel(
            "배터리 건강 잔존 \(VehicleFormat.percent(remainingPercent)), 열화 \(VehicleFormat.percent(degradationPercent)), " +
            "주행가능 \(VehicleFormat.againstBaseline(fullRangeKm, baseline: VehicleBaseline.newRangeKm, unit: "km", fraction: 0)), " +
            "용량 \(VehicleFormat.againstBaseline(capacityKwh, baseline: VehicleBaseline.newCapacityKwh, unit: "kWh", fraction: 1)), " +
            "줄어든 거리 \(VehicleFormat.distance(rangeLostKm))"
        )
    }

    /// 90% 이상 초록, 80~90% 주황, 80% 미만 진한 주황. 판정은 `HealthBand`가 한다 —
    /// **반올림한 값으로 갈라야** 옆에 찍히는 숫자와 색이 어긋나지 않는다.
    private var remainingColor: Color {
        switch HealthBand.of(remainingPercent) {
        case .good: Color.green600
        case .fair: Color.orange500
        case .low: Color.orange700
        case nil: Color.slate500
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
    }
}

/// 표본이 없거나 못 받았을 때 **같은 자리**에 서는 카드.
struct BatteryHealthPlaceholderCard: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.slate400)
                    // 장식 아이콘이다 — VoiceOver가 원문 심벌 이름을 읽지 않도록 숨긴다.
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.slate900)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 제목·설명만 묶는다. 버튼까지 묶으면 눌러도 반응 없는 문구 조각으로 삼켜진다.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(title). \(message)")
                    if let retry {
                        Button("다시 시도", action: retry)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue600, in: Capsule())
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview("건강") {
    VStack(spacing: 12) {
        BatteryHealthCard(remainingPercent: Decimal(string: "92.4"), degradationPercent: 8,
                          fullRangeKm: Decimal(string: "525.3"), capacityKwh: Decimal(string: "71.6"),
                          rangeLostKm: 43)
        BatteryHealthCard(remainingPercent: Decimal(string: "78.1"), degradationPercent: 22,
                          fullRangeKm: 444, capacityKwh: nil, rangeLostKm: 124)
        BatteryHealthPlaceholderCard(icon: "bolt.badge.clock",
                                     title: "아직 잴 만한 충전이 없어요",
                                     message: "80% 이상 충전하면 값이 쌓여요")
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 6: 진한 패널이 하나뿐인지 확인한다**

```bash
grep -rn "batteryPanelBackground\|BatteryPanelBackground" WooriHaru/
```

Expected: `BatteryNowCard.swift`에서만 나온다. `BatteryHealthCard.swift`에 남아 있으면 중복 선언으로 컴파일이 깨진다.

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VehicleHealthTests`

Expected: PASS

- [ ] **Step 8: 커밋한다**

```bash
git add WooriHaru/Models/VehicleHealthModels.swift WooriHaru/Views/Vehicle/BatteryNowCard.swift WooriHaru/Views/Vehicle/BatteryHealthCard.swift WooriHaruTests/VehicleHealthTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 진한 패널과 링을 현재 배터리 카드로 옮긴다"
```

---

## Task 4: 상태 타임라인 차트

**Files:**
- Create: `WooriHaru/Views/Vehicle/StateTimelineChart.swift`

**Interfaces:**
- Consumes: `TimelineBar`, `TimelineKind`, `StateTimelineMath.secondsPerDay` (Task 1)
- Produces: `struct StateTimelineChart: View { init(bars: [TimelineBar], days: Int, from: Date) }`

- [ ] **Step 1: 차트를 쓴다**

이 태스크에는 단위 테스트가 없다. 그리는 일만 하고, 좌표 계산은 Task 1이 이미 테스트로 덮었다.

`WooriHaru/Views/Vehicle/StateTimelineChart.swift`:

```swift
import SwiftUI

/// 최근 며칠의 상태를 하루 한 줄씩 가로 띠로. **위가 가장 오래된 날, 아래가 오늘이다** —
/// 아래로 읽어 내려가면 지금에 닿는다.
///
/// **오늘 행은 지금 이후가 빈칸이다.** 아직 오지 않은 시간을 색으로 칠하지 않는다.
///
/// 실측(2026-08-19)으로 최근 7일은 오프라인이 131시간(78%)이라 화면 대부분이 회색이다.
/// 그게 사실이므로 그대로 그린다.
struct StateTimelineChart: View {
    private let days: Int
    private let from: Date
    /// 행별로 미리 갈라 둔다 — 매 프레임 `filter`를 7번 도는 것을 피한다.
    /// 입력이 이미 레이어 순으로 정렬돼 있어 넣는 순서가 곧 덧칠 순서다.
    private let rows: [[TimelineBar]]

    @Environment(\.displayScale) private var displayScale

    private let rowHeight: CGFloat = 14
    private let rowSpacing: CGFloat = 3
    private let labelWidth: CGFloat = 34

    init(bars: [TimelineBar], days: Int, from: Date) {
        self.days = max(0, days)
        self.from = from
        var rows = Array(repeating: [TimelineBar](), count: max(0, days))
        for bar in bars where bar.dayIndex >= 0 && bar.dayIndex < rows.count {
            rows[bar.dayIndex].append(bar)
        }
        self.rows = rows
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("최근 \(days)일")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                VStack(spacing: rowSpacing) {
                    ForEach(0..<days, id: \.self) { dayIndex in
                        row(dayIndex)
                    }
                }

                hourAxis
                legend
            }
        }
    }

    private func row(_ dayIndex: Int) -> some View {
        HStack(spacing: 6) {
            Text(Self.dayFormatter.string(from: date(dayIndex)))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.slate400)
                .frame(width: labelWidth, alignment: .trailing)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.slate100)
                    ForEach(Array(rows[dayIndex].enumerated()), id: \.offset) { _, bar in
                        Rectangle()
                            .fill(Self.color(bar.kind))
                            // **최소 폭을 두지 않는다.** 바닥값을 깔면 짧은 구간이 실제보다
                            // 길어 보이는 띠가 된다 — 「한쪽만으로 그린 막대는 거짓말이다」와
                            // 같은 규칙이다. 화면의 물리적 하한인 1픽셀만 둔다.
                            .frame(width: max(1 / displayScale, width * (bar.end - bar.start)))
                            .offset(x: width * bar.start)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: rowHeight)
        }
        // 구간 168개를 하나씩 읽게 만들지 않는다 — 하루가 한 정거장이다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(dayIndex))
    }

    private var hourAxis: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: labelWidth)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(hour == 0 ? "0시" : "\(hour)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("24")
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(Color.slate400)
        }
        .accessibilityHidden(true)
    }

    /// **`asleep`을 빼지 않는다.** 최근 7일 표본에는 0건이지만 2026년에도 월 1~4건씩 있었다.
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Array(Self.legendItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(item.kind))
                        .frame(width: 8, height: 8)
                    Text(item.label)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 9))
        .foregroundStyle(Color.slate500)
        .accessibilityHidden(true)
    }

    // MARK: - 값

    private func date(_ dayIndex: Int) -> Date {
        from.addingTimeInterval(Double(dayIndex) * StateTimelineMath.secondsPerDay)
    }

    private func rowLabel(_ dayIndex: Int) -> String {
        let bars = rows[dayIndex]
        let onlineHours = bars
            .filter { $0.kind == .online }
            .reduce(0.0) { $0 + ($1.end - $1.start) } * 24
        let drives = bars.count { $0.kind == .driving }
        let charges = bars.count { $0.kind == .charging }

        var parts = [Self.voiceOverFormatter.string(from: date(dayIndex))]
        if onlineHours >= 0.05 { parts.append("온라인 \(String(format: "%.1f", onlineHours))시간") }
        if drives > 0 { parts.append("주행 \(drives)회") }
        if charges > 0 { parts.append("충전 \(charges)회") }
        if parts.count == 1 { parts.append("기록 없음") }
        return parts.joined(separator: ", ")
    }

    private static func color(_ kind: TimelineKind) -> Color {
        switch kind {
        case .asleep: Color.slate200
        case .offline: Color.slate300
        case .online: Color.blue300
        case .driving: Color.blue600
        case .charging: Color.green600
        }
    }

    private static let legendItems: [(kind: TimelineKind, label: String)] = [
        (.online, "온라인"), (.offline, "오프라인"), (.asleep, "잠자는 중"),
        (.driving, "주행"), (.charging, "충전")
    ]

    /// **KST로 찍는다.** `from`은 `VehicleFormat.parseKST`가 KST 벽시계로 읽은 값이라,
    /// 기기 시간대로 찍으면 시차만큼 날짜가 밀린다.
    private static let dayFormatter = kstFormatter("M/d")
    private static let voiceOverFormatter = kstFormatter("M월 d일")

    private static func kstFormatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.dateFormat = pattern
        return formatter
    }
}

#Preview("타임라인") {
    let response = StateTimelineResponse(
        days: 3, from: "2026-08-17T00:00:00", to: "2026-08-19T12:00:00",
        states: [
            StateSegment(state: "offline", from: "2026-08-17T00:00:00", to: "2026-08-17T07:30:00"),
            StateSegment(state: "online", from: "2026-08-17T07:30:00", to: "2026-08-17T09:10:00"),
            StateSegment(state: "asleep", from: "2026-08-17T09:10:00", to: "2026-08-18T06:00:00"),
            StateSegment(state: "online", from: "2026-08-18T06:00:00", to: "2026-08-18T08:00:00"),
            StateSegment(state: "offline", from: "2026-08-18T08:00:00", to: "2026-08-19T09:00:00"),
            StateSegment(state: "online", from: "2026-08-19T09:00:00", to: "2026-08-19T12:00:00")
        ],
        drives: [
            TimeSegment(from: "2026-08-17T07:40:00", to: "2026-08-17T08:10:00"),
            TimeSegment(from: "2026-08-19T09:20:00", to: "2026-08-19T09:50:00")
        ],
        charges: [TimeSegment(from: "2026-08-18T06:10:00", to: "2026-08-18T07:40:00")])

    return StateTimelineChart(bars: StateTimelineMath.bars(response),
                              days: response.days,
                              from: VehicleFormat.parseKST(response.from) ?? .now)
        .padding(16)
        .background(Color.slate50)
}
```

- [ ] **Step 2: 빌드가 되는지 확인한다**

Run: `xcodebuild build -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 커밋한다**

```bash
git add WooriHaru/Views/Vehicle/StateTimelineChart.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 최근 7일 상태를 가로 띠로 그린다"
```

---

## Task 5: 건강 탭 재배치와 배선

**Files:**
- Modify: `WooriHaru/Views/Vehicle/VehicleHealthTab.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleView.swift`

**Interfaces:**
- Consumes: `BatteryNowCard(status:minutesInState:)`, `BatteryNowPlaceholderCard(icon:title:message:retry:)` (Task 3), `StateTimelineChart(bars:days:from:)` (Task 4), `StateTimelineViewModel` (Task 2)
- Produces: `VehicleHealthTab`에 `timelineViewModel: StateTimelineViewModel` 파라미터가 추가된다(`totalsViewModel` 뒤, `onOpenQueue` 앞)

- [ ] **Step 1: 뷰모델을 하나 더 만들어 넘긴다**

`WooriHaru/Views/Vehicle/VehicleView.swift`에서:

`@State private var totalsViewModel = ChargeTotalsViewModel()` 아래에 한 줄을 더한다.

```swift
    @State private var timelineViewModel = StateTimelineViewModel()
```

`case .health:` 블록을 아래로 바꾼다.

```swift
        case .health:
            VehicleHealthTab(healthViewModel: healthViewModel,
                             statusViewModel: statusViewModel,
                             totalsViewModel: totalsViewModel,
                             timelineViewModel: timelineViewModel) { showingQueue = true }
                // 상태와 타임라인은 탭에 들어올 때마다 새로 받는다 — 「지금」과 「최근 7일」은
                // 둘 다 창이 움직인다. 배터리 건강·충전 누적은 전 기간 집계라 뷰모델이 한 번만
                // 받고, 배지 수만 매번 맞춘다.
                .task {
                    async let status: Void = statusViewModel.load()
                    async let health: Void = healthViewModel.load()
                    async let totals: Void = totalsViewModel.load()
                    async let timeline: Void = timelineViewModel.load()
                    _ = await (status, health, totals, timeline)
                }
```

- [ ] **Step 2: 건강 탭 순서를 바꾼다**

`WooriHaru/Views/Vehicle/VehicleHealthTab.swift`에서 프로퍼티에 한 줄을 더한다.

```swift
    @Bindable var totalsViewModel: ChargeTotalsViewModel
    @Bindable var timelineViewModel: StateTimelineViewModel
```

`body`의 `VStack` 내용을 아래 순서로 바꾼다. **`statusSection`이 `ChargeTotalsCard`보다 위로 올라가고, `healthSection`이 맨 아래로 내려간다.**

```swift
            VStack(spacing: 12) {
                asOfLine.padding(.top, 8)

                // 이 앱에서 사람이 실제로 손을 쓰는 일은 금액을 채우는 것 하나뿐이다.
                // 첫 화면이 바뀌어도 그 일이 한 번의 탭 안에 있어야 한다.
                if healthViewModel.missingCostCount > 0 {
                    missingCostBadge
                }

                // 「지금 어떤가」를 전부 위로 올린다 — 순서가 한 가지 뜻을 갖게 한다.
                statusSection
                timelineSection

                // 값이 하나도 없는 채로 실패하면 네 「—」만 남아 "아직 로딩 중"과 갈리지 않는다 —
                // 한 줄로 알린다. 값이 있는 새로고침 실패는 조용히 있던 값을 그대로 보여준다.
                if totalsViewModel.totals == nil, let error = totalsViewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ChargeTotalsCard(totals: totalsViewModel.totals,
                                 odometerKm: statusViewModel.status?.odometerKm,
                                 fastWonPerKwh: totalsViewModel.fastWonPerKwh,
                                 slowWonPerKwh: totalsViewModel.slowWonPerKwh)

                healthSection
            }
```

- [ ] **Step 3: 새로고침을 다섯 갈래로 늘린다**

같은 파일의 `.refreshable`을 바꾼다.

```swift
        .refreshable {
            // 다섯 다 병렬로 부른다 — `healthViewModel.reload()`와 `.refreshMissingCount()`는
            // 같은 뷰모델 인스턴스를 건드리지만 쓰는 값이 겹치지 않는다(`samples`/`isLoaded`/
            // `errorMessage` vs `missingCostCount`). 나머지 셋은 아예 다른 뷰모델이라 무관하다.
            async let health: Void = healthViewModel.reload()
            async let missingCount: Void = healthViewModel.refreshMissingCount()
            async let status: Void = statusViewModel.reload()
            async let totals: Void = totalsViewModel.reload()
            async let timeline: Void = timelineViewModel.reload()
            _ = await (health, missingCount, status, totals, timeline)
        }
```

- [ ] **Step 4: `batteryCard`를 `BatteryNowCard`로 바꾸고 타임라인 절을 더한다**

같은 파일에서 `statusSection`의 `batteryCard(status)` 호출을 바꾸고, `private func batteryCard(_:)` 전체를 **지운다**(`odometer` 줄이 누적 카드의 「주행」 타일과 중복이라 함께 사라진다).

`statusSection`의 값 있음 가지를 바꾼다.

```swift
        } else if let status = statusViewModel.status, statusViewModel.hasRecord {
            // **1분마다 다시 그린다.** 「3시간 12분째」는 화면을 열어 둔 채로도 흘러간다 —
            // 기준 시각 줄이 같은 이유로 `TimelineView`를 쓴다.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                BatteryNowCard(status: status,
                               minutesInState: minutesInState(status, at: context.date))
            }
            TirePressureCard(tpms: status.tpmsBar)
            cabinCard(status)
        } else if statusViewModel.status != nil {
```

그리고 `statusSection`의 무기록·오류 가지에서 `ContentUnavailableView`/`statusErrorState` 대신 진한 패널 플레이스홀더를 세운다 — **주인공 자리는 비우지 않는다.**

```swift
        if statusViewModel.isLoading && statusViewModel.status == nil {
            BatteryNowPlaceholderCard(icon: "car",
                                      title: "불러오는 중",
                                      message: "차량 상태를 받고 있어요")
        } else if let error = statusViewModel.errorMessage, statusViewModel.status == nil {
            BatteryNowPlaceholderCard(icon: "exclamationmark.triangle",
                                      title: "차량 상태를 불러오지 못했어요",
                                      message: error,
                                      retry: { Task { await statusViewModel.reload() } })
        } else if let status = statusViewModel.status, statusViewModel.hasRecord {
```

무기록 가지도 같은 패널로 바꾼다.

```swift
        } else if statusViewModel.status != nil {
            // 기록이 아직 없는 것과 못 받은 것은 다르다.
            BatteryNowPlaceholderCard(icon: "car",
                                      title: "아직 기록이 없어요",
                                      message: "차가 한 번 깨어나면 값이 쌓여요")
        }
```

`private func statusErrorState(_:)`는 더 이상 쓰이지 않으므로 **지운다.**

`minutesInState`를 같은 파일에 더한다.

```swift
    /// `stateSince`부터 흐른 분. **KST로 읽는다** — 서버가 KST 벽시계 값을 주는데
    /// 기기 시간대로 읽으면 시차만큼 어긋난다. `asOf`와 같은 이유다.
    private func minutesInState(_ status: VehicleStatus, at date: Date) -> Int? {
        guard let since = status.stateSince.flatMap(VehicleFormat.parseKST) else { return nil }
        return VehicleMath.minutesAgo(from: since, now: date)
    }
```

- [ ] **Step 5: 타임라인 절을 더한다**

같은 파일, `statusSection` 아래에 붙인다.

```swift
    // MARK: - 최근 7일

    /// **넷으로 갈린다** — 아직 안 받음 / 못 받음(값 없음) / 기록 없음 / 값 있음.
    /// 값이 있는 새로고침 실패는 띠를 그대로 두고 한 줄만 알린다.
    @ViewBuilder private var timelineSection: some View {
        if let error = timelineViewModel.errorMessage, timelineViewModel.timeline != nil {
            Text(error)
                .font(.caption)
                .foregroundStyle(Color.red500)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let timeline = timelineViewModel.timeline,
           let from = VehicleFormat.parseKST(timeline.from) {
            if timelineViewModel.hasSegments {
                StateTimelineChart(bars: timelineViewModel.bars, days: timeline.days, from: from)
            } else {
                GlassCard {
                    Text("최근 \(timeline.days)일 기록이 없어요")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if let error = timelineViewModel.errorMessage {
            GlassCard {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                    Spacer(minLength: 8)
                    Button("다시 시도") { Task { await timelineViewModel.reload() } }
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
        }
        // 아직 안 받았고 오류도 없으면 아무것도 그리지 않는다 — 위 배터리 패널이 이미
        // 「불러오는 중」을 말하고 있어 스피너가 둘이면 화면이 시끄럽다.
    }
```

- [ ] **Step 6: 전체 테스트를 돌린다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: 전 스위트 PASS

- [ ] **Step 7: 커밋한다**

```bash
git add WooriHaru/Views/Vehicle/VehicleHealthTab.swift WooriHaru/Views/Vehicle/VehicleView.swift
git commit -m "feat: 건강 탭에서 지금 상태를 열화보다 위로 올린다"
```

---

## Task 6: 주행 통계 타일

**Files:**
- Modify: `WooriHaru/Models/DriveInsightsModels.swift`
- Modify: `WooriHaru/Models/VehicleModels.swift` (`VehicleFormat` 확장 안, `distance` 근처)
- Create: `WooriHaru/Views/Vehicle/DriveStatsCard.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleDriveTab.swift`
- Test: `WooriHaruTests/VehicleMathTests.swift` (스위트 끝)
- Modify: `WooriHaruTests/VehicleDriveTests.swift` (생성부 4곳), `WooriHaruTests/VehicleServiceTests.swift` (생성부 2곳)

**Interfaces:**
- Consumes: `DriveInsightsResponse` (기존), `VehicleFormat.distance(_:)` (기존)
- Produces:
  - `DriveInsightsResponse`에 `let maxSpeedKmh: Int?`, `let monthDistanceKm: Decimal?`, `let yearDistanceKm: Decimal?`
  - `VehicleFormat.speed(_ kmh: Int?) -> String`
  - `struct DriveStatsCard: View { let maxSpeedKmh: Int?; let monthDistanceKm: Decimal?; let yearDistanceKm: Decimal? }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleMathTests.swift`의 스위트 안 마지막에 붙인다.

```swift
    @Test func 속도는_정수와_단위로_찍는다() {
        #expect(VehicleFormat.speed(138) == "138km/h")
        #expect(VehicleFormat.speed(0) == "0km/h")
        #expect(VehicleFormat.speed(nil) == ChargeFormat.placeholder)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VehicleMathTests`

Expected: 컴파일 실패 — `type 'VehicleFormat' has no member 'speed'`

- [ ] **Step 3: 응답에 필드 셋을 더한다**

`WooriHaru/Models/DriveInsightsModels.swift`의 `DriveInsightsResponse` 안, `places` 아래에 붙인다.

```swift
    /// **역대 최고다 — `months` 창을 따르지 않는다.** 창이 바뀔 때마다 바뀌면 기록이 아니다
    /// (실측 138km/h는 2024~2025년 것이라 12개월 창으로 자르면 134가 나온다). 화면 라벨을
    /// 「역대 최고」로 두어 옆 두 칸과 범위가 다름을 글자로 드러낸다.
    ///
    /// **그 주행의 날짜를 싣지 않는다** — 138km/h가 최소 3건 동률이라(2025-09-13·2025-03-22·
    /// 2024-03-09) 「그날 기록했다」고 말할 수 없다.
    let maxSpeedKmh: Int?
    /// 이번 달·올해 주행거리(KST 경계). **서버는 주행이 없으면 `0`을 낸다** — 기간이 못박힌
    /// 합계라 「0km 탔다」가 사실이지 기록 부재가 아니다.
    ///
    /// **그래도 앱에서는 옵셔널이다.** 이 필드를 내지 않는 서버를 만나면 `nil`이 되는데, 그때는
    /// 카드째 감춘다 — 앱이 서버보다 먼저 나가도 주행 탭 전체가 디코딩 실패로 무너지지 않는다.
    let monthDistanceKm: Decimal?
    let yearDistanceKm: Decimal?
```

- [ ] **Step 4: 속도 포매터를 더한다**

`WooriHaru/Models/VehicleModels.swift`의 `VehicleFormat` 확장에서 `odometer` 바로 아래에 붙인다.

```swift
    /// 138 → "138km/h". **소수를 두지 않는다** — `drives.speed_max`가 `smallint`다.
    static func speed(_ kmh: Int?) -> String {
        guard let kmh else { return ChargeFormat.placeholder }
        return "\(kmh)km/h"
    }
```

- [ ] **Step 5: 기존 테스트의 생성부를 고친다**

`DriveInsightsResponse(` 생성부 6곳에 인자 셋을 더한다. 위치를 찾는다.

```bash
grep -rn "DriveInsightsResponse(" WooriHaruTests/
```

각 생성부의 `places:` 인자 뒤에 아래를 붙인다(값은 실측 그대로).

```swift
                              maxSpeedKmh: 138,
                              monthDistanceKm: Decimal(string: "1331.3"),
                              yearDistanceKm: Decimal(string: "13440.4")
```

- [ ] **Step 6: 타일 카드를 쓴다**

`WooriHaru/Views/Vehicle/DriveStatsCard.swift`:

```swift
import SwiftUI

/// 주행 통계 타일 셋 — 역대 최고 속도 / 이번 달 / 올해.
///
/// **다섯째 차트를 더하지 않는다.** 이 탭에는 이미 카드가 넷 있고, 여기 들어갈 값 셋은
/// 추세가 아니라 지금의 숫자다. 연도별 막대는 저울질했지만 두지 않았다.
///
/// **라벨이 「최고 속도」가 아니라 「역대 최고」인 이유**는 이 칸만 기간 칩을 따르지 않아서다.
/// 옆 두 칸은 이번 달·올해이고 이 칸은 전 기간이다 — 범위 차이를 글자가 말해야 한다.
struct DriveStatsCard: View {
    let maxSpeedKmh: Int?
    let monthDistanceKm: Decimal?
    let yearDistanceKm: Decimal?

    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                tile(VehicleFormat.speed(maxSpeedKmh), "역대 최고")
                tile(VehicleFormat.distance(monthDistanceKm), "이번 달")
                tile(VehicleFormat.distance(yearDistanceKm), "올해")
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

#Preview("주행 통계") {
    VStack(spacing: 12) {
        DriveStatsCard(maxSpeedKmh: 138,
                       monthDistanceKm: Decimal(string: "1331.3"),
                       yearDistanceKm: Decimal(string: "13440.4"))
        DriveStatsCard(maxSpeedKmh: nil, monthDistanceKm: 0, yearDistanceKm: 0)
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 7: 주행 탭 맨 위에 건다**

`WooriHaru/Views/Vehicle/VehicleDriveTab.swift`의 `cards`에서 **맨 앞**에 붙인다.

```swift
    @ViewBuilder private var cards: some View {
        // **서버가 이 셋을 아직 내지 않으면 카드째 감춘다.** 세 칸이 전부 「—」인 카드는
        // 자리만 차지한다 — 전비 카드를 `showsEfficiency`로 감추는 것과 같은 규칙이다.
        if showsStats {
            DriveStatsCard(maxSpeedKmh: viewModel.insights?.maxSpeedKmh,
                           monthDistanceKm: viewModel.insights?.monthDistanceKm,
                           yearDistanceKm: viewModel.insights?.yearDistanceKm)
        }
        // `cars.efficiency`가 없으면 전비를 낼 수 없다. 카드째 감춘다 —
        // 다섯 줄이 전부 「—」인 카드는 자리만 차지한다.
        if viewModel.showsEfficiency {
```

그리고 같은 파일에 판정을 더한다.

```swift
    /// 셋 다 없으면 서버가 아직 이 필드를 내지 않는 것이다. 하나라도 있으면 그린다 —
    /// 「이번 달 0km」는 값이 없는 것이 아니라 **안 탔다는 사실**이다.
    private var showsStats: Bool {
        guard let insights = viewModel.insights else { return false }
        return insights.maxSpeedKmh != nil
            || insights.monthDistanceKm != nil
            || insights.yearDistanceKm != nil
    }
```

- [ ] **Step 8: 전체 테스트를 돌린다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: 전 스위트 PASS

- [ ] **Step 9: 커밋한다**

```bash
git add WooriHaru/Models/DriveInsightsModels.swift WooriHaru/Models/VehicleModels.swift WooriHaru/Views/Vehicle/DriveStatsCard.swift WooriHaru/Views/Vehicle/VehicleDriveTab.swift WooriHaruTests/VehicleMathTests.swift WooriHaruTests/VehicleDriveTests.swift WooriHaruTests/VehicleServiceTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 주행 탭에 역대 최고 속도와 기간 주행거리를 더한다"
```

---

## Task 7: 설계 문서를 구현에 맞춘다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-19-vehicle-state-timeline-design.md`

- [ ] **Step 1: 「구현 완료」 블록을 넣는다**

문서의 `## 목표` 바로 위에 아래를 넣는다. **1~3단계 문서가 쓰는 것과 같은 형식이다.**

```markdown
> **구현 완료 (2026-08-19).** 설계와 갈라진 곳이 넷이다.
>
> - **`maxSpeedKmh`·`monthDistanceKm`·`yearDistanceKm`를 앱에서 옵셔널로 받는다.** 설계는 서버 계약을 따라 거리 둘을 비옵셔널로 적었지만, 서버가 이 필드를 내기 전에 앱이 먼저 나갈 수 있다 — 비옵셔널이면 키가 없을 때 **주행 탭 응답 전체가 디코딩 실패**로 무너진다. 셋 다 `nil`이면 카드째 감춘다(`showsStats`). 「0km 탔다」는 서버가 `0`을 내므로 이 결정과 부딪히지 않는다.
> - **`statusSection`의 오류·무기록 자리를 `BatteryNowPlaceholderCard`로 바꿨다.** 설계는 카드만 옮긴다고 적었으나, `ContentUnavailableView`가 그대로 남으면 **주인공 자리가 통째로 비는** 화면이 된다 — 진한 패널이 자리를 지켜야 한다는 원래 이유가 자리를 옮겨도 그대로다.
> - **`batteryCard`와 `statusErrorState`를 지웠다.** 전자는 `BatteryNowCard`가 대신하고(`odometer` 줄은 누적 카드와 중복이라 함께 사라졌다), 후자는 플레이스홀더가 대신한다.
> - **`HealthBand`·`BatteryBand`를 모델로 꺼냈다.** 설계는 색 판정을 뷰 안에 둔 채로 테스트하겠다고 적었는데, `ringColor`가 `private`이라 테스트가 닿지 않는다. 판정을 `VehicleHealthModels.swift`로 옮겨 「반올림한 값으로 판정한다」는 규칙에 테스트를 붙였다.
```

- [ ] **Step 2: 남은 확인거리를 적는다**

문서 맨 끝에 붙인다.

```markdown
## 사람이 확인할 것

시뮬레이터에서는 서버가 없어 다음을 실기로 봐야 한다.

- 건강 탭에서 **진한 패널이 하나뿐이고 링도 하나뿐인지** — 스크롤을 끝까지 내려 열화 카드가 밝은지 본다
- 상태 타임라인이 **오늘 행에서 지금 시각에 끊기는지** — 그 뒤가 색으로 칠해지면 안 된다
- 오프라인이 78%인 실측대로 **띠 대부분이 회색인지**, 그리고 주행(파랑)·충전(초록)이 그 위에 보이는지
- 「3시간 12분째」가 **1분마다 갱신되는지** — 화면을 열어 둔 채로 확인한다
- 주행 탭 타일 셋의 「이번 달」이 **요약 탭의 그 달 주행거리와 같은 숫자인지** (실측 기준 1,331.3km → `1,331km`)
- 서버에 새 필드가 없을 때 **주행 탭이 여전히 카드 넷을 그리는지**(타일 카드만 사라져야 한다)
```

- [ ] **Step 3: 커밋한다**

```bash
git add docs/superpowers/specs/2026-08-19-vehicle-state-timeline-design.md
git commit -m "docs: 4단계 구현 완료와 갈라진 결정을 적는다"
```

---

## 자기 점검

**1. 스펙 커버리지**

| 스펙 요구 | 태스크 |
|---|---|
| 건강 탭 순서 재배치 | Task 5 |
| 진한 패널·링 주인공 교체 | Task 3 |
| `BatteryNowCard` (링·상태 배지·사용 가능·위치) | Task 3 |
| `odometer` 줄 제거 | Task 5 |
| `BatteryHealthCard` 강등, 잔존율 색 유지 | Task 3 |
| `StateTimelineChart` (7행·색·범례·VoiceOver) | Task 4 |
| 겹침 순서 상태→주행→충전 | Task 1 (`layer`), Task 4 (그리기) |
| 오늘 행이 지금에서 끊김 | Task 1 (창 클리핑) |
| `asleep`을 범례에서 빼지 않음 | Task 4 |
| `StateTimelineMath.bars` 세 가지 일 | Task 1 |
| 최소 폭 없음, 1픽셀 하한 | Task 4 |
| `StateTimelineViewModel` 캐시 없음 | Task 2 |
| 새로고침 다섯 갈래 | Task 5 |
| 주행 통계 필드 셋 | Task 6 |
| 「역대 최고」 라벨 | Task 6 |
| `VehicleFormat.speed` | Task 6 |
| 경계·오류 표 | Task 5(상태·타임라인), Task 6(타일) |
| 테스트 목록 | Task 1·2·3·6 |

**2. 플레이스홀더 스캔** — 「TBD」·「적절히 처리」·코드 없는 지시 없음. 모든 코드 단계에 실제 코드가 들어 있다.

**3. 타입 일관성**

- `StateTimelineResponse`/`StateSegment`/`TimeSegment`/`TimelineKind`/`TimelineBar`/`StateTimelineMath` — Task 1에서 정의, Task 2·4·5에서 같은 이름으로 사용
- `StateTimelineViewModel.days`(static) — Task 2 정의, Task 2 테스트에서 사용
- `BatteryNowCard(status:minutesInState:)` — Task 3 정의, Task 5 호출과 인자 이름 일치
- `BatteryNowPlaceholderCard(icon:title:message:retry:)` — Task 3 정의, Task 5 호출 세 곳과 일치
- `StateTimelineChart(bars:days:from:)` — Task 4 정의, Task 5 호출과 일치
- `DriveStatsCard(maxSpeedKmh:monthDistanceKm:yearDistanceKm:)` — Task 6 정의·호출 일치
- `HealthBand.of(_:)`/`BatteryBand.of(_:)` — Task 3 정의, 같은 태스크의 뷰와 테스트에서 사용
- `VehicleFormat.speed(_:)` — Task 6 정의, 같은 태스크의 카드와 테스트에서 사용
- `VehicleMath.minutesAgo(from:now:)` — 기존 API, Task 5의 `minutesInState`가 사용

**4. 알려진 위험**

- **Task 3이 가장 크다.** 두 파일을 동시에 뒤집고 `batteryPanelBackground`가 한쪽에만 남아야 한다. Step 7의 `grep`이 그 확인이다.
- **Task 6은 기존 테스트 6곳을 깨뜨린 뒤 고친다.** Step 5를 건너뛰면 전체 빌드가 실패한다.
- **서버가 없다.** Task 2·5·6은 실서버 없이 목으로만 검증된다. Task 7의 「사람이 확인할 것」이 그 빈틈을 명시한다.
