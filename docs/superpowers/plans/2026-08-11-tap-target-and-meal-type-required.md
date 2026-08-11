# 카드 탭 영역과 끼니 타입 강제 선택 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 카드는 어디를 눌러도 열리게 하고, 끼니 타입은 고르지 않으면 저장할 수 없게 한다.

**Architecture:** 독립적인 두 갈래다. **① 공용 `GlassCard`에 `contentShape`을 걸어** 카드를 링크로 감싼 두 화면(수영 기록·식단 홈)의 탭 영역을 한 번에 넓힌다. **② 끼니 타입을 `MealType?`로 바꿔** 「안 골랐다」를 진짜 상태로 만들고, 저장 게이트를 확인 화면 한 곳에 둔다. 서버 작업은 없다.

**Tech Stack:** Swift / SwiftUI, Swift Testing, `@MainActor @Observable` 뷰모델

**설계 문서:** `docs/superpowers/specs/2026-08-11-tap-target-and-meal-type-required-design.md`

## Global Constraints

- **끼니 타입의 기본값을 어디에도 남기지 않는다.** 「골랐는지」를 별도 플래그로 들지 않고 `MealType?`로 표현한다. 플래그를 얹으면 값은 여전히 `.lunch`라, 한 군데서 검사를 빠뜨리는 순간 고르지도 않은 끼니가 서버로 나간다.
- **저장을 막는 자리는 확인 화면의 저장 버튼 하나다.** 사진 시트의 「인식 시작」은 막지 않는다 — 끼니 타입은 인식과 무관한 값이다.
- **「선택 안 함」 세그먼트를 만들지 않는다.** 세그먼티드 Picker는 일치하는 태그가 없으면 아무 칸도 선택하지 않은 채 그려지고, 그것이 미선택 표시다.
- **`save()`에서 강제 언래핑하지 않는다.** `canSave` 가드 뒤라 도달할 수 없지만, `canSave`의 조건이 나중에 하나 바뀌면 그 크래시는 사용자 기기에서 처음 발견된다.
- **`MealDetailView`(저장된 끼니의 타입 수정)는 수정 대상이 아니다.** 저장된 끼니는 반드시 타입이 있으므로 그쪽 `MealType`은 옵셔널이 아니다.
- **서버 계약은 그대로다.** `MealConfirmRequest.mealType`은 여전히 non-optional이다 — 앱이 nil을 보낼 일이 없어야 한다는 뜻이다.
- 테스트 실행:
  ```
  perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:WooriHaruTests > /tmp/t.log 2>&1
  ```
  - **백그라운드로 돌리지 말고 출력은 파일로 리다이렉트한다**(`| tail` 금지 — 파이프가 멈춘다). 이 맥에는 `timeout`/`gtimeout`이 없다. 결과는 `grep -E "Test run with|error:|✘" /tmp/t.log | tail -20`으로 본다.
  - **프로덕션 타입의 멤버 시그니처를 바꾸는 태스크(2·3)는 `clean test`로 돌린다.** 증분 빌드가 옛 모듈로 테스트를 컴파일해 「없는 멤버」 에러를 내거나, 더 나쁘게는 **새 테스트가 안 돈 채 통과로 보고**된 적이 있다.
  - **통과만 보지 말고 개수를 확인한다.** 시작점은 **432 tests / 46 suites**다.
- **`#expect` 뒤에서 런타임 길이가 달라지는 배열(`service.confirmRequests` 등)을 인덱스로 읽지 않는다.** 실패해도 실행이 안 멈춰 범위를 벗어나면 테스트 프로세스가 통째로 죽는다. `.first`/`.last`를 쓴다.
- 테스트 이름과 주석은 한국어로 쓴다(기존 관례).
- 각 태스크는 **고의 파손 확인**으로 끝낸다 — 구현을 망가뜨려 새 테스트가 실제로 빨개지는지 보고 되돌린다. (Task 1은 유닛 테스트가 닿지 않아 예외다. 아래에 대신 할 일을 적었다.)

## File Structure

| 파일 | 하는 일 | 태스크 |
| --- | --- | --- |
| `WooriHaru/Views/Components/Glass/GlassCard.swift` | `contentShape` 한 줄 | 1 |
| `WooriHaru/ViewModels/MealConfirmViewModel.swift` | `mealType` 옵셔널화와 파급 넷 | 2 |
| `WooriHaru/Views/Diet/MealConfirmView.swift` | Picker 태그, 미선택 안내 | 2 |
| `WooriHaruTests/DietConfirmTests.swift` | 저장 게이트 테스트 4건 | 2 |
| `WooriHaru/ViewModels/MealCaptureViewModel.swift` | 기본값 `.lunch` → `nil` | 3 |
| `WooriHaru/Views/Diet/MealCaptureSheet.swift` | Picker 태그 | 3 |
| `WooriHaru/Views/Diet/DietHomeView.swift` | 직접 추가가 넘기는 `.snack` → `nil` | 3 |
| `WooriHaruTests/DietCaptureTests.swift` | 미선택으로 시작하는지 | 3 |

**의존 순서:** 1은 독립. 2 → 3 (Task 3이 넘기는 `nil`을 Task 2의 `init`이 받을 수 있어야 한다).

**Task 2가 뷰까지 함께 고치는 이유:** `MealConfirmView`의 Picker가 `$vm.mealType`에 묶여 있어, 뷰모델만 옵셔널로 바꾸면 태그 타입이 어긋나 **빌드가 깨진다.** 한 태스크 안에서 끝내야 검증 가능한 상태로 남는다.

---

### Task 1: 카드 전체가 탭 영역이 된다

**Files:**
- Modify: `WooriHaru/Views/Components/Glass/GlassCard.swift:10-15`
- Test: 없음 — 아래 「검증」 참고

**Interfaces:**
- Consumes: `GlassTokens.cardCornerRadius`
- Produces: 없음(공개 API가 안 바뀐다). `NavigationLink`로 감싼 `GlassCard`의 히트 영역만 넓어진다.

**검증에 대해 먼저:** SwiftUI 히트 테스트는 유닛 테스트가 닿지 않는다. **테스트를 억지로 만들지 마라** — 뷰 계층을 흉내 내는 테스트는 `contentShape`이 실제로 붙었는지가 아니라 네가 쓴 흉내가 맞는지를 검증한다. 이 태스크의 검증은 ① 기존 432개가 그대로 통과하는지(회귀 없음)와 ② 실기기 확인(사람이 한다)이다.

- [ ] **Step 1: `contentShape`을 넣는다**

`GlassCard.swift`의 `body`를 이렇게 바꾼다:

```swift
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            // 카드처럼 생긴 것은 어디를 눌러도 눌려야 한다. 이게 없으면 `NavigationLink`
            // 안에서 글씨·아이콘 픽셀만 탭에 닿고 그 사이 여백은 통과한다.
            // **모서리를 유리 모양과 맞춘다** — `.rect`로 두면 보이지 않는 귀퉁이가 눌린다.
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
```

- [ ] **Step 2: 전체 스위트로 회귀가 없는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "Test run with|error:|✘" /tmp/t.log | tail -20
```
Expected: PASS, **432 tests in 46 suites** — 개수가 그대로여야 한다(이 태스크는 테스트를 추가하지 않는다).

- [ ] **Step 3: 카드 안에 자체 버튼이 있는 사용처를 한 번 확인한다**

`rg -n "GlassCard" WooriHaru/Views` 로 사용처를 훑고, **카드 안에 `Button`이나 탭 제스처를 둔 곳**이 있으면 그 자식이 여전히 탭을 먼저 받는 구조인지 눈으로 본다(자식 버튼은 부모의 `contentShape`보다 우선한다 — 바뀔 것이 없어야 정상이다). 이상한 곳을 찾으면 **고치지 말고 리포트에 적어라.**

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Components/Glass/GlassCard.swift
git commit -m "fix: 카드 여백을 눌러도 카드가 눌리게 한다"
```

---

### Task 2: 끼니를 고르지 않으면 저장할 수 없다

**Files:**
- Modify: `WooriHaru/ViewModels/MealConfirmViewModel.swift` (프로퍼티 18행, `init` 30-37행, `mergesIntoExisting` 64-66행, `mergeNoticeText` 70-72행, `resolveSaveAction` 120-139행, `canSave` 154행, `save()` 241-250행)
- Modify: `WooriHaru/Views/Diet/MealConfirmView.swift` (`init` 55-76행, Picker 81-85행, 안내 88-94행)
- Test: `WooriHaruTests/DietConfirmTests.swift` (`struct MealConfirmViewModelTests`)

**Interfaces:**
- Consumes: `MealType`(`allCases`, `label`, `mergesWithinDay`), `FakeDietService.confirmRequests: [MealConfirmRequest]`, `FakeDietService.days`
- Produces:
  - `MealConfirmViewModel.mealType: MealType?` (var)
  - `MealConfirmViewModel.init(date: Date, mealType: MealType?, analysis: MealAnalysis?, service: any DietServing)`
  - `MealConfirmView.init(date: Date, mealType: MealType?, analysis: MealAnalysis?, ...)` — Task 3의 두 호출지가 `nil`을 넘긴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

먼저 기존 헬퍼에 끼니 인자를 연다. `DietConfirmTests.swift:169-171`의 `makeVM`을 이렇게 바꾼다(기본값이 있어 기존 호출지는 그대로 컴파일된다):

```swift
    private func makeVM(
        _ analysis: MealAnalysis?,
        mealType: MealType? = .lunch,
        service: FakeDietService = .init()
    ) -> MealConfirmViewModel {
        MealConfirmViewModel(date: Date.from("2026-07-29")!, mealType: mealType, analysis: analysis, service: service)
    }
```

그리고 `항목이_없으면_저장할_수_없다`(246행) 앞에 네 개를 넣는다:

```swift
    /// **기본값으로 잘못 등록되는 것을 막는 게이트다.** 항목이 다 있어도 끼니를 안 고르면
    /// 저장이 열리지 않는다.
    @Test func 끼니를_고르지_않으면_저장할_수_없다() {
        let vm = makeVM(twoPhotoAnalysis(), mealType: nil)

        #expect(!vm.canSave)

        vm.mealType = .dinner
        #expect(vm.canSave)
    }

    /// 게이트가 버튼 비활성화에만 있으면 안 된다 — 뷰모델이 스스로 막아야 한다.
    @Test func 끼니를_고르지_않고_저장을_불러도_요청이_나가지_않는다() async {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), mealType: nil, service: service)

        await vm.save()

        #expect(service.confirmRequests.isEmpty)
        #expect(vm.savedMealID == nil)
    }

    /// 고른 값이 그대로 실려야 한다 — 어디선가 기본값으로 되돌아가면 이 테스트가 잡는다.
    @Test func 끼니를_고르면_그_값이_요청에_실린다() async {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), mealType: nil, service: service)
        vm.mealType = .dinner

        await vm.save()

        #expect(service.confirmRequests.count == 1)
        #expect(service.confirmRequests.last?.mealType == .dinner)
    }

    /// 합쳐질 끼니가 정해지지 않았으므로 병합 안내가 나올 수 없다.
    @Test func 끼니를_고르기_전에는_병합_안내가_뜨지_않는다() async {
        let service = FakeDietService()
        service.days = [makeDay(date: "2026-07-29", meals: [makeMeal(mealType: .breakfast)])]
        let vm = makeVM(nil, mealType: nil, service: service)

        await vm.loadExistingMeals()

        #expect(!vm.mergesIntoExisting)
        #expect(vm.mergeNoticeText == nil)

        // 고르는 순간 원래 동작이 살아난다
        vm.mealType = .breakfast
        #expect(vm.mergeNoticeText == "이미 기록한 아침에 합쳐져요.")
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
Expected: **컴파일 에러** — `'nil' is not compatible with expected argument type 'MealType'`. 이것이 이 태스크의 RED다(`mealType`이 아직 non-optional이라 nil을 넘길 수조차 없다).

- [ ] **Step 3: 뷰모델을 옵셔널로 바꾼다**

`MealConfirmViewModel.swift`에서 여섯 군데를 고친다.

**(a) 프로퍼티(18행):**

```swift
    /// **고르기 전에는 nil이다.** 기본값을 박아 두면 그대로 저장돼, 나중에 고치는 일이
    /// 반복된다. 「골랐는지」를 별도 플래그로 들지 않는 이유는 그때 값이 여전히 남아 있어
    /// 검사를 한 군데만 빠뜨려도 고르지 않은 끼니가 서버로 나가기 때문이다.
    var mealType: MealType?
```

**(b) `init`의 파라미터(32행):** `mealType: MealType,` → `mealType: MealType?,`

**(c) `mergesIntoExisting`(64-66행):**

```swift
    var mergesIntoExisting: Bool {
        guard let mealType else { return false }
        return mealType.mergesWithinDay && existingMealTypes.contains(mealType)
    }
```

**(d) `mergeNoticeText`(70-72행):**

```swift
    var mergeNoticeText: String? {
        guard mergesIntoExisting, let mealType else { return nil }
        return "이미 기록한 \(mealType.label)에 합쳐져요."
    }
```

**(e) `resolveSaveAction`(120-139행):** 두 군데의 `mealType`을 언래핑한다. 저장 버튼이 잠겨 있어 nil로는 도달하지 않지만, nil이면 물어볼 것도 없으므로 그대로 `.save`로 떨어진다.

```swift
    func resolveSaveAction() async -> SaveAction {
        startExistingLookup()
        isResolvingSave = true
        defer { isResolvingSave = false }
        await existingLookup?.value

        // 끼니를 안 골랐으면 물어볼 것이 없다 — 저장 자체가 `canSave`에서 막힌다.
        guard let mealType else { return .save }

        if mergesIntoExisting {
            return .confirm(
                title: "이미 기록한 \(mealType.label)이 있어요",
                message: "저장하면 이미 기록한 \(mealType.label)에 합쳐져요. 따로 남기려면 취소하고 다른 끼니를 골라 주세요."
            )
        }
        if existingLookupFailed, mealType.mergesWithinDay {
            return .confirm(
                title: "이미 기록한 \(mealType.label)이 있는지 확인하지 못했어요",
                message: "있다면 저장할 때 합쳐지고, 합쳐진 뒤에는 되돌릴 수 없어요."
            )
        }
        return .save
    }
```

**(f) `canSave`(154행)와 `save()`(241행):**

```swift
    /// 서버가 빈 배열을 거절한다. 조회를 기다리는 동안에도 잠근다 — 연타로 두 번 눌리면
    /// 알럿이 두 번 뜬다. **끼니를 고르기 전에도 잠근다** — 기본값으로 저장되는 것을 막는
    /// 게이트가 여기 하나다(사진 경로와 직접 추가 경로가 둘 다 이 화면을 거친다).
    var canSave: Bool { mealType != nil && !allItems.isEmpty && !isSaving && !isResolvingSave }
```

`save()`의 첫 줄 `guard canSave else { return }`를 이렇게 바꾼다:

```swift
        // `canSave`가 이미 nil을 막지만 강제 언래핑하지 않는다 — 나중에 `canSave`의 조건이
        // 하나 바뀌면 그 크래시는 사용자 기기에서 처음 발견된다.
        guard canSave, let mealType else { return }
```

(`save()` 안의 `mealType: mealType`은 이제 언래핑된 지역 상수를 가리키므로 그대로 둔다.)

- [ ] **Step 4: 확인 화면을 맞춘다**

`MealConfirmView.swift`에서 세 군데를 고친다.

**(a) `init`의 파라미터(57행):** `mealType: MealType,` → `mealType: MealType?,`

**(b) Picker(81-85행):** 태그를 옵셔널로 올린다. 이게 없으면 선택이 아무 칸과도 일치하지 않아 **고를 수조차 없다.**

```swift
                Picker("끼니", selection: $vm.mealType) {
                    ForEach(MealType.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
```

**(c) 안내(88-94행):** 병합 안내 앞에 미선택 안내를 둔다. 미선택일 때는 병합 안내가 나올 수 없어 둘이 겹치지 않는다.

```swift
                // 피커 **바로 아래**여야 한다 — 끼니 종류를 바꿀 때마다 달라지는 안내라
                // 떨어져 있으면 무엇 때문에 나타났다 사라지는지 읽히지 않는다.
                if vm.mealType == nil {
                    // 빈 세그먼티드만으로는 「왜 저장이 안 되지」가 된다.
                    Label("끼니를 골라 주세요", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let notice = vm.mergeNoticeText {
                    Label(notice, systemImage: "arrow.triangle.merge")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
Expected: PASS, **436 tests**(432 + 4). **기존 병합 테스트 7건이 그대로 통과해야 한다** — `.lunch`·`.breakfast`를 넘기던 호출지는 옵셔널로 자동 승격되어 동작이 안 바뀐다. 하나라도 빨개지면 고치지 말고 보고하라.

- [ ] **Step 6: 고의로 망가뜨려 본다**

`canSave`의 `mealType != nil &&`를 지우고 Step 5를 다시 돌린다.
Expected: `끼니를_고르지_않으면_저장할_수_없다`와 `끼니를_고르지_않고_저장을_불러도_요청이_나가지_않는다`가 **둘 다 실패**해야 한다. 확인했으면 되돌린다.

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/ViewModels/MealConfirmViewModel.swift WooriHaru/Views/Diet/MealConfirmView.swift WooriHaruTests/DietConfirmTests.swift
git commit -m "feat: 끼니를 고르지 않으면 저장할 수 없게 한다"
```

---

### Task 3: 두 진입 경로가 미선택으로 시작한다

**Files:**
- Modify: `WooriHaru/ViewModels/MealCaptureViewModel.swift:24`
- Modify: `WooriHaru/Views/Diet/MealCaptureSheet.swift:113-119`
- Modify: `WooriHaru/Views/Diet/DietHomeView.swift:70-77`
- Test: `WooriHaruTests/DietCaptureTests.swift` (`struct MealCaptureViewModelTests`)

**Interfaces:**
- Consumes: Task 2의 `MealConfirmView.init(date:mealType:analysis:...)`가 `MealType?`를 받는다
- Produces: `MealCaptureViewModel.mealType: MealType?` (var, 기본 `nil`)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`DietCaptureTests.swift`의 `struct MealCaptureViewModelTests` 안, 첫 `@Test`(`사진_N장을_순차로_올리고_인식을_요청한다`, 28행) 앞에 넣는다:

```swift
    /// **기본값이 박혀 있으면 그대로 저장된다.** 미선택으로 시작해 확인 화면에서 고르게 한다.
    @Test func 끼니는_미선택으로_시작한다() {
        #expect(MealCaptureViewModel(service: FakeDietService()).mealType == nil)
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
Expected: **RED.** `mealType`이 아직 non-optional이라 두 모습 중 하나로 나온다 — ① `comparing non-optional value of type 'MealType' to 'nil' always returns false` 경고와 함께 이 테스트가 **실패**하거나, ② 타입 에러로 빌드가 멈춘다. 둘 중 무엇이든 RED다. **경고가 뜨는 쪽이면 Step 3 뒤에 그 경고가 사라졌는지도 확인하라**(테스트 출력은 깨끗해야 한다).

- [ ] **Step 3: 세 곳을 미선택으로 바꾼다**

**(a) `MealCaptureViewModel.swift:24`:**

```swift
    /// **고르기 전에는 nil이다.** 확인 화면이 이 값을 그대로 받고, 거기서 저장이 막힌다.
    var mealType: MealType?
```

**(b) `MealCaptureSheet.swift:113-119`** — 태그를 옵셔널로 올린다(안 하면 고를 수조차 없다):

```swift
    private var mealTypePicker: some View {
        Picker("끼니", selection: $vm.mealType) {
            ForEach(MealType.allCases) { Text($0.label).tag(Optional($0)) }
        }
        .pickerStyle(.segmented)
        .disabled(vm.isBusy)
    }
```

**(c) `DietHomeView.swift:70-77`** — 직접 추가가 `.snack`을 박아 넘기던 것을 없앤다:

```swift
        .sheet(isPresented: $showManualEntry) {
            // 사진 없는 기록 — `MealConfirmView`를 그대로 재사용한다. `PhotoStrip`만 그릴 게 없다.
            // **끼니는 넘기지 않는다** — 기본값을 박으면 그대로 저장된다.
            NavigationStack {
                MealConfirmView(date: vm.selectedDate, mealType: nil, analysis: nil) { _ in
                    showManualEntry = false
                    Task { await vm.reload() }
                }
            }
        }
```

- [ ] **Step 4: 통과하는지 확인한다**

Run:
```
perl -e 'alarm 900; exec @ARGV' xcodebuild clean test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; \
  grep -E "Test run with|error:|✘" /tmp/t.log | tail -20
```
Expected: PASS, **437 tests**(436 + 1). `DietCaptureTests`의 기존 21건이 전부 통과해야 한다 — 그중 어느 것도 `mealType`을 읽지 않는다.

- [ ] **Step 5: 고의로 망가뜨려 본다**

`MealCaptureViewModel`의 `var mealType: MealType?`를 `var mealType: MealType? = .lunch`로 바꾸고 Step 4를 다시 돌린다.
Expected: `끼니는_미선택으로_시작한다`가 **실패**해야 한다. 확인했으면 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/ViewModels/MealCaptureViewModel.swift WooriHaru/Views/Diet/MealCaptureSheet.swift WooriHaru/Views/Diet/DietHomeView.swift WooriHaruTests/DietCaptureTests.swift
git commit -m "feat: 끼니 타입을 미선택으로 시작한다"
```

---

## 마무리 확인

- [ ] 전체 테스트를 `clean test`로 한 번 더 돌려 **437 tests / 46 suites** 통과를 확인한다
- [ ] `rg -n "mealType: \.(breakfast|lunch|dinner|snack)" WooriHaru/Views` 로 **뷰에 남은 끼니 기본값이 없는지** 훑는다(있으면 보고한다 — `MealDetailView`의 수정 기능은 저장된 끼니를 다루므로 해당 없음)
- [ ] 실기기 확인 — ① 수영 기록·식단 홈에서 **카드 여백**을 눌러 상세로 들어가는지 ② 사진/직접 두 경로 모두 끼니가 **아무것도 안 칠해진 채** 열리고, 고르기 전에는 저장이 잠기며 안내가 뜨는지 ③ 고른 뒤 저장하면 그 끼니로 들어가는지
- [ ] `git log --oneline develop..HEAD`로 커밋 5개(설계 1 + 이 계획 1 + 태스크 3)를 확인한다
