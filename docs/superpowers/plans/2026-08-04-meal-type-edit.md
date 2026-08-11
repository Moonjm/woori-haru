# 저장된 끼니의 타입 수정 (앱) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 저장된 끼니의 상세 화면에서 끼니 타입(아침·점심·저녁·간식)을 고칠 길을 연다.

**Architecture:** 세 층을 아래에서 위로 쌓는다 — **① 서비스**(`PATCH`를 보내고 `Location`에서 살아남은 끼니 id를 받는다) → **② 뷰모델**(그날을 조회해 「합쳐지는가」를 판단하고, 알럿 문구를 정하고, 보낸 뒤 화면을 닫을지 정한다) → **③ 화면**(툴바 메뉴와 알럿). 판단을 전부 뷰모델에 두는 이유는 **합침 분기와 조회 실패 분기가 테스트에 닿아야 하기 때문이다.**

**Tech Stack:** Swift / SwiftUI, Swift Testing, `@MainActor @Observable` 뷰모델

**설계 문서 둘 (앱이 원본이 아닌 것에 주의):**
- `docs/superpowers/specs/2026-08-04-meal-type-edit-design.md` (앱)
- `toy-back` `docs/superpowers/specs/2026-08-04-meal-type-edit-design.md` (**서버 계약의 원본**)

## Global Constraints

- **서버가 먼저 나가야 한다.** `PATCH /diet/meals/{id}`는 아직 없다. 이 계획의 코드는 전부 가짜(`FakeDietService`·`MockAPIClient`)로 검증되고, **실기기 확인만 서버 배포 뒤로 미룬다.** 배포 전에 실기기에서 눌러 보면 404가 온다.
- **응답은 본문이 아니라 `Location` 헤더다.** `200 OK` + `Location: /diet/meals/42`. 본문은 비어 있다.
- **상태코드가 201이 아니라 200인 것에 손댈 것은 없다.** `rawFetchWithResponse`가 `200...299`를 통과시키고 `postCreated`·`patchCreated`는 **상태코드를 보지 않고 `Location`만 읽는다.** 확정·분석 생성·사진 업로드는 201로 오는데 이 요청만 200으로 오지만, 앱은 그 둘을 구분하지 않는다.
- **`Location`이 가리키는 것은 「살아남은 끼니」다.** 합쳐졌으면 대상 끼니 id, 아니면 요청한 id 그대로. **원래 id와 다르면 합쳐진 것이다.**
- **같은 타입은 앱에서 걸러 안 보낸다.** 서버도 막지만 헛된 왕복과 유료 피드백 재생성이 나가면 안 된다.
- **간식은 합쳐지지 않는다**(`MealType.mergesWithinDay == false`). 간식 → 저녁은 합쳐지고 **저녁 → 간식은 안 합쳐진다.** 이 비대칭이 이 기능에서 가장 헷갈리는 지점이다.
- **「합쳐진다」와 「모르겠다」는 다른 문구를 쓴다.** 앞은 확정된 사실이고 뒤는 추측이다. `MealConfirmViewModel.resolveSaveAction`이 같은 구분을 이미 하고 있다.
- 테스트 실행: `perl -e 'alarm 500; exec @ARGV' xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests > /tmp/t.log 2>&1`
  - **백그라운드로 돌리지 말고 출력은 파일로 리다이렉트한다**(`| tail` 금지 — 파이프가 멈춘다). 이 맥에는 `timeout`/`gtimeout`이 없다.
  - **프로덕션 타입에 멤버를 추가한 태스크는 `clean test`로 돌린다.** 증분 빌드가 옛 모듈로 테스트를 컴파일해 「없는 멤버」 에러를 내거나, 더 나쁘게는 **새 테스트가 안 돈 채 통과로 보고**된 적이 있다. 통과만 보지 말고 **개수가 예상만큼 늘었는지** 확인한다(시작점: **313개 / 36 스위트**).
  - **`#expect` 뒤에서 배열을 인덱스로 읽지 않는다.** 실패해도 멈추지 않으므로 범위를 벗어나면 테스트가 프로세스째 죽어 남은 테스트가 판정도 못 받는다. `.first`/`.last`나 이름 기준 딕셔너리를 쓴다.
- 각 태스크는 **고의 파손 확인**으로 끝낸다 — 구현을 망가뜨려 새 테스트가 실제로 빨개지는지 보고 되돌린다.
- 커밋 메시지 마지막 줄: `Claude-Session: https://claude.ai/code/session_01TrC1RZQyYUELJnCGe3CjVD`

## File Structure

| 파일 | 하는 일 | 태스크 |
| --- | --- | --- |
| `WooriHaru/Models/Diet.swift` | `MealTypeRequest` 추가 | 1 |
| `WooriHaru/Services/APIClient.swift` | `patchCreated` 추가(프로토콜 + 구현) | 1 |
| `WooriHaru/Services/DietService.swift` | `DietServing.changeMealType` 추가(프로토콜 + 구현) | 1 |
| `WooriHaruTests/MockAPIClient.swift` | `patchCreated` 스텁 | 1 |
| `WooriHaruTests/DietFakes.swift` | `FakeDietService.changeMealType` | 1 |
| `WooriHaru/ViewModels/MealDetailViewModel.swift` | `resolveTypeChange`·`changeMealType` | 2 |
| `WooriHaru/Views/Diet/MealDetailView.swift` | 툴바 메뉴·알럿·닫기 | 3 |

**새 파일이 없다** — `project.pbxproj`를 손댈 일이 없다.

**의존 순서:** 1 → 2 → 3.

---

### Task 1: 서비스 계층 — `PATCH`를 보내고 살아남은 id를 받는다

**Files:**
- Modify: `WooriHaru/Models/Diet.swift`(`MealItemRequest` 아래), `WooriHaru/Services/APIClient.swift:31`(프로토콜)·`:96`(구현), `WooriHaru/Services/DietService.swift:20`(프로토콜)·`:99` 근처(구현)
- Modify: `WooriHaruTests/MockAPIClient.swift`, `WooriHaruTests/DietFakes.swift`
- Test: `WooriHaruTests/DietTests.swift`(`DietServiceTests`가 없으면 새 스위트를 파일 끝에 만든다)

**Interfaces:**
- Produces:
  - `struct MealTypeRequest: Encodable { let mealType: MealType }`
  - `APIClientProtocol.patchCreated(_ path: String, body: (any Encodable)?) async throws -> Int`
  - `DietServing.changeMealType(id: Int, to mealType: MealType) async throws -> Int` — **돌려주는 것은 살아남은 끼니 id다**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietTests.swift` 맨 끝에 새 스위트를 더한다:

```swift
// MARK: - 끼니 타입 수정

struct MealTypeChangeServiceTests {
    /// **경로와 본문이 서버 계약과 맞아야 한다.** 어긋나면 실기기에서 400이나 404로만 보이고
    /// 앱 로그에는 이유가 안 남는다.
    @Test func 경로와_본문이_맞다() async throws {
        let api = MockAPIClient()
        api.stubPatchCreated("/diet/meals/7", result: 7)
        let service = DietService(api: api)

        _ = try await service.changeMealType(id: 7, to: .dinner)

        let call = try #require(api.patchCreatedCalls.first)
        #expect(call.path == "/diet/meals/7")
        let body = try #require(call.body as? MealTypeRequest)
        #expect(body.mealType == .dinner)
    }

    /// **살아남은 끼니 id를 그대로 준다.** 합쳐지면 서버가 다른 id를 주고, 화면은 그 차이로
    /// 「합쳐졌다」를 안다.
    @Test func 합쳐지면_다른_id가_온다() async throws {
        let api = MockAPIClient()
        api.stubPatchCreated("/diet/meals/7", result: 42)
        let service = DietService(api: api)

        let survivor = try await service.changeMealType(id: 7, to: .dinner)

        #expect(survivor == 42)
    }

    @Test func 서버_오류는_그대로_던진다() async {
        let api = MockAPIClient()
        api.setError(dietServerError("INTERNAL_ERROR", status: 500), for: "PATCH /diet/meals/7")
        let service = DietService(api: api)

        await #expect(throws: (any Error).self) {
            _ = try await service.changeMealType(id: 7, to: .dinner)
        }
    }
}
```

**오류 등록은 `setError(_:for:)`다**(`stubError`가 아니다). 키 규칙은 `"메서드 경로"` — `postCreated`가 `"POST \(path)"`를 쓰는 것과 같다.

- [ ] **Step 2: 실패를 확인한다**

Run: `perl -e 'alarm 500; exec @ARGV' xcodebuild build-for-testing -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/t.log 2>&1; grep -E "error:" /tmp/t.log | sort -u | head`

Expected: `cannot find 'MealTypeRequest' in scope`, `value of type 'MockAPIClient' has no member 'stubPatchCreated'`

- [ ] **Step 3: `MealTypeRequest`를 더한다**

`WooriHaru/Models/Diet.swift`의 `MealItemRequest` 정의 아래:

```swift
/// `PATCH /diet/meals/{id}` 본문. **끼니 타입 한 칸뿐이다** — 항목을 같이 보내지 않는다.
/// 항목을 안 보내기 때문에 낡은 화면에서도 이 요청은 안전하다(덮어쓸 목록 자체가 없다).
struct MealTypeRequest: Encodable {
    let mealType: MealType
}
```

- [ ] **Step 4: `APIClient.patchCreated`를 더한다**

`APIClientProtocol`에 `postCreated` 줄 아래로:

```swift
    /// `PATCH` 응답의 `Location`에서 id를 뽑는다. **본문이 아니라 헤더다** — 끼니 확정·분석
    /// 생성·사진 업로드가 이미 같은 방식이라 새 응답 DTO를 만들지 않는다.
    func patchCreated(_ path: String, body: (any Encodable)?) async throws -> Int
```

구현부의 `postCreated` 아래에 같은 모양으로:

```swift
    func patchCreated(_ path: String, body: (any Encodable)? = nil) async throws -> Int {
        let (_, response) = try await rawFetchWithResponse("PATCH", path: path, body: body)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let idString = location.split(separator: "/").last,
              let id = Int(idString) else {
            throw APIError.serverError(statusCode: response.statusCode, message: "Location 헤더에서 ID를 찾을 수 없습니다")
        }
        return id
    }
```

**`postCreated`와 다른 것은 메서드 문자열 하나뿐이다.** 파싱을 공유 함수로 빼고 싶어질 수 있지만, 두 곳뿐이고 `postMultipartCreated`가 이미 같은 여섯 줄을 세 번째로 갖고 있다 — 이 태스크에서 세 곳을 한꺼번에 건드리면 실패 지점이 늘어난다. **그대로 둔다.**

`APIClientProtocol`의 기본 인자 확장(`extension APIClientProtocol`)에도 한 줄 더한다 — `postCreated`가 그렇게 돼 있다:

```swift
    func patchCreated(_ path: String) async throws -> Int {
        try await patchCreated(path, body: nil)
    }
```

- [ ] **Step 5: `MockAPIClient`에 스텁을 더한다**

저장소와 기록 배열을 `postCreated` 것 바로 아래에 나란히 둔다:

```swift
    private var patchCreatedResults: [String: Int] = [:]
    private var recordedPatchCreatedCalls: [(path: String, body: (any Encodable)?)] = []
```

스텁·조회·구현 셋:

```swift
    func stubPatchCreated(_ path: String, result: Int) {
        lock.lock(); defer { lock.unlock() }
        patchCreatedResults[path] = result
    }

    var patchCreatedCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPatchCreatedCalls
    }

    func patchCreated(_ path: String, body: (any Encodable)?) async throws -> Int {
        lock.lock()
        recordedPatchCreatedCalls.append((path, body))
        let error = errors["PATCH \(path)"]
        let result = patchCreatedResults[path]
        lock.unlock()
        if let error { throw error }
        guard let id = result else { throw MockAPIError.unstubbed("PATCH \(path)") }
        return id
    }
```

**오류 키는 `"PATCH \(path)"`다** — `postCreated`가 `"POST \(path)"`를 쓰는 것과 같은 규칙이다.

- [ ] **Step 6: `DietServing`에 메서드를 더한다**

프로토콜의 `updateMealItems` 줄 아래:

```swift
    /// 저장된 끼니의 타입을 바꾼다. **돌려주는 것은 「살아남은 끼니」의 id다** — 대상 타입에
    /// 기존 끼니가 있으면 서버가 항목·사진을 그쪽으로 옮기고 이 끼니를 지운다. 그때 돌아오는
    /// id는 요청한 id와 **다르다.**
    func changeMealType(id: Int, to mealType: MealType) async throws -> Int
```

`DietService` 구현부의 `updateMealItems` 근처:

```swift
    func changeMealType(id: Int, to mealType: MealType) async throws -> Int {
        try await api.patchCreated("/diet/meals/\(id)", body: MealTypeRequest(mealType: mealType))
    }
```

- [ ] **Step 7: `FakeDietService`에 구현을 더한다**

`WooriHaruTests/DietFakes.swift`의 `updateMealItems` 아래. 상단 저장소에 두 줄을 먼저 더한다:

```swift
    /// 타입 변경이 돌려줄 「살아남은 id」. **nil이면 요청한 id를 그대로 준다**(안 합쳐진 경우).
    var changedMealTypeSurvivorId: Int?
    private(set) var changedMealTypes: [(id: Int, mealType: MealType)] = []
```

메서드:

```swift
    func changeMealType(id: Int, to mealType: MealType) async throws -> Int {
        lock.lock(); changedMealTypes.append((id, mealType)); lock.unlock()
        try check("changeMealType")
        lock.lock(); defer { lock.unlock() }
        return changedMealTypeSurvivorId ?? id
    }
```

- [ ] **Step 8: `clean test`**

Run: `perl -e 'alarm 500; exec @ARGV' xcodebuild clean test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests > /tmp/t.log 2>&1; grep -E "Test run with|error:" /tmp/t.log | tail -3`

Expected: **316개**(313 + 3), 전부 통과

- [ ] **Step 9: 고의 파손 확인**

1. `DietService.changeMealType`이 `patchCreated`의 결과 대신 `id`를 그대로 돌려주게 바꾼다 → `합쳐지면_다른_id가_온다`가 빨개진다
2. 경로를 `"/diet/meals/\(id)/type"`으로 바꾼다 → `경로와_본문이_맞다`가 빨개진다

둘 다 되돌리고 `git diff`로 확인한다.

- [ ] **Step 10: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 끼니 타입을 바꾸는 서비스 호출을 더한다

응답은 본문이 아니라 Location 헤더다 — 끼니 확정·분석 생성·사진 업로드가 이미
같은 방식이라 id 하나를 위해 새 응답 DTO를 만들지 않는다.

돌려주는 것은 「살아남은 끼니」의 id다. 대상 타입에 기존 끼니가 있으면 서버가
항목·사진을 그쪽으로 옮기고 이 끼니를 지우므로, 그때는 요청한 id와 다르다.

Claude-Session: https://claude.ai/code/session_01TrC1RZQyYUELJnCGe3CjVD
EOF
```

---

### Task 2: 뷰모델 — 합쳐지는지 판단하고, 보내고, 닫을지 정한다

**Files:**
- Modify: `WooriHaru/ViewModels/MealDetailViewModel.swift`(`replaceItem` 아래)
- Test: `WooriHaruTests/DietDayTests.swift`의 `MealDetailViewModelTests`

**Interfaces:**
- Consumes: `DietServing.changeMealType(id:to:)`(Task 1)
- Produces:
  - `enum MealTypeChangeAction: Equatable { case confirm(title: String, message: String), change }`
  - `enum MealTypeChangeOutcome: Equatable { case changed, merged, failed }`
  - `MealDetailViewModel.resolveTypeChange(to:) async -> MealTypeChangeAction?` — **nil이면 아무것도 하지 않는다**(같은 타입)
  - `MealDetailViewModel.changeMealType(to:) async -> MealTypeChangeOutcome`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietDayTests.swift`의 `MealDetailViewModelTests` 안에 더한다. **`makeVM(_:)`이 이미 있으니 그대로 쓴다.**

```swift
    /// **같은 타입이면 아무것도 하지 않는다.** 저장 한 번에 LLM 호출 한 번이 나가므로,
    /// 메뉴에서 지금 타입을 눌렀다고 유료 호출이 나가면 안 된다.
    @Test func 같은_타입이면_아무것도_안_한다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.resolveTypeChange(to: .snack) == nil)
        #expect(service.changedMealTypes.isEmpty)
    }

    /// **합쳐질 상황은 확인을 받는다.** 되돌릴 수 없는 병합이라 조용히 지나가면 안 된다.
    @Test func 합쳐질_상황이면_확인을_요구한다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        // 그날에 이미 저녁이 있다.
        service.days = [makeDay(meals: [makeMeal(id: 9, mealType: .dinner)])]
        let vm = makeVM(service)
        await vm.load()

        let action = await vm.resolveTypeChange(to: .dinner)

        guard case let .confirm(_, message) = action else {
            Issue.record("확인을 요구해야 한다: \(String(describing: action))")
            return
        }
        #expect(message.contains("합쳐져요"))
        // 아직 보내지 않는다 — 사용자가 확인을 눌러야 나간다.
        #expect(service.changedMealTypes.isEmpty)
    }

    /// 합쳐질 것이 없으면 묻지 않는다 — 잃는 것도 놀랄 것도 없다.
    @Test func 합쳐질_것이_없으면_바로_보낸다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        service.days = [makeDay(meals: [makeMeal(mealType: .snack)])]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.resolveTypeChange(to: .dinner) == .change)
    }

    /// **저녁 → 간식은 묻지 않는다.** 간식은 본래 여러 번이라 합쳐지지 않는다
    /// (`MealType.mergesWithinDay`). 합치기를 대칭으로 생각하면 여기서 틀린다.
    @Test func 간식으로_바꿀_때는_묻지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .dinner)]
        // 그날에 이미 간식이 있어도 합쳐지지 않는다.
        service.days = [makeDay(meals: [makeMeal(id: 9, mealType: .snack)])]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.resolveTypeChange(to: .snack) == .change)
    }

    /// **「합쳐진다」와 「모르겠다」는 다른 말이다.** 같은 문구를 쓰면 사용자가 확인 버튼을
    /// 누를 때 무엇을 승인하는지 모른다.
    @Test func 그날_조회에_실패하면_다른_문구로_묻는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        service.errors["fetchDay"] = dietServerError("INTERNAL_ERROR", status: 500)
        let vm = makeVM(service)
        await vm.load()

        let action = await vm.resolveTypeChange(to: .dinner)

        guard case let .confirm(_, message) = action else {
            Issue.record("확인을 요구해야 한다: \(String(describing: action))")
            return
        }
        #expect(message.contains("있다면"))
        #expect(!message.contains("합쳐져요"))
    }

    /// **돌려받은 id가 다르면 합쳐진 것이다.** 보던 끼니가 사라졌으므로 화면을 닫아야 한다.
    @Test func 합쳐졌으면_닫으라고_알린다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(id: 1, mealType: .snack)]
        service.changedMealTypeSurvivorId = 42
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.changeMealType(to: .dinner) == .merged)
    }

    @Test func 안_합쳐졌으면_화면에_남는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(id: 1, mealType: .snack), makeMeal(id: 1, mealType: .dinner)]
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.changeMealType(to: .dinner) == .changed)
        // 다시 조회해 제목이 바뀐다.
        #expect(vm.meal?.mealType == .dinner)
    }

    /// **낡은 화면에서도 타입은 바꿀 수 있다.** 항목 편집은 목록을 통째로 보내기 때문에 막지만
    /// (`저장_뒤_재조회가_실패하면_다음_편집을_받지_않는다`), 타입 변경은 **항목을 아예 안
    /// 보낸다** — 되살릴 목록 자체가 없다.
    @Test func 낡은_화면에서도_타입을_바꿀_수_있다() async {
        let service = FakeDietService()
        let kept = makeMealItem(id: 1, name: "밥")
        let target = makeMealItem(id: 2, name: "제육볶음")
        service.meals = [makeMeal(id: 1, mealType: .snack, items: [kept, target])]
        let vm = makeVM(service)
        await vm.load()

        // 저장은 성공하고 그 뒤 재조회만 실패한다 — 이것이 isStale이다.
        service.errors["fetchMeal"] = dietServerError("INTERNAL_ERROR", status: 500)
        _ = await vm.deleteItem(target)
        #expect(vm.isStale)

        let outcome = await vm.changeMealType(to: .dinner)

        #expect(outcome != .failed)
        #expect(service.changedMealTypes.count == 1)
    }

    @Test func 실패하면_화면에_남고_오류가_뜬다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(mealType: .snack)]
        service.errors["changeMealType"] = dietServerError("INTERNAL_ERROR", status: 500)
        let vm = makeVM(service)
        await vm.load()

        #expect(await vm.changeMealType(to: .dinner) == .failed)
        #expect(vm.errorMessage != nil)
    }
```

**`makeMeal`에 `mealType` 인자가 이미 있다**(기본값 `.lunch`). `makeDay(meals:)`도 있다. **`service.meals`는 커서로 순서대로 소비된다** — `안_합쳐졌으면_화면에_남는다`가 두 개를 넣는 것은 첫 `load()`와 변경 후 재조회가 각각 하나씩 쓰기 때문이다.

- [ ] **Step 2: 실패를 확인한다**

Run: `perl -e 'alarm 500; exec @ARGV' xcodebuild build-for-testing -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' > /tmp/t.log 2>&1; grep -E "error:" /tmp/t.log | sort -u | head`

Expected: `value of type 'MealDetailViewModel' has no member 'resolveTypeChange'`

- [ ] **Step 3: 결과 타입 둘을 더한다**

`MealDetailViewModel.swift` 파일 최상위(클래스 **바깥**), `import Foundation` 아래:

```swift
/// 타입을 골랐을 때 화면이 할 일. **문구를 뷰모델에서 정한다** — 「합쳐진다」와 「모르겠다」가
/// 다른 말이라, 뷰가 하나의 문구로 뭉뚱그리면 사용자가 무엇을 승인하는지 모른다
/// (`MealConfirmViewModel.SaveAction`과 같은 모양이고 같은 이유다).
enum MealTypeChangeAction: Equatable {
    case confirm(title: String, message: String)
    case change
}

/// 타입을 바꾼 결과.
enum MealTypeChangeOutcome: Equatable {
    /// 화면에 남는다 — 제목만 바뀐다.
    case changed
    /// **보던 끼니가 사라졌다.** 상세를 닫고 하루로 돌아간다.
    case merged
    case failed
}
```

- [ ] **Step 4: `resolveTypeChange`를 구현한다**

`replaceItem(_:with:)` 아래에 더한다:

```swift
    /// 타입을 고른 뒤 **보내기 전에** 부른다. nil이면 아무것도 하지 않는다(같은 타입).
    ///
    /// **그날을 조회해 합쳐질지 먼저 본다.** 판단은 확정 저장과 같다
    /// (`MealConfirmViewModel.resolveSaveAction`) — 조회가 실패했으면 **모르는 채로 넘어가지
    /// 않고 물어본다.** 「없다」와 「모른다」를 같게 다루면 접속이 잠깐 끊긴 것만으로 보호
    /// 장치가 사라진다.
    func resolveTypeChange(to newType: MealType) async -> MealTypeChangeAction? {
        guard let meal, meal.mealType != newType else { return nil }
        // 간식은 본래 여러 번이라 합쳐지지 않는다 — 물어볼 것이 없다.
        guard newType.mergesWithinDay else { return .change }

        do {
            let day = try await service.fetchDay(date: meal.date)
            guard day.meals.contains(where: { $0.mealType == newType && $0.id != meal.id }) else {
                return .change
            }
            return .confirm(
                title: "이미 기록한 \(newType.label)이 있어요",
                message: "이미 기록한 \(newType.label)에 합쳐져요. 사진도 함께 옮겨져요. 합쳐진 뒤에는 되돌릴 수 없어요."
            )
        } catch {
            return .confirm(
                title: "이미 기록한 \(newType.label)이 있는지 확인하지 못했어요",
                message: "있다면 합쳐지고, 합쳐진 뒤에는 되돌릴 수 없어요."
            )
        }
    }
```

**`$0.id != meal.id`가 필요하다** — 그날 목록에 지금 보고 있는 끼니도 들어 있다. 빼지 않으면 자기 자신을 합칠 대상으로 오해할 수 있다(타입이 다르니 지금은 안 걸리지만, 조건을 읽는 사람이 그걸 매번 다시 증명해야 한다).

- [ ] **Step 5: `changeMealType`을 구현한다**

바로 아래에:

```swift
    /// 실제로 보낸다. **`resolveTypeChange`가 `.change`를 줬거나 사용자가 확인을 누른 뒤**에만
    /// 부른다.
    ///
    /// **돌려받은 id가 원래와 다르면 합쳐진 것이다** — 항목·사진이 대상 끼니로 옮겨지고 이
    /// 끼니는 서버에서 사라졌다. 그 자리에서 다시 조회하면 404다.
    func changeMealType(to newType: MealType) async -> MealTypeChangeOutcome {
        guard let meal, meal.mealType != newType, !isSaving else { return .failed }

        isSaving = true
        defer { isSaving = false }

        do {
            let survivorId = try await service.changeMealType(id: meal.id, to: newType)
            guard survivorId == meal.id else { return .merged }
            await load()
            return .changed
        } catch is CancellationError {
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }
```

**`isStale`을 검사하지 않는다.** 항목 편집은 낡은 목록을 통째로 보내서 막지만, 여기는 **항목을 아예 안 보낸다** — 덮어쓸 목록이 없다.

**합쳐졌으면 `load()`를 부르지 않는다.** 그 id는 이미 없어서 404가 돌아오고, `loadFailed`가 서서 닫히는 화면에 배너가 잠깐 뜬다.

- [ ] **Step 6: `clean test`**

Run: `perl -e 'alarm 500; exec @ARGV' xcodebuild clean test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests > /tmp/t.log 2>&1; grep -E "Test run with|error:" /tmp/t.log | tail -3`

Expected: **325개**(316 + 9), 전부 통과

- [ ] **Step 7: 고의 파손 확인**

1. `resolveTypeChange`의 `guard newType.mergesWithinDay else { return .change }`를 지운다 → `간식으로_바꿀_때는_묻지_않는다`가 빨개진다
2. `catch` 갈래의 문구를 합침 문구와 같게 바꾼다 → `그날_조회에_실패하면_다른_문구로_묻는다`가 빨개진다
3. `changeMealType`의 `guard survivorId == meal.id`를 지우고 항상 `.changed`를 준다 → `합쳐졌으면_닫으라고_알린다`가 빨개진다

셋 다 되돌리고 `git diff`로 확인한다.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 끼니 타입 변경 판단을 뷰모델에 둔다

보내기 전에 그날을 조회해 합쳐질지 먼저 본다. 되돌릴 수 없는 병합이라 조용히
지나가면 안 된다 — 확정 저장이 하는 판단과 같다.

「합쳐진다」와 「모르겠다」는 다른 문구를 쓴다. 조회가 실패했는데 「없다」로
다루면 접속이 잠깐 끊긴 것만으로 보호 장치가 사라진다.

간식으로 바꿀 때는 묻지 않는다 — 간식은 본래 여러 번이라 합쳐지지 않는다.

Claude-Session: https://claude.ai/code/session_01TrC1RZQyYUELJnCGe3CjVD
EOF
```

---

### Task 3: 화면 — 툴바 메뉴와 알럿

**Files:**
- Modify: `WooriHaru/Views/Diet/MealDetailView.swift`

**Interfaces:**
- Consumes: `MealTypeChangeAction`·`MealTypeChangeOutcome`·`resolveTypeChange(to:)`·`changeMealType(to:)`(Task 2)

**이 태스크에는 새 단위 테스트가 없다.** 판단은 전부 Task 2에서 검증됐고 여기 남은 것은 배선이다. **판정은 「기존 325개가 그대로 통과하는 것」**과 아래 실기기 확인이다.

- [ ] **Step 1: 상태 두 개를 더한다**

`MealDetailView`의 `@State` 선언들 옆에:

```swift
    /// 확인을 기다리는 타입 변경. **고른 타입을 함께 들고 있어야** 확인을 누른 뒤 무엇으로
    /// 바꿀지 알 수 있다.
    @State private var pendingTypeChange: PendingTypeChange?

    private struct PendingTypeChange: Identifiable {
        let newType: MealType
        let title: String
        let message: String
        var id: String { newType.rawValue }
    }
```

- [ ] **Step 2: 툴바 메뉴를 단다**

`.navigationBarTitleDisplayMode(.inline)` 아래에 더한다:

```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // 저녁을 먹고 간식으로 저장하는 실수가 흔한데, 지금까지 되돌릴 길이
                    // 없었다(끼니를 통째로 지우면 사진 바이트가 앱에 없어 사진이 사라진다).
                    Picker("끼니 바꾸기", selection: Binding(
                        get: { vm.meal?.mealType ?? .lunch },
                        set: { selectType($0) }
                    )) {
                        ForEach(MealType.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("끼니 바꾸기")
                .disabled(vm.meal == nil || vm.isSaving)
            }
        }
```

- [ ] **Step 3: 고르기와 보내기를 잇는다**

`body` 아래 private 메서드로:

```swift
    /// 고른 즉시 보내지 않는다 — **합쳐질 상황이면 먼저 묻는다.**
    private func selectType(_ newType: MealType) {
        Task {
            guard let action = await vm.resolveTypeChange(to: newType) else { return }
            switch action {
            case let .confirm(title, message):
                pendingTypeChange = PendingTypeChange(newType: newType, title: title, message: message)
            case .change:
                await send(newType)
            }
        }
    }

    private func send(_ newType: MealType) async {
        switch await vm.changeMealType(to: newType) {
        case .changed:
            onChanged()
        case .merged:
            // 보던 끼니가 사라졌다 — 끼니 삭제와 같이 닫는다.
            onChanged()
            dismiss()
        case .failed:
            // 상세의 오류 알럿이 띄운다. 이 화면을 덮는 시트가 없어 그대로 보인다.
            break
        }
    }
```

- [ ] **Step 4: 확인 알럿을 단다**

기존 오류 알럿 아래에:

```swift
        .alert(item: $pendingTypeChange) { pending in
            Alert(
                title: Text(pending.title),
                message: Text(pending.message),
                primaryButton: .default(Text("바꾸기")) {
                    Task { await send(pending.newType) }
                },
                secondaryButton: .cancel(Text("취소"))
            )
        }
```

**`alert(item:)`을 쓰는 이유는 고른 타입을 함께 들고 와야 하기 때문이다.** `isPresented:`로 하면 확인을 누른 시점에 무엇으로 바꿀지 따로 보관해야 하고, 그 보관을 빠뜨리면 **엉뚱한 타입으로 바뀐다.**

- [ ] **Step 5: `clean test`**

Run: `perl -e 'alarm 500; exec @ARGV' xcodebuild clean test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests > /tmp/t.log 2>&1; grep -E "Test run with|error:" /tmp/t.log | tail -3`

Expected: **325개 그대로**, 전부 통과. 새 테스트가 없는 태스크다 — **개수가 줄었으면 배선하다 무언가 잃은 것이다.**

- [ ] **Step 6: 고의 파손 확인 — 이 태스크는 건너뛴다**

새 계약이 없다. 판단은 Task 2에서 이미 파손 확인을 마쳤다.

- [ ] **Step 7: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 상세 화면에서 끼니 타입을 바꾼다

저녁을 먹고 간식으로 저장하는 실수가 흔한데 되돌릴 길이 없었다. 끼니를 통째로
지우고 다시 만들면 사진 바이트가 앱에 없어 찍어 둔 사진이 사라진다.

합쳐질 상황이면 먼저 묻는다. 고른 타입을 알럿과 함께 들고 다니려고
alert(item:)을 쓴다 — isPresented로 하면 확인 시점에 무엇으로 바꿀지 따로
보관해야 하고, 빠뜨리면 엉뚱한 타입으로 바뀐다.

합쳐졌으면 보던 끼니가 사라진 것이라 화면을 닫는다.

Claude-Session: https://claude.ai/code/session_01TrC1RZQyYUELJnCGe3CjVD
EOF
```

---

## 실기기 확인 (사용자 몫)

**서버(`toy-back`)가 배포된 뒤에 한다.** 배포 전에는 `PATCH`가 404다.

시뮬레이터를 띄우지 않는다.

- 간식으로 저장한 끼니를 열어 **저녁으로 바꾼다** — 그날 저녁이 없으면 **묻지 않고** 바로 바뀌고 제목이 「저녁」이 되는지
- 그날 저녁이 **이미 있을 때** 같은 걸 하면 **알럿이 뜨고**, 확인하면 **상세가 닫히며** 하루 화면의 저녁 카드에 항목이 합쳐져 있는지
- **합친 뒤 저녁 카드의 사진이 다 있는지** — 간식 쪽 사진이 뒤에 붙어야 한다(순서가 뒤섞이면 서버의 `sortOrder` 문제다)
- **며칠 뒤에 그 사진이 살아 있는지** — 서버가 병합 삭제에서 `detachFiles`를 불렀다면 정리 배치가 수거해 **나중에 깨진다**
- 저녁을 **간식으로** 바꿀 때는 그날 간식이 있어도 **묻지 않고** 카드가 둘이 되는지
- 메뉴에서 **지금 타입을 그대로 고르면** 아무 일도 없는지(피드백이 「만드는 중」으로 깜빡이지 않는지)
- 타입을 바꾼 뒤 **하루 피드백 문장이 새 타입으로 다시 쓰이는지** — 「간식: 치킨」이 남아 있으면 서버가 `contentUpdatedAt`을 안 올린 것이다
- **사진으로 인식한 항목을 합칠 때 「추정」 배지가 살아남는지** — 상세 화면의 항목 배지와 하루 화면의 「추정 N건」 둘 다. 사라지면 서버가 병합에서 `MealItem.source`를 흘린 것이다(`toy-back` 설계 ③의 필드 보존)
- **합친 뒤 하루 점수·목표가 갑자기 움직였다면 앱 버그가 아닐 수 있다** — 사라진 쪽이 그날 첫 끼니였고 그 사이 프로필을 바꿨으면 하루 목표가 두 번째 끼니의 스냅샷으로 넘어간다(`toy-back` 설계 함정 5, 「그대로 둔다」로 정한 알려진 결과). 프로필을 바꾼 적이 없는데도 움직이면 그건 진짜 문제다
