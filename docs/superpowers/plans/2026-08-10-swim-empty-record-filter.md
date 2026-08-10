# 내역 없는 수영 기록 감추기 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 잘못 시작했다가 바로 끝내 보여줄 내용이 없는 수영 기록을 목록에서 감춘다.

**Architecture:** 세 겹으로 쌓는다 — **① 모델**(`SwimWorkout.isEmptyRecord`가 「감출 기록인가」를 판정) → **② 뷰모델 필터**(페이지를 걸러 담고, 다음 커서는 **필터 전** 마지막 기록에서 뽑아 따로 보관) → **③ 이어읽기**(한 페이지가 통째로 걸러져 목록이 안 늘어나면 다음 페이지를 계속 읽어 무한스크롤이 죽는 것을 막는다). 서비스(`HealthKitService`)와 화면(`SwimRecordListView`)은 손대지 않는다.

**Tech Stack:** Swift / SwiftUI, Swift Testing, `@MainActor @Observable` 뷰모델

**설계 문서:** `docs/superpowers/specs/2026-08-10-swim-empty-record-filter-design.md`

## Global Constraints

- **감출 조건은 `duration < 60 && (distanceMeters ?? 0) <= 0`이다.** 두 조건을 **모두** 요구한다. 어느 한쪽만 보면 짧은 스프린트(40초·50m)나 거리를 못 잡은 개방 수역 기록이 사라진다. 경계값 60초는 **감추지 않는다**(미만이다).
- **칼로리·스트로크는 판정에 넣지 않는다.** 바로 끝낸 기록에도 워치가 1kcal를 적어 넣는 일이 있어, 그것까지 0을 요구하면 정작 잡으려던 기록이 안 걸린다.
- **`HealthKitService`와 `SwimRecordListView`는 수정 대상이 아니다.** 빈 상태 안내는 기존 것이 그대로 뜬다.
- **새 파일이 없다** — `project.pbxproj`를 안 건드린다.
- 테스트 실행:
  ```
  perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:WooriHaruTests > /tmp/t.log 2>&1
  ```
  - **백그라운드로 돌리지 말고 출력은 파일로 리다이렉트한다**(`| tail` 금지 — 파이프가 멈춘다). 이 맥에는 `timeout`/`gtimeout`이 없다. 결과는 `grep -E "Test Suite|failed|passed" /tmp/t.log | tail -30`으로 본다.
  - **프로덕션 타입에 멤버를 추가한 태스크(1·2·3 전부)는 `clean test`로 돌린다.** 증분 빌드가 옛 모듈로 테스트를 컴파일해 「없는 멤버」 에러를 내거나, 더 나쁘게는 **새 테스트가 안 돈 채 통과로 보고**된 적이 있다.
  - **통과만 보지 말고 개수가 예상만큼 늘었는지 확인한다.** Task 1을 시작하기 전에 현재 개수(`Executed N tests`)를 적어 두고 기준으로 삼는다.
- **`#expect` 뒤에서 배열을 인덱스로 읽지 않는다.** 실패해도 멈추지 않으므로 범위를 벗어나면 테스트가 프로세스째 죽어 남은 테스트가 판정도 못 받는다. `.first`/`.last`나 `map(\.id)` 비교를 쓴다.
- 각 태스크는 **고의 파손 확인**으로 끝낸다 — 구현을 망가뜨려 새 테스트가 실제로 빨개지는지 보고 되돌린다.
- 테스트 이름과 주석은 한국어로 쓴다(기존 `SwimRecordTests.swift` 관례).

## File Structure

| 파일 | 하는 일 | 태스크 |
| --- | --- | --- |
| `WooriHaru/Models/SwimWorkout.swift` | `isEmptyRecord` 판정 | 1 |
| `WooriHaru/ViewModels/SwimRecordViewModel.swift` | `nextCursor` + 필터 | 2 |
| `WooriHaru/ViewModels/SwimRecordViewModel.swift` | `fetchVisiblePages` 이어읽기 | 3 |
| `WooriHaruTests/SwimRecordTests.swift` | 세 태스크의 테스트 | 1·2·3 |

**의존 순서:** 1 → 2 → 3. Task 2는 Task 1의 `isEmptyRecord`를 쓰고, Task 3은 Task 2가 만든 `nextCursor`를 반복문 안으로 옮긴다.

---

### Task 1: 모델 — 감출 기록인지 판정한다

**Files:**
- Modify: `WooriHaru/Models/SwimWorkout.swift` (`// MARK: - Display Text` 확장 안, `locationText` 뒤)
- Test: `WooriHaruTests/SwimRecordTests.swift` (`struct SwimWorkoutFormatTests`, 117~153행)

**Interfaces:**
- Consumes: `SwimWorkout.duration: TimeInterval`, `SwimWorkout.distanceMeters: Double?`
- Produces: `SwimWorkout.isEmptyRecord: Bool` — Task 2가 필터 조건으로 쓴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`SwimRecordTests.swift`의 `struct SwimWorkoutFormatTests` 안, `locationText` 테스트(138~140행) 뒤에 넣는다. `makeWorkout`은 같은 파일 67행에 이미 있다.

```swift
    /// 잘못 시작해 바로 끝낸 기록. 카드에 채울 것이 「1분 미만」과 「-」뿐이다.
    @Test func 짧으면서_거리가_없으면_감출_기록이다() {
        #expect(makeWorkout(duration: 55, distance: nil).isEmptyRecord == true)
        #expect(makeWorkout(duration: 55, distance: 0).isEmptyRecord == true)
        #expect(makeWorkout(duration: 3, distance: nil).isEmptyRecord == true)
    }

    /// 짧아도 헤엄친 거리가 있으면 남긴다 — 50m 스프린트 한 판이 사라지면 안 된다.
    @Test func 짧아도_거리가_있으면_남긴다() {
        #expect(makeWorkout(duration: 40, distance: 50).isEmptyRecord == false)
    }

    /// 거리를 못 잡은 개방 수역 기록이 통째로 사라지면 안 된다. 시간이 판정을 막는다.
    @Test func 거리가_없어도_1분_이상이면_남긴다() {
        #expect(makeWorkout(duration: 90, distance: 0).isEmptyRecord == false)
        #expect(makeWorkout(duration: 1800, distance: nil).isEmptyRecord == false)
    }

    /// 경계는 「미만」이다 — 정확히 60초는 남긴다.
    @Test func 정확히_1분이면_남긴다() {
        #expect(makeWorkout(duration: 60, distance: 0).isEmptyRecord == false)
    }
```

- [ ] **Step 2: 실패하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "error:|Executed" /tmp/t.log | tail -20
```
Expected: **컴파일 에러** — `value of type 'SwimWorkout' has no member 'isEmptyRecord'`

- [ ] **Step 3: 판정을 넣는다**

`SwimWorkout.swift`의 `extension SwimWorkout` 안, `locationText`(129~132행) 뒤에 넣는다.

```swift
    /// 잘못 시작해 바로 끝낸 기록. 1분 미만이면서 거리가 0이거나 없을 때만 해당한다.
    /// **두 조건을 모두 요구해야** 짧지만 실제로 헤엄친 기록(50m 스프린트)이나 거리를
    /// 못 잡은 개방 수역 기록이 안 사라진다. 칼로리·스트로크는 보지 않는다 — 바로 끝낸
    /// 기록에도 워치가 1kcal를 적어 넣는 일이 있어 그것까지 요구하면 아무것도 안 걸린다.
    var isEmptyRecord: Bool {
        duration < 60 && (distanceMeters ?? 0) <= 0
    }
```

- [ ] **Step 4: 통과하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild clean test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "error:|failed|Executed" /tmp/t.log | tail -20
```
Expected: PASS. 개수가 기준보다 **4개** 늘어야 한다.

- [ ] **Step 5: 고의로 망가뜨려 본다**

`duration < 60`을 `duration < 0`으로 바꾸고 Step 4를 다시 돌린다.
Expected: `짧으면서_거리가_없으면_감출_기록이다`가 **실패**해야 한다. 확인했으면 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Models/SwimWorkout.swift WooriHaruTests/SwimRecordTests.swift
git commit -m "feat: 내역 없는 수영 기록을 가려낸다"
```

---

### Task 2: 뷰모델 — 걸러 담고, 커서를 목록에서 떼어낸다

**Files:**
- Modify: `WooriHaru/ViewModels/SwimRecordViewModel.swift` (프로퍼티 추가 20행 근처, `load()` 50~80행, `loadMoreIfNeeded()` 83~106행)
- Test: `WooriHaruTests/SwimRecordTests.swift` (`@MainActor struct SwimRecordViewModelTests`, `// MARK: - Paging` 구역 끝)

**Interfaces:**
- Consumes: `SwimWorkout.isEmptyRecord`(Task 1), `SwimWorkoutPage.workouts`·`.mayHaveMore`
- Produces: `SwimRecordViewModel`의 `private var nextCursor: Date?` — Task 3이 반복문 안에서 갱신한다.

**왜 커서를 떼어내나:** 지금 커서는 `workouts.last?.startDate`다. 걸러낸 기록이 페이지 끝에 있으면 커서가 그 앞의 살아남은 기록으로 물러나, **다음 페이지가 방금 버린 것들을 다시 실어 온다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`SwimRecordViewModelTests` 안, `같은_시각_기록만_있어도_진행이_멈추지_않는다`(485~504행) 뒤에 넣는다. `makePage`(399행)와 `makeWorkout`(67행)은 이미 있다.

```swift
    // MARK: - 내역 없는 기록

    /// 최신순 `count`건을 하루 간격으로. `emptyAt`에 든 인덱스만 감출 기록으로 만든다.
    private func makeMixedPage(count: Int, emptyAt: Set<Int>) -> [SwimWorkout] {
        let newest = Date(timeIntervalSince1970: 1_753_400_000)
        return (0..<count).map { index in
            let start = newest.addingTimeInterval(TimeInterval(-index) * 86_400)
            return emptyAt.contains(index)
                ? makeWorkout(start: start, duration: 5, distance: nil)
                : makeWorkout(start: start, duration: 1800, distance: 1200)
        }
    }

    @Test func 내역_없는_기록은_목록에서_빠진다() async {
        let all = makeMixedPage(count: 4, emptyAt: [1, 2])
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(workouts: all), pageSize: 30)

        await vm.load()

        #expect(vm.workouts.map(\.id) == [all[0].id, all[3].id])
    }

    /// 커서가 화면에 남은 마지막 기록에서 나오면, 감춘 구간을 다음 페이지가 다시 실어 온다.
    @Test func 커서는_감춘_기록까지_지나간다() async {
        // 3건짜리 페이지의 끝 두 건이 감출 기록이다
        let all = makeMixedPage(count: 6, emptyAt: [1, 2])
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        #expect(vm.workouts.map(\.id) == [all[0].id])

        await vm.loadMoreIfNeeded(currentItem: all[0])

        // 살아남은 all[0]이 아니라 필터 전 마지막인 all[2]가 커서다
        #expect(fetcher.calls.count == 2)
        #expect(fetcher.calls[1].cursor == all[2].startDate)
        #expect(vm.workouts.map(\.id) == [all[0].id, all[3].id, all[4].id, all[5].id])
    }
```

- [ ] **Step 2: 실패하는지 확인한다**

Run: Step 4와 같은 명령(`clean` 없이).
Expected: `내역_없는_기록은_목록에서_빠진다`가 **4건 전부 담겨** 실패하고, `커서는_감춘_기록까지_지나간다`는 커서가 `all[0].startDate`로 와서 실패한다.

- [ ] **Step 3: 필터와 커서를 넣는다**

`SwimRecordViewModel.swift`에서 세 군데를 고친다.

**(a) `generation` 선언(20행) 뒤에 프로퍼티 추가:**

```swift
    /// 다음 페이지의 경계. **필터 전** 마지막 기록의 시작 시각이다 — 감춘 기록에서
    /// 커서를 다시 잡으면 그 구간을 다음 페이지가 통째로 다시 실어 온다.
    private var nextCursor: Date?
```

**(b) `load()`의 `do` 블록(60~71행)을 이렇게 바꾼다:**

```swift
        do {
            try await service.requestAuthorization()
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: nil)
            guard token == generation else { return }
            workouts = page.workouts.filter { !$0.isEmptyRecord }
            nextCursor = page.workouts.last?.startDate
            canLoadMore = page.mayHaveMore
        } catch SwimWorkoutError.healthDataUnavailable {
            // 재시도해도 달라지지 않는 조건이라 실패로 두지 않는다.
            // 빈 상태로 보내야 "건강 데이터를 쓸 수 없는 기기입니다" 안내가 뜬다.
            guard token == generation else { return }
            workouts = []
            nextCursor = nil
            canLoadMore = false
        } catch {
```

**(c) `loadMoreIfNeeded()`(83~106행)를 이렇게 바꾼다:**

```swift
    /// 목록 끝에 도달했을 때 다음 페이지를 잇는다.
    func loadMoreIfNeeded(currentItem: SwimWorkout) async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard currentItem.id == workouts.last?.id else { return }
        // 서비스가 경계 시각의 기록을 통째로 채워 주므로, 이미 읽은 마지막 시각은
        // 배제하고 넘어가면 된다. 동점 무리가 쪼개질 일이 없어 순서에 기대지 않는다.
        guard let cursor = nextCursor else { return }

        let token = generation
        isLoadingMore = true
        do {
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: cursor)
            // 기다리는 사이 새로고침이 끼어들었으면 이 결과는 이미 낡았다.
            guard token == generation else { return }
            let known = Set(workouts.map(\.id))
            workouts.append(contentsOf: page.workouts.filter {
                !known.contains($0.id) && !$0.isEmptyRecord
            })
            nextCursor = page.workouts.last?.startDate ?? nextCursor
            canLoadMore = page.mayHaveMore
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
        guard token == generation else { return }
        isLoadingMore = false
    }
```

- [ ] **Step 4: 통과하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild clean test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "error:|failed|Executed" /tmp/t.log | tail -20
```
Expected: PASS. 개수가 Task 1 뒤보다 **2개** 늘어야 한다. **기존 페이지네이션 테스트 8개가 전부 그대로 통과해야 한다** — 감출 기록이 없는 기존 데이터에서는 `nextCursor`가 `workouts.last?.startDate`와 같은 값이라 동작이 안 바뀐다.

- [ ] **Step 5: 고의로 망가뜨려 본다**

(c)의 `nextCursor = page.workouts.last?.startDate ?? nextCursor`를 `nextCursor = workouts.last?.startDate`로 바꾸고 Step 4를 다시 돌린다.
Expected: `커서는_감춘_기록까지_지나간다`가 **실패**해야 한다. 확인했으면 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/ViewModels/SwimRecordViewModel.swift WooriHaruTests/SwimRecordTests.swift
git commit -m "feat: 내역 없는 수영 기록을 목록에서 감춘다"
```

---

### Task 3: 뷰모델 — 한 페이지가 통째로 걸러져도 멈추지 않는다

**Files:**
- Modify: `WooriHaru/ViewModels/SwimRecordViewModel.swift` (`load()`·`loadMoreIfNeeded()` + `fetchVisiblePages` 추가)
- Test: `WooriHaruTests/SwimRecordTests.swift` (`// MARK: - 내역 없는 기록` 구역 끝)

**Interfaces:**
- Consumes: Task 2의 `nextCursor`, Task 1의 `isEmptyRecord`
- Produces: `private func fetchVisiblePages(token: Int, excluding known: Set<UUID>) async throws -> [SwimWorkout]` — 뷰모델 내부 전용. 밖에서 쓰는 곳은 없다.

**무엇이 문제인가:** 한 페이지 30건이 전부 감출 기록이면 `workouts`에 아무것도 안 붙는다. **새 셀이 안 생기니 `SwimRecordListView`의 `.task`가 다시 안 뜨고**(`SwimRecordListView.swift:15`), 더 읽을 것이 남았는데 사용자는 스크롤로 되살릴 방법이 없다. 첫 페이지에서 이러면 「기록 없음」으로 보인다.

**왜 반복 상한이 없나:** 상한에 걸려 멈춰도 목록이 안 늘어난 채라 **같은 교착**이 된다. 상한은 문제를 안 풀고 발생 조건만 좁힌다. 대신 매 회차 `generation` 토큰을 확인해 새로고침이 끼어들면 그 자리에서 멈춘다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

Task 2에서 만든 `// MARK: - 내역 없는 기록` 구역 끝에 넣는다. `makeMixedPage`는 Task 2에서 이미 만들었다.

```swift
    /// 한 페이지가 통째로 걸러지면 화면에 새 셀이 안 생겨 다음 페이지를 부를 트리거가
    /// 사라진다. 첫 페이지에서 이러면 「기록 없음」으로 보인다.
    @Test func 첫_페이지가_전부_감출_기록이면_이어_읽는다() async {
        // 앞 3건이 감출 기록 — pageSize 3이라 첫 페이지가 통째로 비워진다
        let all = makeMixedPage(count: 6, emptyAt: [0, 1, 2])
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()

        #expect(vm.workouts.map(\.id) == [all[3].id, all[4].id, all[5].id])
        #expect(vm.showsEmptyState == false)
        #expect(fetcher.calls.count == 2)
    }

    /// 이어읽기는 한 건이라도 건지면 멈춘다 — 목록 전체를 미리 당겨 오지 않는다.
    @Test func 한_건이라도_건지면_거기서_멈춘다() async {
        let all = makeMixedPage(count: 9, emptyAt: [0, 1, 2])
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()

        #expect(vm.workouts.map(\.id) == [all[3].id, all[4].id, all[5].id])
        #expect(fetcher.calls.count == 2) // 세 번째 페이지는 안 읽는다
        #expect(vm.canLoadMore == true)
    }

    /// 스크롤 도중에도 같다 — 다음 페이지가 통째로 걸러지면 그 다음까지 읽는다.
    @Test func 스크롤_중에_페이지가_비어도_이어_읽는다() async {
        // 첫 페이지 3건은 정상, 다음 3건이 전부 감출 기록
        let all = makeMixedPage(count: 9, emptyAt: [3, 4, 5])
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        #expect(vm.workouts.count == 3)

        await vm.loadMoreIfNeeded(currentItem: all[2])

        #expect(vm.workouts.map(\.id) == [all[0].id, all[1].id, all[2].id,
                                          all[6].id, all[7].id, all[8].id])
        #expect(fetcher.calls.count == 3)
    }

    /// 전 이력이 감출 기록이면 기존 빈 상태 안내가 그대로 뜬다.
    @Test func 전부_감출_기록이면_빈_상태다() async {
        let all = makeMixedPage(count: 7, emptyAt: Set(0..<7))
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()

        #expect(vm.workouts.isEmpty)
        #expect(vm.showsEmptyState == true)
        #expect(vm.canLoadMore == false)
        #expect(vm.loadFailed == false)
    }
```

- [ ] **Step 2: 실패하는지 확인한다**

Run: Step 4와 같은 명령(`clean` 없이).
Expected: 네 개 다 실패한다 — `첫_페이지가_전부_감출_기록이면_이어_읽는다`와 `한_건이라도_건지면_거기서_멈춘다`는 `vm.workouts`가 **빈 배열**로, `스크롤_중에...`는 3건에서 안 늘어나서, `전부_감출_기록이면_빈_상태다`는 `canLoadMore`가 **true**로 남아서.

- [ ] **Step 3: 이어읽기를 넣는다**

`SwimRecordViewModel.swift`에서 `load()`의 `do` 블록과 `loadMoreIfNeeded()`를 바꾸고, 둘이 함께 쓸 헬퍼를 `// MARK: - Load` 구역 끝(`loadMoreIfNeeded` 뒤)에 넣는다.

**(a) `load()`의 `do` 블록을 이렇게 바꾼다:**

```swift
        do {
            try await service.requestAuthorization()
            // 처음부터 다시 읽으므로 커서를 비운다. `workouts`는 새 페이지가 올 때까지
            // 그대로 둔다 — 여기서 비우면 당겨서 새로고침 중에 목록이 한 번 사라진다.
            nextCursor = nil
            canLoadMore = true
            let fresh = try await fetchVisiblePages(token: token, excluding: [])
            guard token == generation else { return }
            workouts = fresh
        } catch SwimWorkoutError.healthDataUnavailable {
```

(나머지 `catch` 두 개는 Task 2 상태 그대로 둔다.)

**(b) `loadMoreIfNeeded()`의 `do` 블록을 이렇게 바꾼다:**

```swift
        let token = generation
        isLoadingMore = true
        do {
            let fresh = try await fetchVisiblePages(
                token: token, excluding: Set(workouts.map(\.id))
            )
            // 기다리는 사이 새로고침이 끼어들었으면 이 결과는 이미 낡았다.
            guard token == generation else { return }
            workouts.append(contentsOf: fresh)
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
        guard token == generation else { return }
        isLoadingMore = false
```

`guard let cursor = nextCursor else { return }`은 `guard nextCursor != nil else { return }`으로 바꾼다 — 커서는 이제 헬퍼가 읽는다.

**(c) 헬퍼를 추가한다:**

```swift
    /// `nextCursor`부터 페이지를 읽어 **보여줄 기록만** 모아 돌려준다. 커서와
    /// `canLoadMore`는 여기서 갱신한다.
    ///
    /// **한 건이라도 건질 때까지 이어 읽는 것이 요점이다.** 한 페이지가 통째로 걸러지면
    /// 목록에 새 셀이 안 생겨 다음 페이지를 부를 `.task`가 영영 안 뜬다. 반복 상한을
    /// 두지 않는 이유도 같다 — 상한에 걸려 멈춰도 목록이 안 늘어난 채라 같은 교착이 된다.
    /// 대신 매 회차 토큰을 확인해 새로고침이 끼어들면 그 자리에서 멈춘다.
    private func fetchVisiblePages(
        token: Int, excluding known: Set<UUID>
    ) async throws -> [SwimWorkout] {
        var seen = known
        var collected: [SwimWorkout] = []

        while true {
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: nextCursor)
            guard token == generation else { return collected }

            guard let boundary = page.workouts.last?.startDate else {
                // 빈 페이지는 더 읽을 것이 없다는 뜻이다. 커서가 안 움직이므로
                // mayHaveMore를 믿고 계속 돌면 같은 요청을 무한히 반복한다.
                canLoadMore = false
                return collected
            }
            nextCursor = boundary
            canLoadMore = page.mayHaveMore

            collected += page.workouts.filter { !seen.contains($0.id) && !$0.isEmptyRecord }
            seen.formUnion(page.workouts.map(\.id))

            if !collected.isEmpty || !canLoadMore { return collected }
        }
    }
```

- [ ] **Step 4: 통과하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild clean test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "error:|failed|Executed" /tmp/t.log | tail -20
```
Expected: PASS. 개수가 Task 2 뒤보다 **4개** 늘어야 한다. **`같은_시각_기록만_있어도_진행이_멈추지_않는다`(485행)를 특히 본다** — 커서가 안 움직이는 경우를 헬퍼가 빈 페이지로 끊는지 확인하는 기존 테스트다.

- [ ] **Step 5: 고의로 망가뜨려 본다**

(c)의 `if !collected.isEmpty || !canLoadMore { return collected }`를 `return collected`로 바꾸고(반복 없애기) Step 4를 다시 돌린다.
Expected: `첫_페이지가_전부_감출_기록이면_이어_읽는다`가 **실패**해야 한다. 확인했으면 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/ViewModels/SwimRecordViewModel.swift WooriHaruTests/SwimRecordTests.swift
git commit -m "feat: 감출 기록만 있는 페이지에서 목록이 멈추지 않는다"
```

---

## 마무리 확인

- [ ] 전체 테스트를 `clean test`로 한 번 더 돌려 통과와 **개수(기준 + 10개)**를 확인한다
- [ ] 시뮬레이터로 확인할 것은 없다 — 건강 앱 데이터가 필요한 화면이라 **실기기에서 수영 기록 목록을 열어** 짧은 실수 기록이 사라졌는지, 스크롤이 끝까지 이어지는지 본다
- [ ] `git log --oneline develop..HEAD`로 커밋 5개(설계 문서 1 + 이 계획 1 + 태스크 3)를 확인한다
