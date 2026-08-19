# 24시간 타임라인·평균 주행거리 구현 계획 (A단계)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상태 타임라인을 7일 격자에서 **지금부터 거꾸로 24시간 한 줄**로 바꾸고, 주행 타일의 「이번 달·올해」를 **월·연 평균**으로 바꾼다.

**Architecture:** 계산이 줄어드는 변경이다. 행이 하나가 되면서 `StateTimelineMath`의 자정 분할이 통째로 사라지고 `TimelineBar`에서 `dayIndex`가 빠진다. 평균은 서버가 분자(`totalDistanceKm`)와 분모(`recordedMonths`)를 주고 앱이 나눈다 — 이 저장소가 단가·전비를 다루는 방식과 같다.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), `@Observable` 뷰모델, Swift Testing(`import Testing`), 손그림 차트(`GeometryReader`+`Rectangle`, Swift Charts 미사용)

**Spec:** `docs/superpowers/specs/2026-08-19-vehicle-dark-theme-design.md` — **A단계 부분만.** B단계(다크 테마)는 이 계획이 머지된 뒤 별도 계획으로 간다. 같은 파일 열여덟 개를 크게 건드리므로 겹치면 충돌한다.

**서버 설계:** `../toy-back/docs/superpowers/specs/2026-08-19-tesla-state-timeline-drive-stats-design.md` 개정판(`154595a`). **서버는 아직 개정 전 계약으로 돌고 있다** — 이 계획은 개정된 계약을 보고 만들며, 앱이 먼저 나가도 무너지지 않아야 한다.

**앞선 작업:** 4단계가 `main`에 있다(`6222662`). 현재 브랜치는 `feat/vehicle-dark-theme`이고 스펙 커밋(`b6be619`)이 올라가 있다.

## Global Constraints

- **새 파일은 `ruby scripts/xcode-add-files.rb <경로...>`로 앱 타겟에 등록한다.** `WooriHaru/` 아래는 폴더 동기화가 없고 `WooriHaruTests/`는 자동이다. **이 계획은 새 파일을 만들지 않으므로 이 명령을 쓸 일이 없다.**
- 전체 테스트: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. 단일 스위트는 뒤에 `-only-testing:WooriHaruTests/<스위트>`를 붙인다. **포그라운드로 돌린다** — 백그라운드로 띄우고 기다리면 턴이 끝나 버린다. 몇 분 걸리는 것이 정상이다.
- 출력이 길다. `2>&1 | grep -E "Test run with|failed|error:|warning:|TEST SUCCEEDED|TEST FAILED" | tail -30`으로 거른다.
- 편집기의 SourceKit 진단(`No such module 'Testing'`, `Cannot find type X in scope`)은 이 프로젝트의 알려진 색인 잡음이다. **`xcodebuild`가 권위다.**
- **Swift Charts를 쓰지 않는다.** `GeometryReader`·`Rectangle`로 그린다.
- 색은 `Color+Extensions.swift`의 기존 토큰만 쓴다. **새 토큰을 만들지 않는다** — 다크 팔레트는 B단계의 몫이다.
- 시각 문자열은 **KST 벽시계**이고 `VehicleFormat.parseKST`로만 읽는다. 눈금 포매터의 `timeZone`도 `Asia/Seoul`이다.
- **최소 폭을 두지 않는다.** 막대 폭의 하한은 `1 / displayScale`(화면 1픽셀)뿐이다.
- 「값이 있는 새로고침 실패는 있던 값을 그대로 보여주고 한 줄 배너만 띄운다.」 **오류 확인이 값 확인보다 먼저 오면 안 된다.**
- 「기록이 없음」과 「못 받음」을 뭉개지 않는다. **「0」과 「nil」은 다르다.**
- 뷰모델은 `@MainActor @Observable`, `generation` 토큰, `catch is CancellationError`는 조용히 리턴.
- **화면이 쓰는 값은 뷰모델이 낸다.** 뷰에서 다시 계산하면 테스트하는 값과 그리는 값이 다른 코드가 된다(3단계에서 두 번 겪었다).
- 주석과 테스트 함수 이름은 한국어 평서형(`~한다`, `~다`)이며 설계 근거를 담는 산출물의 일부다.
- 커밋 메시지는 한국어 평서형.

## 실측 (2026-08-19, 이 계획의 전제)

| 항목 | 값 |
|---|---|
| 최근 24시간 구간 | 상태 21 · 주행 1 · 충전 0 = **22개** |
| 주행 총거리 | **107,257.8 km** |
| 기록이 있는 달 | **60개월** |
| → 월 평균 | 107257.8 / 60 = **1,787.63** → 화면 `1,788km` |
| → 연 평균 | × 12 = **21,451.56** → 화면 `21,452km` |
| 역대 최고 속도 | **138 km/h** |

---

## 파일 구조

**새로 만들지 않는다.** 전부 기존 파일을 고친다.

| 파일 | 무엇을 |
|---|---|
| `WooriHaru/Models/StateTimelineModels.swift` | `days`→`hours`, `TimelineBar`에서 `dayIndex` 제거, 자정 분할 삭제 |
| `WooriHaru/Services/VehicleService.swift` | `fetchStateTimeline(days:)` → `(hours:)` |
| `WooriHaru/ViewModels/StateTimelineViewModel.swift` | `days` → `hours = 24` |
| `WooriHaru/Views/Vehicle/StateTimelineChart.swift` | 7행 격자 → 한 줄 (전면 개편) |
| `WooriHaru/Views/Vehicle/VehicleHealthTab.swift` | `timelineSection` 배선(`to`도 파싱, 「N시간」) |
| `WooriHaru/Models/DriveInsightsModels.swift` | 거리 필드 둘 → `totalDistanceKm`·`recordedMonths` |
| `WooriHaru/Models/VehicleModels.swift` | `VehicleMath` 평균 둘 추가 |
| `WooriHaru/ViewModels/VehicleDriveViewModel.swift` | `showsStats` 필드 교체, 평균 파생 값 둘 추가 |
| `WooriHaru/Views/Vehicle/DriveStatsCard.swift` | 라벨·인자 교체 |
| `WooriHaruTests/StateTimelineTests.swift` | 자정 분할 테스트 삭제, 좌표 기준으로 재작성 |
| `WooriHaruTests/StateTimelineViewModelTests.swift` | `days`→`hours` |
| `WooriHaruTests/VehicleMathTests.swift` | 평균 테스트 추가 |
| `WooriHaruTests/VehicleDriveTests.swift` | 생성부 4곳 + `showsStats` 테스트 4건 |
| `WooriHaruTests/VehicleServiceTests.swift` | 생성부 2곳 + 타임라인 질의 |
| 설계 문서 | 「구현 완료」 |

---

## Task 1: 계산을 한 줄로 줄인다

**Files:**
- Modify: `WooriHaru/Models/StateTimelineModels.swift`
- Test: `WooriHaruTests/StateTimelineTests.swift` (전면 재작성)

**Interfaces:**
- Consumes: `VehicleFormat.parseKST(_ raw: String) -> Date?` (기존)
- Produces:
  - `struct StateTimelineResponse: Codable, Equatable { let hours: Int; let from: String; let to: String; let states: [StateSegment]; let drives: [TimeSegment]; let charges: [TimeSegment] }`
  - `struct TimelineBar: Equatable { let start: Double; let end: Double; let kind: TimelineKind }` — **`dayIndex`가 없다**
  - `StateTimelineMath.bars(_:) -> [TimelineBar]` — 시그니처 그대로, 의미만 바뀐다
  - `StateSegment`·`TimeSegment`·`TimelineKind`는 그대로다
  - **`StateTimelineMath.secondsPerDay`는 삭제한다** — 하루 단위를 쓰는 곳이 사라진다

- [ ] **Step 1: 테스트를 새로 쓴다**

`WooriHaruTests/StateTimelineTests.swift`를 아래로 **통째로 바꾼다.** 자정 분할 테스트 셋(`하루_안에_든_구간이…`, `자정을_넘는_구간이…`, `이틀을_통째로_덮는_구간이…`)은 그 코드가 사라지므로 **지운다** — 남기면 없는 것을 지키는 테스트가 된다.

```swift
import Foundation
import Testing
@testable import WooriHaru

struct StateTimelineTests {

    /// 범위는 **자정에 맞춰지지 않는다** — 지금부터 거꾸로 24시간이다.
    /// 13:00 ~ 다음날 13:00으로 잡아 비율 계산이 눈으로 검산된다.
    private func response(states: [StateSegment] = [],
                          drives: [TimeSegment] = [],
                          charges: [TimeSegment] = []) -> StateTimelineResponse {
        StateTimelineResponse(hours: 24,
                              from: "2026-08-18T13:00:00",
                              to: "2026-08-19T13:00:00",
                              states: states, drives: drives, charges: charges)
    }

    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 1e-9 }

    @Test func 범위_한가운데_구간이_비율로_나온다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "offline", from: "2026-08-18T19:00:00", to: "2026-08-19T01:00:00")
        ]))
        #expect(bars.count == 1)
        #expect(bars[0].kind == .offline)
        #expect(isClose(bars[0].start, 6.0 / 24))   // 13시 → 19시
        #expect(isClose(bars[0].end, 12.0 / 24))    // 13시 → 다음날 1시
    }

    @Test func 자정을_넘어도_막대가_쪼개지지_않는다() {
        // 4단계에서는 두 행으로 갈렸다. 한 줄이 되면서 하나로 이어진다.
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "asleep", from: "2026-08-18T22:00:00", to: "2026-08-19T06:00:00")
        ]))
        #expect(bars.count == 1)
        #expect(isClose(bars[0].start, 9.0 / 24))
        #expect(isClose(bars[0].end, 17.0 / 24))
    }

    @Test func 범위_앞뒤로_삐져나온_구간이_잘린다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-18T11:00:00", to: "2026-08-18T15:00:00")],
            drives: [TimeSegment(from: "2026-08-19T12:00:00", to: "2026-08-19T18:00:00")]))

        let online = bars.filter { $0.kind == .online }
        #expect(online.count == 1)
        #expect(isClose(online[0].start, 0.0))
        #expect(isClose(online[0].end, 2.0 / 24))

        let driving = bars.filter { $0.kind == .driving }
        #expect(driving.count == 1)
        #expect(isClose(driving[0].start, 23.0 / 24))
        #expect(isClose(driving[0].end, 1.0))       // 오른쪽 끝 = 지금
    }

    @Test func 모르는_상태는_버린다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "teleporting", from: "2026-08-18T14:00:00", to: "2026-08-18T15:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 길이가_0인_구간은_막대를_만들지_않는다() {
        let bars = StateTimelineMath.bars(response(states: [
            StateSegment(state: "online", from: "2026-08-18T14:00:00", to: "2026-08-18T14:00:00")
        ]))
        #expect(bars.isEmpty)
    }

    @Test func 상태_주행_충전_순으로_정렬된다() {
        let bars = StateTimelineMath.bars(response(
            states: [StateSegment(state: "online", from: "2026-08-18T14:00:00", to: "2026-08-18T16:00:00")],
            drives: [TimeSegment(from: "2026-08-18T14:30:00", to: "2026-08-18T15:00:00")],
            charges: [TimeSegment(from: "2026-08-18T15:10:00", to: "2026-08-18T15:40:00")]))
        #expect(bars.map(\.kind) == [.online, .driving, .charging])
    }

    @Test func 빈_응답은_빈_배열을_낸다() {
        #expect(StateTimelineMath.bars(response()).isEmpty)
    }

    @Test func 읽을_수_없는_범위는_빈_배열을_낸다() {
        let broken = StateTimelineResponse(hours: 24, from: "어제", to: "오늘",
                                           states: [], drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }

    @Test func 뒤집힌_범위는_빈_배열을_낸다() {
        let broken = StateTimelineResponse(hours: 24,
                                           from: "2026-08-19T13:00:00",
                                           to: "2026-08-18T13:00:00",
                                           states: [StateSegment(state: "online",
                                                                 from: "2026-08-18T14:00:00",
                                                                 to: "2026-08-18T15:00:00")],
                                           drives: [], charges: [])
        #expect(StateTimelineMath.bars(broken).isEmpty)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineTests 2>&1 | grep -E "error:|TEST FAILED|TEST SUCCEEDED" | tail -10`

Expected: 컴파일 실패 — `StateTimelineResponse`에 `hours` 인자가 없다

- [ ] **Step 3: 모델과 계산을 고친다**

`WooriHaru/Models/StateTimelineModels.swift`에서 세 곳을 바꾼다.

먼저 응답의 `days`를 `hours`로:

```swift
/// 최근 몇 시간의 차량 상태 — **세 배열이 겹친 채로 온다.**
///
/// 서버가 하나의 띠로 합치지 않는 이유는 TeslaMate `states`에 `driving`·`charging`이 없어서다
/// (`CREATE TYPE states_status AS ENUM ('online', 'offline', 'asleep')`). 합치려면 구간 산술이
/// 필요한데, 세 겹을 그대로 받아 화면이 덧칠하면 그 로직이 사라진다.
struct StateTimelineResponse: Codable, Equatable {
    let hours: Int
    /// KST 벽시계. **자정에 맞춰지지 않는다** — `to`가 요청 시각이고 `from`은 그보다 `hours`시간 앞이다.
    let from: String
    let to: String
    let states: [StateSegment]
    let drives: [TimeSegment]
    let charges: [TimeSegment]
}
```

다음으로 `TimelineBar`에서 `dayIndex`를 뺀다:

```swift
/// 한 막대 = 범위 안의 한 조각. `start`·`end`는 **범위 전체에 대한 비율**(0.0 = `from`, 1.0 = `to`)이다.
///
/// **4단계의 `dayIndex`가 사라졌다.** 7일을 하루 한 행씩 그릴 때는 막대가 어느 행에 속하는지
/// 알아야 했지만, 24시간을 한 줄로 그리면 행이 하나뿐이라 그 값이 가리킬 곳이 없다.
struct TimelineBar: Equatable {
    let start: Double
    let end: Double
    let kind: TimelineKind
}
```

마지막으로 `StateTimelineMath` 전체를 아래로 바꾼다. `secondsPerDay`와 `split`이 사라지고 `clip` 하나가 남는다:

```swift
/// 화면이 하는 유일한 계산이다.
///
/// **4단계에서 하던 세 가지 중 하나가 사라졌다** — 자정을 넘는 구간을 날짜 행으로 쪼개는 일이다.
/// 행이 하나뿐이면 쪼갤 곳이 없다. 남은 것은 범위 밖 자르기와 정렬 둘이다.
enum StateTimelineMath {
    static func bars(_ response: StateTimelineResponse) -> [TimelineBar] {
        guard let windowStart = VehicleFormat.parseKST(response.from),
              let windowEnd = VehicleFormat.parseKST(response.to) else { return [] }
        let span = windowEnd.timeIntervalSince(windowStart)
        guard span > 0 else { return [] }

        var bars: [TimelineBar] = []
        for segment in response.states {
            guard let kind = TimelineKind.state(segment.state) else { continue }
            if let bar = clip(segment.from, segment.to, kind: kind, from: windowStart, span: span) {
                bars.append(bar)
            }
        }
        for segment in response.drives {
            if let bar = clip(segment.from, segment.to, kind: .driving, from: windowStart, span: span) {
                bars.append(bar)
            }
        }
        for segment in response.charges {
            if let bar = clip(segment.from, segment.to, kind: .charging, from: windowStart, span: span) {
                bars.append(bar)
            }
        }

        // **정렬 기준을 둘 다 준다.** Swift의 `sorted`는 안정 정렬을 보장하지 않아
        // 레이어만으로 비교하면 같은 레이어 안의 순서가 실행마다 달라질 수 있다.
        return bars.sorted {
            if $0.kind.layer != $1.kind.layer { return $0.kind.layer < $1.kind.layer }
            return $0.start < $1.start
        }
    }

    /// 구간 하나를 범위 안의 비율로 바꾼다. **범위 밖은 자른다** — 서버가 이미 잘라 주지만,
    /// 계약이 깨져도 화면이 무너지지 않게 한 번 더 막는다.
    private static func clip(_ rawFrom: String, _ rawTo: String, kind: TimelineKind,
                             from windowStart: Date, span: TimeInterval) -> TimelineBar? {
        guard let segmentStart = VehicleFormat.parseKST(rawFrom),
              let segmentEnd = VehicleFormat.parseKST(rawTo) else { return nil }
        let windowEnd = windowStart.addingTimeInterval(span)
        let start = max(segmentStart, windowStart)
        let end = min(segmentEnd, windowEnd)
        guard end > start else { return nil }
        return TimelineBar(start: start.timeIntervalSince(windowStart) / span,
                           end: end.timeIntervalSince(windowStart) / span,
                           kind: kind)
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineTests 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -10`

Expected: PASS (9 tests). 다른 스위트는 아직 컴파일되지 않아도 된다 — Task 2·3이 고친다.

- [ ] **Step 5: 커밋한다**

```bash
git add WooriHaru/Models/StateTimelineModels.swift WooriHaruTests/StateTimelineTests.swift
git commit -m "feat: 타임라인 좌표를 24시간 한 줄 비율로 바꾼다"
```

---

## Task 2: 서비스와 뷰모델을 시간 단위로

**Files:**
- Modify: `WooriHaru/Services/VehicleService.swift`
- Modify: `WooriHaru/ViewModels/StateTimelineViewModel.swift`
- Test: `WooriHaruTests/StateTimelineViewModelTests.swift`

**Interfaces:**
- Consumes: `StateTimelineResponse`(`hours` 필드), `TimelineBar`(`dayIndex` 없음), `StateTimelineMath.bars` (Task 1)
- Produces:
  - `VehicleService.fetchStateTimeline(hours: Int = 24) async throws -> StateTimelineResponse` — 질의 키는 `"hours"`
  - `StateTimelineViewModel.hours: Int`(static, 값 24) — **`days`는 사라진다**
  - 나머지(`timeline`·`bars`·`isLoading`·`errorMessage`·`hasSegments`·`load()`·`reload()`·404 처리)는 그대로다

- [ ] **Step 1: 테스트를 고친다**

`WooriHaruTests/StateTimelineViewModelTests.swift`에서 픽스처와 질의 단언을 고친다. 파일 안의 `StateTimelineResponse(days: 7, from: "2026-08-13T00:00:00", to: "2026-08-19T12:00:00", …)` 형태를 전부 아래로 바꾼다:

```swift
        StateTimelineResponse(hours: 24,
                              from: "2026-08-18T13:00:00",
                              to: "2026-08-19T13:00:00",
                              states: states, drives: [], charges: [])
```

그리고 `days`를 질의로 보내는지 보던 테스트를 이렇게 바꾼다:

```swift
    @Test func hours를_질의로_보낸다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/state-timeline", result: DataResponse(data: Self.sample))
        let viewModel = makeViewModel(mock)

        await viewModel.load()

        let call = mock.getCalls.first { $0.path == "/tesla/state-timeline" }
        #expect(call?.query["hours"] == String(StateTimelineViewModel.hours))
        #expect(call?.query["days"] == nil)
    }
```

`generation` 테스트가 쓰는 `fresh` 응답도 같은 범위(`2026-08-18T13:00:00` ~ `2026-08-19T13:00:00`)로 맞춘다. 그 테스트는 **막대 수로 새 값이 이겼는지 판정**하므로, `fresh`의 구간 둘이 같은 범위 안에 들고 `sample`은 하나여야 단언이 성립한다 — 범위를 바꿀 때 이 관계를 깨지 않는다.

`WooriHaruTests/VehicleServiceTests.swift`에는 **타임라인 질의 테스트가 없다**(확인함). 여기서 새로 만들지 않는다 — 위 뷰모델 테스트가 이미 질의 키를 단언한다.

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineViewModelTests 2>&1 | grep -E "error:|TEST FAILED|TEST SUCCEEDED" | tail -10`

Expected: 컴파일 실패 — `StateTimelineViewModel`에 `hours`가 없다

- [ ] **Step 3: 서비스를 고친다**

`WooriHaru/Services/VehicleService.swift`의 `fetchStateTimeline`을 바꾼다:

```swift
    /// 최근 `hours`시간의 상태·주행·충전 구간. **세 배열이 겹친 채로 온다** — 서버가 합치지 않는다.
    /// 범위는 **자정에 맞춰지지 않는다** — `to`가 요청 시각이라 화면의 오른쪽 끝이 「지금」이 된다.
    func fetchStateTimeline(hours: Int = 24) async throws -> StateTimelineResponse {
        let response: DataResponse<StateTimelineResponse> =
            try await api.get("/tesla/state-timeline", query: ["hours": String(hours)])
        guard let timeline = response.data else {
            throw APIError.serverError(statusCode: 200, message: "상태 타임라인 응답이 비어 있습니다")
        }
        return timeline
    }
```

- [ ] **Step 4: 뷰모델을 고친다**

`WooriHaru/ViewModels/StateTimelineViewModel.swift`에서 상수와 호출 한 줄만 바꾼다. **나머지는 손대지 않는다** — 캐시 없음, generation 토큰, 404 조용히 넘기기는 4단계 결정 그대로다.

```swift
    /// 몇 시간을 그릴지는 화면이 정한다. 서버는 1~168을 받는다.
    static let hours = 24
```

```swift
            let loaded = try await service.fetchStateTimeline(hours: Self.hours)
```

클래스 독 코멘트의 「최근 7일」도 「최근 24시간」으로 바꾼다.

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/StateTimelineViewModelTests 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -10`

Expected: PASS

- [ ] **Step 6: 커밋한다**

```bash
git add WooriHaru/Services/VehicleService.swift WooriHaru/ViewModels/StateTimelineViewModel.swift WooriHaruTests/StateTimelineViewModelTests.swift
git commit -m "feat: 타임라인을 24시간 범위로 받아 온다"
```

---

## Task 3: 띠를 한 줄로 그린다

**Files:**
- Modify: `WooriHaru/Views/Vehicle/StateTimelineChart.swift` (전면 개편)
- Modify: `WooriHaru/Views/Vehicle/VehicleHealthTab.swift` (`timelineSection` 배선)

**Interfaces:**
- Consumes: `TimelineBar`(`start`·`end`·`kind`), `TimelineKind`, `StateTimelineResponse`(`hours`·`from`·`to`) (Task 1), `VehicleFormat.parseKST` (기존), `GlassCard` (기존)
- Produces: `StateTimelineChart(bars: [TimelineBar], hours: Int, from: Date, to: Date)`

- [ ] **Step 1: 차트를 새로 쓴다**

단위 테스트가 없다 — 좌표 계산은 Task 1이 덮었고 여기는 그리기만 한다. `WooriHaru/Views/Vehicle/StateTimelineChart.swift`를 아래로 **통째로 바꾼다.**

```swift
import SwiftUI

/// 최근 몇 시간의 상태를 **한 줄**로. **오른쪽 끝이 「지금」이다** — 서버가 `to`를 요청 시각으로
/// 주고 자정에 맞추지 않는다.
///
/// **4단계의 7행 격자를 버렸다.** 한 행이 화면 폭의 1/7이면 밤새 충전 한 건이 손톱만 하게
/// 찍힌다. 같은 폭에 24시간만 놓으면 실측 22개 구간이 들어가 하나가 7배 넓어진다.
///
/// 눈금은 **절대 시각**이다. 이 그림이 답하려는 질문이 「밤새 충전이 **언제** 걸렸나」이므로
/// 「-12시간」 같은 상대 표기로는 읽을 수 없다.
struct StateTimelineChart: View {
    private let bars: [TimelineBar]
    private let hours: Int
    private let from: Date
    private let to: Date

    @Environment(\.displayScale) private var displayScale

    private let barHeight: CGFloat = 24
    private let tickLabelWidth: CGFloat = 30

    init(bars: [TimelineBar], hours: Int, from: Date, to: Date) {
        // 입력이 이미 레이어 순으로 정렬돼 있어 그리는 순서가 곧 덧칠 순서다. 다시 정렬하지 않는다.
        self.bars = bars
        self.hours = hours
        self.from = from
        self.to = to
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("최근 \(hours)시간")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)

                strip
                axis
                legend
            }
        }
    }

    private var strip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.slate100)
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Rectangle()
                        .fill(Self.color(bar.kind))
                        // **최소 폭을 두지 않는다.** 바닥값을 깔면 짧은 구간이 실제보다 길어
                        // 보이는 띠가 된다 — 「한쪽만으로 그린 막대는 거짓말이다」와 같은 규칙이다.
                        // 화면의 물리적 하한인 1픽셀만 둔다.
                        .frame(width: max(1 / displayScale, width * (bar.end - bar.start)))
                        .offset(x: width * bar.start)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: barHeight)
        // 구간을 하나씩 읽게 만들지 않는다 — 띠 전체가 한 정거장이다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stripLabel)
    }

    /// 4시간 간격의 정각과, 오른쪽 끝의 「지금」.
    private var axis: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    Text(tick.label)
                        .frame(width: tickLabelWidth)
                        .offset(x: width * tick.fraction - tickLabelWidth / 2)
                }
                Text("지금")
                    .fontWeight(.bold)
                    .frame(width: tickLabelWidth, alignment: .trailing)
                    .offset(x: width - tickLabelWidth)
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(Color.slate400)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    /// **`asleep`을 빼지 않는다.** 최근 표본에 0건이어도 2026년에 월 1~4건씩 있었다.
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

    private var span: TimeInterval { to.timeIntervalSince(from) }

    /// 범위 안에 드는 4시간 정각들. 범위가 자정에 맞춰져 있지 않으므로 첫 눈금을
    /// **`from` 다음의 4시간 정각**에서 시작한다.
    private var ticks: [(fraction: Double, label: String)] {
        guard span > 0 else { return [] }
        var result: [(Double, String)] = []
        var cursor = Self.firstTick(after: from)
        while cursor < to {
            result.append((cursor.timeIntervalSince(from) / span,
                           Self.hourFormatter.string(from: cursor)))
            cursor = cursor.addingTimeInterval(4 * 3600)
        }
        // 오른쪽 끝의 「지금」과 겹치는 마지막 눈금은 뺀다 — 글자가 포개진다.
        return result.filter { $0.0 < 0.93 }
    }

    private static func firstTick(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kst
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let hourStart = calendar.date(from: parts), let hour = parts.hour else { return date }
        // 지금 시(hour)의 정각에서 다음 4의 배수까지 나아간다. 1~4시간이 더해진다.
        return hourStart.addingTimeInterval(Double(4 - (hour % 4)) * 3600)
    }

    /// 띠 전체를 한 문장으로.
    ///
    /// **오프라인·잠자는 중도 온라인과 똑같이 시간으로 읽는다.** 실측상 대부분이 오프라인이라
    /// 그것을 빼고 읽으면 화면은 꽉 찬 회색 띠를 그리는데 소리는 아무것도 없었다고 말한다.
    /// 「기록 없음」은 막대가 정말 하나도 없을 때만 쓴다.
    private var stripLabel: String {
        var parts = ["최근 \(hours)시간"]

        for (kind, label) in Self.spokenStates {
            let ratio = bars.filter { $0.kind == kind }.reduce(0.0) { $0 + ($1.end - $1.start) }
            let hoursSpent = ratio * Double(hours)
            // 0.05시간(3분) 미만은 말하지 않는다 — 「0.0시간」은 있으나 마나다.
            if hoursSpent >= 0.05 { parts.append("\(label) \(String(format: "%.1f", hoursSpent))시간") }
        }

        let drives = bars.filter { $0.kind == .driving }.count
        let charges = bars.filter { $0.kind == .charging }.count
        if drives > 0 { parts.append("주행 \(drives)회") }
        if charges > 0 { parts.append("충전 \(charges)회") }

        if parts.count == 1 {
            // 3분 미만 조각만 있는 것은 「기록이 없음」이 아니라 「말할 만큼 길지 않음」이다.
            parts.append(bars.isEmpty ? "기록 없음" : "짧은 구간뿐")
        }
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

    /// VoiceOver가 시간으로 읽는 상태 셋. 범례와 같은 순서다 — 눈으로 보는 순서와
    /// 귀로 듣는 순서가 갈리면 같은 그림을 두 가지로 설명하는 셈이 된다.
    private static let spokenStates: [(kind: TimelineKind, label: String)] = [
        (.online, "온라인"), (.offline, "오프라인"), (.asleep, "잠자는 중")
    ]

    private static let legendItems: [(kind: TimelineKind, label: String)] = [
        (.online, "온라인"), (.offline, "오프라인"), (.asleep, "잠자는 중"),
        (.driving, "주행"), (.charging, "충전")
    ]

    private static let kst = TimeZone(identifier: "Asia/Seoul") ?? .current

    /// **KST로 찍는다.** `from`·`to`는 `VehicleFormat.parseKST`가 KST 벽시계로 읽은 값이라,
    /// 기기 시간대로 찍으면 시차만큼 어긋난다.
    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = kst
        formatter.dateFormat = "H시"
        return formatter
    }()
}

#Preview("타임라인") {
    let response = StateTimelineResponse(
        hours: 24, from: "2026-08-18T13:00:00", to: "2026-08-19T13:00:00",
        states: [
            StateSegment(state: "offline", from: "2026-08-18T13:00:00", to: "2026-08-18T18:30:00"),
            StateSegment(state: "online", from: "2026-08-18T18:30:00", to: "2026-08-18T19:40:00"),
            StateSegment(state: "asleep", from: "2026-08-18T19:40:00", to: "2026-08-19T06:00:00"),
            StateSegment(state: "offline", from: "2026-08-19T06:00:00", to: "2026-08-19T09:00:00"),
            StateSegment(state: "online", from: "2026-08-19T09:00:00", to: "2026-08-19T13:00:00")
        ],
        drives: [
            TimeSegment(from: "2026-08-18T18:40:00", to: "2026-08-18T19:10:00"),
            TimeSegment(from: "2026-08-19T09:20:00", to: "2026-08-19T09:50:00")
        ],
        charges: [TimeSegment(from: "2026-08-18T22:10:00", to: "2026-08-19T02:40:00")])

    return StateTimelineChart(bars: StateTimelineMath.bars(response),
                              hours: response.hours,
                              from: VehicleFormat.parseKST(response.from) ?? .now,
                              to: VehicleFormat.parseKST(response.to) ?? .now)
        .padding(16)
        .background(Color.slate50)
}
```

- [ ] **Step 2: 건강 탭 배선을 고친다**

`WooriHaru/Views/Vehicle/VehicleHealthTab.swift`의 `timelineSection`에서 **`to`도 파싱하고** 차트 인자와 빈 문구를 바꾼다. 갈래 구조(값 → 로딩 → 오류 → 아무것도 안 그림)와 배너 위치는 **그대로 둔다.**

```swift
        if let timeline = timelineViewModel.timeline,
           let from = VehicleFormat.parseKST(timeline.from),
           let to = VehicleFormat.parseKST(timeline.to) {
```

```swift
            if timelineViewModel.hasSegments {
                StateTimelineChart(bars: timelineViewModel.bars,
                                   hours: timeline.hours,
                                   from: from, to: to)
            } else {
                GlassCard {
                    Text("최근 \(timeline.hours)시간 기록이 없어요")
```

`// MARK: - 최근 7일`을 `// MARK: - 최근 24시간`으로 바꾸고, `timelineSection`의 독 코멘트에서 「`from`을 못 읽으면 행을 셀 수 없어」를 「`from`·`to`를 못 읽으면 비율을 낼 수 없어」로 고친다.

- [ ] **Step 3: 전체 테스트를 돌린다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|warning:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: 전 스위트 PASS. 손댄 파일에 경고가 있으면 결함이다(`WooriHaruTests/DietFakes.swift`·`DietDayTests.swift`의 기존 경고는 제외).

- [ ] **Step 4: 커밋한다**

```bash
git add WooriHaru/Views/Vehicle/StateTimelineChart.swift WooriHaru/Views/Vehicle/VehicleHealthTab.swift
git commit -m "feat: 최근 24시간을 한 줄 띠로 그린다"
```

---

## Task 4: 평균 주행거리 타일

**Files:**
- Modify: `WooriHaru/Models/DriveInsightsModels.swift`
- Modify: `WooriHaru/Models/VehicleModels.swift` (`VehicleMath` 확장 안)
- Modify: `WooriHaru/ViewModels/VehicleDriveViewModel.swift`
- Modify: `WooriHaru/Views/Vehicle/DriveStatsCard.swift`
- Test: `WooriHaruTests/VehicleMathTests.swift`, `WooriHaruTests/VehicleDriveTests.swift`, `WooriHaruTests/VehicleServiceTests.swift`

**Interfaces:**
- Consumes: `DriveInsightsResponse` (기존), `VehicleFormat.distance(_:)`·`VehicleFormat.speed(_:)` (기존)
- Produces:
  - `DriveInsightsResponse`에 `let totalDistanceKm: Decimal?`, `let recordedMonths: Int?` — **`monthDistanceKm`·`yearDistanceKm`를 대체한다**
  - `VehicleMath.avgMonthlyDistanceKm(totalKm: Decimal?, months: Int?) -> Decimal?`
  - `VehicleMath.avgYearlyDistanceKm(totalKm: Decimal?, months: Int?) -> Decimal?`
  - `VehicleDriveViewModel.avgMonthlyKm: Decimal?`, `.avgYearlyKm: Decimal?`
  - `DriveStatsCard(maxSpeedKmh: Int?, avgMonthlyKm: Decimal?, avgYearlyKm: Decimal?)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleMathTests.swift`의 스위트 끝에 붙인다.

```swift
    /// 실측(2026-08-19) 그대로다 — 총 107,257.8km를 기록이 있는 60개월로 나눈다.
    @Test func 월_평균은_기록이_있는_달_수로_나눈다() {
        let monthly = VehicleMath.avgMonthlyDistanceKm(totalKm: Decimal(string: "107257.8"), months: 60)
        #expect(VehicleFormat.distance(monthly) == "1,788km")
    }

    @Test func 연_평균은_월_평균의_열두_배다() {
        let total = Decimal(string: "107257.8")
        let monthly = VehicleMath.avgMonthlyDistanceKm(totalKm: total, months: 60)
        let yearly = VehicleMath.avgYearlyDistanceKm(totalKm: total, months: 60)
        #expect(yearly == monthly.map { $0 * 12 })
        #expect(VehicleFormat.distance(yearly) == "21,452km")
    }

    /// **서버는 주행이 없으면 `recordedMonths: 0`을 그대로 낸다**(1로 보정하지 않는다).
    /// 0으로 나누면 화면이 무너지므로 앱이 나누기 전에 막는다.
    @Test func 분모가_0이면_평균이_없다() {
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: Decimal(string: "107257.8"), months: 0) == nil)
        #expect(VehicleMath.avgYearlyDistanceKm(totalKm: Decimal(string: "107257.8"), months: 0) == nil)
    }

    @Test func 값이_없으면_평균도_없다() {
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: nil, months: 60) == nil)
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: Decimal(string: "100"), months: nil) == nil)
        #expect(VehicleMath.avgYearlyDistanceKm(totalKm: nil, months: nil) == nil)
    }

    @Test func 총거리가_0이면_평균도_0이다() {
        // 0은 「기록이 없다」가 아니라 「안 탔다」다 — nil로 뭉개지 않는다.
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: 0, months: 12) == 0)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VehicleMathTests 2>&1 | grep -E "error:|TEST FAILED|TEST SUCCEEDED" | tail -10`

Expected: 컴파일 실패 — `type 'VehicleMath' has no member 'avgMonthlyDistanceKm'`

- [ ] **Step 3: 응답 필드를 바꾼다**

`WooriHaru/Models/DriveInsightsModels.swift`의 `DriveInsightsResponse`에서 `monthDistanceKm`·`yearDistanceKm` 둘과 그 주석을 아래로 **교체한다**(`maxSpeedKmh`와 그 주석은 그대로 둔다):

```swift
    /// 평균의 **분자와 분모**다 — 평균 자체가 아니다.
    ///
    /// 서버가 나눠 주지 않는 이유는 이 저장소가 단가·전비를 다루는 방식과 같다. 서버가 평균을
    /// 내 버리면 분모의 정의(「기록이 있는 달 수」)가 응답에서 사라져 화면이 그 뜻을 설명할 수 없다.
    ///
    /// **`recordedMonths`는 0으로 올 수 있다**(주행이 하나도 없을 때). 서버가 1로 보정하지
    /// 않으므로 나누기 전에 앱이 막는다 — `VehicleMath.avgMonthlyDistanceKm`이 그 자리다.
    ///
    /// **옵셔널인 이유는 `maxSpeedKmh`와 같다** — 서버가 개정 전 필드를 내는 동안 앱이 먼저
    /// 나가도 주행 탭 응답 전체가 디코딩 실패로 무너지지 않아야 한다.
    let totalDistanceKm: Decimal?
    let recordedMonths: Int?
```

- [ ] **Step 4: 평균 계산을 더한다**

`WooriHaru/Models/VehicleModels.swift`의 `VehicleMath` 확장 안, `kmPerKwh` 근처에 붙인다:

```swift
    /// 월 평균 주행거리 = 총거리 / 기록이 있는 달 수.
    ///
    /// **분모가 0이거나 없으면 nil이다.** 서버는 주행이 하나도 없을 때 `recordedMonths: 0`을
    /// 그대로 낸다 — 그 자리를 서버가 정해 버리면 화면이 따라야 하므로, 막는 것은 여기다.
    ///
    /// 총거리가 0인 것은 막지 않는다 — 「안 탔다」는 사실이고 평균 0km가 옳다.
    static func avgMonthlyDistanceKm(totalKm: Decimal?, months: Int?) -> Decimal? {
        guard let totalKm, let months, months > 0 else { return nil }
        return totalKm / Decimal(months)
    }

    /// 연 평균 = 월 평균 × 12. **월 평균을 거쳐 낸다** — 두 값이 갈리면
    /// 화면의 두 칸이 서로 어긋난 이야기를 한다.
    static func avgYearlyDistanceKm(totalKm: Decimal?, months: Int?) -> Decimal? {
        guard let monthly = avgMonthlyDistanceKm(totalKm: totalKm, months: months) else { return nil }
        return monthly * 12
    }
```

- [ ] **Step 5: 뷰모델이 값을 낸다**

`WooriHaru/ViewModels/VehicleDriveViewModel.swift`의 「파생 값」 절에서 `showsStats`를 고치고 평균 둘을 더한다:

```swift
    /// 셋 다 없으면 서버가 아직 이 필드를 내지 않는 것이다. 하나라도 있으면 그린다 —
    /// 「총거리 0km」는 값이 없는 것이 아니라 **안 탔다는 사실**이다.
    var showsStats: Bool {
        guard let insights else { return false }
        return insights.maxSpeedKmh != nil
            || insights.totalDistanceKm != nil
            || insights.recordedMonths != nil
    }

    /// **뷰가 아니라 여기서 나눈다.** 뷰에서 다시 계산하면 테스트하는 값과 화면에 나오는 값이
    /// 서로 다른 코드가 된다 — 3단계에서 같은 함정을 두 번 밟았다.
    var avgMonthlyKm: Decimal? {
        VehicleMath.avgMonthlyDistanceKm(totalKm: insights?.totalDistanceKm,
                                         months: insights?.recordedMonths)
    }

    var avgYearlyKm: Decimal? {
        VehicleMath.avgYearlyDistanceKm(totalKm: insights?.totalDistanceKm,
                                        months: insights?.recordedMonths)
    }
```

- [ ] **Step 6: 카드를 고친다**

`WooriHaru/Views/Vehicle/DriveStatsCard.swift`에서 독 코멘트·프로퍼티·타일 셋을 바꾼다:

```swift
/// 주행 통계 타일 셋 — 역대 최고 속도 / 월 평균 / 연 평균.
///
/// **다섯째 차트를 더하지 않는다.** 이 탭에는 이미 카드가 넷 있고, 여기 들어갈 값 셋은
/// 추세가 아니라 지금의 숫자다.
///
/// **평균으로 바꾼 이유:** 「이번 달·올해」는 시점에 끌려다닌다 — 매달 1일에 0으로 떨어지고
/// 12월에 가장 커진다. 그 숫자로는 「내가 얼마나 타는 사람인가」를 알 수 없다.
///
/// **세 칸 모두 기간 칩을 따르지 않는다** — 역대 최고는 전 기간이고, 평균 둘은 전 기간을
/// 달 수로 나눈 값이다. 그래서 이 카드는 기간 분기 위에 그린다.
///
/// **뷰모델이 낸 값을 그대로 받는다.** 여기서 다시 나누면 화면에 나오는 값과 테스트하는 값이
/// 서로 다른 코드가 된다.
struct DriveStatsCard: View {
    let maxSpeedKmh: Int?
    let avgMonthlyKm: Decimal?
    let avgYearlyKm: Decimal?

    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                tile(VehicleFormat.speed(maxSpeedKmh), "역대 최고")
                tile(VehicleFormat.distance(avgMonthlyKm), "월 평균")
                tile(VehicleFormat.distance(avgYearlyKm), "연 평균")
            }
        }
    }
```

`#Preview`의 인자 이름과 값도 함께 고친다:

```swift
#Preview("주행 통계") {
    VStack(spacing: 12) {
        DriveStatsCard(maxSpeedKmh: 138,
                       avgMonthlyKm: Decimal(string: "1787.63"),
                       avgYearlyKm: Decimal(string: "21451.56"))
        DriveStatsCard(maxSpeedKmh: nil, avgMonthlyKm: nil, avgYearlyKm: nil)
    }
    .padding(16)
    .background(Color.slate50)
}
```

- [ ] **Step 7: 주행 탭 호출부를 고친다**

`WooriHaru/Views/Vehicle/VehicleDriveTab.swift`의 `DriveStatsCard` 호출을 바꾼다:

```swift
                if viewModel.showsStats {
                    DriveStatsCard(maxSpeedKmh: viewModel.insights?.maxSpeedKmh,
                                   avgMonthlyKm: viewModel.avgMonthlyKm,
                                   avgYearlyKm: viewModel.avgYearlyKm)
                }
```

- [ ] **Step 8: 기존 테스트의 생성부와 단언을 고친다**

`DriveInsightsResponse(` 생성부는 **6곳**이다(`VehicleDriveTests.swift` 4곳, `VehicleServiceTests.swift` 2곳). 찾는다:

```bash
grep -rn "DriveInsightsResponse(" WooriHaruTests/
```

각 생성부의 `maxSpeedKmh:` 뒤 두 인자를 아래로 바꾼다(값은 실측 그대로):

```swift
                              totalDistanceKm: Decimal(string: "107257.8"),
                              recordedMonths: 60
```

그리고 `WooriHaruTests/VehicleDriveTests.swift`의 `showsStats` 테스트 **4건**이 옛 필드 이름을 쓰고 있다. 필드만 갈아 끼우되 각 테스트가 노리는 상태는 그대로 지킨다:

- 셋 다 nil → `maxSpeedKmh: nil, totalDistanceKm: nil, recordedMonths: nil`
- 하나라도 있음 → `maxSpeedKmh: 138, totalDistanceKm: nil, recordedMonths: nil`
- **0도 값이다** → `maxSpeedKmh: nil, totalDistanceKm: 0, recordedMonths: 0`
- 아직 못 받음 → `insights == nil`인 뷰모델

세 번째 테스트의 이름 `이번_달_올해가_0이어도_카드를_낸다`를 `총거리가_0이어도_카드를_낸다`로 바꾼다.

- [ ] **Step 9: 전체 테스트를 돌린다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|warning:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: 전 스위트 PASS

- [ ] **Step 10: 커밋한다**

```bash
git add WooriHaru/Models/DriveInsightsModels.swift WooriHaru/Models/VehicleModels.swift WooriHaru/ViewModels/VehicleDriveViewModel.swift WooriHaru/Views/Vehicle/DriveStatsCard.swift WooriHaru/Views/Vehicle/VehicleDriveTab.swift WooriHaruTests/VehicleMathTests.swift WooriHaruTests/VehicleDriveTests.swift WooriHaruTests/VehicleServiceTests.swift
git commit -m "feat: 주행 타일을 월·연 평균으로 바꾼다"
```

---

## Task 5: 설계 문서를 구현에 맞춘다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-19-vehicle-dark-theme-design.md`

- [ ] **Step 1: A단계에 「구현 완료」를 넣는다**

`# A단계 — 24시간 타임라인과 평균 타일` 바로 아래, 그 절의 첫 문단(「다크와 무관하고…」) 다음에 넣는다. 실제로 갈라진 것이 없으면 그렇게 적고, 있으면 무엇이 왜 갈라졌는지 한 줄씩 적는다.

```markdown
> **A단계 구현 완료 (2026-08-19).** 설계와 갈라진 곳: <없으면 「없다」라고 적고, 있으면 항목마다 무엇을·왜 한 줄씩>
```

- [ ] **Step 2: 남은 것을 적는다**

문서 맨 끝에 붙인다.

```markdown
## A단계가 남긴 것

- **서버는 아직 개정 전 계약으로 돈다.** `hours`를 모르는 서버는 `days` 기본값으로 7일치를 주는데, 앱은 그것을 24시간 범위로 알고 비율을 낸다 — 띠가 7배 넓은 시간을 24시간인 척 그린다. `totalDistanceKm`·`recordedMonths`가 없으면 타일 카드는 감춰진다(`showsStats`). **서버 개정 배포 전까지는 타임라인 값을 믿지 않는다.**
- B단계(다크 테마)는 이 브랜치가 머지된 뒤 별도 계획으로 간다.
```

- [ ] **Step 3: 커밋한다**

```bash
git add docs/superpowers/specs/2026-08-19-vehicle-dark-theme-design.md
git commit -m "docs: A단계 구현 완료를 적는다"
```

---

## 자기 점검

**1. 스펙 커버리지 (A단계 부분만)**

| 스펙 요구 | 태스크 |
|---|---|
| 한 줄, 높이 24pt | Task 3 |
| 오른쪽 끝이 「지금」 | Task 1(범위 절단) · Task 3(축) |
| 절대 시각 눈금, 4시간 간격 | Task 3 |
| 겹침 순서 상태→주행→충전 | Task 1(`layer` 정렬) · Task 3(배열 순 그리기) |
| 최소 폭 없음, 1픽셀 하한 | Task 3 |
| 자정 분할 삭제, `dayIndex` 제거 | Task 1 |
| 자정 분할 테스트 삭제 | Task 1 Step 1 |
| VoiceOver 한 정거장, 상태 셋 다 읽기 | Task 3 |
| `days` → `hours` (응답·서비스·뷰모델) | Task 1 · Task 2 |
| `totalDistanceKm`·`recordedMonths` | Task 4 |
| 앱이 나눈다, 분모 0 방어 | Task 4 |
| 「월 평균」·「연 평균」 라벨 | Task 4 |
| 옵셔널 유지, 셋 다 nil이면 카드 감춤 | Task 4 |
| 기간 분기 위에 그림 | Task 4 Step 7(기존 위치 유지) |
| 경계·오류 표 | Task 3(타임라인) · Task 4(타일) |
| 테스트 목록 | Task 1 · 2 · 4 |

**2. 플레이스홀더 스캔** — 「TBD」·「적절히 처리」·코드 없는 지시 없음. 모든 코드 단계에 실제 코드가 있다.

**3. 타입 일관성**

- `StateTimelineResponse.hours` — Task 1 정의, Task 2·3에서 사용
- `TimelineBar(start:end:kind:)` — Task 1 정의, Task 3에서 `bar.start`/`bar.end`/`bar.kind`만 읽는다(`dayIndex` 없음)
- `StateTimelineViewModel.hours`(static) — Task 2 정의, 같은 태스크 테스트에서 사용
- `StateTimelineChart(bars:hours:from:to:)` — Task 3 정의, 같은 태스크의 건강 탭 호출과 인자 이름 일치
- `VehicleMath.avgMonthlyDistanceKm(totalKm:months:)` / `avgYearlyDistanceKm(totalKm:months:)` — Task 4 정의, 같은 태스크의 뷰모델·테스트에서 사용
- `DriveStatsCard(maxSpeedKmh:avgMonthlyKm:avgYearlyKm:)` — Task 4 정의·호출 일치
- `VehicleDriveViewModel.avgMonthlyKm`/`.avgYearlyKm` — Task 4 정의, 같은 태스크의 탭에서 사용

**4. 알려진 위험**

- **Task 1이 끝난 시점에 다른 스위트는 컴파일되지 않는다.** `dayIndex`와 `days`를 쓰던 코드가 남아 있기 때문이다. Task 1의 검증을 단일 스위트로 한정한 이유이고, 전체가 초록으로 돌아오는 것은 Task 3 이후다.
- **Task 4는 기존 테스트 10곳을 깨뜨린 뒤 고친다**(생성부 6 + `showsStats` 4). Step 8을 건너뛰면 전체 빌드가 실패한다.
- **서버가 개정 전이다.** 앱만으로는 타임라인 값이 옳은지 확인할 수 없다 — Task 5의 「남은 것」이 그 빈틈을 명시한다.
