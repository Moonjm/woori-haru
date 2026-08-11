# 식단 날짜 이동 — 하루 스와이프와 제스처 경합 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 식단 홈에서 「오늘」로 돌아올 길을 되찾고, 스트립 아래 좌우 스와이프로 하루씩 옮기며, 그 스와이프가 버튼 탭과 경합하지 않게 한다.

**Architecture:** 세 겹이다. **① 「오늘」 버튼 조건**을 선택 날짜가 아니라 오늘 기준으로 판단하는 새 속성으로 분리한다. **② 하루 이동(`stepDay`)**을 뷰모델에 두고, 화면은 즉시 옮기되 서버 조회는 스와이프가 멈춘 뒤 한 번만 낸다. **③ 화면의 제스처**를 고친다 — 버튼은 제 경계 안에서 움직인 손가락도 눌린 것으로 치므로, 스트립 날짜와 끼니 카드를 탭 제스처 기반으로 바꾼다.

**Tech Stack:** Swift / SwiftUI, Swift Testing, `@MainActor @Observable` 뷰모델

**설계 문서:** `docs/superpowers/specs/2026-08-11-diet-date-strip-swipe-design.md`

## Global Constraints

- **`isViewingSelectedWeek`를 지우거나 의미를 바꾸지 않는다.** 이름이 계산 내용과 맞고, `DietDayTests`의 네 곳이 「기준일이 그 주로 맞춰졌다」를 확인하는 데 쓴다. 틀린 것은 속성이 아니라 그것을 버튼 조건으로 쓴 것이다.
- **기존 테스트를 고쳐서 통과시키지 않는다.** 하나라도 빨개지면 구현이 틀린 것이다 — 고치지 말고 보고하라.
- **하루 스와이프의 판정 규칙은 주 스와이프와 같아야 한다** — 가로 이동이 50pt를 넘고, 가로가 세로의 1.5배보다 클 때만. 규칙이 다르면 손끝은 같은 동작인데 위아래가 다르게 반응한다.
- **스와이프 방향:** 왼쪽으로 쓸면(`dx < 0`) 다음 날/다음 주. 스트립의 기존 코드와 같은 방향이다.
- **가로 드래그는 `ScrollView`가 버튼 터치를 취소해 주지 않는다.** 스크롤 축(세로)에서만 취소된다 — 그래서 `Button`/`NavigationLink`를 탭 제스처로 바꾸는 것이 이 작업의 핵심이고, 안 바꾸면 스와이프가 날짜 선택·화면 이동으로 끝난다.
- **`select(_:)` 한 번은 HealthKit 활동량 조회 + 서버 업서트 + 하루 조회이고, 그 하루 조회가 서버의 하루 피드백 생성을 건다.** 스와이프에 그대로 붙이면 안 된다.
- 현재 테스트 개수는 **438 tests / 46 suites**다.
- `#expect` 뒤에서 런타임 길이가 달라지는 배열(`service.fetchedDates` 등)을 인덱스로 읽지 않는다 — 실패해도 실행이 안 멈춰 범위를 벗어나면 테스트 프로세스가 통째로 죽는다. `.first`/`.last`/`.count`를 쓴다.
- 테스트 이름과 주석은 한국어로 쓴다(기존 관례).
- 테스트 실행:
  ```
  perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:WooriHaruTests > /tmp/t.log 2>&1
  ```
  - **백그라운드로 돌리지 말고 출력은 파일로 리다이렉트한다**(`| tail` 금지 — 파이프가 멈춘다). 이 맥에는 `timeout`/`gtimeout`이 없다. 결과는 `grep -E "Test run with|error:|✘" /tmp/t.log | tail -20`으로 본다.
  - **프로덕션 타입에 멤버를 추가하는 태스크(1·2)는 `clean test`로 돌린다.** 증분 빌드가 옛 모듈로 테스트를 컴파일해 「없는 멤버」 에러를 내거나, 더 나쁘게는 **새 테스트가 안 돈 채 통과로 보고**된 적이 있다.
- 각 태스크는 **고의 파손 확인**으로 끝낸다(Task 3은 유닛 테스트가 없어 예외 — 아래에 대신 할 일을 적었다).

## File Structure

| 파일 | 하는 일 | 태스크 |
| --- | --- | --- |
| `WooriHaru/ViewModels/DietDayViewModel.swift` | `showsTodayButton` | 1 |
| `WooriHaru/Views/Diet/DietHomeView.swift` | 버튼 조건 교체 | 1 |
| `WooriHaru/ViewModels/DietDayViewModel.swift` | `stepDay(by:)`, 예약 취소, 지연 주입 | 2 |
| `WooriHaru/Views/Diet/DietHomeView.swift` | 스트립 탭 제스처, 하루 스와이프, 끼니 행 항목 기반 이동 | 3 |
| `WooriHaruTests/DietDayTests.swift` | 1·2의 테스트 (`struct DietWeekStripTests`) | 1·2 |

**의존 순서:** 1 → 2 → 3. Task 3의 스와이프가 Task 2의 `stepDay(by:)`를 부른다.

---

### Task 1: 「오늘」 버튼이 오늘을 기준으로 판단한다

**Files:**
- Modify: `WooriHaru/ViewModels/DietDayViewModel.swift` (`isViewingSelectedWeek` 바로 뒤, 96~99행 근처)
- Modify: `WooriHaru/Views/Diet/DietHomeView.swift` (「오늘」 버튼 조건, 218행 근처)
- Test: `WooriHaruTests/DietDayTests.swift` (`@MainActor struct DietWeekStripTests`)

**Interfaces:**
- Consumes: `selectedDate`, `visibleWeekAnchor`
- Produces: `DietDayViewModel.showsTodayButton: Bool`

**무엇이 문제인가:** 버튼 조건이 `!vm.isViewingSelectedWeek`(보이는 주에 **선택 날짜**가 있는가)다. `select(_:)`가 `visibleWeekAnchor = date`로 기준일을 선택 날짜에 맞추므로, 2주 전으로 넘겨 날짜를 고르는 순간 조건이 거짓이 되어 **버튼이 사라지고 오늘로 돌아올 길이 없어진다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`DietDayTests.swift`의 `struct DietWeekStripTests` 안, `월_표시는_보이는_주를_따라간다` 뒤(스위트 끝)에 넣는다. `makeVM(on:)`(1438행)과 `makeDay(_:)`는 이미 있다.

```swift
    // MARK: - 오늘 버튼

    /// **이번 버그의 재현 케이스다.** 주를 넘겨 그 주의 날짜를 고르면 기준일이 선택 날짜에
    /// 맞춰지는데, 그것으로 버튼을 감추면 2주 전을 보면서 돌아올 길이 없어진다.
    /// **시작점을 오늘 기준 상대 날짜로 잡는다** — 고정 날짜로 두면 실행 시점에 따라
    /// 넘어간 주가 오늘의 주와 겹쳐 아무것도 검증하지 못하는 날이 생긴다.
    @Test func 주를_넘겨_고른_날짜에서도_오늘_버튼이_남는다() async {
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let target = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let (vm, service) = makeVM(on: start.dateString)
        service.days = [makeDay(date: start.dateString), makeDay(date: target.dateString)]
        await vm.load()

        vm.showNextWeek()
        await vm.select(target)

        #expect(vm.isViewingSelectedWeek)   // 기준일은 선택 주로 맞춰졌지만
        #expect(vm.showsTodayButton)        // 오늘로 돌아올 길은 남아야 한다
    }

    /// 오늘을 보고 있으면 돌아갈 곳이 없다 — 버튼도 없다.
    @Test func 오늘을_보고_있으면_오늘_버튼이_없다() async {
        let (vm, _) = makeVM(on: Date().dateString)
        await vm.load()

        #expect(!vm.showsTodayButton)
    }

    /// 오늘을 고른 채 주만 넘긴 경우 — 선택은 오늘이지만 화면 밖이라 돌아올 길이 필요하다.
    @Test func 오늘을_고른_뒤_주를_넘기면_오늘_버튼이_다시_뜬다() async {
        let (vm, _) = makeVM(on: Date().dateString)
        await vm.load()

        vm.showNextWeek()

        #expect(vm.showsTodayButton)
    }
```

- [ ] **Step 2: 실패하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "Test run with|error:|✘" /tmp/t.log | tail -20
```
Expected: **컴파일 에러** — `value of type 'DietDayViewModel' has no member 'showsTodayButton'`.

- [ ] **Step 3: 속성을 추가한다**

`DietDayViewModel.swift`의 `isViewingSelectedWeek` 정의 바로 뒤에 넣는다.

```swift
    /// 「오늘」 버튼을 띄울지. **`isViewingSelectedWeek`를 쓰면 안 된다** — 주를 넘겨 그 주의
    /// 날짜를 고르면 `select(_:)`가 기준일을 선택 날짜에 맞추므로 그 조건이 참이 되고,
    /// 2주 전을 보고 있는데 버튼이 사라져 오늘로 돌아올 길이 없어진다. 버튼이 하는 일이
    /// 「오늘로 간다」이므로 판단도 오늘을 기준으로 한다.
    var showsTodayButton: Bool {
        let calendar = Calendar.current
        let isTodaySelected = calendar.isDateInToday(selectedDate)
        let isTodayVisible = calendar.isDate(visibleWeekAnchor, equalTo: Date(), toGranularity: .weekOfYear)
        return !(isTodaySelected && isTodayVisible)
    }
```

- [ ] **Step 4: 화면을 갈아탄다**

`DietHomeView.swift`의 「오늘」 버튼 조건을 바꾼다. 주석도 함께 고친다.

```swift
                // 오늘에서 벗어나 있으면 돌아올 길을 띄운다. **선택 날짜가 아니라 오늘을
                // 기준으로 판단한다** — 주를 넘겨 그 주의 날짜를 고르면 기준일이 선택 날짜에
                // 맞춰지므로, 선택 기준으로는 버튼이 사라져 돌아올 길이 없어진다.
                if vm.showsTodayButton {
                    Button("오늘") {
                        Task { await vm.goToToday() }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.blue500)
                    .buttonStyle(.plain)
                }
```

- [ ] **Step 5: 통과하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild clean test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "Test run with|error:|✘" /tmp/t.log | tail -20
```
Expected: PASS, **441 tests**(438 + 3). `DietWeekStripTests`의 기존 테스트가 전부 그대로 통과해야 한다 — `isViewingSelectedWeek`는 손대지 않았다.

- [ ] **Step 6: 고의로 망가뜨려 본다**

`showsTodayButton`의 본문을 `!isViewingSelectedWeek`로 바꾸고 Step 5를 다시 돌린다(옛 조건 그대로 되돌리는 것이다).
Expected: `주를_넘겨_고른_날짜에서도_오늘_버튼이_남는다`가 **실패**해야 한다. 확인했으면 되돌린다.

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/ViewModels/DietDayViewModel.swift WooriHaru/Views/Diet/DietHomeView.swift WooriHaruTests/DietDayTests.swift
git commit -m "fix: 주를 넘겨 날짜를 골라도 오늘로 돌아올 수 있게 한다"
```

---

### Task 2: 하루 이동은 멈춘 뒤 한 번만 조회한다

**Files:**
- Modify: `WooriHaru/ViewModels/DietDayViewModel.swift` (프로퍼티, `init`, `showPreviousWeek`/`showNextWeek` 근처에 `stepDay`, `select(_:)` 첫머리)
- Test: `WooriHaruTests/DietDayTests.swift` (`struct DietWeekStripTests`)

**Interfaces:**
- Consumes: `selectedDate`, `visibleWeekAnchor`, `generation`, `feedbackTask`, `syncActivity()`, `load()`
- Produces:
  - `DietDayViewModel.stepDay(by days: Int)` — Task 3의 스와이프가 `vm.stepDay(by: 1)` / `vm.stepDay(by: -1)`로 부른다
  - `DietDayViewModel.waitForPendingSelection() async`
  - `init(..., daySwipeDelay: Duration = .milliseconds(350))`

**무엇을 만드나:** 화면은 손끝을 즉시 따라가고, **활동량 업서트와 하루 조회만 늦춘다.** 다섯 칸을 넘겨도 왕복은 한 번이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

먼저 스위트의 헬퍼에 지연 인자를 연다. `DietDayTests.swift:1438`의 `makeVM(on:)`을 이렇게 바꾼다(기본값이 있어 기존 호출지는 그대로 컴파일된다):

```swift
    private func makeVM(
        on dateString: String,
        daySwipeDelay: Duration = .milliseconds(350)
    ) -> (DietDayViewModel, FakeDietService) {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: dateString)]
        let date = Date.from(dateString)!
        return (
            DietDayViewModel(
                service: service,
                energyFetcher: FakeActiveEnergyFetcher(),
                date: date,
                daySwipeDelay: daySwipeDelay
            ),
            service
        )
    }
```

그리고 Task 1에서 만든 `// MARK: - 오늘 버튼` 구역 뒤에 넣는다:

```swift
    // MARK: - 하루 이동

    /// **스와이프에 조회가 칸마다 붙으면 안 된다.** `select(_:)` 한 번은 활동량 업서트와
    /// 하루 조회이고, 그 조회가 서버의 하루 피드백 생성을 건다.
    @Test func 하루_이동을_연속하면_조회는_한_번만_나간다() async {
        let (vm, service) = makeVM(on: "2026-07-15", daySwipeDelay: .milliseconds(10))
        await vm.load()
        let before = service.fetchedDates.count

        vm.stepDay(by: 1)
        vm.stepDay(by: 1)
        vm.stepDay(by: 1)
        await vm.waitForPendingSelection()

        #expect(vm.selectedDate == Date.from("2026-07-18"))
        #expect(service.fetchedDates.count == before + 1)
        #expect(service.fetchedDates.last == "2026-07-18")
    }

    /// 하루 이동이 주 경계를 넘으면 스트립도 따라가야 한다 — 선택 날짜가 화면 밖에 남으면 안 된다.
    @Test func 하루_이동이_주_경계를_넘으면_스트립도_따라간다() async {
        let (vm, _) = makeVM(on: "2026-07-18", daySwipeDelay: .milliseconds(10))   // 토요일
        await vm.load()

        vm.stepDay(by: 1)   // 7/19 일요일 — 다음 주 첫날
        await vm.waitForPendingSelection()

        #expect(vm.weekDates.first == Date.from("2026-07-19"))
    }

    /// **이전 날짜의 하루를 새 날짜 라벨 아래 남기지 않는다** — 조회를 늦춰도 이 방어는
    /// 즉시 걸려야 한다. 안 그러면 0.35초 동안 다른 날의 끼니를 이 날짜 것으로 알고 연다.
    @Test func 하루_이동_직후에_이전_날짜의_하루가_지워진다() async {
        let (vm, service) = makeVM(on: "2026-07-15", daySwipeDelay: .milliseconds(10))
        service.days = [makeDay(date: "2026-07-15"), makeDay(date: "2026-07-16")]
        await vm.load()
        #expect(vm.day?.date == "2026-07-15")

        vm.stepDay(by: 1)

        #expect(vm.day == nil)
        #expect(vm.isLoading)

        await vm.waitForPendingSelection()
        #expect(vm.day?.date == "2026-07-16")
    }

    /// 탭은 기다리지 않는다. **예약된 스와이프 조회는 취소해야 한다** — 안 그러면 탭한
    /// 날짜 위에 0.35초 뒤 스와이프가 겨눴던 날짜의 조회가 덮인다.
    @Test func 날짜를_탭하면_예약된_하루_조회가_취소된다() async {
        let (vm, service) = makeVM(on: "2026-07-15", daySwipeDelay: .milliseconds(200))
        service.days = [
            makeDay(date: "2026-07-15"), makeDay(date: "2026-07-16"), makeDay(date: "2026-07-20")
        ]
        await vm.load()
        let before = service.fetchedDates.count

        vm.stepDay(by: 1)                           // 7/16으로 예약
        await vm.select(Date.from("2026-07-20")!)   // 예약을 취소하고 즉시 조회

        #expect(vm.selectedDate == Date.from("2026-07-20"))
        #expect(service.fetchedDates.count == before + 1)
        #expect(service.fetchedDates.last == "2026-07-20")
    }
```

- [ ] **Step 2: 실패하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "Test run with|error:|✘" /tmp/t.log | tail -20
```
Expected: **컴파일 에러** — `extra argument 'daySwipeDelay' in call`과 `has no member 'stepDay'`.

- [ ] **Step 3: 지연값과 예약 자리를 만든다**

`DietDayViewModel.swift`에서 세 군데를 고친다.

**(a) 저장 프로퍼티** — `private var feedbackTask: Task<Void, Never>?` 뒤에 넣는다:

```swift
    /// 예약해 둔 하루 조회. 스와이프가 이어지는 동안 취소하고 다시 잡는다.
    private var pendingSelection: Task<Void, Never>?
```

**(b) 지연값** — `private let pollTimeout: Duration` 뒤에 넣는다:

```swift
    /// 하루 스와이프가 멈췄다고 보고 조회를 내기까지의 시간. 테스트가 줄여 쓴다.
    private let daySwipeDelay: Duration
```

**(c) `init`** — 파라미터와 대입을 더한다(`pollTimeout` 다음 자리):

```swift
    init(
        service: any DietServing = DietService(),
        energyFetcher: any ActiveEnergyFetching = HealthKitService(),
        date: Date = Date(),
        pollInterval: Duration = DietPolicy.pollInterval,
        pollTimeout: Duration = DietPolicy.pollTimeout,
        daySwipeDelay: Duration = .milliseconds(350)
    ) {
        self.service = service
        self.energyFetcher = energyFetcher
        self.selectedDate = date
        self.visibleWeekAnchor = date
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.daySwipeDelay = daySwipeDelay
    }
```

- [ ] **Step 4: `stepDay`를 넣는다**

`showNextWeek()`/`shiftVisibleWeek(by:)` 뒤, `goToToday()` 앞에 넣는다.

```swift
    /// 하루 단위 이동(스트립 아래 좌우 스와이프). **화면은 즉시 옮기고 조회만 늦춘다** —
    /// `select(_:)` 한 번은 활동량 업서트와 하루 조회이고 그 조회가 서버의 하루 피드백
    /// 생성을 건다. 초당 서너 번 나가는 스와이프에 그대로 붙이면 왕복이 그만큼 늘어난다.
    func stepDay(by days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }

        selectedDate = moved
        // 선택이 화면 밖에 남지 않게 스트립도 따라간다.
        visibleWeekAnchor = moved

        // **이 방어는 조회와 함께 늦추면 안 된다.** 이전 날짜의 끼니가 새 날짜 라벨 아래
        // 남아 있으면 사용자가 그것을 이 날짜 것으로 알고 열어 고치거나 지운다
        // (`select(_:)`가 같은 이유로 같은 일을 한다).
        day = nil
        isLoading = true
        // 진행 중이던 조회·폴링을 여기서 무효화한다 — 늦게 온 이전 날짜 응답이 되채운다.
        generation += 1
        feedbackTask?.cancel()

        pendingSelection?.cancel()
        let delay = daySwipeDelay
        pendingSelection = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await syncActivity()
            await load()
        }
    }

    /// 예약된 하루 조회를 기다린다. **테스트가 쓴다** — 화면은 기다릴 일이 없다.
    func waitForPendingSelection() async {
        await pendingSelection?.value
    }
```

- [ ] **Step 5: 탭이 예약을 취소하게 한다**

`select(_:)`의 첫 줄(`visibleWeekAnchor = date` 앞)에 넣는다.

```swift
        // **스와이프로 예약해 둔 조회를 취소한다.** 안 그러면 탭한 날짜 위에 0.35초 뒤
        // 스와이프가 겨눴던 날짜의 조회가 덮인다.
        pendingSelection?.cancel()
        pendingSelection = nil
```

- [ ] **Step 6: 통과하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild clean test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "Test run with|error:|✘" /tmp/t.log | tail -20
```
Expected: PASS, **445 tests**(441 + 4). 기존 `DietWeekStripTests`·`DietDayViewModelTests`가 전부 그대로 통과해야 한다.

- [ ] **Step 7: 고의로 망가뜨려 본다**

`stepDay`에서 `pendingSelection?.cancel()` 한 줄을 지우고 Step 6을 다시 돌린다.
Expected: `하루_이동을_연속하면_조회는_한_번만_나간다`가 **실패**해야 한다(조회가 세 번 나간다). 확인했으면 되돌린다.

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/DietDayViewModel.swift WooriHaruTests/DietDayTests.swift
git commit -m "feat: 하루 단위 날짜 이동을 만들고 연속 이동은 한 번만 조회한다"
```

---

### Task 3: 화면의 제스처 — 버튼을 탭 제스처로 바꾸고 하루 스와이프를 붙인다

**Files:**
- Modify: `WooriHaru/Views/Diet/DietHomeView.swift` (`@State` 추가, `body`의 콘텐츠 블록, `navigationDestination`, `weekStrip`의 날짜 셀, `mealList`)
- Test: 없음 — 아래 「검증」 참고

**Interfaces:**
- Consumes: `DietDayViewModel.stepDay(by days: Int)`(Task 2), `DietDayViewModel.select(_:) async`
- Produces: 없음(화면 내부 변경)

**검증에 대해 먼저:** SwiftUI 제스처·히트 테스트는 유닛 테스트가 닿지 않는다. **테스트를 억지로 만들지 마라** — 뷰 계층을 흉내 내는 테스트는 제스처가 실제로 붙었는지가 아니라 네가 쓴 흉내가 맞는지를 검증한다. 이 태스크의 검증은 ① 기존 445개가 그대로 통과하는지 ② 실기기 확인(사람이 한다)이다.

- [ ] **Step 1: 끼니 상세로 가는 길을 항목 기반으로 바꾼다**

`NavigationLink`도 버튼이라, 하루 스와이프를 붙이면 **카드 위에서 가로로 쓸고 뗄 때 상세로 들어가면서 날짜까지 바뀐다.**

**(a)** 다른 `@State` 옆에 추가한다:

```swift
    /// 끼니 상세로 가는 길. **`NavigationLink`를 쓰지 않는다** — 버튼은 제 경계 안에서
    /// 움직인 손가락도 떼는 순간 눌린 것으로 쳐서, 카드 위에서 시작한 하루 스와이프가
    /// 상세 화면 진입으로 끝난다. 탭 제스처는 손가락이 움직이면 스스로 취소된다.
    @State private var selectedMealId: Int?
```

**(b)** `navigationDestination(for: Int.self)`를 항목 기반으로 바꾼다. `Int` 목적지를 쓰는 곳은 이 목록 하나뿐이라 다른 화면에 영향이 없다.

```swift
        .navigationDestination(item: $selectedMealId) { mealId in
            MealDetailView(mealId: mealId) { Task { await vm.reload() } }
        }
```

**(c)** `mealList`의 행에서 `NavigationLink`와 `.buttonStyle(.plain)`을 걷어내고 탭 제스처를 단다. **`contentShape`을 새로 붙이지 않는다** — `GlassCard`가 이미 카드 모서리 모양으로 걸어 둔다.

```swift
    /// 서버가 아침→점심→저녁→간식 순으로 주므로 **다시 정렬하지 않는다.**
    private var mealList: some View {
        VStack(spacing: 12) {
            ForEach(vm.meals) { meal in
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: meal.mealType.iconName)
                            .foregroundStyle(Color.blue500)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.mealType.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.slate700)
                            Text(meal.items.map(\.foodName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Color.slate400)
                                .lineLimit(1)
                        }
                        Spacer()
                        DietScoreRing(score: meal.score, size: 44)
                    }
                }
                .onTapGesture { selectedMealId = meal.id }
            }
        }
    }
```

- [ ] **Step 2: 스트립의 날짜를 탭 제스처로 바꾼다**

`weekStrip`의 `ForEach` 안에서 `Button`을 걷어낸다. 나머지(원 배경·글꼴)는 그대로다.

```swift
            HStack(spacing: 4) {
                ForEach(vm.weekDates, id: \.timeIntervalSince1970) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: vm.selectedDate)
                    VStack(spacing: 4) {
                        Text(weekdayText(date))
                            .font(.caption2)
                            .foregroundStyle(Color.slate400)
                        Text("\(date.day)")
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .white : Color.slate700)
                            .frame(width: 32, height: 32)
                            .background(isSelected ? Color.blue500 : .clear, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                    // **`Button`을 쓰면 안 된다.** 버튼은 제 경계 안에서 움직인 손가락도 떼는
                    // 순간 눌린 것으로 치고, `ScrollView`는 스크롤 축(세로)에서만 그 터치를
                    // 취소해 준다 — 그래서 날짜 원 위에서 시작한 가로 스와이프가 「그 날짜
                    // 선택」으로 끝나고(조회까지 나간다), 원 안에서 움직인 거리는 주 넘김
                    // 기준(50pt)에 못 미쳐 주도 안 넘어간다.
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await vm.select(date) } }
                }
            }
```

- [ ] **Step 3: 스트립 아래에 하루 스와이프를 붙인다**

`body`의 `VStack`에서 스트립 아래 콘텐츠를 프로퍼티로 뽑고 제스처를 단다.

**(a)** `body`의 `VStack` 내용을 이렇게 바꾼다:

```swift
            VStack(spacing: GlassTokens.cardSpacing) {
                weekStrip
                dayContent
            }
```

**(b)** `weekStrip` 정의 앞에 새 프로퍼티를 넣는다:

```swift
    /// 스트립 아래 본문. **여기서 좌우로 쓸면 하루씩 옮긴다** — 스트립은 주 단위이고
    /// 여기는 하루 단위다. 판정 규칙은 스트립과 같게 둔다(가로 50pt 초과 + 세로의 1.5배
    /// 초과). 규칙이 다르면 손끝은 같은 동작인데 위아래가 다르게 반응한다.
    private var dayContent: some View {
        VStack(spacing: GlassTokens.cardSpacing) {
            if vm.loadFailed && vm.day == nil {
                failureState
            } else {
                summaryCard

                // 하루 점수에도 같은 카드를 쓴다 — 칼로리 항목이 하나 더 붙는다.
                if let basis = vm.day?.scoreBasis {
                    ScoreBasisCard(title: "하루 점수", score: vm.day?.dayScore, dayBasis: basis)
                }

                mealList
            }
        }
        // 카드 사이 빈 곳에서 시작한 스와이프도 받는다.
        .contentShape(Rectangle())
        // `.gesture`는 배타적이라 세로 드래그를 통째로 가져가 바깥 `ScrollView`의 스크롤이
        // 죽는다 — 스트립과 같은 이유로 `.simultaneousGesture`를 쓴다.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 50, abs(dx) > abs(dy) * 1.5 else { return }
                    // 왼쪽으로 쓸면 다음 날 — 스트립의 주 넘김과 같은 방향이다.
                    vm.stepDay(by: dx < 0 ? 1 : -1)
                }
        )
    }
```

- [ ] **Step 4: 회귀가 없는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "Test run with|error:|✘" /tmp/t.log | tail -20
```
Expected: PASS, **445 tests** — 개수가 그대로여야 한다(이 태스크는 테스트를 추가하지 않는다).

- [ ] **Step 5: 남은 `NavigationLink`가 없는지 훑는다**

`rg -n "NavigationLink" WooriHaru/Views/Diet/DietHomeView.swift`로 확인한다. **매치가 없어야 한다.** 남아 있으면 그 자리는 하루 스와이프와 경합한다 — 리포트에 적어라.

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Views/Diet/DietHomeView.swift
git commit -m "feat: 스트립 아래 좌우 스와이프로 하루씩 옮긴다"
```

---

## 마무리 확인

- [ ] 전체 테스트를 `clean test`로 한 번 더 돌려 **445 tests / 46 suites** 통과를 확인한다
- [ ] 실기기 확인 — ① 스트립에서 가로로 쓸면 **날짜가 안 바뀌고 주만** 넘어간다 ② 스트립 날짜 탭은 그대로 선택된다 ③ 스트립 아래(요약 카드·끼니 카드 위 포함)에서 가로로 쓸면 **하루씩** 옮겨진다 ④ 끼니 카드 위에서 가로로 쓸어도 상세로 안 들어간다 ⑤ 끼니 카드 탭은 상세로 들어간다 ⑥ 세로 스크롤이 어느 영역에서도 죽지 않는다 ⑦ 주를 넘겨 날짜를 골라도 「오늘」 버튼이 남아 있고, 누르면 오늘로 돌아온다
- [ ] `git log --oneline develop..HEAD`로 이번 작업의 커밋 5개(설계 1 + 이 계획 1 + 태스크 3)를 확인한다
