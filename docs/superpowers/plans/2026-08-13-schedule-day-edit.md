# 스케줄표 하루 편집 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 스케줄표 달력 칸을 눌러 그날의 아빠·엄마 근무와 순번을 고친다.

**Architecture:** 모델에 `slotCode`와 편집 요청 타입을 더하고, `DispatchService.editDay`가 `PUT /dispatch/shifts/{date}`를 부른다. 편집 폼 상태는 `ScheduleDayEditViewModel`이 홀로 들고, `ScheduleViewModel`은 저장 응답을 받아 그 날짜의 badge만 갈아 끼운다. 화면은 `ScheduleDayEditSheet`가 새로 맡고 `ScheduleDayCellView`는 탭과 `slotCode` 표시만 더한다.

**Tech Stack:** Swift 6 / SwiftUI / `@Observable` / swift-testing(`@Test`, `#expect`)

## Global Constraints

- 서버는 `toy-back`의 `feat/dispatch-day-edit-spec` 브랜치에 **이미 구현돼 있다**(`11cb1b8`). 계약은 `toy-back/docs/superpowers/specs/2026-08-13-dispatch-day-edit-design.md`. 앱 테스트는 대역(fake)으로 검증하고, 실제 왕복은 기기에서 확인한다.
- 설계 문서: `docs/superpowers/specs/2026-08-13-schedule-day-edit-design.md`. 여기 적힌 판단과 어긋나게 구현하지 않는다.
- 날짜 계산은 `Calendar.dispatchGregorian`(주입된 `calendar`)만 쓴다. `Date+Extensions`의 `.day`·`.month`·`.year`·`.weekday`는 `Calendar.current`(기기 설정)를 타므로 쓰지 않는다. **`.dateString`은 예외로 써도 된다** — 고정 포맷터(`ko_KR` + `yyyy-MM-dd`)라 기기 달력을 타지 않고, 기존 `ScheduleView`가 이미 조회 키로 쓰고 있다.
- 아빠 순번 선택지는 `1`, `2`. 엄마 순번 선택지는 `"A"`, `"B"`, `"C"`. **저장된 값이 선택지에 없으면 그 값도 선택지에 함께 넣는다.**
- 주석과 커밋 메시지는 한국어. 커밋 형식은 `feat: ~한다` / `fix: ~한다` / `docs: ~한다`.
- 빌드·테스트 명령:
  ```bash
  xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:WooriHaruTests/<테스트타입이름> 2>&1 | tail -30
  ```
  전체는 `-only-testing`을 빼고 돌린다.

---

### Task 1: 모델 — `slotCode`와 편집 요청 타입

**Files:**
- Modify: `WooriHaru/Models/DispatchModels.swift`
- Test: `WooriHaruTests/DispatchTests.swift` (`DispatchModelTests`)

**Interfaces:**
- Consumes: 없음
- Produces:
  - `DispatchShiftDay.slotCode: String?` (기존 `date`·`role`·`working`·`slot`·`note` 뒤에 온다)
  - `struct DispatchRoleEdit: Encodable, Equatable { let working: Bool; let slot: Int?; let slotCode: String? }`
  - `struct DispatchDayEditRequest: Encodable, Equatable { let father: DispatchRoleEdit?; let mother: DispatchRoleEdit? }`

**주의:** `DispatchShiftDay`에 필드를 더하면 이 타입을 만드는 **기존 테스트가 전부 컴파일 실패한다**(`ScheduleTests.swift`에 다수, `DispatchTests.swift`에 일부). Step 3에서 한꺼번에 고친다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DispatchTests.swift`의 `DispatchModelTests` 안에 더한다.

```swift
    @Test func 조회_응답의_순번코드를_디코딩한다() throws {
        let json = """
        {"data":{"days":[
          {"date":"2026-08-15","role":"MOTHER","working":true,"slot":null,"slotCode":"A","note":null}
        ]}}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DataResponse<DispatchShiftRange>.self, from: json)

        #expect(decoded.data?.days.first?.slotCode == "A")
    }

    /// 서버가 아직 내려주지 않는 동안에도 조회가 깨지지 않아야 한다.
    @Test func 순번코드가_없어도_디코딩된다() throws {
        let json = """
        {"data":{"days":[
          {"date":"2026-08-15","role":"FATHER","working":true,"slot":1,"note":null}
        ]}}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DataResponse<DispatchShiftRange>.self, from: json)

        #expect(decoded.data?.days.first?.slotCode == nil)
    }

    @Test func 하루_편집_요청은_건드린_역할만_싣는다() throws {
        let request = DispatchDayEditRequest(
            father: nil,
            mother: DispatchRoleEdit(working: true, slot: nil, slotCode: "B")
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // **키 자체가 없어야 한다.** null로 나가면 서버가 「비우라」로 읽을 여지가 생긴다.
        #expect(json["father"] == nil)
        let mother = try #require(json["mother"] as? [String: Any])
        #expect(mother["working"] as? Bool == true)
        #expect(mother["slotCode"] as? String == "B")
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WooriHaruTests/DispatchModelTests 2>&1 | tail -30
```
Expected: 컴파일 실패 — `cannot find 'DispatchDayEditRequest' in scope`, `value of type 'DispatchShiftDay' has no member 'slotCode'`

- [ ] **Step 3: 모델을 더하고 기존 호출부를 고친다**

`WooriHaru/Models/DispatchModels.swift`의 `DispatchShiftDay`를 이렇게 바꾼다.

```swift
/// 조회된 하루. 엄마는 패턴에서 계산돼 내려오므로 `slot`이 늘 nil이다.
struct DispatchShiftDay: Codable, Equatable {
    /// `2026-08-01` 형식.
    let date: String
    let role: DispatchRole
    /// 그날 일하는가. **판정은 이 값만 본다** — `slot`이 nil이어도 근무일 수 있다.
    let working: Bool
    let slot: Int?
    /// 엄마 근무조(`A`·`B`·`C`). 아빠는 늘 nil이다 — 아빠 순번은 정수 `slot`이다.
    ///
    /// **옵셔널로 두어 없는 응답도 받는다.** 서버가 이 필드를 내려주기 전에 앱이 먼저
    /// 배포될 수 있고, 그때 조회가 통째로 디코딩 실패로 죽으면 달력이 빈다.
    let slotCode: String?
    /// 칸의 원문. 달력에는 쓰지 않는다 — 무인증 응답에 실려 나가는 자유 입력이다.
    let note: String?
}
```

같은 파일 `DispatchShiftSaveRequest` 아래에 더한다.

```swift
/// 하루 편집에서 역할 하나를 어떻게 바꿀지.
///
/// **아빠는 `slot`, 엄마는 `slotCode`다.** 한 필드에 정수와 문자를 겹쳐 담지 않는다 —
/// 겹치면 같은 값의 뜻이 역할마다 갈려, 엄마 순번이 늘어나는 순간 무너진다.
/// 역할에 맞지 않는 필드를 보내면 서버가 400을 낸다.
struct DispatchRoleEdit: Encodable, Equatable {
    let working: Bool
    let slot: Int?
    let slotCode: String?
}

/// 날짜 하나의 편집 요청. **손대지 않은 역할은 nil로 두어 아예 보내지 않는다.**
///
/// 아빠 배차표를 아직 안 올린 달에 엄마만 고칠 때, 아빠까지 값을 실어 보내면 사람이
/// 고른 적 없는 「휴무」가 그 달 아빠의 첫 레코드로 생긴다. 「저장된 적 없음」과 「휴무」는
/// 조회에서 이미 갈리는 상태다.
///
/// `JSONEncoder`는 nil 프로퍼티의 키를 아예 빼므로 별도 처리가 필요 없다.
struct DispatchDayEditRequest: Encodable, Equatable {
    let father: DispatchRoleEdit?
    let mother: DispatchRoleEdit?
}
```

이제 `DispatchShiftDay(...)`를 부르는 기존 테스트가 전부 깨진다. **`slotCode:`를 `slot:`과 `note:` 사이에 끼워 넣는다.** 다음으로 위치를 찾는다.

```bash
grep -rn "DispatchShiftDay(" WooriHaruTests/ WooriHaru/
```

전부 `slotCode: nil`을 넣으면 된다. 예:

```swift
DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, slotCode: nil, note: nil)
```

- [ ] **Step 4: 통과를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```
Expected: 전체 PASS (모든 타겟이 다시 컴파일돼야 하므로 여기서는 전체를 돌린다)

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/DispatchModels.swift WooriHaruTests/
git commit -m "feat: 근무 모델에 엄마 순번코드와 하루 편집 요청을 더한다"
```

---

### Task 2: 서비스 — `editDay`

**Files:**
- Modify: `WooriHaru/Services/DispatchService.swift`
- Modify: `WooriHaruTests/ScheduleTests.swift` (`FakeScheduleService`에 새 메서드)
- Modify: `WooriHaruTests/DispatchTests.swift` (`FakeDispatchService`에 새 메서드, `DispatchServiceTests`에 새 테스트)

**Interfaces:**
- Consumes: `DispatchDayEditRequest`, `DispatchRoleEdit` (Task 1)
- Produces: `DispatchServing.editDay(date: String, request: DispatchDayEditRequest) async throws`
  - `date`는 `2026-08-15` 형식이고 경로에 그대로 붙는다.
  - **서버가 `204 No Content`를 준다. 반환값이 없다.**

**MockAPIClient는 손대지 않는다.** `putVoid`가 이미 호출을 `putVoidCalls`에 기록하고 `errors["PUT 경로"]`로 실패도 만들 수 있다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DispatchTests.swift`의 `DispatchServiceTests` 안에 더한다.

```swift
    @Test func 하루_편집은_날짜를_경로에_붙인다() async throws {
        let api = MockAPIClient()
        let service = DispatchService(api: api)

        try await service.editDay(
            date: "2026-08-15",
            request: DispatchDayEditRequest(
                father: nil,
                mother: DispatchRoleEdit(working: true, slot: nil, slotCode: "A")
            )
        )

        #expect(api.putVoidCalls.map(\.path) == ["/dispatch/shifts/2026-08-15"])
    }

    /// 204라 본문이 없다. 디코딩을 기대하면 성공한 저장이 실패로 보인다.
    @Test func 하루_편집은_204라_본문을_기대하지_않는다() async throws {
        let api = MockAPIClient()
        let service = DispatchService(api: api)

        try await service.editDay(
            date: "2026-08-15",
            request: DispatchDayEditRequest(
                father: DispatchRoleEdit(working: false, slot: nil, slotCode: nil),
                mother: nil
            )
        )

        let body = try #require(api.putVoidCalls.first?.body as? DispatchDayEditRequest)
        #expect(body.father == DispatchRoleEdit(working: false, slot: nil, slotCode: nil))
        #expect(body.mother == nil)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WooriHaruTests/DispatchServiceTests 2>&1 | tail -30
```
Expected: 컴파일 실패 — `value of type 'DispatchService' has no member 'editDay'`

- [ ] **Step 3: 프로토콜과 구현을 더한다**

`WooriHaru/Services/DispatchService.swift`의 `DispatchServing`에 더한다.

```swift
    /// 날짜 하나의 근무를 고친다. **보낸 역할만 바뀐다** — nil인 역할은 서버가 건드리지 않는다.
    ///
    /// **응답이 없다(204).** 호출자는 자기가 보낸 값을 이미 알고 있고, 안 보낸 역할은
    /// 서버도 건드리지 않으므로 화면에 그려진 그대로다. 두 역할이 한 트랜잭션이라
    /// 204를 받으면 보낸 것이 전부 들어갔다.
    func editDay(date: String, request: DispatchDayEditRequest) async throws
```

`DispatchService`에 구현을 더한다.

```swift
    func editDay(date: String, request: DispatchDayEditRequest) async throws {
        try await api.putVoid("/dispatch/shifts/\(date)", body: request)
    }
```

프로토콜에 메서드를 더했으므로 **기존 대역 두 개가 컴파일 실패한다.** 각각에 더한다.

`WooriHaruTests/ScheduleTests.swift`의 `FakeScheduleService` — 이 대역을 Task 3의 편집 뷰모델 테스트가 쓴다.

```swift
    /// 하루 편집이 받은 인자. Task 3의 뷰모델 테스트가 본다.
    var editError: Error?
    private(set) var editCalls: [(date: String, request: DispatchDayEditRequest)] = []

    func editDay(date: String, request: DispatchDayEditRequest) async throws {
        editCalls.append((date, request))
        if let editError { throw editError }
    }
```

`WooriHaruTests/DispatchTests.swift`의 `FakeDispatchService` — 업로드·검수 화면 대역이라 이 경로를 쓰지 않는다.

```swift
    func editDay(date: String, request: DispatchDayEditRequest) async throws {
        fatalError("이 화면은 하루를 고치지 않는다")
    }
```

- [ ] **Step 4: 통과를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```
Expected: 전체 PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/DispatchService.swift WooriHaruTests/
git commit -m "feat: 하루 근무를 고치는 API 호출을 더한다"
```

---

### Task 3: 편집 폼 뷰모델

**Files:**
- Create: `WooriHaru/ViewModels/ScheduleDayEditViewModel.swift`
- Create: `WooriHaruTests/ScheduleDayEditTests.swift`

**Interfaces:**
- Consumes: `DispatchServing.editDay` (Task 2), `ScheduleViewModel.Badge`는 쓰지 않는다 — 초기값은 `[DispatchShiftDay]`로 받는다(휴무와 미등록을 구분해야 하는데 `Badge`는 근무일만 담는다).
- Produces:
  - `@MainActor @Observable final class ScheduleDayEditViewModel`
  - `init(date: String, dayLabel: String, days: [DispatchShiftDay], service: DispatchServing = DispatchService())`
  - `enum Working: Equatable { case working, off }`
  - `var fatherWorking: Working?` / `var motherWorking: Working?` (nil = 미등록·미선택)
  - `var fatherSlot: Int?` / `var motherSlotCode: String?`
  - `var fatherSlotOptions: [Int]` / `var motherSlotCodeOptions: [String]`
  - `var canSave: Bool`
  - `private(set) var isSaving: Bool` / `private(set) var errorMessage: String?`
  - `func save() async -> [DispatchShiftDay]?` — 성공하면 **앱이 만든** 그날의 최종 상태, 실패하면 nil
  - `let date: String` / `let dayLabel: String`

**서버는 `204`를 준다.** 그래서 갈아 끼울 값을 여기서 만든다 — 건드린 역할은 폼의 값으로, 손대지 않은 역할은 시트를 열 때 받은 원본 그대로. `note`도 원본을 지킨다(서버가 건드리지 않는 값이다).

**설계 근거(주석에 남길 것):** 「건드렸다」를 값의 변화로 추론하지 않고 **선택 자체를 옵셔널로 둔다.** 미등록은 값이 없는 상태이고, 사용자가 근무/휴무 중 하나를 누른 순간 그 역할이 보낼 대상이 된다. 이미 저장된 역할은 그 값으로 시작하므로 처음부터 보낼 대상이다 — 아무것도 안 바꾸고 저장하면 같은 값이 다시 저장되는데, upsert라 결과가 같다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ScheduleDayEditTests.swift`를 새로 만든다.

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct ScheduleDayEditViewModelTests {
    private func day(
        _ role: DispatchRole,
        working: Bool,
        slot: Int? = nil,
        slotCode: String? = nil,
        note: String? = nil
    ) -> DispatchShiftDay {
        DispatchShiftDay(date: "2026-08-15", role: role, working: working, slot: slot, slotCode: slotCode, note: note)
    }

    private func makeViewModel(
        days: [DispatchShiftDay],
        service: FakeScheduleService = FakeScheduleService(days: [])
    ) -> ScheduleDayEditViewModel {
        ScheduleDayEditViewModel(date: "2026-08-15", dayLabel: "8월 15일 (토)", days: days, service: service)
    }

    @Test func 미등록인_역할은_선택_없이_시작한다() {
        let vm = makeViewModel(days: [day(.mother, working: true)])

        #expect(vm.fatherWorking == nil)
        #expect(vm.motherWorking == .working)
    }

    @Test func 아무것도_건드리지_않으면_저장이_잠긴다() {
        let vm = makeViewModel(days: [])

        #expect(vm.canSave == false)
    }

    @Test func 한_역할만_고르면_저장이_열린다() {
        let vm = makeViewModel(days: [])

        vm.motherWorking = .off

        #expect(vm.canSave)
    }

    @Test func 건드린_역할만_요청에_실린다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        vm.motherSlotCode = "B"
        _ = await vm.save()

        #expect(service.editCalls.count == 1)
        #expect(service.editCalls.first?.date == "2026-08-15")
        #expect(service.editCalls.first?.request.father == nil)
        #expect(service.editCalls.first?.request.mother == DispatchRoleEdit(working: true, slot: nil, slotCode: "B"))
    }

    @Test func 이미_저장된_역할은_그대로_다시_실린다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 2)], service: service)

        vm.motherWorking = .off
        _ = await vm.save()

        #expect(service.editCalls.first?.request.father == DispatchRoleEdit(working: true, slot: 2, slotCode: nil))
        #expect(service.editCalls.first?.request.mother == DispatchRoleEdit(working: false, slot: nil, slotCode: nil))
    }

    @Test func 휴무를_고르면_순번이_비워진다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 1)], service: service)

        vm.fatherWorking = .off
        _ = await vm.save()

        #expect(service.editCalls.first?.request.father == DispatchRoleEdit(working: false, slot: nil, slotCode: nil))
    }

    @Test func 순번_선택지는_1과_2다() {
        let vm = makeViewModel(days: [])

        #expect(vm.fatherSlotOptions == [1, 2])
        #expect(vm.motherSlotCodeOptions == ["A", "B", "C"])
    }

    /// 사진 인식이 넣어 둔 값이 선택지에 없으면, 휴무만 고치려던 저장이 순번을 조용히 지운다.
    @Test func 선택지에_없는_저장값도_선택지에_들어간다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 3)], service: service)

        #expect(vm.fatherSlotOptions == [1, 2, 3])
        #expect(vm.fatherSlot == 3)

        vm.motherWorking = .off
        _ = await vm.save()

        #expect(service.editCalls.first?.request.father?.slot == 3)
    }

    /// 서버는 204라 돌려주는 것이 없다. 화면에 그릴 값은 여기서 만든다.
    @Test func 저장에_성공하면_보낸_값으로_그날을_만든다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        vm.motherSlotCode = "A"
        let result = await vm.save()

        #expect(result == [day(.mother, working: true, slotCode: "A")])
        #expect(vm.errorMessage == nil)
    }

    /// 화면에서 건드리지 않은 역할도 결과에 원본값 그대로 담긴다.
    @Test func 결과에_기존_역할이_원본값으로_담긴다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 2, note: "*97")], service: service)

        vm.motherWorking = .off
        let result = await vm.save()

        #expect(result?.contains(day(.father, working: true, slot: 2, note: "*97")) == true)
        #expect(result?.contains(day(.mother, working: false)) == true)
    }

    /// `note`는 이 경로에서 읽지도 쓰지도 않는다. 화면 값에서도 지워지면 안 된다.
    @Test func 고친_역할의_메모도_남는다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 1, note: "간담회")], service: service)

        vm.fatherSlot = 2
        let result = await vm.save()

        #expect(result == [day(.father, working: true, slot: 2, note: "간담회")])
    }

    /// 미등록인 채로 남은 역할은 레코드가 없다. 휴무로 만들어 두면 달력이 거짓말을 한다.
    @Test func 미등록으로_남은_역할은_결과에_없다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        let result = await vm.save()

        #expect(result?.contains { $0.role == .father } == false)
    }

    @Test func 저장에_실패하면_nil을_주고_메시지를_남긴다() async {
        let service = FakeScheduleService(days: [])
        service.editError = APIError.serverError(statusCode: 400, message: "엄마 순번은 slotCode입니다")
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        let result = await vm.save()

        #expect(result == nil)
        #expect(vm.errorMessage == "엄마 순번은 slotCode입니다")
        #expect(vm.isSaving == false)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WooriHaruTests/ScheduleDayEditViewModelTests 2>&1 | tail -30
```
Expected: 컴파일 실패 — `cannot find 'ScheduleDayEditViewModel' in scope`

- [ ] **Step 3: 뷰모델을 만든다**

`WooriHaru/ViewModels/ScheduleDayEditViewModel.swift`

```swift
import Foundation

/// 날짜 하나의 근무를 고치는 폼. **역할마다 「아직 고르지 않음」이 따로 있다.**
///
/// 데이터에는 근무·휴무 말고 **미등록**(레코드 없음)이 있다. 아빠 배차표를 아직 안 올린
/// 달이 통째로 그 상태다. 미등록을 휴무로 미리 칠해 두면, 엄마만 고치려고 연 시트에서
/// 저장 한 번에 아빠의 그 달 첫 레코드가 사람이 고른 적 없는 「휴무」로 생긴다.
///
/// 그래서 선택 자체를 옵셔널로 둔다. 값이 nil인 역할은 요청에 실리지 않고 서버도
/// 건드리지 않는다.
@MainActor
@Observable
final class ScheduleDayEditViewModel {
    enum Working: Equatable {
        case working
        case off
    }

    /// 아빠 순번 선택지. 실제로 쓰이는 값이 둘뿐이라 자유 입력을 열지 않는다 —
    /// 열면 숫자 아닌 값과 오타를 거르는 검증이 따라붙는다.
    private static let baseFatherSlots = [1, 2]
    private static let baseMotherSlotCodes = ["A", "B", "C"]

    let date: String
    /// `8월 15일 (토)`처럼 이미 만들어진 제목. **여기서 날짜를 다시 계산하지 않는다** —
    /// 기기 달력이 비그레고리력이면 달력 칸과 시트 제목이 서로 다른 날을 가리킨다.
    let dayLabel: String

    private let service: DispatchServing

    /// 시트를 열 때 받은 그날의 원본. **저장 성공 뒤 화면에 그릴 값을 여기서 만든다** —
    /// 서버가 204라 돌려주는 것이 없다. 손대지 않은 역할과 `note`가 여기서 나온다.
    private let originalDays: [DispatchShiftDay]

    var fatherWorking: Working? {
        didSet { if fatherWorking == .off { fatherSlot = nil } }
    }

    var motherWorking: Working? {
        didSet { if motherWorking == .off { motherSlotCode = nil } }
    }

    var fatherSlot: Int?
    var motherSlotCode: String?

    private(set) var fatherSlotOptions: [Int]
    private(set) var motherSlotCodeOptions: [String]

    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init(
        date: String,
        dayLabel: String,
        days: [DispatchShiftDay],
        service: DispatchServing = DispatchService()
    ) {
        self.date = date
        self.dayLabel = dayLabel
        self.service = service
        self.originalDays = days

        let father = days.first { $0.role == .father }
        let mother = days.first { $0.role == .mother }

        self.fatherWorking = father.map { $0.working ? .working : .off }
        self.motherWorking = mother.map { $0.working ? .working : .off }
        self.fatherSlot = father?.slot
        self.motherSlotCode = mother?.slotCode

        // **저장된 값이 선택지에 없으면 함께 넣는다.** 사진 인식이 `3`을 넣어 둔 날을
        // 열었을 때 선택이 비어 보이면, 휴무만 고치려던 저장이 순번을 조용히 지운다.
        self.fatherSlotOptions = Self.options(base: Self.baseFatherSlots, current: father?.slot)
        self.motherSlotCodeOptions = Self.options(base: Self.baseMotherSlotCodes, current: mother?.slotCode)
    }

    /// 건드린 역할이 하나라도 있어야 보낼 것이 있다.
    var canSave: Bool {
        !isSaving && (fatherWorking != nil || motherWorking != nil)
    }

    /// 성공하면 **그 날짜의 최종 상태**를, 실패하면 nil을 준다.
    /// 실패해도 시트를 닫지 않으므로 화면은 `errorMessage`를 그대로 보여 준다.
    ///
    /// 서버는 204라 돌려주는 것이 없다. **두 역할이 한 트랜잭션이므로 204를 받으면 보낸
    /// 것이 전부 들어갔고**, 안 보낸 역할은 서버가 건드리지 않아 원본 그대로다. 그래서
    /// 최종 상태를 여기서 만들 수 있다.
    func save() async -> [DispatchShiftDay]? {
        guard canSave else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let father = fatherWorking.map { edit(working: $0, slot: fatherSlot, slotCode: nil) }
        let mother = motherWorking.map { edit(working: $0, slot: nil, slotCode: motherSlotCode) }

        do {
            try await service.editDay(
                date: date,
                request: DispatchDayEditRequest(father: father, mother: mother)
            )
        } catch is CancellationError {
            return nil
        } catch {
            // 서버 메시지가 이미 사용자용 한국어다. 봉투 JSON째 보여주지 않는다.
            errorMessage = error.serverMessage ?? error.localizedDescription
            return nil
        }

        return [
            saved(role: .father, edit: father),
            saved(role: .mother, edit: mother)
        ].compactMap { $0 }
    }

    /// 저장 뒤 그 역할의 상태. 보낸 적이 없으면 원본을 그대로 쓰고, 원본도 없으면
    /// **레코드가 없는 것이다** — 없는 것을 휴무로 만들어 두면 달력이 거짓말을 한다.
    ///
    /// `note`는 원본에서 가져온다. 이 경로는 `note`를 보내지 않고 서버도 건드리지 않으므로,
    /// 화면 값에서만 지워지면 다음 조회에 되살아나 잠깐 사라졌다 돌아오는 것처럼 보인다.
    private func saved(role: DispatchRole, edit: DispatchRoleEdit?) -> DispatchShiftDay? {
        let original = originalDays.first { $0.role == role }
        guard let edit else { return original }
        return DispatchShiftDay(
            date: date,
            role: role,
            working: edit.working,
            slot: edit.slot,
            slotCode: edit.slotCode,
            note: original?.note
        )
    }

    /// **휴무면 순번을 싣지 않는다.** 화면에서 이미 비우지만 여기서 한 번 더 못 박는다 —
    /// 두 곳이 어긋나면 휴무인데 순번이 남은 레코드가 생긴다.
    private func edit(working: Working, slot: Int?, slotCode: String?) -> DispatchRoleEdit {
        guard working == .working else {
            return DispatchRoleEdit(working: false, slot: nil, slotCode: nil)
        }
        return DispatchRoleEdit(working: true, slot: slot, slotCode: slotCode)
    }

    private static func options<T: Equatable>(base: [T], current: T?) -> [T] {
        guard let current, !base.contains(current) else { return base }
        return base + [current]
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WooriHaruTests/ScheduleDayEditViewModelTests 2>&1 | tail -30
```
Expected: 전부 PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/ScheduleDayEditViewModel.swift WooriHaruTests/ScheduleDayEditTests.swift WooriHaru.xcodeproj
git commit -m "feat: 하루 근무 편집 폼의 상태를 만든다"
```

---

### Task 4: 달력 뷰모델 — 저장 결과 반영

**Files:**
- Modify: `WooriHaru/ViewModels/ScheduleViewModel.swift`
- Modify: `WooriHaruTests/ScheduleTests.swift`

**Interfaces:**
- Consumes: `DispatchShiftDay` (Task 1)
- Produces:
  - `ScheduleViewModel.Badge`에 `let slotCode: String?` 추가 → `Badge(role:slot:slotCode:)`
  - `func apply(_ days: [DispatchShiftDay], on dateString: String)` — 그 날짜의 badge와 「둘 다 휴무」를 다시 계산한다
  - `func shiftDays(on dateString: String) -> [DispatchShiftDay]` — 편집 시트에 넘길 초기값

**왜 `Badge`로는 부족한가:** `badgesByDate`는 `working == true`인 날만 담는다. 편집 시트는 휴무와 미등록을 갈라야 하므로 원본 `DispatchShiftDay`가 필요하다. **날짜별 원본을 따로 들고 있는다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ScheduleTests.swift`의 `ScheduleViewModelTests` 안에 더한다.

```swift
    @Test func 엄마_순번코드가_밴드에_실린다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: true, slot: nil, slotCode: "A", note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        #expect(vm.badges(on: "2026-08-15") == [ScheduleViewModel.Badge(role: .mother, slot: nil, slotCode: "A")])
    }

    /// 편집 시트는 휴무와 미등록을 갈라야 한다. 밴드는 근무일만 담으므로 원본이 따로 필요하다.
    @Test func 그날의_원본을_휴무까지_돌려준다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: false, slot: nil, slotCode: nil, note: "휴")
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        #expect(vm.shiftDays(on: "2026-08-15").count == 1)
        #expect(vm.shiftDays(on: "2026-08-15").first?.working == false)
        #expect(vm.shiftDays(on: "2026-08-16").isEmpty)
    }

    @Test func 저장_결과가_그_날짜의_밴드를_바꾼다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, slotCode: nil, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()

        vm.apply([
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 2, slotCode: nil, note: nil),
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: true, slot: nil, slotCode: "C", note: nil)
        ], on: "2026-08-15")

        #expect(vm.badges(on: "2026-08-15") == [
            ScheduleViewModel.Badge(role: .mother, slot: nil, slotCode: "C"),
            ScheduleViewModel.Badge(role: .father, slot: 2, slotCode: nil)
        ])
    }

    @Test func 저장_결과가_다른_날짜를_건드리지_않는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-20", role: .father, working: true, slot: 1, slotCode: nil, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()

        vm.apply([
            DispatchShiftDay(date: "2026-08-15", role: .father, working: false, slot: nil, slotCode: nil, note: nil)
        ], on: "2026-08-15")

        #expect(vm.badges(on: "2026-08-20") == [ScheduleViewModel.Badge(role: .father, slot: 1, slotCode: nil)])
        #expect(vm.badges(on: "2026-08-15").isEmpty)
    }

    @Test func 저장으로_둘_다_휴무가_되면_배경이_따라온다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, slotCode: nil, note: nil),
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: false, slot: nil, slotCode: nil, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()
        #expect(vm.isBothOff(on: "2026-08-15") == false)

        vm.apply([
            DispatchShiftDay(date: "2026-08-15", role: .father, working: false, slot: nil, slotCode: nil, note: nil),
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: false, slot: nil, slotCode: nil, note: nil)
        ], on: "2026-08-15")

        #expect(vm.isBothOff(on: "2026-08-15"))
    }

    @Test func 둘_다_휴무였다가_한쪽이_일하면_배경이_사라진다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: false, slot: nil, slotCode: nil, note: nil),
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: false, slot: nil, slotCode: nil, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()
        #expect(vm.isBothOff(on: "2026-08-15"))

        vm.apply([
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, slotCode: nil, note: nil),
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: false, slot: nil, slotCode: nil, note: nil)
        ], on: "2026-08-15")

        #expect(vm.isBothOff(on: "2026-08-15") == false)
    }
```

기존 테스트에서 `Badge(role:slot:)`를 쓰는 곳을 전부 `Badge(role:slot:slotCode:)`로 고친다.

```bash
grep -rn "ScheduleViewModel.Badge(" WooriHaruTests/
```

- [ ] **Step 2: 실패를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WooriHaruTests/ScheduleViewModelTests 2>&1 | tail -30
```
Expected: 컴파일 실패 — `extra argument 'slotCode' in call`, `value of type 'ScheduleViewModel' has no member 'apply'`

- [ ] **Step 3: 뷰모델을 고친다**

`WooriHaru/ViewModels/ScheduleViewModel.swift`.

`Badge`에 `slotCode`를 더한다.

```swift
    /// 칸 하나에 그릴 근무 표시. 순번이 없으면 색만 칠한다.
    /// **아빠는 `slot`, 엄마는 `slotCode`다.** 역할마다 쓰는 필드가 다르다.
    struct Badge: Equatable {
        let role: DispatchRole
        let slot: Int?
        let slotCode: String?
    }
```

날짜별 원본을 들 저장소를 더한다(`badgesByDate` 옆).

```swift
    /// 날짜별 원본. **편집 시트가 휴무와 미등록을 갈라야 해서 필요하다** — `badgesByDate`는
    /// 근무일만 담으므로 「휴무로 저장됨」과 「저장된 적 없음」이 둘 다 빈 값으로 보인다.
    private var daysByDate: [String: [DispatchShiftDay]] = [:]
```

`group`이 `slotCode`를 싣게 한다.

```swift
            result[day.date, default: []].append(Badge(role: day.role, slot: day.slot, slotCode: day.slotCode))
```

`load()`의 성공 분기에서 원본도 담는다.

```swift
            badgesByDate = Self.group(days)
            bothOffDates = Self.datesBothOff(days)
            daysByDate = Dictionary(grouping: days, by: \.date)
```

`show(_:)`에서 이전 달 값을 지울 때 함께 지운다.

```swift
        badgesByDate = [:]
        bothOffDates = []
        daysByDate = [:]
```

조회·반영 메서드를 더한다(`isBothOff` 아래).

```swift
    /// 편집 시트에 넘길 그날의 원본. 휴무도 들어 있고, 미등록이면 비어 있다.
    func shiftDays(on dateString: String) -> [DispatchShiftDay] {
        daysByDate[dateString] ?? []
    }

    /// 하루 편집의 저장 응답을 화면에 반영한다. **그 날짜만 갈아 끼운다.**
    ///
    /// 달 전체를 다시 조회하지 않는다 — 칸 하나를 고치자고 한 달치를 다시 받는 왕복이고,
    /// 그 사이 화면이 잠깐 비었다 채워진다. 서버가 그 날짜의 최종 상태를 돌려주는 이유가
    /// 이것이다.
    ///
    /// **「둘 다 휴무」도 같이 다시 센다.** 밴드만 갈면, 두 사람이 함께 쉬게 된 날의 초록
    /// 배경이 달을 옮겼다 돌아올 때까지 따라오지 않는다.
    func apply(_ days: [DispatchShiftDay], on dateString: String) {
        daysByDate[dateString] = days

        let badges = Self.group(days)[dateString] ?? []
        if badges.isEmpty {
            badgesByDate.removeValue(forKey: dateString)
        } else {
            badgesByDate[dateString] = badges
        }

        if Self.datesBothOff(days).contains(dateString) {
            bothOffDates.insert(dateString)
        } else {
            bothOffDates.remove(dateString)
        }
    }
```

- [ ] **Step 4: 통과를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```
Expected: 전체 PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/ScheduleViewModel.swift WooriHaruTests/ScheduleTests.swift
git commit -m "feat: 하루 저장 결과를 그 칸에만 반영한다"
```

---

### Task 5: 편집 시트 화면

**Files:**
- Create: `WooriHaru/Views/Schedule/ScheduleDayEditSheet.swift`

**Interfaces:**
- Consumes: `ScheduleDayEditViewModel` (Task 3)
- Produces: `struct ScheduleDayEditSheet: View`
  - `init(vm: ScheduleDayEditViewModel, onSaved: @escaping ([DispatchShiftDay]) -> Void)`
  - 저장에 성공하면 `onSaved(days)`를 부르고 스스로 닫는다. 실패하면 닫지 않는다.

**테스트:** SwiftUI 뷰라 단위 테스트를 두지 않는다. 이 저장소의 다른 뷰(`ScheduleView`, `DispatchReviewView`)도 같다 — 판단이 들어가는 부분은 전부 Task 3의 뷰모델에 있다.

- [ ] **Step 1: 시트를 만든다**

`WooriHaru/Views/Schedule/ScheduleDayEditSheet.swift`

```swift
import SwiftUI

/// 날짜 하나의 근무를 고치는 시트. **엄마가 위, 아빠가 아래** — 달력 칸의 밴드 순서와 같다.
/// 화면마다 순서가 뒤집히면 어느 밴드를 고치고 있는지 헷갈린다.
struct ScheduleDayEditSheet: View {
    @State var vm: ScheduleDayEditViewModel
    let onSaved: ([DispatchShiftDay]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                roleSection(
                    title: "엄마",
                    color: .pink500,
                    working: $vm.motherWorking,
                    slotPicker: {
                        Picker("순번", selection: $vm.motherSlotCode) {
                            Text("없음").tag(String?.none)
                            ForEach(vm.motherSlotCodeOptions, id: \.self) { code in
                                Text(code).tag(String?.some(code))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                )

                roleSection(
                    title: "아빠",
                    color: .blue500,
                    working: $vm.fatherWorking,
                    slotPicker: {
                        Picker("순번", selection: $vm.fatherSlot) {
                            Text("없음").tag(Int?.none)
                            ForEach(vm.fatherSlotOptions, id: \.self) { slot in
                                Text("\(slot)").tag(Int?.some(slot))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                )

                if let message = vm.errorMessage {
                    Section {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(vm.dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("저장") { save() }.disabled(!vm.canSave)
                    }
                }
            }
        }
        .onDisappear { saveTask?.cancel() }
    }

    /// 근무/휴무는 **아직 고르지 않음**을 포함한 세 상태다. 미등록인 역할은 아무것도
    /// 선택되지 않은 채로 뜨고, 그 상태로 저장하면 그 역할은 요청에 실리지 않는다.
    @ViewBuilder
    private func roleSection(
        title: String,
        color: Color,
        working: Binding<ScheduleDayEditViewModel.Working?>,
        @ViewBuilder slotPicker: () -> some View
    ) -> some View {
        Section {
            Picker("근무", selection: working) {
                Text("근무").tag(ScheduleDayEditViewModel.Working?.some(.working))
                Text("휴무").tag(ScheduleDayEditViewModel.Working?.some(.off))
            }
            .pickerStyle(.segmented)

            // 휴무면 순번이 없다. 잠그기만 하고 감추지 않는다 — 자리가 들고 나면
            // 근무/휴무를 오갈 때마다 아래 항목이 위아래로 튄다.
            slotPicker()
                .disabled(working.wrappedValue != .working)
        } header: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
                Text(title)
            }
        }
    }

    private func save() {
        saveTask?.cancel()
        saveTask = Task {
            guard let days = await vm.save() else { return }
            onSaved(days)
            dismiss()
        }
    }
}
```

- [ ] **Step 2: 빌드를 확인한다**

Run:
```bash
xcodebuild build -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Views/Schedule/ScheduleDayEditSheet.swift WooriHaru.xcodeproj
git commit -m "feat: 하루 근무를 고치는 시트를 만든다"
```

---

### Task 6: 달력 칸 — `slotCode` 표시와 탭

**Files:**
- Modify: `WooriHaru/Views/Schedule/ScheduleDayCellView.swift`

**Interfaces:**
- Consumes: `ScheduleViewModel.Badge.slotCode` (Task 4)
- Produces: `ScheduleDayCellView(date:day:month:isCurrentMonth:isToday:holidayNames:badges:isBothOff:onTap:)`
  - `let onTap: () -> Void` — 마지막 인자로 더한다.

- [ ] **Step 1: 밴드 글자를 역할에 맞게 고른다**

`badgeRow(for:)`의 `Text(...)` 줄을 바꾼다.

```swift
    /// 아빠는 파랑, 엄마는 분홍. **순번이 있으면 쓰고 없으면 색만 칠한다.**
    /// 아빠는 정수 `slot`, 엄마는 문자 `slotCode`를 쓴다.
    @ViewBuilder
    private func badgeRow(for role: DispatchRole) -> some View {
        if let badge = badges.first(where: { $0.role == role }) {
            Text(Self.label(for: badge))
                .font(.system(size: 10))
                .fontWeight(.bold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.badgeRowHeight)
                .background(role == .father ? Color.blue500 : Color.pink500)
                .foregroundStyle(.white)
                .cornerRadius(2)
        } else {
            Color.clear.frame(height: Self.badgeRowHeight)
        }
    }

    /// 빈 밴드도 높이를 지켜야 하므로 공백 한 칸을 준다.
    private static func label(for badge: ScheduleViewModel.Badge) -> String {
        switch badge.role {
        case .father: return badge.slot.map(String.init) ?? " "
        case .mother: return badge.slotCode ?? " "
        }
    }
```

- [ ] **Step 2: 접근성 문구도 역할에 맞게 고친다**

`accessibilityDescription`의 for 루프 안을 바꾼다.

```swift
        for role in [DispatchRole.mother, .father] {
            guard let badge = badges.first(where: { $0.role == role }) else { continue }
            let who = role == .father ? "아빠" : "엄마"
            let slotText = role == .father ? badge.slot.map(String.init) : badge.slotCode
            parts.append(slotText.map { "\(who) \($0)번 근무" } ?? "\(who) 근무")
        }
```

- [ ] **Step 3: 탭을 받는다**

프로퍼티에 더한다(`isBothOff` 아래).

```swift
    /// 이 칸을 눌렀다. **이번 달 칸에서만 불린다** — 화면에 보이는 달이 아닌 날짜를 고치면
    /// 저장한 뒤 그 결과가 어디에도 보이지 않는다.
    let onTap: () -> Void
```

`body`의 `.background(...)` 아래, `.accessibilityElement` 위에 더한다.

```swift
        // 빈 자리도 눌리게 한다. 숫자나 밴드 위에서만 먹으면 될 때와 안 될 때가 갈려
        // 고장 난 것처럼 느껴진다.
        .contentShape(Rectangle())
        .onTapGesture { if isCurrentMonth { onTap() } }
```

접근성에도 알린다. `.accessibilityLabel(...)` 아래에 더한다.

```swift
        .accessibilityAddTraits(isCurrentMonth ? .isButton : [])
        .accessibilityHint(isCurrentMonth ? "근무 수정 열기" : "")
```

- [ ] **Step 4: 빌드가 깨지는 것을 확인한다**

Run:
```bash
xcodebuild build -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: 실패 — `ScheduleView.swift`가 `onTap`을 넘기지 않는다. Task 7에서 잇는다.

- [ ] **Step 5: 커밋하지 않고 Task 7로 넘어간다**

칸과 화면이 한 번에 맞아야 빌드가 통과한다. 두 Task를 하나의 커밋으로 묶는다.

---

### Task 7: 달력 화면 — 시트 연결

**Files:**
- Modify: `WooriHaru/Views/Schedule/ScheduleView.swift`

**Interfaces:**
- Consumes: `ScheduleDayEditSheet` (Task 5), `ScheduleDayCellView.onTap` (Task 6), `ScheduleViewModel.shiftDays(on:)`·`apply(_:on:)` (Task 4)
- Produces: 없음 (최종 화면)

- [ ] **Step 1: 편집 대상 상태를 더한다**

`@State private var savedMessage: String?` 아래에 더한다.

```swift
    /// 편집 시트에 넘길 뷰모델. **날짜가 아니라 뷰모델을 담는다** — 시트가 뜨는 순간의
    /// 근무 값으로 폼을 채워야 하므로, 만들 때 한 번 읽고 그 뒤로는 시트가 홀로 들고 있는다.
    @State private var editing: ScheduleDayEditViewModel?
```

- [ ] **Step 2: 칸에 탭을 잇는다**

`LazyVGrid` 안의 `ScheduleDayCellView(...)` 호출에 마지막 인자를 더한다.

```swift
                    ScheduleDayCellView(
                        date: cell.date,
                        day: cell.day,
                        month: cell.month,
                        isCurrentMonth: cell.isCurrentMonth,
                        isToday: vm.isToday(cell.date),
                        holidayNames: cell.isCurrentMonth ? vm.holidayNames(on: cell.date.dateString) : [],
                        badges: cell.isCurrentMonth ? vm.badges(on: cell.date.dateString) : [],
                        isBothOff: cell.isCurrentMonth && vm.isBothOff(on: cell.date.dateString),
                        onTap: { openEditor(for: cell) }
                    )
```

- [ ] **Step 3: 시트를 띄운다**

`.sheet(isPresented: $showPicker) { ... }` 아래에 더한다.

```swift
        .sheet(item: $editing) { editVM in
            ScheduleDayEditSheet(vm: editVM) { days in
                vm.apply(days, on: editVM.date)
                savedMessage = "\(editVM.dayLabel) 근무를 저장했습니다."
            }
        }
```

`sheet(item:)`은 `Identifiable`을 요구한다. **`ScheduleDayEditViewModel`에 준수를 더한다** — `WooriHaru/ViewModels/ScheduleDayEditViewModel.swift`의 선언을 바꾼다.

```swift
final class ScheduleDayEditViewModel: Identifiable {
```

그리고 프로퍼티에 더한다(`let date` 아래).

```swift
    /// `sheet(item:)`이 쓴다. 날짜가 곧 이 시트의 정체다.
    nonisolated var id: String { date }
```

- [ ] **Step 4: 여는 함수를 더한다**

`private func reload()` 아래에 더한다.

```swift
    /// **이번 달 칸에서만 연다.** 그리드 앞뒤 패딩(지난달·다음달 날짜)을 고치면 저장한
    /// 결과가 지금 보이는 화면 어디에도 나타나지 않는다.
    ///
    /// 제목의 요일까지 여기서 만든다. 시트가 다시 계산하면 기기 달력이 비그레고리력일 때
    /// 달력 칸과 시트가 서로 다른 날을 가리킨다.
    private func openEditor(for cell: MonthData.DayCell) {
        guard cell.isCurrentMonth else { return }
        let dateString = cell.date.dateString
        editing = ScheduleDayEditViewModel(
            date: dateString,
            dayLabel: dayLabel(for: cell),
            days: vm.shiftDays(on: dateString)
        )
    }

    private func dayLabel(for cell: MonthData.DayCell) -> String {
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let index = Calendar.dispatchGregorian.component(.weekday, from: cell.date) - 1
        return "\(cell.month)월 \(cell.day)일 (\(weekdays[index]))"
    }
```

- [ ] **Step 5: 빌드와 전체 테스트를 확인한다**

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```
Expected: `BUILD SUCCEEDED` + 전체 PASS

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Views/Schedule/
git commit -m "feat: 달력 칸을 눌러 그날 근무를 고친다"
```

---

### Task 8: 실기에서 확인 — **사용자가 직접 한다**

**Files:** 없음 (검증만)

**왜 필요한가:** 설계의 열린 항목 하나가 여기서만 풀린다 — **칸 탭과 달 이동 스와이프가 겹치지 않는가.** `monthSwipe`는 `DragGesture(minimumDistance: 30)`이라 논리상 탭과 갈리지만, 칸이 76pt로 작아 실제로는 손가락이 미세하게 움직여 스와이프로 새는 경우가 있다. 단위 테스트가 닿지 않는 자리이고, 손가락의 흔들림은 시뮬레이터 클릭으로 재현되지도 않는다.

- [ ] **Step 1: 기기에서 다음을 눈으로 확인한다**

- 사이드 메뉴 → 스케줄표 → 아무 칸이나 탭하면 시트가 뜬다
- 좌우로 밀면 시트가 뜨지 않고 달이 넘어간다
- 지난달·다음달 흐린 칸을 탭하면 아무 일도 없다
- 미등록인 날을 열면 근무/휴무 어느 쪽도 선택돼 있지 않다
- 휴무를 고르면 순번 칸이 잠긴다
- 아무것도 안 고르면 저장 버튼이 잠겨 있다
- 저장하면 시트가 닫히고 그 칸의 밴드가 바뀐다. 두 사람이 함께 쉬게 되면 배경이 초록으로 바뀐다
- 엄마 순번을 넣으면 분홍 밴드에 `A`가 뜬다
- 실패하면 **시트가 닫히지 않고** 안에 빨간 메시지가 뜬다

- [ ] **Step 2: 어긋난 것이 있으면 고친다**

칸 탭이 스와이프에 먹히면 `ScheduleDayCellView`의 `.onTapGesture`를 `.simultaneousGesture(TapGesture().onEnded { ... })`로 바꿔 본다.

---

### Task 9: 설계 문서의 열린 항목 정리 — **Task 8 이후**

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-schedule-day-edit-design.md`

- [ ] **Step 1: 「칸 탭과 달 이동 스와이프」 항목을 Task 8의 결과로 바꾼다**

「열린 항목」에서 지우고, 그 자리에 실제로 어떻게 됐는지 한 줄 적는다. 손을 댔다면 무엇을 왜 바꿨는지도 적는다.

- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/specs/2026-08-13-schedule-day-edit-design.md
git commit -m "docs: 칸 탭과 스와이프 확인 결과를 적는다"
```

---

## 남는 것 (이 계획 밖)

- **서버 배포.** 구현은 `toy-back`의 `feat/dispatch-day-edit-spec`(`11cb1b8`)에 있다. 배포 전에는 앱에서 저장이 실패한다.
- **엄마 배차표 사진 인식.** `slotCode`를 채우는 길이 지금은 하루 편집뿐이다.
