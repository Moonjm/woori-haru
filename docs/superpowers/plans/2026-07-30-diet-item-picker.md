# 항목 고르기 화면 개편 · 날짜 스트립 주 이동 (iOS) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `MealItemEditView`를 필라이즈식 3탭 + ⊕ 즉시 담기 + 상세 시트 + (새 끼니일 때만) 다중 선택 구조로 다시 짜고, 하루 화면 날짜 스트립에 좌우 스와이프 주 단위 이동을 넣는다.

**Architecture:** 화면은 「출처(`FoodPickSource`) → 행(`FoodPickRow`) → 상세 시트(`FoodDetailSheet`) → 바구니(`MealItemPickViewModel`)」 네 층으로 나뉜다. 출처는 검색 결과(`Food`, 100g당 값)와 자주 드셨어요(`FrequentItem`, 저장된 절대값) **둘뿐이고 환산 함수가 서로 다르므로** 항목을 만드는 순간까지 출처를 그대로 들고 다닌다. 날짜 스트립은 「보이는 주(`visibleWeekAnchor`)」와 「선택 날짜(`selectedDate`)」를 분리해 스와이프에 네트워크가 붙지 않게 한다.

**Tech Stack:** SwiftUI (iOS 26), `@MainActor @Observable` ViewModel, Swift Testing(`@Test`/`#expect`), `DietServing` 프로토콜 주입, `DragGesture`.

## Global Constraints

- **짝 스펙:** `docs/superpowers/specs/2026-07-30-diet-item-picker-design.md`. 스펙과 이 계획이 어긋나면 **스펙이 이긴다.**
- **백엔드 변경은 없다.** 지금 있는 엔드포인트(`GET /diet/foods`, `GET /diet/items/frequent`, `GET /diet/profile`)와 지금 있는 7개 영양소(열량·탄수·단백·지방·당류·나트륨·식이섬유)로만 만든다. 포화지방·트랜스지방·콜레스테롤, 즐겨찾기, 인기도, 서버 `dataset` 파라미터는 **이 계획 밖**이다.
- **환산은 `NutritionMath` 한 곳에서만 한다.** 검색 결과는 `NutritionMath.item(from:quantityG:)`, 자주 드셨어요는 `NutritionMath.rescaled(_:to:)`. 화면이 직접 곱하지 않는다.
- **주의 영양소 3필드(`sugarG`·`sodiumMg`·`fiberG`)는 모든 새 경로에서 살아 있어야 한다.** 서버는 빠진 값을 검증 오류 없이 `0.0`으로 저장한다. 경로가 늘 때마다 이 확인이 따라붙는다.
- **수량 0을 절대 허용하지 않는다.** 인분 하한 0.5, g 하한 10. 0이 되면 영양소 전체가 0으로 굳는다(기존에 한 번 났던 결함이다).
- **`servingSizeKnown == false`인 `Food`의 `servingSizeG`(200)는 서버가 채운 자리채움값이다.** 기본 수량으로 쓰면 안 되고, 열량 표시도 100g 기준으로 해야 한다.
- **ViewModel은 `@MainActor @Observable final class`**, 서비스는 `DietServing`으로 주입한다.
- **UI는 `Views/Components/Glass`의 기존 컴포넌트를 쓴다** — `GlassCard`, `.glassScreenBackground()`, `.appGlassProminentButton()`, `.glassInputField()`, 색은 `Color.slate*`/`blue*`/`orange*`.
- **주석·커밋 메시지는 한국어**(저장소 관례). 커밋 접두어는 `feat:`/`test:`/`refactor:`.
- **모든 커밋 메시지 마지막 줄:** `Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC`
- **시뮬레이터로 앱을 띄우지 않는다.** UI 확인은 사용자가 실기기로 한다. `xcodebuild test`만 실행한다.

### 테스트 파일 배치 — 스펙에서 한 가지 벗어난다

스펙은 항목 고르기 테스트를 `DietConfirmTests.swift`에 붙이라고 적었다. **`WooriHaruTests/DietPickTests.swift`를 새로 만들어 거기 넣는다.** `DietConfirmTests.swift`는 이미 두 스위트가 든 700줄 파일이고, 이번에 세 스위트(`FoodPickSourceTests`·`FoodDetailViewModelTests`·`MealItemPickViewModelTests`)가 더 붙으면 `-only-testing`으로 좁혀 돌리기도 어려워진다. 기존 관례(「영역별로 나누되 접두어를 `Diet`로 맞춘다」)와도 이쪽이 맞는다. 날짜 스트립 테스트는 스펙대로 `DietDayTests.swift`에 붙인다.

### 테스트 실행

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/<SuiteName> 2>&1 | tail -30
```

전체 실행은 `-only-testing`을 뺀다. 테스트 타깃(`WooriHaruTests`)은 파일시스템 동기화 그룹이라 **새 테스트 파일은 프로젝트 등록이 필요 없다.**

### 파일 등록 절차 (앱 타깃은 자동 동기화가 아니다)

`WooriHaru` 메인 타깃은 클래식 `PBXGroup`이라 **새 `.swift` 파일마다 `WooriHaru.xcodeproj/project.pbxproj`에 4곳을 손으로 넣어야 한다.** 빠뜨리면 "cannot find X in scope"로 빌드가 깨진다. 각 태스크가 쓸 ID는 태스크 안에 적어 뒀다.

1. `/* Begin PBXBuildFile section */` 아래에 한 줄:
   `		DT10030 /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = DT20030 /* Foo.swift */; };`
2. `/* Begin PBXFileReference section */` 아래에 한 줄:
   `		DT20030 /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };`
3. 해당 그룹의 `children = (` 안에 `				DT20030 /* Foo.swift */,`
   그룹 ID — `B40001` Models · `B40003` ViewModels · `DT40001` Views/Diet · `DT40002` Views/Diet/Components.
4. 앱 타깃 Sources 빌드 페이즈 `A60001 /* Sources */`의 `files = (` 안에 `				DT10030 /* Foo.swift in Sources */,`

이번 계획이 새로 쓰는 ID는 **DT10030~DT10034 / DT20030~DT20034**다(기존 최대치는 DT10029/DT20029).

### 실행 순서

**1 → 2 → 3 → 4 → 5** 번호순 그대로다. Task 5가 화면과 호출부를 한꺼번에 갈아 끼우므로 그 앞의 넷은 모두 **기존 코드를 건드리지 않고 새 파일만 더한다** — 각 태스크 끝에서 전체 테스트가 초록이어야 한다.

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `Models/FoodPickSource.swift` (신규) | 고를 수 있는 항목의 두 출처와 그 표시 문구·기본 수량 판정 |
| `Views/Diet/Components/FoodPickRow.swift` (신규) | 세 탭이 공유하는 세로 목록 행 (⊕ + 담김 배지) |
| `ViewModels/FoodDetailViewModel.swift` (신규) | 상세 시트의 단위·수량·영양소 표·일일목표 % |
| `Views/Diet/FoodDetailSheet.swift` (신규) | 상세 시트 화면 |
| `ViewModels/MealItemPickViewModel.swift` (신규) | 모드·탭·필터 칩·검색·바구니·직접 등록 |
| `Views/Diet/MealItemEditView.swift` (전면 교체) | 3탭 고르기 화면. 옛 `MealItemEditViewModel`은 삭제된다 |
| `ViewModels/DietDayViewModel.swift` (수정) | `visibleWeekAnchor` 계열 추가 |
| `ViewModels/MealDetailViewModel.swift` (수정) | `editableItem(matching:)` 추가 |
| `Views/Diet/DietHomeView.swift` (수정) | 월 표시 · 「오늘」 버튼 · 스와이프 |
| `Views/Diet/MealConfirmView.swift` (수정) | 호출부 — 추가는 `.addMany`, 교체는 `.replace` |
| `Views/Diet/MealDetailView.swift` (수정) | 호출부 — 둘 다 한 개 모드 |
| `Services/DietService.swift` (수정) | `searchFoods` `size` 20 → 50 |
| `WooriHaruTests/DietPickTests.swift` (신규) | 출처·상세 시트·고르기 VM 테스트 |
| `WooriHaruTests/DietDayTests.swift` (수정) | 날짜 스트립 테스트 |
| `WooriHaruTests/DietConfirmTests.swift` (수정) | 옛 `MealItemEditViewModelTests` 삭제 |

`Views/Diet/Components/FrequentItemList.swift`는 **그대로 둔다** — `DietStatsView`의 「자주 먹은 음식」 가로 스트립이 쓰고 있고 그쪽 용도에는 맞는다.

---

## Task 1: 날짜 스트립 주 단위 이동

**Files:**
- Modify: `WooriHaru/ViewModels/DietDayViewModel.swift:51-56` (`weekDates`), `:114-118` (`select`)
- Modify: `WooriHaru/Views/Diet/DietHomeView.swift:127-149` (`weekStrip`)
- Test: `WooriHaruTests/DietDayTests.swift` (새 스위트 `DietWeekStripTests`를 파일 끝에 추가)

**Interfaces:**
- Consumes: `DietServing`, `FakeDietService`, `makeDay()`, `makeProfile()` (모두 기존)
- Produces: `DietDayViewModel.visibleWeekAnchor` / `.showPreviousWeek()` / `.showNextWeek()` / `.goToToday()` / `.isViewingSelectedWeek` / `.visibleMonthText`. 뒤 태스크는 이걸 쓰지 않는다 — 이 태스크는 독립이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietDayTests.swift` 맨 끝에 추가한다:

```swift
@MainActor
struct DietWeekStripTests {
    /// 스트립의 기준일과 선택 날짜를 분리한 이유가 전부 여기 있다 — 주를 넘기는 것은
    /// 「보기」이고 조회가 아니다.
    private func makeVM(on dateString: String) -> (DietDayViewModel, FakeDietService) {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: dateString)]
        let date = Date.from(dateString)!
        return (DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher(), date: date), service)
    }

    @Test func 다음_주로_넘기면_보이는_주만_7일_뒤로_간다() async {
        let (vm, _) = makeVM(on: "2026-07-15")   // 수요일
        await vm.load()
        let before = vm.weekDates

        vm.showNextWeek()

        #expect(vm.selectedDate == Date.from("2026-07-15"))
        for (old, new) in zip(before, vm.weekDates) {
            #expect(Calendar.current.dateComponents([.day], from: old, to: new).day == 7)
        }
    }

    @Test func 이전_주로_넘기면_보이는_주만_7일_앞으로_간다() async {
        let (vm, _) = makeVM(on: "2026-07-15")
        await vm.load()
        let before = vm.weekDates

        vm.showPreviousWeek()

        #expect(vm.selectedDate == Date.from("2026-07-15"))
        for (old, new) in zip(before, vm.weekDates) {
            #expect(Calendar.current.dateComponents([.day], from: old, to: new).day == -7)
        }
    }

    /// **스와이프에 네트워크가 붙으면 안 된다.** 주를 세 번 넘기는 동안 조회가 세 번 나가면
    /// 화면이 매번 갈아엎힌다.
    @Test func 주를_넘겨도_서버를_다시_부르지_않는다() async {
        let (vm, service) = makeVM(on: "2026-07-15")
        await vm.load()
        let callCount = service.fetchedDates.count

        vm.showNextWeek()
        vm.showNextWeek()
        vm.showPreviousWeek()

        #expect(service.fetchedDates.count == callCount)
    }

    /// 넘긴 주에 선택 날짜가 없으면 「오늘」 버튼이 떠야 한다.
    @Test func 주를_넘기면_선택한_주를_보고_있지_않다() async {
        let (vm, _) = makeVM(on: "2026-07-15")
        await vm.load()

        #expect(vm.isViewingSelectedWeek)

        vm.showNextWeek()
        #expect(!vm.isViewingSelectedWeek)

        vm.showPreviousWeek()
        #expect(vm.isViewingSelectedWeek)
    }

    /// 주를 넘긴 뒤 날짜를 탭하면 기준일이 그 날짜의 주로 맞춰진다 — 둘이 다시 일치한다.
    @Test func 날짜를_고르면_기준일이_그_주로_맞춰진다() async {
        let (vm, service) = makeVM(on: "2026-07-15")
        service.days = [makeDay(date: "2026-07-15"), makeDay(date: "2026-07-22")]
        await vm.load()

        vm.showNextWeek()
        await vm.select(Date.from("2026-07-22")!)

        #expect(vm.selectedDate == Date.from("2026-07-22"))
        #expect(vm.isViewingSelectedWeek)
        #expect(service.fetchedDates.last == "2026-07-22")
    }

    /// 몇 주를 넘긴 뒤 돌아올 길. 선택과 기준일이 함께 오늘로 돌아온다.
    @Test func 오늘_버튼은_선택과_기준일을_함께_되돌린다() async {
        let (vm, _) = makeVM(on: "2026-07-15")
        await vm.load()

        vm.showNextWeek()
        vm.showNextWeek()
        vm.showNextWeek()
        await vm.goToToday()

        #expect(Calendar.current.isDateInToday(vm.selectedDate))
        #expect(vm.isViewingSelectedWeek)
    }

    /// 스트립 위 월 표시. 주를 넘겨 달이 바뀌면 표시도 따라간다.
    @Test func 월_표시는_보이는_주를_따라간다() async {
        let (vm, _) = makeVM(on: "2026-07-29")   // 수요일
        await vm.load()

        #expect(vm.visibleMonthText == "7월")

        vm.showNextWeek()   // 8/2~8/8 주
        #expect(vm.visibleMonthText == "8월")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietWeekStripTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `value of type 'DietDayViewModel' has no member 'showNextWeek'`

- [ ] **Step 3: ViewModel에 보이는 주를 넣는다**

`WooriHaru/ViewModels/DietDayViewModel.swift`의 `weekDates`(51~56줄)를 아래로 **교체**한다:

```swift
    /// 스트립에 보이는 주(일~토). **`selectedDate`가 아니라 `visibleWeekAnchor`에서 파생된다** —
    /// 좌우 스와이프로 주를 넘길 때 조회가 나가면 안 되고, 선택 날짜는 탭했을 때만 바뀐다.
    var weekDates: [Date] {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: visibleWeekAnchor)?.start else {
            return [visibleWeekAnchor]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// 「7월」 — 스트립 위에 붙는다. 주를 넘겨 달이 바뀌면 여기가 따라간다.
    var visibleMonthText: String {
        "\(Calendar.current.component(.month, from: visibleWeekAnchor))월"
    }

    /// 보이는 주에 선택 날짜가 있는가. 없으면 화면이 「오늘」 버튼을 띄운다 —
    /// 몇 주를 넘긴 뒤 돌아올 길이 필요하다.
    var isViewingSelectedWeek: Bool {
        Calendar.current.isDate(visibleWeekAnchor, equalTo: selectedDate, toGranularity: .weekOfYear)
    }

    /// 보이는 주만 옮긴다. **네트워크 호출이 없다.**
    func showPreviousWeek() { shiftVisibleWeek(by: -7) }
    func showNextWeek() { shiftVisibleWeek(by: 7) }

    private func shiftVisibleWeek(by days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: visibleWeekAnchor) else { return }
        visibleWeekAnchor = moved
    }

    /// 몇 주를 넘긴 뒤 돌아온다 — 선택과 기준일을 함께 오늘로 되돌린다.
    func goToToday() async {
        await select(Date())
    }
```

`selectedDate` 선언(14줄) 바로 아래에 저장 프로퍼티를 더한다:

```swift
    /// 스트립에 보이는 주의 기준일. **`selectedDate`와 분리한다** — 스와이프는 「보기」의
    /// 변경이고 조회가 아니다. 둘이 붙어 있으면 주를 세 번 넘기는 동안 조회가 세 번 나간다.
    private(set) var visibleWeekAnchor: Date
```

`init`에서 `self.selectedDate = date` 바로 아래에 한 줄 더한다:

```swift
        self.visibleWeekAnchor = date
```

`select(_:)`(114~118줄)를 아래로 **교체**한다:

```swift
    func select(_ date: Date) async {
        // 조회를 건너뛰는 경우에도 기준일은 맞춰야 한다 — 주를 넘긴 뒤 이미 선택돼 있는
        // 날짜를 다시 탭했을 때 기준일이 그대로면 「오늘」 버튼이 계속 남는다.
        visibleWeekAnchor = date
        guard !Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return }
        selectedDate = date
        await load()
    }
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietWeekStripTests 2>&1 | tail -30`
Expected: PASS (7 tests)

- [ ] **Step 5: 고의 파손 확인**

테스트가 진짜로 판별하는지 확인한다. `select(_:)`의 `visibleWeekAnchor = date` 줄을 **주석 처리**하고 위 명령을 다시 돌린다.
Expected: `날짜를_고르면_기준일이_그_주로_맞춰진다` 실패. 확인 후 주석을 되돌린다.

이어서 `shiftVisibleWeek(by:)`의 본문을 `visibleWeekAnchor = selectedDate`로 바꿔 다시 돌린다.
Expected: `다음_주로_넘기면...`·`주를_넘기면_선택한_주를...` 실패. 확인 후 되돌린다.

- [ ] **Step 6: 화면에 월 표시·「오늘」 버튼·스와이프를 붙인다**

`WooriHaru/Views/Diet/DietHomeView.swift`의 `weekStrip`(127~149줄)을 아래로 **교체**한다:

```swift
    private var weekStrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text(vm.visibleMonthText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.slate500)

                Spacer()

                // 몇 주를 넘긴 뒤 돌아올 길. 보이는 주에 선택 날짜가 있으면 필요 없다.
                if !vm.isViewingSelectedWeek {
                    Button("오늘") {
                        Task { await vm.goToToday() }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.blue500)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 4) {
                ForEach(vm.weekDates, id: \.timeIntervalSince1970) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: vm.selectedDate)
                    Button {
                        Task { await vm.select(date) }
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // 빈 곳에서 시작한 스와이프도 받아야 한다 — 날짜 버튼 사이 여백이 넓다.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    // 바깥 `ScrollView`의 세로 스크롤과 싸우지 않게, 가로 이동이 임계값을
                    // 넘고 **세로 이동보다 클 때만** 주를 넘긴다.
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 50, abs(dx) > abs(dy) else { return }
                    if dx < 0 {
                        vm.showNextWeek()
                    } else {
                        vm.showPreviousWeek()
                    }
                }
        )
    }
```

- [ ] **Step 7: 전체 테스트를 돌린다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전부 PASS (기존 181개 + 7개 = 188개)

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/DietDayViewModel.swift WooriHaru/Views/Diet/DietHomeView.swift WooriHaruTests/DietDayTests.swift
git commit -m "$(cat <<'EOF'
feat: 날짜 스트립을 좌우 스와이프로 주 단위 이동시킨다

보이는 주(visibleWeekAnchor)와 선택 날짜(selectedDate)를 분리해 스와이프에
네트워크가 붙지 않게 한다. 넘긴 주에 선택 날짜가 없으면 「오늘」 버튼을 띄운다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
)"
```

---

## Task 2: 항목 출처(`FoodPickSource`)와 목록 행(`FoodPickRow`)

**Files:**
- Create: `WooriHaru/Models/FoodPickSource.swift`
- Create: `WooriHaru/Views/Diet/Components/FoodPickRow.swift`
- Create: `WooriHaruTests/DietPickTests.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `Food`, `FrequentItem`, `MealItemRequest`, `NutritionMath`, `Double.trimmedText`, `FoodDataset.badge` (모두 기존)
- Produces:
  - `enum FoodPickSource: Identifiable, Hashable { case food(Food); case frequent(FrequentItem) }`
  - 프로퍼티 `id: String` · `name: String` · `badge: String?` · `detailText: String` · `displayKcal: Double` · `kcalText: String` · `quickAddItem: MealItemRequest?` · `canQuickAdd: Bool`
  - `struct FoodPickRow: View { let source: FoodPickSource; var pickedCount: Int = 0; var onTapRow: () -> Void; var onQuickAdd: () -> Void }`
  - Task 3·4·5가 전부 이 타입을 쓴다.

**pbxproj ID:** `FoodPickSource.swift` → `DT10030`/`DT20030`, 그룹 `B40001 /* Models */`. `FoodPickRow.swift` → `DT10031`/`DT20031`, 그룹 `DT40002 /* Components */`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietPickTests.swift`를 새로 만든다:

```swift
import Testing
import Foundation
@testable import WooriHaru

// MARK: - 픽스처

func makePickFood(
    _ name: String = "제육볶음",
    code: String = "D9",
    dataset: FoodDataset = .dish,
    known: Bool = true,
    serving: Double = 250
) -> Food {
    Food(
        code: code, name: name, dataset: dataset,
        servingSizeG: serving, servingSizeKnown: known,
        kcalPer100g: 150, carbsPer100g: 12, proteinPer100g: 10, fatPer100g: 7,
        sugarPer100g: 3, sodiumMgPer100g: 400, fiberPer100g: 1.5
    )
}

func makeFrequent(
    _ name: String = "사과",
    code: String? = "R1",
    quantityG: Double = 200,
    count: Int = 7
) -> FrequentItem {
    FrequentItem(
        foodName: name, foodCode: code, quantityG: quantityG, kcal: 104,
        carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
        source: .dbMatched, count: count, lastEatenOn: "2026-07-29"
    )
}

// MARK: - 출처

struct FoodPickSourceTests {
    /// 「1인분 (250g)」과 **1인분 기준 열량**. 150kcal/100g × 250g = 375kcal.
    @Test func 일인분을_아는_음식은_일인분_기준으로_보여준다() {
        let source = FoodPickSource.food(makePickFood(known: true, serving: 250))

        #expect(source.name == "제육볶음")
        #expect(source.detailText == "1인분 (250g)")
        #expect(source.kcalText == "375kcal")
    }

    /// **모르는 항목은 100g 기준이다.** 서버가 채운 200g으로 계산한 열량을 먼저 보여주면
    /// 그럴듯하게 틀린 수치를 각인시킨다 — 150kcal/100g × 200g = 300kcal가 아니라 150kcal다.
    @Test func 일인분을_모르는_음식은_100g_기준으로_보여준다() {
        let source = FoodPickSource.food(makePickFood("달걀", known: false, serving: 200))

        #expect(source.detailText == "100g 기준")
        #expect(source.kcalText == "150kcal")
    }

    /// 자주 드셨어요는 지난번 수량과 빈도를 쓴다.
    @Test func 자주_드셨어요는_지난번_수량과_빈도를_보여준다() {
        let source = FoodPickSource.frequent(makeFrequent(quantityG: 200, count: 7))

        #expect(source.detailText == "200g · 7회")
        #expect(source.kcalText == "104kcal")
    }

    /// 조리 음식은 기본값이라 배지를 달지 않고, 원재료·가공식품만 단다.
    @Test func 배지는_데이터셋이_있을_때만_붙는다() {
        #expect(FoodPickSource.food(makePickFood(dataset: .dish)).badge == nil)
        #expect(FoodPickSource.food(makePickFood(dataset: .raw)).badge == "원재료")
        #expect(FoodPickSource.food(makePickFood(dataset: .processed)).badge == "가공식품")
        #expect(FoodPickSource.frequent(makeFrequent()).badge == nil)
    }

    /// **⊕가 갈리는 자리다.** 1인분을 알면 그대로 담기고, 모르면 담을 기본 수량이 없다.
    @Test func 일인분을_모르는_음식은_즉시_담을_수_없다() {
        #expect(FoodPickSource.food(makePickFood(known: true)).canQuickAdd)
        #expect(FoodPickSource.food(makePickFood(known: false)).quickAddItem == nil)
        // 자주 드셨어요는 지난번 수량이 딸려 오므로 항상 담긴다.
        #expect(FoodPickSource.frequent(makeFrequent()).canQuickAdd)
    }

    /// **주의 영양소 3필드가 ⊕ 즉시 담기에서도 살아 있어야 한다** — 서버는 빠진 값을
    /// 검증 오류 없이 0으로 저장한다.
    @Test func 즉시_담기는_주의_영양소까지_환산한다() throws {
        let item = try #require(FoodPickSource.food(makePickFood(known: true, serving: 250)).quickAddItem)

        #expect(item.quantityG == 250)
        #expect(item.kcal == 375)
        #expect(item.sugarG == 7.5)
        #expect(item.sodiumMg == 1000)
        #expect(item.fiberG == 3.75)
        #expect(item.foodCode == "D9")
        #expect(item.source == .dbMatched)
    }

    /// 자주 드셨어요는 **다시 계산하지 않는다** — 저장된 값이 그대로 온다.
    @Test func 자주_드셨어요_즉시_담기는_저장된_값을_그대로_쓴다() throws {
        let item = try #require(FoodPickSource.frequent(makeFrequent(quantityG: 200)).quickAddItem)

        #expect(item.quantityG == 200)
        #expect(item.kcal == 104)
        #expect(item.sugarG == 21)
        #expect(item.sodiumMg == 2)
        #expect(item.fiberG == 4.8)
    }

    /// 목록에서 서로 다른 행으로 구분돼야 한다 — 코드는 데이터셋 안에서만 유일하다.
    @Test func 출처가_다르면_아이디가_다르다() {
        let food = FoodPickSource.food(makePickFood(code: "X1", dataset: .dish))
        let sameCodeOtherDataset = FoodPickSource.food(makePickFood(code: "X1", dataset: .raw))
        let frequent = FoodPickSource.frequent(makeFrequent(code: "X1"))

        #expect(food.id != sameCodeOtherDataset.id)
        #expect(food.id != frequent.id)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/FoodPickSourceTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'FoodPickSource' in scope`

- [ ] **Step 3: `FoodPickSource`를 만든다**

`WooriHaru/Models/FoodPickSource.swift`:

```swift
import Foundation

/// 고를 수 있는 항목의 **두 출처**. 검색 결과(`Food`)는 100g당 값이고 자주 드셨어요
/// (`FrequentItem`)는 저장된 절대값이라 **환산 함수가 서로 다르다** —
/// 앞은 `NutritionMath.item(from:quantityG:)`, 뒤는 `NutritionMath.rescaled(_:to:)`.
/// 그래서 항목을 만드는 순간까지 어느 쪽인지 그대로 들고 다닌다.
enum FoodPickSource: Identifiable, Hashable {
    case food(Food)
    case frequent(FrequentItem)

    /// 검색 결과와 자주 드셨어요에 같은 식품이 있을 수 있으므로 접두어로 갈라 둔다.
    var id: String {
        switch self {
        case let .food(food): "food-\(food.id)"
        case let .frequent(item): "frequent-\(item.id)"
        }
    }

    var name: String {
        switch self {
        case let .food(food): food.name
        case let .frequent(item): item.foodName
        }
    }

    /// 조리 음식과 포장 제품이 섞여 나오므로 목록에서 구분해 보여준다. 자주 드셨어요에는
    /// `dataset`이 없다 — 저장된 항목이라 어느 데이터셋에서 왔는지 응답에 없다.
    var badge: String? {
        switch self {
        case let .food(food): food.dataset.badge
        case .frequent: nil
        }
    }

    /// 행 둘째 줄. 「1인분 (250g)」 · 「100g 기준」 · 「200g · 7회」
    var detailText: String {
        switch self {
        case let .food(food):
            food.servingSizeKnown ? "1인분 (\(food.servingSizeG.trimmedText)g)" : "100g 기준"
        case let .frequent(item):
            "\(item.quantityG.trimmedText)g · \(item.countText)"
        }
    }

    /// 행에 보이는 열량. **1인분을 모르면 100g 기준으로 낸다** — 서버가 채운 200g
    /// 자리채움값으로 계산한 열량을 먼저 보여주면 그럴듯하게 틀린 수치가 각인된다.
    var displayKcal: Double {
        switch self {
        case let .food(food):
            NutritionMath.scale(
                per100g: food.kcalPer100g,
                quantityG: food.servingSizeKnown ? food.servingSizeG : 100
            )
        case let .frequent(item):
            item.kcal
        }
    }

    var kcalText: String { "\(Int(displayKcal.rounded()))kcal" }

    /// ⊕가 그대로 담을 항목. **1인분을 모르는 검색 결과는 nil이다** — 채워 넣을 기본 수량이
    /// 없으므로 화면이 상세 시트를 열어야 한다. 200g은 1800g과 달리 그럴듯해 보여서
    /// 사용자가 고치지 않는다.
    var quickAddItem: MealItemRequest? {
        switch self {
        case let .food(food):
            guard let quantity = NutritionMath.defaultQuantity(for: food) else { return nil }
            return NutritionMath.item(from: food, quantityG: quantity)
        case let .frequent(item):
            return NutritionMath.request(from: item)
        }
    }

    var canQuickAdd: Bool { quickAddItem != nil }
}
```

`project.pbxproj`에 `DT10030`/`DT20030`을 「파일 등록 절차」대로 4곳 넣는다(그룹은 `B40001 /* Models */`).

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/FoodPickSourceTests 2>&1 | tail -30`
Expected: PASS (8 tests)

- [ ] **Step 5: 고의 파손 확인**

`displayKcal`의 `food.servingSizeKnown ? food.servingSizeG : 100`을 `food.servingSizeG`로 바꾸고 다시 돌린다.
Expected: `일인분을_모르는_음식은_100g_기준으로_보여준다` 실패(300kcal). 확인 후 되돌린다.

- [ ] **Step 6: `FoodPickRow`를 만든다**

`WooriHaru/Views/Diet/Components/FoodPickRow.swift`:

```swift
import SwiftUI

/// 항목 고르기 세 탭이 공유하는 세로 목록 행.
///
/// **⊕와 행 탭이 다른 동작이다** — ⊕는 기본 수량으로 즉시 담고, 행을 누르면 상세 시트가
/// 열린다. 1인분을 모르는 항목은 ⊕도 상세 시트를 열어야 하는데, 그 판단은 화면이 아니라
/// `FoodPickSource.quickAddItem`이 한다.
struct FoodPickRow: View {
    let source: FoodPickSource
    /// 여러 개 모드에서 이미 담은 횟수. 0이면 배지를 그리지 않는다.
    var pickedCount: Int = 0
    var onTapRow: () -> Void
    var onQuickAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTapRow) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(source.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.slate700)
                            .lineLimit(1)

                        if let badge = source.badge {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(Color.slate500)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.slate100, in: Capsule())
                        }

                        if pickedCount > 0 {
                            Text("담김 \(pickedCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue500, in: Capsule())
                        }
                    }

                    Text(source.detailText)
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(source.kcalText)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate500)

            Button(action: onQuickAdd) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(Color.blue500)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(source.name) 담기")
        }
        .padding(.vertical, 8)
    }
}
```

`project.pbxproj`에 `DT10031`/`DT20031`을 넣는다(그룹은 `DT40002 /* Components */`).

- [ ] **Step 7: 전체 테스트를 돌린다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전부 PASS (196개)

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/Models/FoodPickSource.swift WooriHaru/Views/Diet/Components/FoodPickRow.swift WooriHaruTests/DietPickTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat: 항목 고르기 출처 타입과 목록 행을 만든다

검색 결과와 자주 드셨어요를 FoodPickSource 하나로 묶되 환산 함수는 갈라 둔다.
1인분을 모르는 항목은 담을 기본 수량이 없어 quickAddItem이 nil이다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
)"
```

---

## Task 3: 상세 시트 — 단위·수량·영양소 표

**Files:**
- Create: `WooriHaru/ViewModels/FoodDetailViewModel.swift`
- Create: `WooriHaru/Views/Diet/FoodDetailSheet.swift`
- Modify: `WooriHaruTests/DietPickTests.swift` (스위트 추가)
- Modify: `WooriHaru.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `FoodPickSource`(Task 2), `NutritionMath`, `MealItemRequest`, `Double.trimmedText`
- Produces:
  - `FoodDetailViewModel(source: FoodPickSource, targetKcal: Int? = nil)`
  - `enum FoodDetailViewModel.Unit { case serving, gram }`, `struct FoodDetailViewModel.NutrientRow`
  - 프로퍼티 `unit` · `servings` · `gramText` · `quantityG: Double?` · `item: MealItemRequest?` · `canAdd` · `kcalText` · `dailyGoalPercentText: String?` · `nutrientRows: [NutrientRow]` · `showsUnitPicker` · `showsQuickGramChips` · `servingSizeText: String?` · `servingsText` · `servingSizeUnknownHint: String?`
  - 메서드 `increaseServings()` · `decreaseServings()` · `increaseGram()` · `decreaseGram()` · `selectQuickGram(_:)` · `setUnit(_:)`
  - 상수 `FoodDetailViewModel.quickGrams: [Double] = [50, 100, 200]`
  - `struct FoodDetailSheet: View { init(source:targetKcal:onAdd:) }`
  - Task 5의 `MealItemEditView`가 `FoodDetailSheet`를 연다.

**pbxproj ID:** `FoodDetailViewModel.swift` → `DT10032`/`DT20032`, 그룹 `B40003 /* ViewModels */`. `FoodDetailSheet.swift` → `DT10033`/`DT20033`, 그룹 `DT40001 /* Diet */`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietPickTests.swift` 끝에 추가한다:

```swift
@MainActor
struct FoodDetailViewModelTests {
    /// 1인분을 아는 항목은 1인분 모드로 뜨고 수량이 1인분이다.
    @Test func 일인분을_알면_인분_모드로_열린다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        #expect(vm.unit == .serving)
        #expect(vm.servings == 1)
        #expect(vm.servingsText == "1인분")
        #expect(vm.servingSizeText == "1인분 = 250g")
        #expect(vm.showsUnitPicker)
        #expect(vm.quantityG == 250)
        #expect(try #require(vm.item).kcal == 375)
    }

    /// **수량이 인분 수에 비례한다** — `quantityG = servingSizeG × 인분수`이고 영양소 7개가 따라온다.
    @Test func 인분_수를_올리면_수량과_영양소가_함께_커진다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        vm.increaseServings()   // 1.5인분

        #expect(vm.servings == 1.5)
        #expect(vm.servingsText == "1.5인분")
        #expect(vm.quantityG == 375)

        let item = try #require(vm.item)
        #expect(item.quantityG == 375)
        #expect(item.kcal == 562.5)
        #expect(item.carbsG == 45)
        #expect(item.proteinG == 37.5)
        #expect(item.fatG == 26.25)
        #expect(item.sugarG == 11.25)
        #expect(item.sodiumMg == 1500)
        #expect(item.fiberG == 5.625)
    }

    /// **「반 그릇」이 가장 흔한 조정이다.** 한 번 내리면 0.5인분 = 125g, 열량도 절반.
    @Test func 인분은_0점5씩_움직이고_0점5_아래로_내려가지_않는다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        vm.decreaseServings()

        #expect(vm.servings == 0.5)
        #expect(vm.servingsText == "0.5인분")
        #expect(vm.quantityG == 125)
        #expect(try #require(vm.item).kcal == 187.5)

        // 하한을 넘어 내려가면 안 된다 — 0이 되면 영양소가 전부 0으로 굳는다.
        vm.decreaseServings()
        vm.decreaseServings()
        #expect(vm.servings == 0.5)
        #expect(try #require(vm.item).kcal == 187.5)
    }

    /// **1인분을 모르면 g 모드로 고정하고 수량을 비운다.** 단위 선택도 감춘다.
    @Test func 일인분을_모르면_g_모드로_고정되고_수량이_비어_있다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false, serving: 200)))

        #expect(vm.unit == .gram)
        #expect(vm.gramText.isEmpty)
        #expect(!vm.showsUnitPicker)
        #expect(vm.servingSizeText == nil)
        #expect(vm.servingSizeUnknownHint != nil)
        #expect(vm.quantityG == nil)
        #expect(vm.item == nil)
        #expect(!vm.canAdd)
    }

    /// **빠른 선택 칩** — 1인분을 모르는 항목의 타이핑을 대부분 없앤다.
    @Test func 빠른_선택_칩을_누르면_수량과_영양소가_따라온다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false, serving: 200)))

        #expect(vm.showsQuickGramChips)
        #expect(FoodDetailViewModel.quickGrams == [50, 100, 200])

        vm.selectQuickGram(100)

        #expect(vm.gramText == "100")
        #expect(vm.quantityG == 100)
        let item = try #require(vm.item)
        #expect(item.kcal == 150)
        #expect(item.sodiumMg == 400)
        #expect(item.fiberG == 1.5)
    }

    /// **1인분 모드에서는 칩이 안 보인다** — 1인분을 아는 항목의 화면을 어지럽히지 않는다.
    @Test func 인분_모드에서는_빠른_선택_칩이_보이지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        #expect(vm.unit == .serving)
        #expect(!vm.showsQuickGramChips)

        vm.setUnit(.gram)
        #expect(vm.showsQuickGramChips)
    }

    /// g 스테퍼는 ±25이고 25 아래로 내려가지 않는다.
    @Test func g_스테퍼는_25씩_움직이고_25_아래로_내려가지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false)))
        vm.selectQuickGram(50)

        vm.increaseGram()
        #expect(vm.gramText == "60")

        vm.decreaseGram()
        vm.decreaseGram()
        #expect(vm.gramText == "40")

        vm.selectQuickGram(50)
        for _ in 0..<10 { vm.decreaseGram() }
        #expect(vm.gramText == "10")
    }

    /// 단위를 바꿔도 숫자가 튀지 않는다 — 지금 수량을 옮겨 담는다.
    @Test func 단위를_바꾸면_지금_수량이_옮겨진다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        vm.increaseServings()       // 1.5인분 = 375g

        vm.setUnit(.gram)
        #expect(vm.gramText == "375")

        vm.selectQuickGram(200)     // 200g = 0.8인분 → 가장 가까운 0.5 배수는 1.0
        vm.setUnit(.serving)
        #expect(vm.servings == 1)
        #expect(vm.quantityG == 250)
    }

    /// **자주 드셨어요는 저장된 절대값뿐이라 1인분 개념이 없다** — 지난번 수량이 채워진
    /// g 모드로 뜨고, 수량을 바꾸면 비례 환산한다(100g당 값이 남아 있지 않다).
    @Test func 자주_드셨어요는_지난번_수량의_g_모드로_열리고_비례_환산한다() throws {
        let vm = FoodDetailViewModel(source: .frequent(makeFrequent(quantityG: 200)))

        #expect(vm.unit == .gram)
        #expect(vm.gramText == "200")
        #expect(!vm.showsUnitPicker)
        #expect(try #require(vm.item).kcal == 104)

        vm.selectQuickGram(100)

        let halved = try #require(vm.item)
        #expect(halved.quantityG == 100)
        #expect(halved.kcal == 52)
        #expect(halved.sugarG == 10.5)
        #expect(halved.sodiumMg == 1)
        #expect(halved.fiberG == 2.4)
    }

    /// **프로필이 없으면 감춘다** — 목표가 없으면 비율에 의미가 없다.
    @Test func 일일목표_배지는_목표가_있을_때만_보인다() {
        let withTarget = FoodDetailViewModel(
            source: .food(makePickFood(known: true, serving: 250)), targetKcal: 2509
        )
        // 375 / 2509 = 14.9% → 15%
        #expect(withTarget.dailyGoalPercentText == "일일목표 15%")

        let withoutTarget = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        #expect(withoutTarget.dailyGoalPercentText == nil)
    }

    /// 영양소 표는 7줄이다 — 참고 화면에 없는 **식이섬유**가 우리에게는 있다.
    @Test func 영양소_표는_당류를_탄수화물_아래_들여쓴다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        let rows = vm.nutrientRows
        #expect(rows.map(\.name) == ["탄수화물", "당류", "단백질", "지방", "나트륨", "식이섬유"])
        #expect(rows[1].isSub)
        #expect(!rows[0].isSub)
        #expect(rows[0].valueText == "30g")
        #expect(rows[1].valueText == "7.5g")
        #expect(rows[4].valueText == "1,000mg")
        #expect(rows[5].valueText == "3.8g")
        #expect(vm.kcalText == "375kcal")
    }

    /// **주의 영양소 3필드가 상세 시트 경로에서도 살아 있어야 한다.**
    @Test func 상세_시트에서_담아도_주의_영양소가_남는다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        vm.setUnit(.gram)
        vm.selectQuickGram(100)

        let item = try #require(vm.item)
        #expect(item.sugarG == 3)
        #expect(item.sodiumMg == 400)
        #expect(item.fiberG == 1.5)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/FoodDetailViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'FoodDetailViewModel' in scope`

- [ ] **Step 3: `FoodDetailViewModel`을 만든다**

`WooriHaru/ViewModels/FoodDetailViewModel.swift`:

```swift
import Foundation

/// 상세 시트 — 수량·단위를 조절하고 담기 전에 영양소를 미리 본다.
///
/// **출처마다 환산 함수가 다르다.** 검색 결과는 100g당 값에서 계산하고
/// (`NutritionMath.item(from:quantityG:)`), 자주 드셨어요는 저장된 절대값을 비례 환산한다
/// (`NutritionMath.rescaled`). 그래서 수량이 바뀔 때마다 **출처에서 새로 만든다** — 이미
/// 만들어 둔 항목을 고쳐 쓰면 조작할 때마다 환산 오차가 쌓인다.
@MainActor
@Observable
final class FoodDetailViewModel {
    enum Unit: String, CaseIterable, Identifiable {
        case serving, gram

        var id: String { rawValue }
        var label: String {
            switch self {
            case .serving: "1인분"
            case .gram: "g"
            }
        }
    }

    struct NutrientRow: Identifiable, Equatable {
        let name: String
        let valueText: String
        /// 탄수화물 아래 당류처럼 한 단계 들여쓰는 줄
        let isSub: Bool

        var id: String { name }
    }

    /// g 모드 빠른 선택. **1인분을 모르는 항목은 지금 반드시 타이핑해야 하는데** 검색 결과의
    /// 상당수가 여기 해당한다(원재료 전부·가공식품 31%·음식 21%). 칩 셋이 그 타이핑을 없앤다.
    static let quickGrams: [Double] = [50, 100, 200]

    /// 인분 스테퍼 한 칸과 하한. 「반 그릇」이 실제로 가장 흔한 조정이다.
    static let servingStep: Double = 0.5
    static let minimumServings: Double = 0.5
    /// g 스테퍼 한 칸과 하한. **0으로 내려가면 영양소가 전부 0으로 굳는다.**
    static let gramStep: Double = 25
    static let minimumGram: Double = 25

    let source: FoodPickSource
    private(set) var unit: Unit
    private(set) var servings: Double = 1
    /// g 모드 수량. 직접 입력도 되므로 문자열로 들고 있는다.
    var gramText: String

    /// 「일일목표 N%」의 분모. 프로필이 없으면 nil이고 배지를 감춘다.
    private let targetKcal: Int?

    init(source: FoodPickSource, targetKcal: Int? = nil) {
        self.source = source
        self.targetKcal = targetKcal

        switch source {
        case let .food(food) where food.servingSizeKnown:
            unit = .serving
            gramText = food.servingSizeG.trimmedText
        case .food:
            // 1인분을 모르면 g 모드로 고정하고 수량을 비운다 — 서버가 채운 200g은
            // 그럴듯해 보여서 사용자가 고치지 않는다.
            unit = .gram
            gramText = ""
        case let .frequent(item):
            // 저장된 절대값뿐이라 1인분 개념이 없다. 지난번 수량으로 채운다.
            unit = .gram
            gramText = item.quantityG.trimmedText
        }
    }

    // MARK: - 단위

    /// 1인분 크기를 아는 항목만 단위를 고를 수 있다.
    var servingSizeG: Double? {
        guard case let .food(food) = source, food.servingSizeKnown else { return nil }
        return food.servingSizeG
    }

    /// **1인분을 모르면 단위 선택 자체를 감춘다.**
    var showsUnitPicker: Bool { servingSizeG != nil }

    /// **g 모드에서만 보인다** — 1인분을 아는 항목의 화면을 어지럽히지 않는다.
    var showsQuickGramChips: Bool { unit == .gram }

    /// 「1인분 = 250g」
    var servingSizeText: String? {
        servingSizeG.map { "1인분 = \($0.trimmedText)g" }
    }

    var servingSizeUnknownHint: String? {
        guard case let .food(food) = source, !food.servingSizeKnown else { return nil }
        return "1인분 정보 없음 — 드신 양을 넣어 주세요"
    }

    /// 「1.5인분」
    var servingsText: String { "\(servings.trimmedText)인분" }

    // MARK: - 수량

    /// 지금 담길 수량. 비어 있거나 0 이하면 nil이고 「추가하기」가 눌리지 않는다.
    var quantityG: Double? {
        switch unit {
        case .serving:
            guard let servingSizeG else { return nil }
            let quantity = servingSizeG * servings
            return quantity > 0 ? quantity : nil
        case .gram:
            guard let quantity = Double(gramText), quantity > 0 else { return nil }
            return quantity
        }
    }

    func increaseServings() { servings += Self.servingStep }

    /// **0.5 아래로 내려가지 않는다** — 0이 되면 영양소가 전부 0으로 굳는다.
    func decreaseServings() {
        servings = max(Self.minimumServings, servings - Self.servingStep)
    }

    func increaseGram() { setGram((currentGram ?? 0) + Self.gramStep) }
    func decreaseGram() { setGram((currentGram ?? Self.minimumGram) - Self.gramStep) }
    func selectQuickGram(_ gram: Double) { setGram(gram) }

    private var currentGram: Double? { Double(gramText) }

    private func setGram(_ value: Double) {
        gramText = max(Self.minimumGram, value).trimmedText
    }

    /// 단위를 바꾼다. **숫자가 튀지 않게 지금 수량을 옮겨 담는다.** g에서 인분으로 갈 때는
    /// 가장 가까운 0.5 배수로 맞춘다 — 1인분 크기를 아는 항목에서만 가능하다.
    func setUnit(_ newUnit: Unit) {
        guard newUnit != unit, let servingSizeG else { return }
        switch newUnit {
        case .gram:
            gramText = (servingSizeG * servings).trimmedText
        case .serving:
            let gram = currentGram ?? servingSizeG
            servings = max(Self.minimumServings, ((gram / servingSizeG) * 2).rounded() / 2)
        }
        unit = newUnit
    }

    // MARK: - 담을 항목

    /// 지금 수량으로 담을 항목. **출처에 맞는 환산 함수를 쓴다.**
    var item: MealItemRequest? {
        guard let quantityG else { return nil }
        switch source {
        case let .food(food):
            return NutritionMath.item(from: food, quantityG: quantityG)
        case let .frequent(frequent):
            return NutritionMath.rescaled(NutritionMath.request(from: frequent), to: quantityG)
        }
    }

    var canAdd: Bool { item != nil }

    var kcalText: String { "\(Int((item?.kcal ?? 0).rounded()))kcal" }

    /// **프로필이 없으면 감춘다** — 목표가 없으면 비율에 의미가 없다.
    var dailyGoalPercentText: String? {
        guard let targetKcal, targetKcal > 0, let item else { return nil }
        return "일일목표 \(Int((item.kcal / Double(targetKcal) * 100).rounded()))%"
    }

    /// 참고 화면에 없는 **식이섬유**가 우리에게는 있어 한 줄이 더 붙는다.
    var nutrientRows: [NutrientRow] {
        guard let item else { return [] }
        return [
            NutrientRow(name: "탄수화물", valueText: formattedGram(item.carbsG), isSub: false),
            NutrientRow(name: "당류", valueText: formattedGram(item.sugarG), isSub: true),
            NutrientRow(name: "단백질", valueText: formattedGram(item.proteinG), isSub: false),
            NutrientRow(name: "지방", valueText: formattedGram(item.fatG), isSub: false),
            NutrientRow(name: "나트륨", valueText: "\(Int(item.sodiumMg.rounded()).formatted())mg", isSub: false),
            NutrientRow(name: "식이섬유", valueText: formattedGram(item.fiberG), isSub: false)
        ]
    }

    /// 환산 결과는 `30.000000000000004`처럼 나올 수 있다 — 소수 첫째 자리에서 끊고
    /// 정수면 소수점을 뗀다(`Double.trimmedText`는 끊어 주지 않는다).
    private func formattedGram(_ value: Double) -> String {
        "\(((value * 10).rounded() / 10).trimmedText)g"
    }
}
```

`project.pbxproj`에 `DT10032`/`DT20032`를 넣는다(그룹은 `B40003 /* ViewModels */`).

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/FoodDetailViewModelTests 2>&1 | tail -30`
Expected: PASS (12 tests)

- [ ] **Step 5: 고의 파손 확인**

`decreaseServings()`의 `max(Self.minimumServings, ...)`를 `servings - Self.servingStep`으로 바꿔 다시 돌린다.
Expected: `인분은_0점5씩_움직이고_0점5_아래로_내려가지_않는다` 실패. 확인 후 되돌린다.

이어서 `item`의 `.frequent` 분기를 `NutritionMath.item(from:)`이 아닌 `NutritionMath.request(from: frequent)`(수량 무시)로 바꿔 다시 돌린다.
Expected: `자주_드셨어요는_지난번_수량의_g_모드로_열리고_비례_환산한다` 실패. 확인 후 되돌린다.

- [ ] **Step 6: `FoodDetailSheet`을 만든다**

`WooriHaru/Views/Diet/FoodDetailSheet.swift`:

```swift
import SwiftUI

/// 상세 시트 — 수량·단위를 조절하고 「추가하기」로 담는다.
///
/// **1인분을 모르는 항목이 여기로 온다.** 목록의 ⊕가 조용히 담지 못하는 경우가 곧 이 화면이
/// 필요한 경우다(검색 결과의 상당수가 여기 해당한다).
struct FoodDetailSheet: View {
    var onAdd: (MealItemRequest) -> Void

    @State private var vm: FoodDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        source: FoodPickSource,
        targetKcal: Int? = nil,
        onAdd: @escaping (MealItemRequest) -> Void
    ) {
        self.onAdd = onAdd
        _vm = State(initialValue: FoodDetailViewModel(source: source, targetKcal: targetKcal))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassTokens.cardSpacing) {
                    quantityCard
                    nutritionCard
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let item = vm.item else { return }
                    onAdd(item)
                } label: {
                    Text("추가하기").frame(maxWidth: .infinity)
                }
                .appGlassProminentButton()
                .disabled(!vm.canAdd)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassScreenBackground()
            .navigationTitle(vm.source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("닫기")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 수량

    private var quantityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if let servingSize = vm.servingSizeText {
                    Text(servingSize)
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                }

                HStack(spacing: 12) {
                    stepper
                    if vm.showsUnitPicker { unitPicker }
                }

                // g 모드에서만 보인다 — 1인분을 아는 항목의 화면을 어지럽히지 않는다.
                if vm.showsQuickGramChips { quickGramChips }

                if let hint = vm.servingSizeUnknownHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Color.orange400)
                }
            }
        }
    }

    @ViewBuilder
    private var stepper: some View {
        HStack(spacing: 10) {
            Button {
                if vm.unit == .serving { vm.decreaseServings() } else { vm.decreaseGram() }
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
            .accessibilityLabel("수량 줄이기")

            if vm.unit == .serving {
                Text(vm.servingsText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                    .frame(minWidth: 72)
            } else {
                HStack(spacing: 2) {
                    TextField("0", text: $vm.gramText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 56)
                    Text("g").foregroundStyle(Color.slate400)
                }
            }

            Button {
                if vm.unit == .serving { vm.increaseServings() } else { vm.increaseGram() }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
            .accessibilityLabel("수량 늘리기")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassInputField()
    }

    private var unitPicker: some View {
        Picker("단위", selection: Binding(
            get: { vm.unit },
            set: { vm.setUnit($0) }
        )) {
            ForEach(FoodDetailViewModel.Unit.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
    }

    private var quickGramChips: some View {
        HStack(spacing: 6) {
            ForEach(FoodDetailViewModel.quickGrams, id: \.self) { gram in
                Button {
                    vm.selectQuickGram(gram)
                } label: {
                    Text("\(gram.trimmedText)g")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.slate100, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 영양소

    private var nutritionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(vm.kcalText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.slate700)

                    // 목표가 없으면 비율에 의미가 없다 — 프로필이 없으면 감춘다.
                    if let goal = vm.dailyGoalPercentText {
                        Text(goal)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.blue500)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.slate100, in: Capsule())
                    }
                }

                ForEach(vm.nutrientRows) { row in
                    Divider()
                    HStack {
                        Text(row.isSub ? "↳ \(row.name)" : row.name)
                            .font(.caption)
                            .foregroundStyle(row.isSub ? Color.slate400 : Color.slate500)
                            .padding(.leading, row.isSub ? 10 : 0)
                        Spacer()
                        Text(row.valueText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.slate700)
                    }
                }
            }
        }
    }
}
```

`project.pbxproj`에 `DT10033`/`DT20033`을 넣는다(그룹은 `DT40001 /* Diet */`).

- [ ] **Step 7: 전체 테스트를 돌린다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전부 PASS (208개)

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/FoodDetailViewModel.swift WooriHaru/Views/Diet/FoodDetailSheet.swift WooriHaruTests/DietPickTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat: 항목 상세 시트에 인분·g 단위와 빠른 선택 칩을 넣는다

인분은 0.5씩(최소 0.5), g은 25씩(최소 25) 움직인다. 1인분을 모르는 항목은
g 모드로 고정하고 수량을 비운다. 일일목표 %는 프로필이 있을 때만 보인다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
)"
```

---

## Task 4: 고르기 ViewModel — 모드·탭·필터 칩·바구니

**Files:**
- Create: `WooriHaru/ViewModels/MealItemPickViewModel.swift`
- Modify: `WooriHaruTests/DietPickTests.swift` (스위트 추가)
- Modify: `WooriHaru.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `FoodPickSource`(Task 2), `DietServing`, `NutritionProfile`, `NutritionMath.manualItem`, `FakeDietService`, `makeProfile()`
- Produces:
  - `enum MealItemPickMode: Equatable { case replace(MealItemRequest); case addOne; case addMany }` + `allowsMultiple` · `title` · `replacingText`
  - `MealItemPickViewModel(mode:service:)`
  - 중첩 타입 `Tab`(`.frequent`/`.search`/`.manual`) · `DatasetFilter`(`.all`/`.dish`/`.raw`/`.processed`) · `PickOutcome`(`.needsDetail`/`.commit([MealItemRequest])`/`.collected`) · `PickedItem`
  - 프로퍼티 `mode` · `tab`(var) · `filter`(var) · `query`(var) · `frequentSources` · `filteredSearchSources` · `isSearching` · `targetKcal: Int?` · `showsBottomBar` · `bottomBarText` · `canCommitPicked` · 직접 등록 9칸 · `errorMessage`
  - 메서드 `load()` · `search()` · `quickAdd(_:) -> PickOutcome` · `accept(_:from:) -> PickOutcome` · `acceptManual() -> PickOutcome?` · `commitPicked() -> [MealItemRequest]` · `pickedCount(for:) -> Int` · `buildManualItem()` · `clearManualInput()`
  - Task 5의 `MealItemEditView`가 이 전부를 쓴다.

**pbxproj ID:** `MealItemPickViewModel.swift` → `DT10034`/`DT20034`, 그룹 `B40003 /* ViewModels */`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietPickTests.swift` 끝에 추가한다:

```swift
@MainActor
struct MealItemPickViewModelTests {
    private func makeVM(_ mode: MealItemPickMode = .addMany) -> (MealItemPickViewModel, FakeDietService) {
        let service = FakeDietService()
        service.profile = makeProfile()
        return (MealItemPickViewModel(mode: mode, service: service), service)
    }

    /// 진입하면 자주 드셨어요와 프로필을 함께 읽는다. **프로필은 상세 시트의 일일목표 %에만
    /// 쓰이므로 없어도 화면을 막지 않는다.**
    @Test func 진입하면_자주_드셨어요와_프로필을_읽는다() async {
        let (vm, service) = makeVM()
        service.frequentItems = [makeFrequent()]

        await vm.load()

        #expect(vm.frequentSources.count == 1)
        #expect(vm.targetKcal == 2509)
        #expect(service.frequentCallCount == 1)
        #expect(service.searchQueries.isEmpty)
    }

    @Test func 프로필_조회가_실패해도_고르기는_열린다() async {
        let (vm, service) = makeVM()
        service.frequentItems = [makeFrequent()]
        service.errors["fetchProfile"] = dietServerError("INTERNAL_ERROR", status: 500)

        await vm.load()

        #expect(vm.frequentSources.count == 1)
        #expect(vm.targetKcal == nil)
    }

    /// **검색어를 확정하면 검색결과 탭으로 자동 전환한다** — 결과가 다른 탭 뒤에 숨으면 안 된다.
    @Test func 검색하면_검색결과_탭으로_넘어간다() async {
        let (vm, service) = makeVM()
        service.foods = [makePickFood()]
        vm.query = "제육"

        #expect(vm.tab == .frequent)
        await vm.search()

        #expect(vm.tab == .search)
        #expect(service.searchQueries == ["제육"])
        #expect(vm.filteredSearchSources.count == 1)
    }

    /// **필터 칩은 받아 온 페이지를 앱에서 거른다** — 서버에 `dataset` 파라미터가 없다.
    @Test func 필터_칩이_데이터셋으로_거른다() async {
        let (vm, service) = makeVM()
        service.foods = [
            makePickFood("제육볶음", code: "D1", dataset: .dish),
            makePickFood("달걀", code: "R1", dataset: .raw),
            makePickFood("삼각김밥", code: "P1", dataset: .processed),
            makePickFood("김치찌개", code: "D2", dataset: .dish)
        ]
        vm.query = "김"
        await vm.search()

        #expect(vm.filter == .all)
        #expect(vm.filteredSearchSources.count == 4)

        vm.filter = .dish
        #expect(vm.filteredSearchSources.map(\.name) == ["제육볶음", "김치찌개"])

        vm.filter = .raw
        #expect(vm.filteredSearchSources.map(\.name) == ["달걀"])

        vm.filter = .processed
        #expect(vm.filteredSearchSources.map(\.name) == ["삼각김밥"])

        vm.filter = .all
        #expect(vm.filteredSearchSources.count == 4)
    }

    /// **⊕가 갈린다** — 1인분을 알면 바로 담기고, 모르면 상세 시트를 열라고 알린다.
    ///
    /// (함수 이름에 `⊕`를 쓰지 않는다 — U+2295는 Swift 식별자로 허용되지 않아
    /// 테스트 타깃 전체가 파싱 단계에서 깨진다. 주석 안에서는 문제없다.)
    @Test func 일인분을_모르는_항목의_담기_버튼은_상세_시트를_연다() {
        let (vm, _) = makeVM()

        let known = FoodPickSource.food(makePickFood(known: true, serving: 250))
        let unknown = FoodPickSource.food(makePickFood("달걀", known: false, serving: 200))

        #expect(vm.quickAdd(unknown) == .needsDetail)
        #expect(vm.commitPicked().isEmpty)

        #expect(vm.quickAdd(known) == .collected)
        #expect(vm.commitPicked().count == 1)
    }

    /// 여러 개 모드 — 세 개를 담으면 원소 3개 배열이 나온다.
    @Test func 여러_개_모드는_모아_두었다가_한꺼번에_넘긴다() {
        let (vm, _) = makeVM(.addMany)
        let a = FoodPickSource.food(makePickFood("제육볶음", code: "D1"))
        let b = FoodPickSource.food(makePickFood("김치찌개", code: "D2"))

        #expect(vm.showsBottomBar)
        #expect(!vm.canCommitPicked)

        #expect(vm.quickAdd(a) == .collected)
        #expect(vm.quickAdd(b) == .collected)
        #expect(vm.quickAdd(a) == .collected)   // 같은 음식 2인분

        #expect(vm.canCommitPicked)
        #expect(vm.bottomBarText == "3개 담기")
        #expect(vm.pickedCount(for: a) == 2)
        #expect(vm.pickedCount(for: b) == 1)

        let committed = vm.commitPicked()
        #expect(committed.count == 3)
        #expect(committed.map(\.foodName) == ["제육볶음", "김치찌개", "제육볶음"])
    }

    /// **한 개 모드는 고르는 즉시 닫힌다** — 하단 바도 담김 배지도 없다.
    @Test func 한_개_모드는_바로_넘기고_바구니를_쓰지_않는다() {
        for mode in [MealItemPickMode.addOne, .replace(makeManualRequest())] {
            let service = FakeDietService()
            let vm = MealItemPickViewModel(mode: mode, service: service)
            let source = FoodPickSource.food(makePickFood(known: true, serving: 250))

            #expect(!vm.showsBottomBar)

            guard case let .commit(items) = vm.quickAdd(source) else {
                Issue.record("한 개 모드는 .commit이어야 한다: \(mode)")
                return
            }
            #expect(items.count == 1)
            #expect(items[0].quantityG == 250)
            #expect(vm.pickedCount(for: source) == 0)
            #expect(vm.commitPicked().isEmpty)
        }
    }

    /// **주의 영양소 3필드가 바구니를 거쳐도 살아 있어야 한다.**
    @Test func 바구니를_거쳐도_주의_영양소가_남는다() throws {
        let (vm, _) = makeVM(.addMany)
        vm.quickAdd(.food(makePickFood(known: true, serving: 250)))
        vm.quickAdd(.frequent(makeFrequent(quantityG: 200)))

        let items = vm.commitPicked()
        #expect(items.count == 2)
        #expect(items[0].sugarG == 7.5)
        #expect(items[0].sodiumMg == 1000)
        #expect(items[0].fiberG == 3.75)
        #expect(items[1].sugarG == 21)
        #expect(items[1].sodiumMg == 2)
        #expect(items[1].fiberG == 4.8)
    }

    /// 직접 등록 — `foodCode`는 `""`가 아니라 `nil`이고 `source`는 `.llmEstimated`다.
    @Test func 직접_등록은_코드를_보내지_않는다() throws {
        let (vm, _) = makeVM(.addOne)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"
        vm.manualKcal = "430"
        vm.manualCarbs = "60"
        vm.manualProtein = "12"
        vm.manualFat = "15"
        vm.manualSugar = "4"
        vm.manualSodium = "980"
        vm.manualFiber = "3"

        guard case let .commit(items) = try #require(vm.acceptManual()) else {
            Issue.record("한 개 모드의 직접 등록은 .commit이어야 한다")
            return
        }
        #expect(items[0].foodCode == nil)
        #expect(items[0].source == .llmEstimated)
        #expect(items[0].sugarG == 4)
        #expect(items[0].sodiumMg == 980)
        #expect(items[0].fiberG == 3)
    }

    @Test func 직접_등록에_이름이나_수량이_없으면_담을_수_없다() {
        let (vm, _) = makeVM(.addOne)

        #expect(vm.acceptManual() == nil)

        vm.manualName = "포장 김밥"
        #expect(vm.acceptManual() == nil)

        vm.manualQuantity = "0"
        #expect(vm.acceptManual() == nil)

        vm.manualQuantity = "230"
        #expect(vm.acceptManual() != nil)
    }

    /// **여러 개 모드에서 직접 등록을 담으면 칸을 비운다** — 다음 항목이 앞 항목의
    /// 영양소를 물려받으면 이름만 다른 값이 조용히 담긴다.
    @Test func 직접_등록을_담으면_다음_입력을_위해_칸을_비운다() {
        let (vm, _) = makeVM(.addMany)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"
        vm.manualSodium = "980"
        vm.manualFiber = "3"

        #expect(vm.acceptManual() == .collected)

        #expect(vm.manualName.isEmpty)
        #expect(vm.manualQuantity.isEmpty)
        #expect(vm.manualSodium.isEmpty)
        #expect(vm.manualFiber.isEmpty)
        #expect(vm.buildManualItem() == nil)

        vm.manualName = "우유"
        vm.manualQuantity = "200"
        let second = vm.commitPicked()
        #expect(second.count == 1)   // 아직 두 번째는 안 담았다
        _ = vm.acceptManual()
        let both = vm.commitPicked()
        #expect(both.count == 2)
        #expect(both[1].foodName == "우유")
        #expect(both[1].sodiumMg == 0)   // 앞 항목의 980이 새 나가면 안 된다
        #expect(both[1].fiberG == 0)
    }

    /// 상세 시트에서 「추가하기」로 온 항목도 같은 길을 탄다.
    @Test func 상세_시트에서_온_항목도_모드를_따른다() {
        let source = FoodPickSource.food(makePickFood(known: false))
        let edited = NutritionMath.item(from: makePickFood(known: false), quantityG: 100)

        let (many, _) = makeVM(.addMany)
        #expect(many.accept(edited, from: source) == .collected)
        #expect(many.pickedCount(for: source) == 1)

        let (one, _) = makeVM(.addOne)
        #expect(one.accept(edited, from: source) == .commit([edited]))
        #expect(one.commitPicked().isEmpty)
    }

    /// 교체 모드는 무엇을 바꾸는지 화면에 적어 준다.
    @Test func 교체_모드는_대상을_제목_아래_적는다() {
        let target = makeManualRequest(name: "제육볶음")

        #expect(MealItemPickMode.replace(target).title == "음식 교체")
        #expect(MealItemPickMode.replace(target).replacingText == "「제육볶음」을 교체합니다")
        #expect(MealItemPickMode.addOne.title == "음식 추가")
        #expect(MealItemPickMode.addOne.replacingText == nil)
        #expect(MealItemPickMode.addMany.replacingText == nil)
    }

    private func makeManualRequest(name: String = "제육볶음") -> MealItemRequest {
        NutritionMath.manualItem(
            name: name, quantityG: 250, kcal: 375, carbsG: 30, proteinG: 25,
            fatG: 17, sugarG: 7, sodiumMg: 1000, fiberG: 3
        )
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealItemPickViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'MealItemPickViewModel' in scope`

- [ ] **Step 3: `MealItemPickViewModel`을 만든다**

`WooriHaru/ViewModels/MealItemPickViewModel.swift`:

```swift
import Foundation

/// 시트가 열린 자리마다 다중 선택 여부가 다르다.
enum MealItemPickMode: Equatable {
    /// 교체 — 대상이 하나로 정해져 있다.
    case replace(MealItemRequest)
    /// 한 개 담기 — **항목 하나마다 서버 왕복**이라 모아 보낼 이유가 없다.
    case addOne
    /// 여러 개 담기 — 아직 저장 전이라 모아서 담아도 왕복이 없다.
    case addMany

    var allowsMultiple: Bool { self == .addMany }

    var title: String {
        switch self {
        case .replace: "음식 교체"
        case .addOne, .addMany: "음식 추가"
        }
    }

    /// 「「제육볶음」을 교체합니다」 — 교체 모드에서만 보인다.
    var replacingText: String? {
        guard case let .replace(item) = self else { return nil }
        return "「\(item.foodName)」을 교체합니다"
    }
}

/// 항목 고르기 — 자주 드셨어요 · 검색결과 · 직접 등록 세 탭과 (여러 개 모드의) 바구니.
@MainActor
@Observable
final class MealItemPickViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case frequent, search, manual

        var id: String { rawValue }
        var label: String {
            switch self {
            case .frequent: "자주 드셨어요"
            case .search: "검색결과"
            case .manual: "직접 등록"
            }
        }
    }

    /// 검색결과 탭에서만 보인다. **가공식품 30만 건과 원재료 523건이 섞여 나오므로
    /// 구분이 실제로 필요하다.**
    enum DatasetFilter: String, CaseIterable, Identifiable {
        case all, dish, raw, processed

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "전체"
            case .dish: "음식"
            case .raw: "원재료"
            case .processed: "가공식품"
            }
        }
        var dataset: FoodDataset? {
            switch self {
            case .all: nil
            case .dish: .dish
            case .raw: .raw
            case .processed: .processed
            }
        }
    }

    /// 고르기 한 번의 결과. 화면은 이 값만 보고 움직인다.
    enum PickOutcome: Equatable {
        /// 담을 기본 수량이 없다 — 상세 시트를 연다.
        case needsDetail
        /// 한 개 모드 — 이 항목을 넘기고 시트를 닫는다.
        case commit([MealItemRequest])
        /// 여러 개 모드 — 바구니에 담았다. 시트는 열려 있다.
        case collected
    }

    /// 바구니 한 칸. 같은 음식을 두 번 담을 수 있으므로 항목의 UUID가 키다.
    struct PickedItem: Identifiable, Hashable {
        let sourceId: String
        let item: MealItemRequest

        var id: UUID { item.id }
    }

    let mode: MealItemPickMode

    var tab: Tab = .frequent
    var filter: DatasetFilter = .all
    var query = ""

    private(set) var frequentItems: [FrequentItem] = []
    private(set) var searchResults: [Food] = []
    private(set) var isSearching = false
    private(set) var profile: NutritionProfile?
    /// 여러 개 모드에서 모아 둔 항목. 한 개 모드에서는 항상 비어 있다.
    private(set) var picked: [PickedItem] = []

    // 직접 등록 — 포장지 영양성분표를 보고 채운다. **당류·나트륨·식이섬유 칸이 반드시
    // 있어야 한다** — 넷만 채워 보내면 서버가 나머지를 0.0으로 받아 말없이 저장한다.
    var manualName = ""
    var manualQuantity = ""
    var manualKcal = ""
    var manualCarbs = ""
    var manualProtein = ""
    var manualFat = ""
    var manualSugar = ""
    var manualSodium = ""
    var manualFiber = ""

    var errorMessage: String?

    private let service: any DietServing

    init(mode: MealItemPickMode, service: any DietServing = DietService()) {
        self.mode = mode
        self.service = service
    }

    // MARK: - 목록

    var frequentSources: [FoodPickSource] { frequentItems.map(FoodPickSource.frequent) }

    /// **받아 온 페이지를 앱에서 거른다** — 서버에 `dataset` 파라미터가 없다. 그래서 상위
    /// 결과가 전부 가공식품이면 「음식」 칩이 빈 목록을 보여준다. `size`를 50(서버 상한)으로
    /// 올려 완화했고, 근본 해법은 서버 필터라 별도 작업이다.
    var filteredSearchSources: [FoodPickSource] {
        let filtered = filter.dataset.map { dataset in
            searchResults.filter { $0.dataset == dataset }
        } ?? searchResults
        return filtered.map(FoodPickSource.food)
    }

    /// 상세 시트의 「일일목표 %」 분모. 프로필이 없으면 nil이라 배지가 감춰진다.
    var targetKcal: Int? { profile?.targetKcal }

    // MARK: - 조회

    func load() async {
        do {
            frequentItems = try await service.fetchFrequentItems()
        } catch is CancellationError {
            return
        } catch {
            // 자주 드셨어요가 비어도 검색은 되어야 한다 — 화면을 막지 않는다.
            frequentItems = []
        }

        do {
            profile = try await service.fetchProfile()
        } catch {
            // 「일일목표 %」 배지만 못 보여준다. 담는 것 자체는 프로필과 무관하다.
            profile = nil
        }
    }

    /// 검색어를 확정하면 **검색결과 탭으로 자동 전환한다** — 결과가 다른 탭 뒤에 숨으면 안 된다.
    func search() async {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else {
            searchResults = []
            return
        }
        tab = .search
        isSearching = true
        // 새 조회를 시작할 때 지난 오류를 지운다 — 안 지우면 실패 뒤 성공한 검색에서
        // 정상 결과 위에 낡은 오류가 계속 떠 있는다(`DietDayViewModel.load()`와 같은 처리).
        errorMessage = nil
        defer { isSearching = false }

        do {
            searchResults = try await service.searchFoods(query: keyword)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 담기

    /// ⊕를 눌렀다. **담을 기본 수량이 없으면 담지 않고 상세 시트를 열라고 알린다.**
    @discardableResult
    func quickAdd(_ source: FoodPickSource) -> PickOutcome {
        guard let item = source.quickAddItem else { return .needsDetail }
        return accept(item, from: source)
    }

    /// 상세 시트에서 「추가하기」를 눌렀다.
    @discardableResult
    func accept(_ item: MealItemRequest, from source: FoodPickSource) -> PickOutcome {
        guard mode.allowsMultiple else { return .commit([item]) }
        picked.append(PickedItem(sourceId: source.id, item: item))
        return .collected
    }

    /// 직접 등록 탭에서 담았다. 칸이 덜 찼으면 nil.
    @discardableResult
    func acceptManual() -> PickOutcome? {
        guard let item = buildManualItem() else { return nil }
        guard mode.allowsMultiple else { return .commit([item]) }
        picked.append(PickedItem(sourceId: "manual-\(item.id.uuidString)", item: item))
        // **다음 항목이 앞 항목의 영양소를 물려받으면 안 된다** — 이름만 바꿔 담으면
        // 전혀 다른 음식이 앞 항목의 나트륨·식이섬유를 달고 조용히 저장된다.
        clearManualInput()
        return .collected
    }

    /// 하단 바 「N개 담기」가 넘길 항목들.
    func commitPicked() -> [MealItemRequest] { picked.map(\.item) }

    /// 행에 붙는 「담김 N」 배지. **여러 개 모드에서만 센다.**
    func pickedCount(for source: FoodPickSource) -> Int {
        picked.filter { $0.sourceId == source.id }.count
    }

    var showsBottomBar: Bool { mode.allowsMultiple }
    var canCommitPicked: Bool { !picked.isEmpty }
    var bottomBarText: String { "\(picked.count)개 담기" }

    // MARK: - 직접 등록

    /// 탭을 옮겨도 칸을 지우지 않는다. 옛 화면은 검색과 직접 입력이 같은 자리를 번갈아 써서
    /// **안 보이는 값이 남아 다른 음식 이름을 달고 담기는** 결함이 있었지만, 탭에서는 직접
    /// 등록 화면에 있는 동안 모든 칸이 그대로 보이므로 남아 있는 편이 맞다.
    func buildManualItem() -> MealItemRequest? {
        let name = manualName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let quantity = Double(manualQuantity), quantity > 0 else { return nil }
        return NutritionMath.manualItem(
            name: name,
            quantityG: quantity,
            kcal: Double(manualKcal) ?? 0,
            carbsG: Double(manualCarbs) ?? 0,
            proteinG: Double(manualProtein) ?? 0,
            fatG: Double(manualFat) ?? 0,
            sugarG: Double(manualSugar) ?? 0,
            sodiumMg: Double(manualSodium) ?? 0,
            fiberG: Double(manualFiber) ?? 0
        )
    }

    func clearManualInput() {
        manualName = ""
        manualQuantity = ""
        manualKcal = ""
        manualCarbs = ""
        manualProtein = ""
        manualFat = ""
        manualSugar = ""
        manualSodium = ""
        manualFiber = ""
    }
}
```

`project.pbxproj`에 `DT10034`/`DT20034`를 넣는다(그룹은 `B40003 /* ViewModels */`).

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealItemPickViewModelTests 2>&1 | tail -30`
Expected: PASS (13 tests)

- [ ] **Step 5: 고의 파손 확인**

`acceptManual()`의 `clearManualInput()` 호출을 지우고 다시 돌린다.
Expected: `직접_등록을_담으면_다음_입력을_위해_칸을_비운다` 실패. 확인 후 되돌린다.

이어서 `accept(_:from:)`의 `guard mode.allowsMultiple else { return .commit([item]) }`를 지우고 다시 돌린다.
Expected: `한_개_모드는_바로_넘기고_바구니를_쓰지_않는다`·`상세_시트에서_온_항목도_모드를_따른다` 실패. 확인 후 되돌린다.

- [ ] **Step 6: 전체 테스트를 돌린다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전부 PASS (221개)

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/ViewModels/MealItemPickViewModel.swift WooriHaruTests/DietPickTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat: 항목 고르기에 모드·탭·필터 칩·바구니를 넣는다

다중 선택은 새 끼니를 만들 때(.addMany)만이다. 한 개 모드는 고르는 즉시
onCommit으로 넘긴다. 필터 칩은 서버 파라미터가 없어 받아 온 페이지를 앱에서 거른다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
)"
```

---

## Task 5: 고르기 화면 교체와 호출부 연결

**Files:**
- Rewrite: `WooriHaru/Views/Diet/MealItemEditView.swift` (기존 `MealItemEditViewModel`은 이 파일에서 삭제된다)
- Modify: `WooriHaru/Views/Diet/MealConfirmView.swift:109-118`
- Modify: `WooriHaru/Views/Diet/MealDetailView.swift:40-61`
- Modify: `WooriHaru/ViewModels/MealDetailViewModel.swift` (`editableItem(matching:)` 추가)
- Modify: `WooriHaru/Services/DietService.swift:127` (`size` 20 → 50)
- Modify: `WooriHaruTests/DietTests.swift:255-264` (`식품_검색은_q와_size를_붙인다` — 기대값 20 → 50)
- Modify: `WooriHaruTests/DietConfirmTests.swift` (옛 `MealItemEditViewModelTests` 스위트 삭제)
- Modify: `WooriHaruTests/DietPickTests.swift` (`editableItem(matching:)` 테스트 추가)

**Interfaces:**
- Consumes: `MealItemPickViewModel`·`MealItemPickMode`(Task 4), `FoodDetailSheet`(Task 3), `FoodPickRow`·`FoodPickSource`(Task 2), `MealConfirmViewModel.addItem/replaceItem`, `MealDetailViewModel.replaceItem/replaceItems`
- Produces: `MealItemEditView(mode: MealItemPickMode, service: any DietServing = DietService(), onCommit: @escaping ([MealItemRequest]) -> Void)`. **`onCommit`은 항상 배열이다.** 기존 `current: MealItemRequest?` 이니셜라이저는 사라진다.

새 파일이 없으므로 **`project.pbxproj` 수정은 없다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

먼저 **기존 테스트를 고친다.** `WooriHaruTests/DietTests.swift:255-264`의
`식품_검색은_q와_size를_붙인다`에서 마지막 줄을 바꾸고 주석을 단다:

```swift
    @Test func 식품_검색은_q와_size를_붙인다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/foods", result: DataResponse<[Food]>(data: []))

        _ = try await DietService(api: api).searchFoods(query: "제육")

        #expect(api.getCalls.first?.path == "/diet/foods")
        #expect(api.getCalls.first?.query["q"] == "제육")
        // **서버 상한인 50이다.** 필터 칩이 받아 온 페이지를 앱에서 거르기 때문에 페이지가
        // 작으면 상위 결과가 전부 가공식품일 때 「음식」 칩이 빈 목록을 보여준다.
        #expect(api.getCalls.first?.query["size"] == "50")
    }
```

이어서 `WooriHaruTests/DietPickTests.swift` 끝에 추가한다:

```swift
@MainActor
struct MealDetailEditTargetTests {
    /// 교체 시트는 **무엇을 바꾸는지** 알아야 한다 — 옛 화면은 `current: nil`을 넘겨
    /// 대상을 안 보여줬다.
    @Test func 교체_대상을_편집용_요청으로_바꾼다() async throws {
        let service = FakeDietService()
        let target = makeMealItem(id: 7, name: "제육볶음", quantityG: 250, sodium: 1000)
        service.meals = [makeMeal(items: [makeMealItem(id: 6, name: "밥"), target])]
        let vm = MealDetailViewModel(mealId: 1, service: service)
        await vm.load()

        let request = try #require(vm.editableItem(matching: target))

        #expect(request.foodName == "제육볶음")
        #expect(request.quantityG == 250)
        #expect(request.sodiumMg == 1000)

        // 목록에 없는 항목이면 nil이다.
        #expect(vm.editableItem(matching: makeMealItem(id: 999)) == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietServiceTests -only-testing:WooriHaruTests/MealDetailEditTargetTests 2>&1 | tail -30`
Expected: `식품_검색은_q와_size를_붙인다`가 `size == "20"`으로 실패하고, `MealDetailEditTargetTests`는 `cannot find 'editableItem'`로 컴파일 실패

(`DietTests.swift`에서 이 테스트가 든 스위트 이름을 먼저 확인하고 `-only-testing` 인자를 그 이름으로 맞춘다.)

- [ ] **Step 3: `searchFoods` 상한과 `editableItem(matching:)`을 넣는다**

`WooriHaru/Services/DietService.swift:127`:

```swift
    /// **`size`는 서버 상한인 50이다.** 필터 칩이 받아 온 페이지를 앱에서 거르기 때문에
    /// 페이지가 작으면 「음식」 칩이 빈 목록을 보여준다. 근본 해법은 서버 `dataset`
    /// 파라미터이고 그건 백엔드 작업이다.
    func searchFoods(query: String) async throws -> [Food] {
        let response: DataResponse<[Food]> = try await api.get("/diet/foods", query: ["q": query, "size": "50"])
        return response.data ?? []
    }
```

`WooriHaru/ViewModels/MealDetailViewModel.swift`의 `editableItems`(44~52줄) 바로 아래에 더한다:

```swift
    /// 교체 시트에 넘길 대상. **id로 자리를 찾는다** — 이름·수량으로 거르면 같은 음식을
    /// 두 번 담은 끼니에서 엉뚱한 쪽을 집는다. 목록에 없으면 nil.
    func editableItem(matching item: MealItem) -> MealItemRequest? {
        guard let items = meal?.items, let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return editableItems[index]
    }
```

- [ ] **Step 4: 두 테스트가 통과하는지 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietServiceTests -only-testing:WooriHaruTests/MealDetailEditTargetTests 2>&1 | tail -30`
Expected: PASS

- [ ] **Step 5: `MealItemEditView`를 통째로 교체한다**

`WooriHaru/Views/Diet/MealItemEditView.swift`의 **전체 내용**을 아래로 바꾼다. 옛 `MealItemEditViewModel`은 이 파일에서 사라진다(다른 파일에는 없다).

```swift
import SwiftUI

/// 항목 고르기 — 자주 드셨어요 · 검색결과 · 직접 등록 세 탭.
///
/// **담기는 두 속도다.** ⊕는 기본 수량으로 즉시 담고, 행을 누르면 상세 시트가 열려 수량·단위를
/// 조정한다. **1인분을 모르는 항목은 ⊕도 상세 시트를 연다** — 채워 넣을 기본 수량이 없다.
///
/// 다중 선택은 **새 끼니를 만들 때(`.addMany`)만**이다. 끼니 상세의 추가·교체는 항목 하나마다
/// 서버 왕복이라 모아 보낼 이유가 없다.
struct MealItemEditView: View {
    /// **항상 배열이다.** 한 개 모드에서는 원소가 하나라 호출부가 두 모양을 구분하지 않아도 된다.
    var onCommit: ([MealItemRequest]) -> Void

    @State private var vm: MealItemPickViewModel
    @State private var detailSource: FoodPickSource?
    @Environment(\.dismiss) private var dismiss

    init(
        mode: MealItemPickMode,
        service: any DietServing = DietService(),
        onCommit: @escaping ([MealItemRequest]) -> Void
    ) {
        self.onCommit = onCommit
        _vm = State(initialValue: MealItemPickViewModel(mode: mode, service: service))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .safeAreaInset(edge: .bottom) {
                // 여러 개 모드에서만 뜬다. **끼니 종류 피커는 두지 않는다** — 바로 뒤
                // `MealConfirmView`가 그 피커를 이미 갖고 있어 둘 다 두면 같은 값을 만지는
                // 컨트롤이 한 화면에 둘 생긴다.
                if vm.showsBottomBar { bottomBar }
            }
            .glassScreenBackground()
            .navigationTitle(vm.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .task { await vm.load() }
            .sheet(item: $detailSource) { source in
                FoodDetailSheet(source: source, targetKcal: vm.targetKcal) { item in
                    detailSource = nil
                    handle(vm.accept(item, from: source))
                }
            }
            .alert("오류", isPresented: .init(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    /// ⊕·상세 시트의 결과를 화면 동작으로 옮긴다.
    private func handle(_ outcome: MealItemPickViewModel.PickOutcome, fallback: FoodPickSource? = nil) {
        switch outcome {
        case .needsDetail:
            detailSource = fallback
        case let .commit(items):
            onCommit(items)
            dismiss()
        case .collected:
            break
        }
    }

    // MARK: - 상단 (검색창 · 탭 · 필터 칩)

    private var header: some View {
        VStack(spacing: 10) {
            if let replacing = vm.mode.replacingText {
                Text(replacing)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // **검색창은 탭 위에 둔다** — 어느 탭에서든 바로 검색으로 들어갈 수 있어야 한다.
            HStack {
                TextField("음식 검색", text: $vm.query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { Task { await vm.search() } }
                if vm.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassInputField()

            Picker("탭", selection: $vm.tab) {
                ForEach(MealItemPickViewModel.Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if vm.tab == .search { filterChips }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// 가공식품 30만 건과 원재료 523건이 섞여 나오므로 「조리 음식만」으로 좁힐 길이 필요하다.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MealItemPickViewModel.DatasetFilter.allCases) { option in
                    let isOn = vm.filter == option
                    Button {
                        vm.filter = option
                    } label: {
                        Text(option.label)
                            .font(.caption)
                            .foregroundStyle(isOn ? .white : Color.slate500)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isOn ? Color.blue500 : Color.slate100, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 본문

    @ViewBuilder
    private var content: some View {
        switch vm.tab {
        case .frequent:
            pickList(vm.frequentSources, emptyText: "아직 자주 드신 음식이 없어요.")
        case .search:
            pickList(vm.filteredSearchSources, emptyText: "찾을 음식을 검색해 주세요.")
        case .manual:
            manualForm
        }
    }

    private func pickList(_ sources: [FoodPickSource], emptyText: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if sources.isEmpty {
                    Text(emptyText)
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                        .padding(.vertical, 40)
                } else {
                    ForEach(sources) { source in
                        FoodPickRow(
                            source: source,
                            pickedCount: vm.pickedCount(for: source),
                            onTapRow: { detailSource = source },
                            onQuickAdd: { handle(vm.quickAdd(source), fallback: source) }
                        )
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// 포장지 영양성분표를 보고 채우는 자리. **당류·나트륨·식이섬유 칸이 반드시 있어야 한다** —
    /// 넷만 채워 보내면 서버가 나머지를 0.0으로 받아 말없이 저장한다.
    private var manualForm: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("음식 이름", text: $vm.manualName)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .glassInputField()

                    HStack(spacing: 8) {
                        numberField("수량", unit: "g", text: $vm.manualQuantity)
                        numberField("칼로리", unit: "kcal", text: $vm.manualKcal)
                    }
                    HStack(spacing: 8) {
                        numberField("탄수화물", unit: "g", text: $vm.manualCarbs)
                        numberField("단백질", unit: "g", text: $vm.manualProtein)
                        numberField("지방", unit: "g", text: $vm.manualFat)
                    }
                    HStack(spacing: 8) {
                        numberField("당류", unit: "g", text: $vm.manualSugar)
                        numberField("나트륨", unit: "mg", text: $vm.manualSodium)
                        numberField("식이섬유", unit: "g", text: $vm.manualFiber)
                    }

                    Button {
                        guard let outcome = vm.acceptManual() else { return }
                        handle(outcome)
                    } label: {
                        Text("추가하기").frame(maxWidth: .infinity)
                    }
                    .appGlassProminentButton()
                    .disabled(vm.buildManualItem() == nil)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }

    private func numberField(_ label: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label)(\(unit))")
                .font(.caption2)
                .foregroundStyle(Color.slate400)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .glassInputField(cornerRadius: 8)
        }
    }

    private var bottomBar: some View {
        Button {
            onCommit(vm.commitPicked())
            dismiss()
        } label: {
            Text(vm.bottomBarText).frame(maxWidth: .infinity)
        }
        .appGlassProminentButton()
        .disabled(!vm.canCommitPicked)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

- [ ] **Step 6: 호출부 세 곳을 바꾼다**

`WooriHaru/Views/Diet/MealConfirmView.swift:109-118`을 아래로 바꾼다:

```swift
        .sheet(item: $editTarget) { target in
            // **「음식 추가」만 여러 개 모드다** — 아직 저장 전이라 모아서 담아도 왕복이 없다.
            // 교체는 대상이 하나로 정해져 있다.
            MealItemEditView(mode: target.item.map(MealItemPickMode.replace) ?? .addMany) { picked in
                if let original = target.item {
                    if let edited = picked.first {
                        vm.replaceItem(original, with: edited, in: target.groupId)
                    }
                } else {
                    for item in picked {
                        vm.addItem(item, to: target.groupId)
                    }
                }
                editTarget = nil
            }
        }
```

`WooriHaru/Views/Diet/MealDetailView.swift:40-61`을 아래로 바꾼다:

```swift
        .sheet(item: $editingItem) { item in
            // **항목 하나마다 서버 왕복**이라 여기서는 모아 담지 않는다.
            if let current = vm.editableItem(matching: item) {
                MealItemEditView(mode: .replace(current)) { picked in
                    if let replacement = picked.first {
                        Task {
                            // 성공했을 때만 하루 화면을 재조회시킨다 — 가드가 막았거나 서버가
                            // 거절하면 아무것도 안 바뀐 채로 화면만 깜빡인다.
                            if await vm.replaceItem(item, with: replacement) {
                                onChanged()
                            }
                        }
                    }
                    editingItem = nil
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            MealItemEditView(mode: .addOne) { picked in
                if let added = picked.first {
                    Task {
                        if await vm.replaceItems(vm.editableItems + [added]) {
                            onChanged()
                        }
                    }
                }
                showAddItem = false
            }
        }
```

- [ ] **Step 7: 옛 테스트 스위트를 지운다**

`WooriHaruTests/DietConfirmTests.swift`의 **1~178줄** — `MealItemEditViewModelTests` 스위트 전체 — 를 지운다. 파일 맨 위 `import` 세 줄은 남기고, 뒤이은 `@MainActor struct MealConfirmViewModelTests {`부터가 새 시작이다.

여기서 사라지는 검증 중 **다음 다섯은 Task 2~4가 이미 새 자리에서 덮는다** — 확인만 하고 넘어간다:

| 옛 테스트 | 새 자리 |
| --- | --- |
| `진입하면_자주_먹는_음식을_먼저_읽는다` | `MealItemPickViewModelTests.진입하면_자주_드셨어요와_프로필을_읽는다` |
| `자주_먹는_음식은_계산_없이_그대로_담긴다` | `FoodPickSourceTests.자주_드셨어요_즉시_담기는_저장된_값을_그대로_쓴다` |
| `검색어를_넣으면_식품DB를_찾는다` | `MealItemPickViewModelTests.검색하면_검색결과_탭으로_넘어간다` |
| `일인분_미상이면_수량_칸이_비어_있다` | `FoodDetailViewModelTests.일인분을_모르면_g_모드로_고정되고_수량이_비어_있다` |
| `검색_결과를_담으면_주의_영양소가_환산된다` | `FoodPickSourceTests.즉시_담기는_주의_영양소까지_환산한다` |
| `직접_입력은_코드를_보내지_않는다` | `MealItemPickViewModelTests.직접_등록은_코드를_보내지_않는다` |
| `직접_입력에_이름이나_수량이_없으면_담을_수_없다` | `MealItemPickViewModelTests.직접_등록에_이름이나_수량이_없으면_담을_수_없다` |
| `검색을_거쳐_직접_입력으로_돌아오면...` · `직접_입력_중_다시_불러도...` | 모드 전환 자체가 사라졌다(탭이 됐다). 대신 `직접_등록을_담으면_다음_입력을_위해_칸을_비운다`가 같은 위험(앞 항목 값 물려받기)을 덮는다 |

`일인분을_알면_기본_수량이_채워진다`는 `DietTests.swift:124-125`(`NutritionMathTests`)에 **같은 단언이 이미 있다.** 그대로 지운다.

- [ ] **Step 8: 새 두 경로를 주의 영양소 통과 스위트에 등록한다**

`WooriHaruTests/DietTests.swift`의 `NutrientPassthroughTests`(400줄~)가 이 저장소의 **정식 3필드 확인 자리**다 — `assertNutrientsSurvive`가 `MealConfirmViewModel.save()`까지 태워 `confirmRequests`에 실제로 실린 값을 본다. 스펙이 「경로가 늘 때마다 이 확인이 따라붙어야 한다」고 한 곳이 여기다. `⑤ 저장된_끼니_편집_경로` 뒤에 두 개를 더한다:

```swift
    /// ⑥ ⊕ 즉시 담기 경로 — 목록에서 한 번에 담는다. 상세 시트를 거치지 않으므로
    /// 환산이 `FoodPickSource.quickAddItem` 한 곳에서만 일어난다.
    @Test func 즉시_담기_경로() async throws {
        let food = Food(
            code: "D1", name: "제육볶음", dataset: .dish,
            servingSizeG: 250, servingSizeKnown: true,
            kcalPer100g: 150, carbsPer100g: 12, proteinPer100g: 10, fatPer100g: 7,
            sugarPer100g: 3, sodiumMgPer100g: 400, fiberPer100g: 1.5
        )
        let item = try #require(FoodPickSource.food(food).quickAddItem)

        await assertNutrientsSurvive(item, sugar: 7.5, sodium: 1000, fiber: 3.75)
    }

    /// ⑦ 상세 시트 경로 — 수량·단위를 조정한 뒤 담는다. 자주 드셨어요 출처는 100g당 값이
    /// 없어 **비례 환산**을 타므로 검색 출처와 다른 코드 경로다.
    @Test func 상세_시트_경로() async throws {
        let frequent = FrequentItem(
            foodName: "사과", foodCode: "R1", quantityG: 200, kcal: 104,
            carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
            source: .dbMatched, count: 7, lastEatenOn: "2026-07-29"
        )
        let vm = FoodDetailViewModel(source: .frequent(frequent))
        vm.selectQuickGram(100)
        let item = try #require(vm.item)

        await assertNutrientsSurvive(item, sugar: 10.5, sodium: 1, fiber: 2.4)
    }
```

`FoodDetailViewModel`이 `@MainActor`라 이 스위트가 이미 `@MainActor`인지 확인한다(400줄 바로 위에 붙어 있다 — 그대로면 손댈 것이 없다).

- [ ] **Step 9: 빌드와 전체 테스트를 돌린다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30`
Expected: 전부 PASS. 옛 스위트 11개가 빠지고 새 3개가 붙어 **215개** 안팎.

빌드가 깨지면 다음을 먼저 본다:
- `MealItemEditView(current:)`를 아직 부르는 곳 — `grep -rn "MealItemEditView(" WooriHaru`
- `MealItemEditViewModel`을 아직 참조하는 곳 — `grep -rn "MealItemEditViewModel" WooriHaru WooriHaruTests`

- [ ] **Step 10: 고의 파손 확인**

`MealConfirmView`의 `?? .addMany`를 `?? .addOne`으로 바꾸고 빌드한다. 컴파일은 되지만 여러 개 담기가 사라진다 — **이건 테스트가 못 잡는다.** 되돌리고, 대신 `MealItemPickViewModel`의 `showsBottomBar`를 `true`로 고정해 전체 테스트를 돌린다.
Expected: `한_개_모드는_바로_넘기고_바구니를_쓰지_않는다` 실패. 확인 후 되돌린다.

> 호출부 모드 선택은 뷰 코드라 단위 테스트가 닿지 않는다. **사용자의 실기기 확인 항목**으로 남긴다:
> ① 확인 화면 「음식 추가」 → 하단 바가 뜨고 여러 개가 담기는지
> ② 확인 화면 항목 탭(교체) → 하단 바가 없고 고르는 즉시 닫히는지
> ③ 끼니 상세 추가·교체 → 둘 다 하단 바 없이 즉시 닫히는지
> ④ 달걀(1인분 미상)의 ⊕ → 담기지 않고 상세 시트가 열리는지

- [ ] **Step 11: 커밋**

```bash
git add WooriHaru/Views/Diet/MealItemEditView.swift WooriHaru/Views/Diet/MealConfirmView.swift WooriHaru/Views/Diet/MealDetailView.swift WooriHaru/ViewModels/MealDetailViewModel.swift WooriHaru/Services/DietService.swift WooriHaruTests/DietTests.swift WooriHaruTests/DietConfirmTests.swift WooriHaruTests/DietPickTests.swift
git commit -m "$(cat <<'EOF'
feat: 항목 고르기 화면을 3탭·⊕·상세 시트 구조로 다시 짠다

onCommit이 항상 배열이 되고 current: MealItemRequest?는 MealItemPickMode로
갈라진다. 확인 화면의 「음식 추가」만 여러 개 모드다. 검색 size를 50으로 올린다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
)"
```

---

## 자기 점검 (계획 작성자용 — 실행자는 읽고 넘어가도 된다)

스펙 대조 결과다.

| 스펙 요구 | 담당 |
| --- | --- |
| 탭 셋(자주 드셨어요·검색결과·직접 등록) | Task 4 `Tab` · Task 5 `header` |
| 검색 확정 시 검색결과 탭 자동 전환 | Task 4 `search()` |
| 검색창을 탭 위에 | Task 5 `header` |
| 필터 칩 4종, 검색결과 탭에서만 | Task 4 `DatasetFilter` · Task 5 `filterChips` |
| `size` 20 → 50 | Task 5 Step 3 |
| 행 — 「1인분 (250g)」/「100g 기준」 + 열량 + ⊕ | Task 2 `detailText`·`displayKcal`·`FoodPickRow` |
| 자주 드셨어요 행 — 「200g · 7회」 | Task 2 `detailText` |
| ⊕ 즉시 담기 / 행 탭 상세 시트 | Task 4 `quickAdd` · Task 5 `pickList` |
| 1인분 미상은 ⊕도 상세 시트 | Task 2 `quickAddItem` · Task 4 `PickOutcome.needsDetail` |
| 상세 시트 — 인분 ±0.5 최소 0.5 | Task 3 `increaseServings`/`decreaseServings` |
| 상세 시트 — g ±25 최소 25 + 직접 입력 | Task 3 `increaseGram`/`decreaseGram`/`gramText` |
| 빠른 선택 칩 50·100·200, g 모드에서만 | Task 3 `quickGrams`·`showsQuickGramChips` |
| `servingSizeKnown == false` → g 고정·단위 감춤·수량 빔·힌트 | Task 3 `init`·`showsUnitPicker`·`servingSizeUnknownHint` |
| 「일일목표 N%」, 프로필 없으면 감춤 | Task 3 `dailyGoalPercentText` · Task 4 `targetKcal` |
| 7영양소 표(당류는 탄수화물 아래) | Task 3 `nutrientRows` |
| 두 출처가 다른 환산 함수 | Task 2 `FoodPickSource` · Task 3 `item` |
| `MealItemPickMode` 3종 · `onCommit`은 배열 | Task 4 · Task 5 |
| 하단 바 「N개 담기」, 끼니 종류 피커 없음 | Task 5 `bottomBar` |
| 「담김 N」 배지, 여러 개 모드에서만 | Task 2 `FoodPickRow.pickedCount` · Task 4 `pickedCount(for:)` |
| 한 개 모드는 즉시 닫힘 | Task 4 `accept` · Task 5 `handle` |
| `FrequentItemList`는 그대로 | 건드리지 않는다 |
| 날짜 스트립 — `visibleWeekAnchor` 계열 6가지 | Task 1 |
| 스와이프 50pt · 가로 > 세로 | Task 1 Step 6 |
| 월 표시 · 「오늘」 버튼 | Task 1 |
| 주의 영양소 3필드 통과 확인(상세 시트·⊕ 양쪽) | 단위 확인은 Task 2 `즉시_담기는_주의_영양소까지_환산한다` · Task 3 `상세_시트에서_담아도_주의_영양소가_남는다` · Task 4 `바구니를_거쳐도_주의_영양소가_남는다`. **저장 요청까지 태우는 정식 확인은 Task 5 Step 8**이 `NutrientPassthroughTests`에 ⑥·⑦로 등록한다 |

**범위 밖으로 남긴 것**(스펙과 같다): 즐겨찾기 · 인기도 · 세트/레시피 · 서버 `dataset` 파라미터 · 바코드 · `MealDetailView` 다중 선택 · 사용자 정의 단위 · 포화지방·트랜스지방·콜레스테롤(백엔드 별도 작업서 `toy-back/docs/superpowers/specs/2026-07-30-food-extra-nutrients-design.md`).
