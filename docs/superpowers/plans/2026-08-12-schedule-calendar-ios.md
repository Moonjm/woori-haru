# 스케줄표 — 앱 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱에서 근무를 월 단위 달력으로 보고, 업로드 화면에서 연월을 묻지 않는다.

**Architecture:** 스케줄표는 자기 화면(`ScheduleView`)과 자기 셀을 가진다. 기록·파트너·과식에 묶인 `CalendarView`·`DayCellView`는 건드리지 않고, 월 그리드 칸을 만드는 규칙만 `MonthGridBuilder`로 빼서 같이 쓴다. 연월은 서버가 사진에서 읽어 주므로 업로드 화면에서 없애고 검수 화면으로 옮긴다.

**Tech Stack:** SwiftUI, `@MainActor @Observable`, Swift Testing (`@Test`/`#expect`/`#require`)

## Global Constraints

- 설계 문서: `docs/superpowers/specs/2026-08-12-schedule-calendar-design.md`
- **서버 계획이 먼저 끝나야 한다** — `toy-back/docs/superpowers/plans/2026-08-12-schedule-yearmonth-server.md`. Task 1과 Task 5가 그 응답 모양(`yearMonth: String?`)에 의존한다
- 커밋 메시지는 **한국어**
- 색은 `Color+Extensions.swift`에 있는 것만 쓴다. 아빠 `blue500`, 엄마 `purple400`, 공휴일은 기본 달력과 같은 `Color.red.opacity(0.1)` 배경 + `red500` 글자
- 달력에 `note`를 쓰지 않는다 — 무인증 응답에 실려 나가는 자유 입력이다

**테스트 실행**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/<스위트명> 2>&1 | tail -20
```

**`-only-testing`은 파일명이 아니라 스위트명(struct 이름)을 받는다.** 파일명을 넣으면 아무 테스트도 매치되지 않고 **0개가 돌면서 조용히 `TEST SUCCEEDED`가 뜬다.**

| 태스크 | 스위트명 |
|---|---|
| 1 | `DispatchServiceTests`, `DispatchModelTests` |
| 2 | `CalendarMonthTests`, `MonthGridBuilderTests` |
| 3 | `ScheduleViewModelTests` |
| 4 | (뷰 — 전체 실행으로 컴파일만 확인) |
| 5 | `DispatchReviewViewModelTests`, `DispatchUploadViewModelTests` |

전체: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `WooriHaru/Models/DispatchModels.swift` | 배차 API 모델. **수정** — 조회 응답 타입 추가, `yearMonth` nullable |
| `WooriHaru/Services/DispatchService.swift` | 배차 API 호출. **수정** — 조회 추가, 인식에서 연월 제거 |
| `WooriHaru/Views/Calendar/MonthGridBuilder.swift` | **신규** — 월 그리드 칸 생성. 기본 달력과 스케줄표가 함께 쓴다 |
| `WooriHaru/ViewModels/CalendarViewModel.swift` | **수정** — 칸 생성을 `MonthGridBuilder`에 위임 |
| `WooriHaru/ViewModels/ScheduleViewModel.swift` | **신규** — 달 이동, 근무·공휴일 조회, 셀 표시 데이터 |
| `WooriHaru/Views/Schedule/ScheduleView.swift` | **신규** — 헤더, 요일 머리글, 월 그리드 |
| `WooriHaru/Views/Schedule/ScheduleDayCellView.swift` | **신규** — 날짜, 공휴일 밴드, 역할별 근무 밴드 |
| `WooriHaru/ViewModels/DispatchUploadViewModel.swift` | **수정** — 연월 제거 |
| `WooriHaru/ViewModels/DispatchReviewViewModel.swift` | **수정** — 연월 편집·검증, 저장 잠금 |
| `WooriHaru/Views/Dispatch/DispatchUploadView.swift` | **수정** — 연월 칸 제거 |
| `WooriHaru/Views/Dispatch/DispatchReviewView.swift` | **수정** — 연월 칸 추가 |
| `WooriHaru/ContentView.swift`, `WooriHaru/Views/Components/SideDrawerView.swift` | **수정** — `.dispatch` → `.schedule` |

---

### Task 1: 근무 조회 모델과 서비스

**Files:**
- Modify: `WooriHaru/Models/DispatchModels.swift`
- Modify: `WooriHaru/Services/DispatchService.swift`
- Test: `WooriHaruTests/DispatchTests.swift`

**Interfaces:**
- Consumes: 서버 `GET /dispatch/shifts?yearMonth=2026-08` → `{"data":{"days":[{"date":"2026-08-01","role":"FATHER","working":true,"slot":1,"note":null}]}}`
- Produces:
  - `enum DispatchRole: String, Codable { case father = "FATHER"; case mother = "MOTHER" }`
  - `struct DispatchShiftDay: Codable, Equatable { let date: String; let role: DispatchRole; let working: Bool; let slot: Int?; let note: String? }`
  - `DispatchServing.findShifts(yearMonth: String) async throws -> [DispatchShiftDay]`
  - `DispatchServing.recognize(imageData: Data) async throws -> DispatchRecognition` — **`yearMonth` 인자가 사라진다**
  - `DispatchRecognition.yearMonth: String?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DispatchTests.swift`의 `DispatchModelTests`에 추가한다.

```swift
    @Test func 근무_조회_응답을_디코딩한다() throws {
        let json = """
        {"data":{"days":[
          {"date":"2026-08-01","role":"FATHER","working":true,"slot":1,"note":null},
          {"date":"2026-08-01","role":"MOTHER","working":true,"slot":null,"note":null},
          {"date":"2026-08-02","role":"FATHER","working":false,"slot":null,"note":"휴"}
        ]}}
        """
        let response = try JSONDecoder().decode(DataResponse<DispatchShiftRange>.self, from: Data(json.utf8))
        let range = try #require(response.data)

        #expect(range.days.count == 3)
        #expect(range.days[0].role == .father)
        #expect(range.days[1].role == .mother)
        // 엄마는 순번을 넣지 않는다. 근무 판정은 working만 본다.
        #expect(range.days[1].working == true)
        #expect(range.days[1].slot == nil)
    }

    @Test func 인식_응답의_연월은_비어_올_수_있다() throws {
        // 제목이 잘린 사진은 서버가 연월을 못 읽는다. 검수 화면이 채운다.
        let json = """
        {"data":{"yearMonth":null,"hasNameColumn":false,"matchedBy":"ROW_INDEX",
        "rowIndex":2,"rowCount":13,"warnings":["ROSTER_FROM_OTHER_MONTH"],"days":[]}}
        """
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: Data(json.utf8)).data
        )
        #expect(recognition.yearMonth == nil)
    }
```

`DispatchServiceTests`에 추가한다.

```swift
    @Test func 근무를_연월로_조회한다() async throws {
        let api = MockAPIClient()
        api.stubGet("/dispatch/shifts", result: DataResponse(data: DispatchShiftRange(days: [
            DispatchShiftDay(date: "2026-08-01", role: .father, working: true, slot: 1, note: nil)
        ])))
        let service = DispatchService(api: api)

        let days = try await service.findShifts(yearMonth: "2026-08")

        #expect(days.count == 1)
        #expect(api.getCalls.contains { $0.path == "/dispatch/shifts" && $0.query["yearMonth"] == "2026-08" })
    }

    @Test func 인식은_연월을_보내지_않는다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        _ = try await service.recognize(imageData: Data([0x01]))

        let call = try #require(api.multipartJSONCalls.first)
        // 연월은 서버가 사진에서 읽는다. 앱이 보내면 그 값이 기준이 되어 사진 제목을 덮는다.
        #expect(call.query.isEmpty)
    }
```

기존 `DispatchServiceTests.recognition()` 헬퍼의 `yearMonth: String = "2026-08"` 인자는 그대로 두되, `DispatchRecognition(yearMonth:)`에 `String?`가 들어가므로 컴파일은 그대로 통과한다.

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test ... -only-testing:WooriHaruTests/DispatchModelTests`
Expected: 컴파일 실패 — `DispatchShiftRange`가 없다

- [ ] **Step 3: 모델을 더한다**

`DispatchModels.swift`의 `DispatchMatchedBy` 위에 넣는다.

```swift
/// 달력에 표시할 대상. **실명을 쓰지 않는다** — 무인증 조회로 나가는 값이다.
enum DispatchRole: String, Codable, Equatable {
    case father = "FATHER"
    case mother = "MOTHER"
}

/// 조회된 하루. 엄마는 패턴에서 계산돼 내려오므로 `slot`이 늘 nil이다.
struct DispatchShiftDay: Codable, Equatable {
    /// `2026-08-01` 형식.
    let date: String
    let role: DispatchRole
    /// 그날 일하는가. **판정은 이 값만 본다** — `slot`이 nil이어도 근무일 수 있다.
    let working: Bool
    let slot: Int?
    /// 칸의 원문. 달력에는 쓰지 않는다 — 무인증 응답에 실려 나가는 자유 입력이다.
    let note: String?
}

struct DispatchShiftRange: Codable, Equatable {
    let days: [DispatchShiftDay]
}
```

`DispatchRecognition.yearMonth`를 nullable로 바꾼다.

```swift
struct DispatchRecognition: Codable, Equatable {
    /// 사진 제목이 잘려 서버가 못 읽으면 nil이다. **검수 화면이 채운다.**
    let yearMonth: String?
```

- [ ] **Step 4: 서비스를 고친다**

`DispatchService.swift`의 프로토콜과 구현을 바꾼다.

```swift
protocol DispatchServing: Sendable {
    /// 그 달의 근무를 조회한다. **무인증으로 열려 있고 실명이 실리지 않는다.**
    func findShifts(yearMonth: String) async throws -> [DispatchShiftDay]

    /// 사진 한 장을 인식한다. **아무것도 저장되지 않는다** — 검수를 거쳐 `saveShifts`로 확정한다.
    ///
    /// **연월을 보내지 않는다.** 배차표 사진 위에 연월이 적혀 있고 서버가 그것을 읽는다.
    /// 앱이 보내면 그 값이 기준이 되어 사진 제목을 덮으므로, 사람이 손으로 넣은 오타가
    /// 그대로 엉뚱한 달에 저장된다.
    func recognize(imageData: Data) async throws -> DispatchRecognition

    /// 검수 확정분을 저장한다. **보낸 날짜만 갱신된다.**
    func saveShifts(_ request: DispatchShiftSaveRequest) async throws
}
```

```swift
    func findShifts(yearMonth: String) async throws -> [DispatchShiftDay] {
        let response: DataResponse<DispatchShiftRange> = try await api.get(
            "/dispatch/shifts",
            query: ["yearMonth": yearMonth]
        )
        return response.data?.days ?? []
    }

    func recognize(imageData: Data) async throws -> DispatchRecognition {
        let response: DataResponse<DispatchRecognition> = try await api.postMultipart(
            "/dispatch/recognitions",
            query: [:],
            fileData: imageData,
            fileName: "dispatch.jpg",
            mimeType: "image/jpeg"
        )
        guard let recognition = response.data else {
            throw APIError.serverError(statusCode: 200, message: "인식 응답이 비어 있습니다")
        }
        return recognition
    }
```

`DispatchUploadViewModel.recognize()`의 호출부도 함께 고쳐야 컴파일된다 — `service.recognize(imageData: imageData)`. 연월 관련 나머지 정리는 Task 5에서 한다.

- [ ] **Step 5: 통과를 확인한다**

Run: `xcodebuild test ... -only-testing:WooriHaruTests/DispatchModelTests` 그리고 `-only-testing:WooriHaruTests/DispatchServiceTests`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Models/DispatchModels.swift WooriHaru/Services/DispatchService.swift \
        WooriHaru/ViewModels/DispatchUploadViewModel.swift WooriHaruTests/DispatchTests.swift
git commit -m "feat: 근무 조회 API를 붙이고 인식에서 연월을 뺀다"
```

---

### Task 2: 월 그리드 칸 생성을 분리한다

`CalendarViewModel.buildMonthData` 안에 있는 칸 생성 규칙(일요일 시작, 앞뒤 패딩, 셀 id)을 `MonthGridBuilder`로 뺀다. 스케줄표가 같은 규칙을 쓰되 기본 달력을 건드리지 않기 위해서다.

**Files:**
- Create: `WooriHaru/Views/Calendar/MonthGridBuilder.swift`
- Modify: `WooriHaru/ViewModels/CalendarViewModel.swift`
- Test: `WooriHaruTests/CalendarMonthTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `MonthGridBuilder.cells(for startOfMonth: Date, calendar: Calendar) -> [MonthData.DayCell]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/CalendarMonthTests.swift` 맨 아래에 새 스위트를 만든다.

```swift
/// 기본 달력과 스케줄표가 같은 규칙으로 칸을 만든다. 한쪽만 고쳐 어긋나면
/// 두 화면의 날짜가 서로 다른 자리에 놓인다.
@MainActor
struct MonthGridBuilderTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func 일요일_시작으로_앞을_채운다() throws {
        // 2026-08-01은 토요일이라 앞에 6칸이 붙는다.
        let cells = MonthGridBuilder.cells(for: Date.from("2026-08-01")!, calendar: calendar)

        #expect(cells.count % 7 == 0)
        #expect(cells.prefix(while: { !$0.isCurrentMonth }).count == 6)
        #expect(cells.filter(\.isCurrentMonth).count == 31)
    }

    @Test func 패딩이_없는_달도_있다() {
        // 2026-02-01은 일요일이고 28일까지라 정확히 4주다.
        let cells = MonthGridBuilder.cells(for: Date.from("2026-02-01")!, calendar: calendar)

        #expect(cells.count == 28)
        #expect(cells.allSatisfy(\.isCurrentMonth))
    }

    @Test func 셀_id는_유일하다() {
        let cells = MonthGridBuilder.cells(for: Date.from("2026-08-01")!, calendar: calendar)
        #expect(Set(cells.map(\.id)).count == cells.count)
    }

    @Test func 기본_달력과_같은_칸을_만든다() {
        // 기본 달력이 이 빌더를 쓰도록 바꿨는지 확인한다. 한쪽만 고치면 어긋난다.
        let vm = CalendarViewModel()
        let start = Date.from("2026-08-01")!

        let fromViewModel = vm.buildMonthData(start).cells
        let fromBuilder = MonthGridBuilder.cells(for: start, calendar: Calendar.current)

        #expect(fromViewModel.map(\.id) == fromBuilder.map(\.id))
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test ... -only-testing:WooriHaruTests/MonthGridBuilderTests`
Expected: 컴파일 실패 — `MonthGridBuilder`가 없다

- [ ] **Step 3: 빌더를 만든다**

`WooriHaru/Views/Calendar/MonthGridBuilder.swift`:

```swift
import Foundation

/// 한 달의 달력 칸을 만든다. 일요일 시작이고 앞뒤를 이웃 달 날짜로 채워 7의 배수로 맞춘다.
///
/// **기본 달력과 스케줄표가 함께 쓴다.** 규칙이 갈라지면 같은 날짜가 두 화면에서 다른
/// 자리에 놓인다. 순수 함수라 어느 쪽에도 상태를 만들지 않는다.
enum MonthGridBuilder {
    static func cells(for startOfMonth: Date, calendar: Calendar) -> [MonthData.DayCell] {
        let id = startOfMonth.yearMonth
        let leadingEmpties = startOfMonth.weekday - 1
        let daysInMonth = startOfMonth.daysInMonth()

        var cells: [MonthData.DayCell] = []

        // 이전 달 날짜 — id에 `prev`를 넣어 다음 달 같은 날짜와 겹치지 않게 한다.
        for i in (0..<leadingEmpties).reversed() {
            let prevDate = calendar.date(byAdding: .day, value: -(i + 1), to: startOfMonth)!
            cells.append(.init(id: "\(id)-prev-\(prevDate.dateString)", date: prevDate, day: prevDate.day, isCurrentMonth: false))
        }

        for day in 1...daysInMonth {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            cells.append(.init(id: dayDate.dateString, date: dayDate, day: day, isCurrentMonth: true))
        }

        // 다음 달 날짜 — 7의 배수가 될 때까지 채운다.
        let trailing = (7 - cells.count % 7) % 7
        for i in 0..<trailing {
            let nextDate = calendar.date(byAdding: .day, value: daysInMonth + i, to: startOfMonth)!
            cells.append(.init(id: "\(id)-next-\(nextDate.dateString)", date: nextDate, day: nextDate.day, isCurrentMonth: false))
        }

        return cells
    }
}
```

**주의:** 위 코드의 마지막 블록(다음 달 채우기)은 `CalendarViewModel.buildMonthData`의 해당 부분과 **글자 그대로 같아야 한다.** 옮기기 전에 그 파일의 `// 다음 월 날짜` 이후를 열어 id 형식과 반복 범위를 확인하고, 다르면 원본 쪽을 따른다. Step 1의 `기본_달력과_같은_칸을_만든다`가 이 차이를 잡는다.

- [ ] **Step 4: 기본 달력이 빌더를 쓰게 한다**

`CalendarViewModel.buildMonthData`의 칸 생성 부분을 지우고 한 줄로 바꾼다. `year`·`month`·`id` 계산과 반환은 그대로 둔다.

```swift
    func buildMonthData(_ startOfMonth: Date) -> MonthData {
        MonthData(
            id: startOfMonth.yearMonth,
            year: startOfMonth.year,
            month: startOfMonth.month,
            startDate: startOfMonth,
            cells: MonthGridBuilder.cells(for: startOfMonth, calendar: calendar)
        )
    }
```

`MonthData`의 나머지 필드는 기본값(`[:]`)이 있으므로 생략된다.

- [ ] **Step 5: 통과를 확인한다**

Run: `xcodebuild test ... -only-testing:WooriHaruTests/CalendarMonthTests` 그리고 `-only-testing:WooriHaruTests/MonthGridBuilderTests`
Expected: PASS — `CalendarMonthTests`의 기존 그리드 불변식이 그대로 통과해야 한다. 하나라도 깨지면 옮기면서 규칙이 바뀐 것이다.

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Views/Calendar/MonthGridBuilder.swift WooriHaru/ViewModels/CalendarViewModel.swift \
        WooriHaruTests/CalendarMonthTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "refactor: 월 그리드 칸 생성을 MonthGridBuilder로 뺀다"
```

---

### Task 3: ScheduleViewModel

달을 옮기며 근무와 공휴일을 조회하고, 칸에 그릴 값을 만든다.

**Files:**
- Create: `WooriHaru/ViewModels/ScheduleViewModel.swift`
- Test: `WooriHaruTests/ScheduleTests.swift`

**Interfaces:**
- Consumes: `DispatchServing.findShifts(yearMonth:)`, `HolidayService.fetchHolidays(year:)`, `MonthGridBuilder.cells(for:calendar:)`
- Produces:
  - `ScheduleViewModel(service:holidayService:now:calendar:)`
  - `var monthLabel: String` (`"2026년 8월"`)
  - `var cells: [MonthData.DayCell]`
  - `func badges(on dateString: String) -> [ScheduleViewModel.Badge]`
  - `func holidayNames(on dateString: String) -> [String]`
  - `func load() async`, `func move(by months: Int) async`, `func jump(year: Int, month: Int) async`
  - `struct Badge: Equatable { let role: DispatchRole; let slot: Int? }`
  - `var yearMonth: String` (`"2026-08"`), `var pickerYear: Int`, `var pickerMonth: Int`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ScheduleTests.swift`를 새로 만든다.

```swift
import Foundation
import Testing
@testable import WooriHaru

/// 조회 전용 화면이다. 여기서 근무를 고치지 않는다 — 수정은 사진 → 검수 경로로만 한다.
@MainActor
struct ScheduleViewModelTests {
    private func makeViewModel(
        mock: MockAPIClient,
        service: FakeScheduleService
    ) -> ScheduleViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return ScheduleViewModel(
            service: service,
            holidayService: HolidayService(api: mock),
            now: calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!,
            calendar: calendar
        )
    }

    @Test func 진입하면_이번_달을_조회한다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        #expect(vm.yearMonth == "2026-08")
        #expect(vm.monthLabel == "2026년 8월")
        #expect(service.requestedYearMonths == ["2026-08"])
        #expect(vm.badges(on: "2026-08-15") == [ScheduleViewModel.Badge(role: .father, slot: 1)])
    }

    @Test func 휴무는_밴드를_만들지_않는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: false, slot: nil, note: "휴")
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 휴무와 미등록을 구분하지 않는다. 아빠는 그 달 전체를 한 번에 등록하므로
        // 미등록이면 달 전체가 비어 한눈에 보인다.
        #expect(vm.badges(on: "2026-08-15").isEmpty)
    }

    @Test func 순번_없는_근무도_밴드를_만든다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: true, slot: nil, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 엄마는 순번을 넣지 않는다. 색만 칠한다.
        #expect(vm.badges(on: "2026-08-15") == [ScheduleViewModel.Badge(role: .mother, slot: nil)])
    }

    @Test func 아빠와_엄마가_같은_날에_함께_온다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: true, slot: nil, note: nil),
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 2, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 순서를 역할로 고정한다 — 응답 순서대로 그리면 날마다 위아래가 바뀐다.
        #expect(vm.badges(on: "2026-08-15") == [
            ScheduleViewModel.Badge(role: .father, slot: 2),
            ScheduleViewModel.Badge(role: .mother, slot: nil)
        ])
    }

    @Test func 달을_옮기면_그_달을_조회한다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()

        await vm.move(by: 1)
        #expect(vm.yearMonth == "2026-09")

        await vm.move(by: -2)
        #expect(vm.yearMonth == "2026-07")
        #expect(service.requestedYearMonths == ["2026-08", "2026-09", "2026-07"])
    }

    @Test func 해를_넘어도_이동한다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let vm = makeViewModel(mock: mock, service: FakeScheduleService(days: []))
        await vm.load()

        await vm.move(by: 5)

        #expect(vm.yearMonth == "2027-01")
        #expect(vm.monthLabel == "2027년 1월")
    }

    @Test func 공휴일은_달을_오가도_남는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: ["2026-08-15": ["광복절"]]))
        let vm = makeViewModel(mock: mock, service: FakeScheduleService(days: []))

        await vm.load()
        await vm.move(by: 1)
        await vm.move(by: -1)

        // 받은 값을 연 단위로 들고 있어야 한다. 화면 상태 안에만 두고 「이미 받았다」는
        // 표시를 따로 두면 둘이 어긋나 공휴일이 통째로 사라진다(#70).
        #expect(vm.holidayNames(on: "2026-08-15") == ["광복절"])
        #expect(mock.getCalls.filter { $0.path == "/holidays" }.count == 1)
    }

    @Test func 공휴일_조회가_실패해도_근무는_보인다() async {
        let mock = MockAPIClient()
        mock.setError(APIError.serverError(statusCode: 500, message: "nope"), for: "GET /holidays")
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 근무가 주 정보고 공휴일은 부가다. 부가 때문에 화면이 비면 안 된다.
        #expect(vm.badges(on: "2026-08-15").isEmpty == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func 근무_조회가_실패하면_알린다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [])
        service.error = APIError.serverError(statusCode: 500, message: """
        {"status":500,"message":"조회에 실패했습니다.","code":"500","error":"INTERNAL"}
        """)
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        #expect(vm.errorMessage == "조회에 실패했습니다.")
    }

    @Test func 늦게_온_이전_달_응답을_버린다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)
        service.duringFetch = { [vm] in
            // 한 번만 끼어든다. 그대로 두면 move가 부른 load에서 또 걸려 무한히 돈다.
            service.duringFetch = nil
            await vm.move(by: 1)
        }

        await vm.load()

        // 8월 응답이 9월 화면에 그려지면 사용자는 9월에 그 근무가 있다고 믿는다.
        #expect(vm.yearMonth == "2026-09")
        #expect(vm.badges(on: "2026-08-15").isEmpty)
    }
}

/// 조회만 하는 대역. 요청한 연월을 기록한다.
final class FakeScheduleService: DispatchServing, @unchecked Sendable {
    var days: [DispatchShiftDay]
    var error: Error?
    /// 조회가 진행 중인 순간에 끼어들 자리.
    var duringFetch: (@Sendable () async -> Void)?
    private(set) var requestedYearMonths: [String] = []

    init(days: [DispatchShiftDay]) {
        self.days = days
    }

    func findShifts(yearMonth: String) async throws -> [DispatchShiftDay] {
        requestedYearMonths.append(yearMonth)
        await duringFetch?()
        if let error { throw error }
        return days
    }

    func recognize(imageData: Data) async throws -> DispatchRecognition {
        fatalError("이 화면은 인식하지 않는다")
    }

    func saveShifts(_ request: DispatchShiftSaveRequest) async throws {
        fatalError("이 화면은 저장하지 않는다")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test ... -only-testing:WooriHaruTests/ScheduleViewModelTests`
Expected: 컴파일 실패 — `ScheduleViewModel`이 없다

- [ ] **Step 3: 뷰모델을 만든다**

`WooriHaru/ViewModels/ScheduleViewModel.swift`:

```swift
import Foundation

/// 배차 근무를 월 단위로 보여준다. **조회 전용이다** — 여기서 고치지 않는다.
///
/// 서버 조회가 월 단위(`GET /dispatch/shifts?yearMonth=`)라 화면 단위도 한 달로 맞춘다.
/// 기본 달력처럼 세로로 이어 붙이면 화면 단위와 조회 단위가 어긋나 조회가 흩어진다.
@MainActor
@Observable
final class ScheduleViewModel {
    /// 칸 하나에 그릴 근무 표시. 순번이 없으면 색만 칠한다.
    struct Badge: Equatable {
        let role: DispatchRole
        let slot: Int?
    }

    private let service: DispatchServing
    private let holidayService: HolidayService
    private let calendar: Calendar

    private(set) var yearMonth: String
    private(set) var cells: [MonthData.DayCell] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var startOfMonth: Date
    private var badgesByDate: [String: [Badge]] = [:]

    /// 받아 둔 공휴일을 연 단위로 들고 있는다. **달을 옮겨도 남는다.**
    /// 화면 상태 안에만 두고 「이미 받았다」는 표시를 바깥에 따로 두면 둘이 어긋나
    /// 공휴일이 통째로 사라진다 — 기본 달력에서 실제로 그렇게 됐다(#70).
    private var holidaysByYear: [Int: [String: [String]]] = [:]

    /// 달을 옮길 때마다 올린다. 늦게 온 이전 달 응답이 새 달 화면을 채우지 못하게 막는다.
    private var generation = 0

    init(
        service: DispatchServing = DispatchService(),
        holidayService: HolidayService = HolidayService(),
        now: Date = Date(),
        calendar: Calendar = .dispatchGregorian
    ) {
        self.service = service
        self.holidayService = holidayService
        self.calendar = calendar
        let start = now.startOfMonth()
        self.startOfMonth = start
        self.yearMonth = start.yearMonth
        self.cells = MonthGridBuilder.cells(for: start, calendar: calendar)
    }

    var monthLabel: String {
        "\(startOfMonth.year)년 \(startOfMonth.month)월"
    }

    var pickerYear: Int { startOfMonth.year }
    var pickerMonth: Int { startOfMonth.month }

    func badges(on dateString: String) -> [Badge] {
        badgesByDate[dateString] ?? []
    }

    func holidayNames(on dateString: String) -> [String] {
        holidaysByYear[startOfMonth.year]?[dateString] ?? []
    }

    func load() async {
        let token = generation
        isLoading = true
        errorMessage = nil

        await loadHolidaysIfNeeded(year: startOfMonth.year)

        do {
            let days = try await service.findShifts(yearMonth: yearMonth)
            // 조회 중에 달이 바뀌었다. 이 결과는 지금 보이는 달의 것이 아니다.
            guard token == generation else { return }
            badgesByDate = Self.group(days)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            // 서버 메시지가 이미 사용자용 한국어다. 봉투 JSON째 보여주지 않는다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
        guard token == generation else { return }
        isLoading = false
    }

    func move(by months: Int) async {
        guard let next = calendar.date(byAdding: .month, value: months, to: startOfMonth) else { return }
        await show(next)
    }

    func jump(year: Int, month: Int) async {
        guard let next = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return }
        await show(next)
    }

    private func show(_ start: Date) async {
        generation += 1
        startOfMonth = start
        yearMonth = start.yearMonth
        cells = MonthGridBuilder.cells(for: start, calendar: calendar)
        // 이전 달 값을 지운다. 남겨 두면 조회가 끝나기 전까지 이전 달 근무가 새 달에 보인다.
        badgesByDate = [:]
        await load()
    }

    /// **실패해도 조용히 넘어간다.** 근무가 주 정보고 공휴일은 부가다.
    private func loadHolidaysIfNeeded(year: Int) async {
        guard holidaysByYear[year] == nil else { return }
        do {
            holidaysByYear[year] = try await holidayService.fetchHolidays(year: String(year))
        } catch {
            Logger.calendar.error("공휴일 조회 실패: \(year) \(error.localizedDescription)")
        }
    }

    /// 날짜별로 모으고 **역할 순서를 고정한다.** 응답 순서대로 그리면 날마다 위아래가 바뀐다.
    private static func group(_ days: [DispatchShiftDay]) -> [String: [Badge]] {
        var result: [String: [Badge]] = [:]
        for day in days where day.working {
            result[day.date, default: []].append(Badge(role: day.role, slot: day.slot))
        }
        return result.mapValues { badges in
            badges.sorted { lhs, _ in lhs.role == .father }
        }
    }

}
```

`Logger.calendar`는 `WooriHaru/Extensions/Logger+Extensions.swift`에 있다. `CalendarViewModel`이 쓰는 것과 같다.

`MockAPIClient`에는 이미 `setError(_:for:)`가 있다 — 새로 만들지 않는다.

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test ... -only-testing:WooriHaruTests/ScheduleViewModelTests`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/ScheduleViewModel.swift WooriHaruTests/ScheduleTests.swift \
        WooriHaruTests/MockAPIClient.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 스케줄표 뷰모델을 만든다"
```

---

### Task 4: 스케줄표 화면

**Files:**
- Create: `WooriHaru/Views/Schedule/ScheduleView.swift`
- Create: `WooriHaru/Views/Schedule/ScheduleDayCellView.swift`
- Modify: `WooriHaru/ContentView.swift`
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift`

**Interfaces:**
- Consumes: `ScheduleViewModel`, `WeekdayHeaderView`, `MonthPickerSheet`, `DispatchUploadView`
- Produces: `AppDestination.schedule`

- [ ] **Step 1: 셀을 만든다**

`WooriHaru/Views/Schedule/ScheduleDayCellView.swift`:

```swift
import SwiftUI

/// 스케줄표의 한 칸. 날짜 → 공휴일 → 근무 밴드 순으로 쌓는다.
///
/// **근무일에만 밴드를 그린다.** 휴무와 미등록은 둘 다 밴드가 없다 — 아빠는 그 달 전체를
/// 한 번에 등록하므로 미등록이면 달 전체가 비어 한눈에 보이고, 엄마는 패턴이라 늘 채워진다.
struct ScheduleDayCellView: View {
    let date: Date
    let isCurrentMonth: Bool
    let holidayNames: [String]
    let badges: [ScheduleViewModel.Badge]

    static let cellHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("\(date.day)")
                    .font(.system(size: 13))
                    .fontWeight(date.isToday && isCurrentMonth ? .bold : .regular)
                    .foregroundStyle(dateColor)
                Spacer()
            }

            if isCurrentMonth {
                // 공휴일 — 기본 달력과 같은 모양이라 두 화면이 같은 것으로 읽힌다.
                ForEach(holidayNames.prefix(1), id: \.self) { name in
                    Text(name.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(Color.red500)
                        .cornerRadius(2)
                }

                ForEach(badges, id: \.role) { badge in
                    Text(badge.slot.map(String.init) ?? " ")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(badge.role == .father ? Color.blue500 : Color.purple400)
                        .foregroundStyle(.white)
                        .cornerRadius(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .frame(height: Self.cellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var dateColor: Color {
        guard isCurrentMonth else { return .slate300 }
        if !holidayNames.isEmpty || date.weekday == 1 { return .red500 }
        if date.weekday == 7 { return .blue500 }
        return .slate900
    }

    private var accessibilityDescription: String {
        var parts = ["\(date.month)월 \(date.day)일"]
        parts += holidayNames
        for badge in badges {
            let who = badge.role == .father ? "아빠" : "엄마"
            parts.append(badge.slot.map { "\(who) \($0)번 근무" } ?? "\(who) 근무")
        }
        return parts.joined(separator: ", ")
    }
}
```

`ForEach(badges, id: \.role)`이 되려면 `DispatchRole`이 `Hashable`이어야 한다. `String` raw value 열거형이라 자동으로 `Hashable`이다.

- [ ] **Step 2: 화면을 만든다**

`WooriHaru/Views/Schedule/ScheduleView.swift`:

```swift
import SwiftUI

/// 배차 근무 달력. 진입점이고, 오른쪽 위에서 사진 등록으로 들어간다.
struct ScheduleView: View {
    @Binding var navPath: NavigationPath
    @State private var vm = ScheduleViewModel()
    @State private var showPicker = false
    @State private var loadTask: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            WeekdayHeaderView()

            if let message = vm.errorMessage {
                HStack(spacing: 8) {
                    Text(message).font(.footnote).foregroundStyle(.red)
                    Button("다시 시도") { reload() }.font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(vm.cells) { cell in
                    ScheduleDayCellView(
                        date: cell.date,
                        isCurrentMonth: cell.isCurrentMonth,
                        holidayNames: cell.isCurrentMonth ? vm.holidayNames(on: cell.date.dateString) : [],
                        badges: cell.isCurrentMonth ? vm.badges(on: cell.date.dateString) : []
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .navigationTitle("스케줄표")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("사진 등록") { navPath.append(AppDestination.dispatchUpload) }
            }
        }
        .sheet(isPresented: $showPicker) {
            MonthPickerSheet(initialYear: vm.pickerYear, initialMonth: vm.pickerMonth) { year, month in
                loadTask?.cancel()
                loadTask = Task { await vm.jump(year: year, month: month) }
            }
            .presentationDetents([.height(320)])
        }
        .task { await vm.load() }
        // 사진 등록에서 돌아오면 다시 조회한다. 방금 넣은 것이 안 보이면 이 화면의 뜻이 없다.
        .onChange(of: navPath.count) { _, newCount in
            if newCount == 1 { reload() }
        }
        .onDisappear { loadTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").font(.title3).foregroundStyle(Color.slate700)
            }
            .accessibilityLabel("이전 달")

            Button { showPicker = true } label: {
                Text(vm.monthLabel)
                    .font(.title3).fontWeight(.bold).foregroundStyle(Color.slate900)
            }
            .accessibilityHint("연월 선택 열기")

            Button { move(1) } label: {
                Image(systemName: "chevron.right").font(.title3).foregroundStyle(Color.slate700)
            }
            .accessibilityLabel("다음 달")

            Spacer()

            if vm.isLoading { ProgressView() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func move(_ months: Int) {
        loadTask?.cancel()
        loadTask = Task { await vm.move(by: months) }
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await vm.load() }
    }
}
```

**`navPath.count == 1`인 이유:** 드로어에서 `.schedule`을 넣으면 깊이가 1이고, 그 위에 업로드·검수가 쌓인다. 다시 1로 줄었다는 것은 업로드 쪽에서 돌아왔다는 뜻이다.

- [ ] **Step 3: 라우팅을 바꾼다**

`ContentView.swift`의 `AppDestination`에서 `case dispatch`를 두 개로 나눈다.

```swift
    case schedule
    case dispatchUpload
```

`navigationDestination`의 분기도 바꾼다.

```swift
                    case .schedule: ScheduleView(navPath: $path)
                    case .dispatchUpload: DispatchUploadView()
```

`SideDrawerView.swift:85`의 항목을 바꾼다.

```swift
                drawerItem(icon: "calendar", label: "스케줄표") {
                    // 닫는 처리는 기존 코드를 그대로 둔다
                    navPath.append(AppDestination.schedule)
                }
```

- [ ] **Step 4: 빌드와 전체 테스트**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS — 뷰는 테스트가 없으므로 컴파일과 기존 테스트 통과가 기준이다

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Schedule/ WooriHaru/ContentView.swift \
        WooriHaru/Views/Components/SideDrawerView.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 스케줄표 달력 화면을 연다"
```

---

### Task 5: 연월을 업로드에서 검수로 옮긴다

업로드 화면에서 연월을 묻지 않고, 검수 화면에서 확인·수정한다. 연월이 없으면 저장이 잠긴다.

**Files:**
- Modify: `WooriHaru/ViewModels/DispatchUploadViewModel.swift`
- Modify: `WooriHaru/ViewModels/DispatchReviewViewModel.swift`
- Modify: `WooriHaru/Views/Dispatch/DispatchUploadView.swift`
- Modify: `WooriHaru/Views/Dispatch/DispatchReviewView.swift`
- Test: `WooriHaruTests/DispatchTests.swift`

**Interfaces:**
- Consumes: Task 1의 `DispatchRecognition.yearMonth: String?`
- Produces:
  - `DispatchReviewViewModel.yearMonth: String` (읽기 전용), `setYearMonth(_:)`, `isYearMonthValid`
  - `DispatchUploadViewModel`에서 `yearMonth`·`isYearMonthValid`·`defaultYearMonth`·`isValidYearMonth`가 **사라진다**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`DispatchReviewViewModelTests`에 추가한다.

```swift
    @Test func 연월을_못_읽었으면_저장이_잠긴다() {
        let recognition = sampleRecognition(yearMonth: nil)
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 날짜 값은 멀쩡히 있지만 어느 달인지 모른다. 그대로 저장하면 날짜를 만들 수 없다.
        #expect(vm.yearMonth == "")
        #expect(vm.canSave == false)

        vm.setYearMonth("2026-08")
        #expect(vm.canSave == true)
    }

    @Test func 연월_형식이_어긋나면_저장이_잠긴다() {
        let recognition = sampleRecognition(yearMonth: nil)
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 서버 YearMonth 파싱은 2026-3에 400을 낸다.
        for invalid in ["2026-3", "2026-13", "26-08", "2026-08-01", ""] {
            vm.setYearMonth(invalid)
            #expect(vm.isYearMonthValid == false, "\(invalid)는 막아야 한다")
            #expect(vm.canSave == false, "\(invalid)는 막아야 한다")
        }
    }

    @Test func 확정한_연월로_날짜를_만든다() async throws {
        let recognition = sampleRecognition(yearMonth: nil, days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setYearMonth("2026-09")
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days[0].date == "2026-09-01")
    }

    @Test func 연월을_채우면_요일과_말일이_맞춰진다() {
        let recognition = sampleRecognition(yearMonth: nil, days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 연월을 모르면 며칠까지인지도 모른다. 넉넉히 31일로 두고 시작한다.
        #expect(vm.entries.count == 31)
        #expect(vm.entries[0].weekday == "")

        vm.setYearMonth("2026-02")

        // 2026년 2월은 28일까지고 1일은 일요일이다.
        #expect(vm.entries.count == 28)
        #expect(vm.entries[0].weekday == "일")
        // 고쳐 둔 값은 남아야 한다 — 연월을 나중에 채운다고 검수가 날아가면 안 된다.
        #expect(vm.entries[0].working == true)
        #expect(vm.entries[0].slot == 1)
    }

    @Test func 다른_달_기준을_빌려_썼으면_알린다() {
        let recognition = sampleRecognition(yearMonth: nil, warnings: ["ROSTER_FROM_OTHER_MONTH"])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        #expect(vm.warningMessages == [
            "저장된 줄 위치를 다른 달 것으로 맞췄습니다. 순번이 밀리지 않았는지 사진과 대조해 주세요."
        ])
    }
```

`sampleRecognition` 헬퍼에 `yearMonth` 인자를 더한다.

```swift
private func sampleRecognition(
    yearMonth: String? = "2026-08",
    matchedBy: DispatchMatchedBy = .name,
    warnings: [String] = [],
    days: [DispatchRecognitionDay] = [
        DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
    ]
) -> DispatchRecognition {
    DispatchRecognition(
        yearMonth: yearMonth,
        hasNameColumn: matchedBy == .name,
        matchedBy: matchedBy,
        rowIndex: 2,
        rowCount: 13,
        warnings: warnings,
        days: days
    )
}
```

**지워야 하는 테스트.** 업로드 화면에서 연월이 사라지므로 `DispatchUploadViewModelTests`의 다음 테스트를 삭제한다. 남겨 두면 컴파일되지 않는다.

- `연월_형식이_어긋나면_인식할_수_없다`
- `인식_중에_연월을_바꾸면_이전_달_결과를_버린다`
- `기본_연월은_이번_달이다`
- `한자리_월은_0을_채운다`
- `기기_달력이_불교력이어도_그레고리력으로_보낸다`

마지막 것의 알맹이(기기 달력이 아니라 그레고리력을 쓴다)는 검수 화면으로 옮긴다.

```swift
    @Test func 요일은_기기_달력이_아니라_그레고리력으로_센다() {
        // 기기 달력이 불교력이면 Calendar.current가 2569년으로 계산해 요일이 어긋난다.
        #expect(Calendar.dispatchGregorian.identifier == .gregorian)

        let recognition = sampleRecognition(yearMonth: "2026-08")
        let vm = DispatchReviewViewModel(
            recognition: recognition,
            service: FakeDispatchService(recognizeResult: .success(recognition))
        )
        // 2026-08-01은 토요일이다.
        #expect(vm.entries[0].weekday == "토")
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test ... -only-testing:WooriHaruTests/DispatchReviewViewModelTests`
Expected: 컴파일 실패 — `setYearMonth`가 없다

- [ ] **Step 3: 검수 뷰모델을 고친다**

`DispatchReviewViewModel`에서 `calendar`를 보관하고, `yearMonth`를 상태로 둔다.

```swift
    private let recognition: DispatchRecognition
    private let service: DispatchServing
    private let calendar: Calendar

    /// **사진에서 못 읽었으면 빈 문자열이다.** 사람이 채우기 전에는 저장할 수 없다 —
    /// 어느 달인지 모르면 `2026-08-01` 같은 날짜를 만들 수 없다.
    private(set) var yearMonth: String

    init(
        recognition: DispatchRecognition,
        service: DispatchServing = DispatchService(),
        calendar: Calendar = .dispatchGregorian
    ) {
        self.recognition = recognition
        self.service = service
        self.calendar = calendar
        self.yearMonth = recognition.yearMonth ?? ""
        self.entries = Self.buildEntries(from: recognition, yearMonth: recognition.yearMonth, calendar: calendar)
    }

    /// 화면이 형식 오류를 알리고 저장을 잠그는 데 쓴다.
    var isYearMonthValid: Bool {
        Self.isValidYearMonth(yearMonth)
    }

    /// `^\d{4}-(0[1-9]|1[0-2])$`. **월에 0을 채워야 한다** — `2026-3`·`2026-13`은
    /// 서버의 `YearMonth` 파싱이 400을 낸다.
    static func isValidYearMonth(_ value: String) -> Bool {
        value.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil
    }

    /// 연월이 정해지면 **요일과 말일이 따라온다.** 고쳐 둔 값은 날짜 기준으로 옮겨 살린다 —
    /// 연월을 나중에 채운다고 검수한 내용이 날아가면 처음부터 다시 해야 한다.
    func setYearMonth(_ value: String) {
        yearMonth = value
        guard Self.isValidYearMonth(value) else { return }

        let existing = Dictionary(entries.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        let rebuilt = Self.buildEntries(from: recognition, yearMonth: value, calendar: calendar)
        entries = rebuilt.map { entry in
            guard let kept = existing[entry.day] else { return entry }
            var merged = kept
            // 요일만 새 연월 기준으로 갈아 끼운다.
            return DayEntry(
                day: merged.day,
                weekday: entry.weekday,
                recognized: merged.recognized,
                working: merged.working,
                slot: merged.slot,
                note: merged.note,
                conflict: merged.conflict
            )
        }
    }

    var canSave: Bool {
        entries.contains(where: \.recognized) && isYearMonthValid
    }
```

`warningMessages`에 새 코드를 더한다.

```swift
            case "ROSTER_FROM_OTHER_MONTH":
                return "저장된 줄 위치를 다른 달 것으로 맞췄습니다. 순번이 밀리지 않았는지 사진과 대조해 주세요."
```

`save()`의 날짜 생성과 잠금 문구를 바꾼다.

```swift
        guard canSave else {
            errorMessage = isYearMonthValid
                ? "저장할 날짜가 없습니다. 한 날 이상 값을 정해 주세요."
                : "연월을 2026-08처럼 적어 주세요."
            return
        }
```
```swift
                    date: String(format: "%@-%02d", yearMonth, entry.day),
```

`buildEntries`가 연월을 인자로 받게 바꾼다. `recognition.yearMonth` 대신 넘겨받은 값을 쓰고, 없으면 31일·빈 요일로 만든다.

```swift
    private static func buildEntries(
        from recognition: DispatchRecognition,
        yearMonth: String?,
        calendar: Calendar
    ) -> [DayEntry] {
        let recognizedByDay = Dictionary(recognition.days.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        let parsed = yearMonth.flatMap(Self.parseYearMonth)
        // 연월을 모르면 며칠까지인지도 모른다. 넉넉히 31일로 두면 사진에 있던 날이 사라지지 않는다.
        let dayCount = Self.dayCount(of: parsed, calendar: calendar)
        ...
```

`var merged = kept`에서 `var`가 경고를 내면 `let`으로 바꾼다.

- [ ] **Step 4: 업로드 뷰모델에서 연월을 지운다**

`DispatchUploadViewModel`에서 다음을 **삭제**한다.

- `var yearMonth: String`과 `init`의 `now`·`calendar` 인자, `self.yearMonth = ...`
- `var isYearMonthValid`
- `static func isValidYearMonth`, `static func defaultYearMonth`
- `recognize()`의 `requestedYearMonth` 스냅샷과 그 가드 두 곳

`canRecognize`와 `recognize()`는 이렇게 남는다.

```swift
    var canRecognize: Bool {
        imageData != nil && phase != .recognizing
    }
```
```swift
        let token = generation
        do {
            let result = try await service.recognize(imageData: imageData)
            // 인식이 도는 동안 사진이 바뀌었다. **여기서 phase를 건드리면 안 된다** —
            // 새 인식이 이미 시작됐을 수 있고, 그 스피너를 꺼 버리면 유료 요청이 두 번 나간다.
            guard token == generation else { return }
            recognition = result
            phase = .completed
```

- [ ] **Step 5: 화면 둘을 고친다**

`DispatchUploadView`에서 `yearMonthField`와 그 호출, `TextField` 관련 import를 지운다. `VStack`의 첫 줄이 `photoSection`이 된다.

`DispatchReviewView`의 `List` 맨 위(사진 섹션 **위**)에 연월 섹션을 넣는다.

```swift
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("연월").font(.footnote).foregroundStyle(.secondary)
                    TextField(
                        "2026-08",
                        text: Binding(get: { vm.yearMonth }, set: { vm.setYearMonth($0) })
                    )
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    if !vm.isYearMonthValid {
                        // 사진 제목이 잘리면 서버가 못 읽는다. 사진을 보고 채워야 한다.
                        Text("사진에서 연월을 읽지 못했습니다. 2026-08처럼 적어 주세요.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
```

**`Binding`을 직접 만든다.** `$vm.yearMonth`로 묶으면 `setYearMonth`를 건너뛰어 요일과 말일이 갱신되지 않는다.

- [ ] **Step 6: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: PASS — 전체 통과

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/ViewModels/Dispatch*.swift WooriHaru/Views/Dispatch/ WooriHaruTests/DispatchTests.swift
git commit -m "feat: 연월을 업로드에서 검수 화면으로 옮긴다"
```

---

## 수동 확인

시뮬레이터로는 안 되는 것들이다.

- **카메라로 찍은 HEIC 사진** — 앨범 원본이 HEIC면 서버가 못 읽는다. JPEG 정규화가 도는지
- **가로로 찍은 사진** — EXIF 회전이 픽셀에 반영되는지. 화면에는 똑바로 보이는데 서버가 눕혀 받으면 가로로 2등분해 엉뚱하게 자른다
- **대용량 사진** — 4,800만 화소에서 10MB 상한에 걸리는지, 굽는 동안 화면이 멈추지 않는지
- **제목이 잘린 사진** — 검수 화면 연월이 비고 저장이 잠기는지, `ROSTER_FROM_OTHER_MONTH` 경고가 뜨는지
- **등록 후 달력** — 저장하고 돌아왔을 때 방금 넣은 근무가 보이는지
- **아빠·엄마 색 구분** — 실물에서 `blue500`과 `purple400`이 구분되는지
