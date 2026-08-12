# 배차표 사진 업로드·검수 (iOS) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 배차표 사진을 앱에서 올려 서버가 읽은 결과를 사진과 대조해 고친 뒤 확정 저장한다.

**Architecture:** 식단의 `MealCaptureSheet` → `MealConfirmView` 흐름을 그대로 따른다. 업로드 화면에서 연월과 사진을 고르고 인식을 요청하면, 검수 화면이 사진과 날짜 목록을 나란히 놓는다. 사용자가 고친 것만 `POST /dispatch/shifts`로 확정한다. 조회 달력은 웹이 담당하므로 앱에는 만들지 않는다.

**Tech Stack:** SwiftUI, `@Observable` ViewModel, Swift Testing, `PhotosPicker`

서버 설계: `toy-back/docs/superpowers/specs/2026-08-11-dispatch-calendar-design.md`
서버 구현: `toy-back` PR #31 (develop 머지 완료)

## Global Constraints

- **사진을 축소하지 않는다.** 기존 `UIImage.downsampledJPEG(maxDimension: 1024)`를 배차 사진에 쓰면 안 된다. 실측에서 **전처리 해상도가 인식 정확도 0%와 100%를 갈랐고**, 1024px로 줄이면 서버가 아무리 확대해도 정보가 이미 없다. 서버 multipart 한도는 10MB이고 원본 스크린샷은 ~600KB다.
- **판정은 `working`만 본다.** `slot`이 `nil`이어도 `working == true`면 근무다. `slot`으로 근무를 판정하는 코드를 만들지 마라.
- **사진에 없던 날짜는 저장에서 제외한다.** 서버는 「보낸 날짜만 upsert」하므로, 안 보내면 기존 값이 유지된다. 미인식 날짜를 휴무로 채워 보내면 **멀쩡한 기존 값이 휴무로 덮인다.**
- **`note`에 개인 식별 정보를 넣지 않는다.** 무인증 `GET /dispatch/shifts`로 그대로 나간다. 서버 컬럼 길이가 100자다.
- ViewModel은 `@MainActor @Observable final class`, 서비스는 `protocol XxxServing: Sendable` + 구현. 기존 `DietService`·`MealCaptureViewModel` 패턴을 따른다.
- 테스트는 **Swift Testing**(`import Testing`, `@Test`, `#expect`). XCTest를 쓰지 마라.
- **새로 만든 Swift 파일은 앱 타겟에 등록해야 컴파일된다.** 폴더 동기화(`PBXFileSystemSynchronizedRootGroup`)가 걸린 곳은 `WooriHaruTests`와 `StudyTimerWidget` 뿐이고, **앱 타겟 `WooriHaru`는 `PBXSourcesBuildPhase`에 파일을 하나씩 등록하는 전통 방식**이다. `WooriHaru/` 아래에 파일만 만들면 「테스트는 컴파일되는데 본 코드가 없다」는 형태로 깨진다. 파일을 만든 뒤 반드시 돌려라:

  ```bash
  export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
  ruby scripts/xcode-add-files.rb WooriHaru/경로/파일.swift
  ```

  여러 번 돌려도 안전하다(이미 등록된 파일은 건너뛴다). **`WooriHaruTests/` 파일은 등록하지 마라** — 그쪽은 자동으로 잡힌다.
- **파일 이름을 Apple 시스템 모듈과 같게 짓지 마라.** `Dispatch.swift`는 GCD 모듈 `Dispatch`와 겹쳐 `Circular dependency between modules 'Dispatch' and 'Foundation'`으로 빌드가 깨진다. 이 계획의 모델 파일이 `DispatchModels.swift`인 이유다.
- 커밋 메시지는 **한국어**. 기존 관례를 따른다.

**테스트 실행 명령**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/<스위트명> 2>&1 | tail -20
```

**`-only-testing`은 파일명이 아니라 스위트명(struct 이름)을 받는다.** 파일명(`DispatchTests`)을
넣으면 아무 테스트도 매치되지 않고 **0개가 돌면서 조용히 `TEST SUCCEEDED`가 뜬다** — 실제로
한 번 그렇게 속았다. 스위트명은 태스크마다 다르다:

| 태스크 | 스위트명 |
|---|---|
| 1 | `DispatchModelTests` |
| 2 | `DispatchServiceTests` |
| 3 | `DispatchUploadViewModelTests` |
| 4 | `DispatchReviewViewModelTests` |

**통과했다고 보고하기 전에 출력에서 「Test run with N tests」의 N이 0이 아닌지 확인해라.**

전체 스위트는 `-only-testing`을 빼고 돌린다(453개 기준).

---

## 서버 API 계약

이 값들은 서버 코드에서 그대로 옮긴 것이다. 추측하지 마라.

**인식** — `POST /dispatch/recognitions?yearMonth=2026-08`, multipart 파트명 `file`

```jsonc
// 200 { "data": { ... } }
{
  "yearMonth": "2026-08",
  "hasNameColumn": true,
  "matchedBy": "NAME",              // "NAME" | "ROW_INDEX"
  "rowIndex": 2,
  "rowCount": 13,
  "warnings": ["ROW_COUNT_CHANGED"], // 비어 있을 수 있다
  "days": [
    { "day": 1, "working": true,  "slot": 1,    "note": null,  "conflict": false },
    { "day": 2, "working": false, "slot": null, "note": null,  "conflict": false },
    { "day": 3, "working": false, "slot": null, "note": "*97", "conflict": true }
  ]
}
```

`days`에는 **사진에서 읽은 날짜만** 들어온다. 잘린 사진이면 일부만 온다.

**확정 저장** — `POST /dispatch/shifts` → **204 No Content**

```jsonc
{
  "role": "FATHER",
  "days": [
    { "date": "2026-08-01", "working": true, "slot": 1, "note": null }
  ]
}
```

**에러 (서버 메시지가 이미 사용자용 한국어다. 그대로 보여준다)**

| 코드 | 상태 | 메시지 |
|---|---|---|
| `TARGET_NOT_FOUND` | 400 | 배차표 사진에서 대상 기사를 찾지 못했습니다. 사진을 확인해 주세요. |
| `ROSTER_NOT_FOUND` | 400 | 배차표 기준이 없습니다. 성명 컬럼이 보이는 사진을 먼저 올려 주세요. |
| `IMAGE_UNREADABLE` | 400 | 이미지를 읽을 수 없습니다. |
| `VISION_UNAVAILABLE` | 503 | 사진 인식에 실패했습니다. 잠시 후 다시 시도해 주세요. |

---

## File Structure

**신규**

| 파일 | 책임 |
|---|---|
| `WooriHaru/Models/DispatchModels.swift` | 요청·응답 모델 전부 |
| `WooriHaru/Services/DispatchService.swift` | `DispatchServing` 프로토콜과 구현 |
| `WooriHaru/ViewModels/DispatchUploadViewModel.swift` | 사진·연월 보유, 인식 요청 |
| `WooriHaru/ViewModels/DispatchReviewViewModel.swift` | 인식 결과 편집, 저장 요청 구성 |
| `WooriHaru/Views/Dispatch/DispatchUploadView.swift` | 업로드 화면 |
| `WooriHaru/Views/Dispatch/DispatchReviewView.swift` | 검수 화면 |
| `WooriHaruTests/DispatchTests.swift` | 테스트 전부 |

**수정**

| 파일 | 변경 |
|---|---|
| `WooriHaru/Services/APIClient.swift` | multipart + JSON 응답 메서드 추가 |
| `WooriHaruTests/MockAPIClient.swift` | 그 메서드의 테스트 대역 |
| `WooriHaru/ContentView.swift` | `AppDestination.dispatch` 추가와 라우팅 |
| `WooriHaru/Views/Components/SideDrawerView.swift` | 메뉴 항목 추가 |

---

### Task 1: 모델과 multipart JSON 응답

**Files:**
- Create: `WooriHaru/Models/DispatchModels.swift`
- Modify: `WooriHaru/Services/APIClient.swift`
- Modify: `WooriHaruTests/MockAPIClient.swift`
- Test: `WooriHaruTests/DispatchTests.swift`

**Interfaces:**
- Consumes: `APIClientProtocol`, `DataResponse<T>`(기존)
- Produces:
  - `enum DispatchMatchedBy: String, Codable { case name = "NAME", rowIndex = "ROW_INDEX" }`
  - `struct DispatchRecognitionDay: Codable, Equatable { day: Int, working: Bool, slot: Int?, note: String?, conflict: Bool }`
  - `struct DispatchRecognition: Codable, Equatable { yearMonth: String, hasNameColumn: Bool, matchedBy: DispatchMatchedBy, rowIndex: Int, rowCount: Int, warnings: [String], days: [DispatchRecognitionDay] }`
  - `struct DispatchShiftSaveDay: Encodable, Equatable { date: String, working: Bool, slot: Int?, note: String? }`
  - `struct DispatchShiftSaveRequest: Encodable { role: String, days: [DispatchShiftSaveDay] }`
  - `APIClientProtocol.postMultipart<T: Decodable>(_ path: String, query: [String: String], fileData: Data, fileName: String, mimeType: String) async throws -> T`

- [ ] **Step 1: 실패하는 테스트 작성**

`WooriHaruTests/DispatchTests.swift` (신규)

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct DispatchModelTests {
    /// 서버 `RecognitionResponse`를 그대로 옮긴 응답. 필드가 하나라도 어긋나면 디코딩이 깨진다.
    static let recognitionJSON = """
    {
      "data": {
        "yearMonth": "2026-08",
        "hasNameColumn": true,
        "matchedBy": "NAME",
        "rowIndex": 2,
        "rowCount": 13,
        "warnings": ["ROW_COUNT_CHANGED"],
        "days": [
          { "day": 1, "working": true, "slot": 1, "note": null, "conflict": false },
          { "day": 2, "working": false, "slot": null, "note": null, "conflict": false },
          { "day": 3, "working": false, "slot": null, "note": "*97", "conflict": true }
        ]
      }
    }
    """

    @Test func 인식_응답을_디코딩한다() throws {
        let data = Data(Self.recognitionJSON.utf8)
        let response = try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: data)
        let recognition = try #require(response.data)

        #expect(recognition.yearMonth == "2026-08")
        #expect(recognition.matchedBy == .name)
        #expect(recognition.rowIndex == 2)
        #expect(recognition.rowCount == 13)
        #expect(recognition.warnings == ["ROW_COUNT_CHANGED"])
        #expect(recognition.days.count == 3)
    }

    @Test func 근무_판정은_working만_본다() throws {
        let data = Data(Self.recognitionJSON.utf8)
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: data).data
        )

        // 1일은 slot이 있는 근무, 2일은 휴무, 3일은 note가 있지만 휴무다.
        #expect(recognition.days[0].working == true)
        #expect(recognition.days[0].slot == 1)
        #expect(recognition.days[1].working == false)
        #expect(recognition.days[2].working == false)
        #expect(recognition.days[2].note == "*97")
    }

    @Test func ROW_INDEX_매칭을_디코딩한다() throws {
        let json = """
        {"data":{"yearMonth":"2026-08","hasNameColumn":false,"matchedBy":"ROW_INDEX",
        "rowIndex":2,"rowCount":13,"warnings":[],"days":[]}}
        """
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: Data(json.utf8)).data
        )
        #expect(recognition.matchedBy == .rowIndex)
        #expect(recognition.hasNameColumn == false)
    }

    @Test func 저장_요청을_인코딩한다() throws {
        let request = DispatchShiftSaveRequest(
            role: "FATHER",
            days: [DispatchShiftSaveDay(date: "2026-08-01", working: true, slot: 1, note: nil)]
        )
        let encoded = try JSONEncoder().encode(request)
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(json["role"] as? String == "FATHER")
        let days = try #require(json["days"] as? [[String: Any]])
        #expect(days.count == 1)
        #expect(days[0]["date"] as? String == "2026-08-01")
        #expect(days[0]["working"] as? Bool == true)
        #expect(days[0]["slot"] as? Int == 1)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: 위의 테스트 실행 명령 (`-only-testing:WooriHaruTests/DispatchTests`)
Expected: 컴파일 실패 — `cannot find 'DispatchRecognition' in scope`

- [ ] **Step 3: 모델 작성**

`WooriHaru/Models/DispatchModels.swift`

```swift
import Foundation

/// 서버가 대상 행을 어떻게 찾았는지.
///
/// `rowIndex`면 **사진에 성명 컬럼이 없어 저장된 행 위치로 맞춘 것**이라, 검수 화면이
/// 그 사실을 알려야 한다. 인원이 바뀌어 행 순서가 밀리면 엉뚱한 기사의 근무가 들어오는데
/// 화면만 봐서는 구분되지 않기 때문이다.
// `DataResponse<T: Codable>`로 감싸 받으므로 Decodable만으로는 부족하다.
enum DispatchMatchedBy: String, Codable, Equatable {
    case name = "NAME"
    case rowIndex = "ROW_INDEX"
}

/// 사진에서 읽은 하루. **`days`에는 사진에 보인 날짜만 들어온다** — 잘린 사진이면 일부만 온다.
struct DispatchRecognitionDay: Codable, Equatable {
    let day: Int
    /// 그날 일하는가. **판정은 이 값만 본다** — `slot`이 nil이어도 근무일 수 있다.
    let working: Bool
    /// 배차 순번. 근무여도 미정이면 nil.
    let slot: Int?
    /// 칸의 원문(`휴`·`간담회`·`*97` 등). 표시용이고 판정에 끼어들지 않는다.
    let note: String?
    /// 겹친 구간에서 두 조각의 답이 갈렸다. 화면이 강조한다.
    let conflict: Bool
}

struct DispatchRecognition: Codable, Equatable {
    let yearMonth: String
    let hasNameColumn: Bool
    let matchedBy: DispatchMatchedBy
    let rowIndex: Int
    let rowCount: Int
    /// `ROW_COUNT_CHANGED`, `YEAR_MONTH_MISMATCH` 등. 비어 있을 수 있다.
    let warnings: [String]
    let days: [DispatchRecognitionDay]
}

struct DispatchShiftSaveDay: Encodable, Equatable {
    /// `2026-08-01` 형식. 서버가 `LocalDate`로 받는다.
    let date: String
    let working: Bool
    let slot: Int?
    /// **개인 식별 정보를 넣지 않는다** — 무인증 조회로 그대로 나간다. 서버 한도 100자.
    let note: String?
}

struct DispatchShiftSaveRequest: Encodable {
    /// 지금은 항상 `FATHER`다. 사진에서 읽는 대상이 아빠뿐이다.
    let role: String
    let days: [DispatchShiftSaveDay]
}
```

- [ ] **Step 4: APIClient에 multipart JSON 메서드를 더한다**

`APIClient.swift`의 `APIClientProtocol`에 선언을 더한다. 기존 `postMultipartCreated` 선언 **아래**에 둔다.

```swift
    /// multipart로 보내고 **JSON 본문을 돌려받는다.** 기존 `postMultipartCreated`는
    /// 201 + Location에서 id만 꺼내는 형태라 배차 인식(200 + 결과 JSON)에는 쓸 수 없다.
    func postMultipart<T: Decodable>(
        _ path: String,
        query: [String: String],
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> T
```

그리고 구현을 더한다. 기존 `postMultipartCreated` 구현 아래에 두고, `rawMultipartFetch`와 `multipartBody`를 재사용한다.

```swift
    func postMultipart<T: Decodable>(
        _ path: String,
        query: [String: String],
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartBody(boundary: boundary, fileData: fileData, fileName: fileName, mimeType: mimeType)
        let pathWithQuery = Self.appending(query: query, to: path)
        let (data, _) = try await rawMultipartFetch(pathWithQuery, body: body, boundary: boundary)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 쿼리를 경로에 붙인다. `rawMultipartFetch`가 경로 문자열만 받기 때문이다.
    static func appending(query: [String: String], to path: String) -> String {
        guard !query.isEmpty else { return path }
        let encoded = query
            .map { key, value in
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(escaped)"
            }
            .joined(separator: "&")
        return path.contains("?") ? "\(path)&\(encoded)" : "\(path)?\(encoded)"
    }
```

- [ ] **Step 5: MockAPIClient에 대역을 더한다**

`WooriHaruTests/MockAPIClient.swift`에 저장소·기록·메서드를 더한다. 기존 `multipartResults` 패턴을 따른다.

```swift
    // 파일 상단의 저장소 선언 근처에 더한다
    private var multipartJSONResults: [String: Any] = [:]
    private var recordedMultipartJSONCalls: [(path: String, query: [String: String], fileData: Data)] = []
```

```swift
    // 프로토콜 구현부에 더한다
    func postMultipart<T: Decodable>(
        _ path: String,
        query: [String: String],
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> T {
        lock.lock()
        recordedMultipartJSONCalls.append((path, query, fileData))
        let error = errors["POST \(path)"]
        let result = multipartJSONResults[path]
        lock.unlock()

        if let error { throw error }
        guard let value = result as? T else {
            throw MockAPIError.unstubbed("postMultipart \(path)")
        }
        return value
    }

    // 테스트가 쓰는 헬퍼 — 기존 stub/record 헬퍼들 옆에 둔다
    func stubMultipartJSON<T>(_ path: String, result: T) {
        lock.lock(); defer { lock.unlock() }
        multipartJSONResults[path] = result
    }

    var multipartJSONCalls: [(path: String, query: [String: String], fileData: Data)] {
        lock.lock(); defer { lock.unlock() }
        return recordedMultipartJSONCalls
    }
```

> `errors[path]`·`lock`·`MockAPIError`는 이 파일에 이미 있다. 없으면 기존 메서드가 쓰는 이름을 그대로 따라라.

- [ ] **Step 6: 앱 타겟에 등록하고 테스트 통과 확인**

새 파일은 등록하지 않으면 컴파일되지 않는다.

```bash
export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
ruby scripts/xcode-add-files.rb WooriHaru/Models/DispatchModels.swift
```

Run: 테스트 실행 명령
Expected: PASS (4개)

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/Models/DispatchModels.swift WooriHaru/Services/APIClient.swift \
        WooriHaru.xcodeproj scripts/xcode-add-files.rb \
        WooriHaruTests/DispatchTests.swift WooriHaruTests/MockAPIClient.swift
git commit -m "feat: 배차표 인식 모델과 multipart JSON 응답 경로를 만든다

기존 postMultipartCreated는 201 + Location에서 id만 꺼내는 형태라 인식 결과를
JSON으로 돌려받는 배차 API에는 쓸 수 없다.

근무 판정은 working만 본다. slot이 nil이어도 근무일 수 있어서(순번 미정)
slot으로 판정하면 근무일이 휴무로 읽힌다."
```

---

### Task 2: 배차 서비스

**Files:**
- Create: `WooriHaru/Services/DispatchService.swift`
- Modify: `WooriHaruTests/DispatchTests.swift`

**Interfaces:**
- Consumes: Task 1의 모델 전부, `APIClientProtocol.postMultipart`, `APIClientProtocol.postVoid`
- Produces:
  - `protocol DispatchServing: Sendable { func recognize(imageData: Data, yearMonth: String) async throws -> DispatchRecognition; func saveShifts(_ request: DispatchShiftSaveRequest) async throws }`
  - `struct DispatchService: DispatchServing { init(api: APIClientProtocol = APIClient.shared) }`

- [ ] **Step 1: 실패하는 테스트 작성**

`DispatchTests.swift` 끝에 더한다.

```swift
@MainActor
struct DispatchServiceTests {
    private func recognition(yearMonth: String = "2026-08") -> DispatchRecognition {
        DispatchRecognition(
            yearMonth: yearMonth,
            hasNameColumn: true,
            matchedBy: .name,
            rowIndex: 2,
            rowCount: 13,
            warnings: [],
            days: [DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)]
        )
    }

    @Test func 인식은_연월을_쿼리로_보낸다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        _ = try await service.recognize(imageData: Data([0x01, 0x02]), yearMonth: "2026-08")

        let call = try #require(api.multipartJSONCalls.first)
        #expect(call.path == "/dispatch/recognitions")
        // 연월을 안 보내면 서버가 어느 달 기준을 조회할지 모른다.
        #expect(call.query["yearMonth"] == "2026-08")
        #expect(call.fileData == Data([0x01, 0x02]))
    }

    @Test func 인식_결과를_그대로_돌려준다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        let result = try await service.recognize(imageData: Data([0x01]), yearMonth: "2026-08")

        #expect(result.yearMonth == "2026-08")
        #expect(result.matchedBy == .name)
        #expect(result.days.count == 1)
    }

    @Test func 저장은_204라_본문을_기대하지_않는다() async throws {
        let api = MockAPIClient()
        let service = DispatchService(api: api)

        try await service.saveShifts(
            DispatchShiftSaveRequest(
                role: "FATHER",
                days: [DispatchShiftSaveDay(date: "2026-08-01", working: true, slot: 1, note: nil)]
            )
        )

        // postVoid는 recordedPostCalls에 남는다(MockAPIClient 기존 구현).
        #expect(api.postCalls.contains { $0.path == "/dispatch/shifts" })
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: 테스트 실행 명령
Expected: 컴파일 실패 — `cannot find 'DispatchService' in scope`

- [ ] **Step 3: 구현**

`WooriHaru/Services/DispatchService.swift`

```swift
import Foundation

/// 배차 API. 테스트에서 대체할 수 있도록 프로토콜로 분리한다.
protocol DispatchServing: Sendable {
    /// 사진 한 장을 인식한다. **아무것도 저장되지 않는다** — 검수를 거쳐 `saveShifts`로 확정한다.
    ///
    /// `yearMonth`(`2026-08`)를 함께 보낸다. 서버가 사진에서 연월을 읽어 정하면 「읽기 전에는
    /// 어느 달 기준을 조회할지 모른다」는 순환에 빠지고, 현재 달로 대신하면 8월 말에 9월
    /// 배차표를 미리 올릴 때 엉뚱한 달의 기준을 본다.
    func recognize(imageData: Data, yearMonth: String) async throws -> DispatchRecognition

    /// 검수 확정분을 저장한다. **보낸 날짜만 갱신된다.**
    func saveShifts(_ request: DispatchShiftSaveRequest) async throws
}

struct DispatchService: DispatchServing {
    private let api: APIClientProtocol

    init(api: APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func recognize(imageData: Data, yearMonth: String) async throws -> DispatchRecognition {
        let response: DataResponse<DispatchRecognition> = try await api.postMultipart(
            "/dispatch/recognitions",
            query: ["yearMonth": yearMonth],
            fileData: imageData,
            fileName: "dispatch.jpg",
            mimeType: "image/jpeg"
        )
        guard let recognition = response.data else {
            throw APIError.serverError(statusCode: 200, message: "인식 응답이 비어 있습니다")
        }
        return recognition
    }

    func saveShifts(_ request: DispatchShiftSaveRequest) async throws {
        try await api.postVoid("/dispatch/shifts", body: request)
    }
}
```

> `APIClient.shared`가 이 이름이 아니면 `DietService`가 쓰는 기본값을 그대로 따라라.

- [ ] **Step 4: 앱 타겟에 등록하고 테스트 통과 확인**

```bash
export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
ruby scripts/xcode-add-files.rb WooriHaru/Services/DispatchService.swift
```

Run: 테스트 실행 명령
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/DispatchService.swift WooriHaru.xcodeproj WooriHaruTests/
git commit -m "feat: 배차 인식·저장 서비스를 만든다

인식 요청에 연월을 함께 보낸다. 서버가 사진에서 읽어 정하면 어느 달 기준을
조회할지 모르는 순환에 빠지고, 현재 달로 대신하면 월말에 다음 달 배차표를
미리 올릴 때 엉뚱한 달 기준을 본다."
```

---

### Task 3: 업로드 ViewModel

**Files:**
- Create: `WooriHaru/ViewModels/DispatchUploadViewModel.swift`
- Modify: `WooriHaruTests/DispatchTests.swift`

**Interfaces:**
- Consumes: `DispatchServing`(Task 2), `DispatchRecognition`(Task 1)
- Produces:
  - `@MainActor @Observable final class DispatchUploadViewModel`
  - `enum Phase: Equatable { case idle, recognizing, completed, failed }`
  - `var phase: Phase`, `var errorMessage: String?`, `var imageData: Data?`, `var yearMonth: String`, `var recognition: DispatchRecognition?`
  - `func setImage(_ data: Data)`, `func recognize() async`, `var canRecognize: Bool`
  - `static func defaultYearMonth(now: Date, calendar: Calendar) -> String`

- [ ] **Step 1: 실패하는 테스트 작성**

`DispatchTests.swift` 끝에 더한다.

```swift
/// 인식만 하는 대역. 호출 인자를 기록하고 미리 정한 결과를 돌려준다.
private final class FakeDispatchService: DispatchServing, @unchecked Sendable {
    var recognizeResult: Result<DispatchRecognition, Error>
    var saveError: Error?
    private(set) var recognizeCalls: [(imageData: Data, yearMonth: String)] = []
    private(set) var savedRequests: [DispatchShiftSaveRequest] = []

    init(recognizeResult: Result<DispatchRecognition, Error>) {
        self.recognizeResult = recognizeResult
    }

    func recognize(imageData: Data, yearMonth: String) async throws -> DispatchRecognition {
        recognizeCalls.append((imageData, yearMonth))
        return try recognizeResult.get()
    }

    func saveShifts(_ request: DispatchShiftSaveRequest) async throws {
        savedRequests.append(request)
        if let saveError { throw saveError }
    }
}

private func sampleRecognition(
    matchedBy: DispatchMatchedBy = .name,
    warnings: [String] = [],
    days: [DispatchRecognitionDay] = [
        DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
    ]
) -> DispatchRecognition {
    DispatchRecognition(
        yearMonth: "2026-08",
        hasNameColumn: matchedBy == .name,
        matchedBy: matchedBy,
        rowIndex: 2,
        rowCount: 13,
        warnings: warnings,
        days: days
    )
}

@MainActor
struct DispatchUploadViewModelTests {
    @Test func 사진이_없으면_인식할_수_없다() {
        let vm = DispatchUploadViewModel(service: FakeDispatchService(recognizeResult: .success(sampleRecognition())))
        #expect(vm.canRecognize == false)

        vm.setImage(Data([0x01]))
        #expect(vm.canRecognize == true)
    }

    @Test func 인식에_성공하면_결과를_들고_완료된다() async {
        let service = FakeDispatchService(recognizeResult: .success(sampleRecognition()))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01, 0x02]))
        vm.yearMonth = "2026-08"

        await vm.recognize()

        #expect(vm.phase == .completed)
        #expect(vm.recognition?.yearMonth == "2026-08")
        #expect(service.recognizeCalls.first?.yearMonth == "2026-08")
        // 원본 바이트가 그대로 가야 한다 — 줄이면 인식이 망가진다.
        #expect(service.recognizeCalls.first?.imageData == Data([0x01, 0x02]))
    }

    @Test func 인식에_실패하면_서버_메시지를_그대로_보여준다() async {
        let error = APIError.serverError(statusCode: 400, message: "배차표 사진에서 대상 기사를 찾지 못했습니다. 사진을 확인해 주세요.")
        let service = FakeDispatchService(recognizeResult: .failure(error))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))

        await vm.recognize()

        #expect(vm.phase == .failed)
        // 서버 메시지가 이미 사용자용 한국어다. 앱이 다시 쓰지 않는다.
        #expect(vm.errorMessage?.contains("대상 기사를 찾지 못했습니다") == true)
    }

    @Test func 기본_연월은_이번_달이다() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!

        #expect(DispatchUploadViewModel.defaultYearMonth(now: date, calendar: calendar) == "2026-08")
    }

    @Test func 한자리_월은_0을_채운다() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        // "2026-3"으로 보내면 서버의 YearMonth 파싱이 400을 낸다.
        #expect(DispatchUploadViewModel.defaultYearMonth(now: date, calendar: calendar) == "2026-03")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: 테스트 실행 명령
Expected: 컴파일 실패 — `cannot find 'DispatchUploadViewModel' in scope`

- [ ] **Step 3: 구현**

`WooriHaru/ViewModels/DispatchUploadViewModel.swift`

```swift
import Foundation

/// 사진 한 장과 연월을 골라 인식을 요청한다.
///
/// **사진을 축소하지 않는다.** 식단은 `UIImage.downsampledJPEG(maxDimension: 1024)`로 줄여
/// 올리지만, 배차표는 표가 가로로 길어 한 칸이 몇 픽셀밖에 안 된다. 줄이면 서버가 잘라
/// 확대해도 정보가 이미 없어 모델이 빈 칸을 숫자로 메운다 — 실측에서 전처리 해상도가
/// 정확도 0%와 100%를 갈랐다. 서버 multipart 한도는 10MB이고 원본은 ~600KB다.
@MainActor
@Observable
final class DispatchUploadViewModel {
    enum Phase: Equatable {
        case idle
        case recognizing
        case completed
        case failed
    }

    private let service: DispatchServing

    var imageData: Data?
    var yearMonth: String
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var recognition: DispatchRecognition?

    init(
        service: DispatchServing = DispatchService(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.service = service
        self.yearMonth = Self.defaultYearMonth(now: now, calendar: calendar)
    }

    var canRecognize: Bool {
        imageData != nil && phase != .recognizing
    }

    func setImage(_ data: Data) {
        imageData = data
        phase = .idle
        errorMessage = nil
        recognition = nil
    }

    func recognize() async {
        guard let imageData else { return }
        phase = .recognizing
        errorMessage = nil
        do {
            recognition = try await service.recognize(imageData: imageData, yearMonth: yearMonth)
            phase = .completed
        } catch {
            // 서버 메시지가 이미 사용자용 한국어다(`TARGET_NOT_FOUND` 등). 앱이 다시 쓰지 않는다.
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    /// `2026-08` 형식. **월에 0을 채워야 한다** — `2026-3`은 서버의 `YearMonth` 파싱이 400을 낸다.
    static func defaultYearMonth(now: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: now)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }
}
```

> `APIError.serverError`의 `localizedDescription`이 서버 메시지를 담지 않으면, `DietService`나 기존 ViewModel이 서버 메시지를 꺼내는 방식을 그대로 따라라. 그 방식이 이 저장소의 관례다.

- [ ] **Step 4: 앱 타겟에 등록하고 테스트 통과 확인**

```bash
export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
ruby scripts/xcode-add-files.rb WooriHaru/ViewModels/DispatchUploadViewModel.swift
```

Run: 테스트 실행 명령
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/DispatchUploadViewModel.swift WooriHaru.xcodeproj WooriHaruTests/DispatchTests.swift
git commit -m "feat: 배차표 사진 업로드 ViewModel을 만든다

사진을 축소하지 않는다. 배차표는 표가 가로로 길어 한 칸이 몇 픽셀이라,
줄이면 서버가 확대해도 정보가 없어 모델이 빈 칸을 숫자로 메운다.

연월은 0을 채운 2026-08 형식으로 보낸다. 2026-3은 서버 파싱이 400을 낸다."
```

---

### Task 4: 검수 ViewModel

**Files:**
- Create: `WooriHaru/ViewModels/DispatchReviewViewModel.swift`
- Modify: `WooriHaruTests/DispatchTests.swift`

**Interfaces:**
- Consumes: `DispatchServing`(Task 2), `DispatchRecognition`(Task 1)
- Produces:
  - `@MainActor @Observable final class DispatchReviewViewModel`
  - `struct DayEntry: Identifiable, Equatable { id: Int, day: Int, recognized: Bool, working: Bool, slot: Int?, note: String?, conflict: Bool }`
  - `var entries: [DayEntry]`, `var isSaving: Bool`, `var errorMessage: String?`, `var didSave: Bool`
  - `var needsRowIndexWarning: Bool`, `var warningMessages: [String]`
  - `func setWorking(day: Int, working: Bool, slot: Int?)`, `func markUnrecognized(day: Int)`
  - `func save() async`
  - `init(recognition: DispatchRecognition, service: DispatchServing, calendar: Calendar)`

- [ ] **Step 1: 실패하는 테스트 작성**

`DispatchTests.swift` 끝에 더한다.

```swift
@MainActor
struct DispatchReviewViewModelTests {
    private func makeViewModel(
        recognition: DispatchRecognition,
        service: FakeDispatchService
    ) -> DispatchReviewViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return DispatchReviewViewModel(recognition: recognition, service: service, calendar: calendar)
    }

    @Test func 그_달_전체를_보여주되_사진에_없던_날은_미인식이다() {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false),
            DispatchRecognitionDay(day: 2, working: false, slot: nil, note: nil, conflict: false)
        ])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 2026-08은 31일까지다.
        #expect(vm.entries.count == 31)
        #expect(vm.entries[0].recognized == true)
        #expect(vm.entries[1].recognized == true)
        #expect(vm.entries[2].recognized == false)
        #expect(vm.entries[30].recognized == false)
    }

    @Test func 미인식_날짜는_저장에서_빠진다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false),
            DispatchRecognitionDay(day: 2, working: false, slot: nil, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        await vm.save()

        let request = try #require(service.savedRequests.first)
        // 서버는 「보낸 날짜만 upsert」한다. 미인식 날짜를 휴무로 채워 보내면
        // 멀쩡한 기존 값이 휴무로 덮인다.
        #expect(request.days.count == 2)
        #expect(request.days.map(\.date) == ["2026-08-01", "2026-08-02"])
        #expect(request.role == "FATHER")
    }

    @Test func 값을_고치면_저장에_반영된다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 1, working: true, slot: 2)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days[0].slot == 2)
        #expect(request.days[0].working == true)
    }

    @Test func 미인식이던_날을_직접_채우면_저장에_들어간다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 5, working: false, slot: nil)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days.map(\.date).contains("2026-08-05"))
    }

    @Test func 인식된_날을_미인식으로_되돌리면_저장에서_빠진다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false),
            DispatchRecognitionDay(day: 2, working: false, slot: nil, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.markUnrecognized(day: 2)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days.map(\.date) == ["2026-08-01"])
    }

    @Test func 행_위치로_매칭했으면_배너를_띄운다() {
        let byIndex = sampleRecognition(matchedBy: .rowIndex)
        let vm = makeViewModel(recognition: byIndex, service: FakeDispatchService(recognizeResult: .success(byIndex)))
        // 성명 컬럼이 없어 저장된 행 위치로 맞춘 것이라 사람이 사진과 대조해야 한다.
        #expect(vm.needsRowIndexWarning == true)

        let byName = sampleRecognition(matchedBy: .name)
        let vm2 = makeViewModel(recognition: byName, service: FakeDispatchService(recognizeResult: .success(byName)))
        #expect(vm2.needsRowIndexWarning == false)
    }

    @Test func 서버_경고를_사람이_읽는_문장으로_바꾼다() {
        let recognition = sampleRecognition(warnings: ["ROW_COUNT_CHANGED", "YEAR_MONTH_MISMATCH"])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        #expect(vm.warningMessages.count == 2)
        #expect(vm.warningMessages[0].contains("인원"))
        #expect(vm.warningMessages[1].contains("달"))
    }

    @Test func 저장에_실패하면_메시지를_남기고_완료로_치지_않는다() async {
        let recognition = sampleRecognition()
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        service.saveError = APIError.serverError(statusCode: 400, message: "저장에 실패했습니다")
        let vm = makeViewModel(recognition: recognition, service: service)

        await vm.save()

        #expect(vm.didSave == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.isSaving == false)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: 테스트 실행 명령
Expected: 컴파일 실패 — `cannot find 'DispatchReviewViewModel' in scope`

- [ ] **Step 3: 구현**

`WooriHaru/ViewModels/DispatchReviewViewModel.swift`

```swift
import Foundation

/// 인식 결과를 사진과 대조해 고치고 확정한다.
///
/// **그 달 전체를 보여주되 사진에 없던 날은 「미인식」으로 둔다.** 잘린 변경분 사진은 그 달의
/// 일부만 담으므로 `days`에 일부만 온다. 미인식 날짜를 휴무로 채워 보내면 서버가 그대로
/// upsert해 **멀쩡한 기존 값이 휴무로 덮인다.**
@MainActor
@Observable
final class DispatchReviewViewModel {
    /// 화면 한 줄. `recognized == false`면 저장에서 빠진다.
    struct DayEntry: Identifiable, Equatable {
        var id: Int { day }
        let day: Int
        var recognized: Bool
        var working: Bool
        var slot: Int?
        var note: String?
        var conflict: Bool
    }

    private let recognition: DispatchRecognition
    private let service: DispatchServing

    private(set) var entries: [DayEntry] = []
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    init(
        recognition: DispatchRecognition,
        service: DispatchServing = DispatchService(),
        calendar: Calendar = .current
    ) {
        self.recognition = recognition
        self.service = service
        self.entries = Self.buildEntries(from: recognition, calendar: calendar)
    }

    /// 성명 컬럼이 없어 저장된 행 위치로 맞춘 경우. 인원이 바뀌어 행이 밀리면 엉뚱한 기사의
    /// 근무가 들어오는데 화면만 봐서는 구분되지 않으므로, 사진과 대조하라고 알린다.
    var needsRowIndexWarning: Bool {
        recognition.matchedBy == .rowIndex
    }

    var warningMessages: [String] {
        recognition.warnings.map { code in
            switch code {
            case "ROW_COUNT_CHANGED":
                return "배차표 인원이 지난번과 다릅니다. 줄이 밀리지 않았는지 사진과 대조해 주세요."
            case "YEAR_MONTH_MISMATCH":
                return "사진의 달이 고른 달과 다릅니다. 연월을 확인해 주세요."
            default:
                return code
            }
        }
    }

    func setWorking(day: Int, working: Bool, slot: Int?) {
        guard let index = entries.firstIndex(where: { $0.day == day }) else { return }
        entries[index].recognized = true
        entries[index].working = working
        entries[index].slot = slot
        // 사람이 값을 정했으면 조각 간 불일치는 해소된 것이다.
        entries[index].conflict = false
    }

    /// 저장 대상에서 뺀다. 서버는 보낸 날짜만 갱신하므로 기존 값이 그대로 남는다.
    func markUnrecognized(day: Int) {
        guard let index = entries.firstIndex(where: { $0.day == day }) else { return }
        entries[index].recognized = false
        entries[index].conflict = false
    }

    func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        // 첫 저장이 성공한 뒤 값을 고쳐 다시 저장했다가 실패하면, 이 값이 남아 있어
        // 화면이 「저장됨」과 오류를 동시에 보여준다.
        didSave = false

        let days = entries
            .filter(\.recognized)
            .map { entry in
                DispatchShiftSaveDay(
                    date: String(format: "%@-%02d", recognition.yearMonth, entry.day),
                    working: entry.working,
                    slot: entry.slot,
                    note: entry.note
                )
            }

        do {
            try await service.saveShifts(DispatchShiftSaveRequest(role: "FATHER", days: days))
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private static func buildEntries(from recognition: DispatchRecognition, calendar: Calendar) -> [DayEntry] {
        // `uniqueKeysWithValues`는 같은 키가 두 번 오면 **크래시한다.** 서버가 중복 `day`를
        // 주는 일은 없어야 하지만, 모델 응답 하나 때문에 검수 화면이 죽는 것보다는
        // 뒤에 온 값을 쓰는 편이 낫다.
        let recognizedByDay = Dictionary(recognition.days.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        let dayCount = Self.dayCount(of: recognition.yearMonth, calendar: calendar)

        return (1...dayCount).map { day in
            if let recognized = recognizedByDay[day] {
                return DayEntry(
                    day: day,
                    recognized: true,
                    working: recognized.working,
                    slot: recognized.slot,
                    note: recognized.note,
                    conflict: recognized.conflict
                )
            }
            return DayEntry(day: day, recognized: false, working: false, slot: nil, note: nil, conflict: false)
        }
    }

    private static func dayCount(of yearMonth: String, calendar: Calendar) -> Int {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else {
            return 31
        }
        return range.count
    }
}
```

- [ ] **Step 4: 앱 타겟에 등록하고 테스트 통과 확인**

```bash
export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
ruby scripts/xcode-add-files.rb WooriHaru/ViewModels/DispatchReviewViewModel.swift
```

Run: 테스트 실행 명령
Expected: PASS (8개)

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/DispatchReviewViewModel.swift WooriHaru.xcodeproj WooriHaruTests/DispatchTests.swift
git commit -m "feat: 배차표 인식 결과 검수 ViewModel을 만든다

그 달 전체를 보여주되 사진에 없던 날은 미인식으로 두고 저장에서 뺀다.
서버가 보낸 날짜만 upsert하므로, 미인식을 휴무로 채워 보내면 멀쩡한
기존 값이 휴무로 덮인다.

행 위치로 매칭한 경우와 서버 경고를 사람이 읽는 문장으로 바꿔 알린다."
```

---

### Task 5: 화면과 진입점

**Files:**
- Create: `WooriHaru/Views/Dispatch/DispatchUploadView.swift`
- Create: `WooriHaru/Views/Dispatch/DispatchReviewView.swift`
- Modify: `WooriHaru/ContentView.swift`
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift`

**Interfaces:**
- Consumes: `DispatchUploadViewModel`(Task 3), `DispatchReviewViewModel`(Task 4)
- Produces: `AppDestination.dispatch`

이 태스크는 UI라 자동 테스트를 만들지 않는다 — 이 저장소에도 View 테스트가 없다. **빌드가 통과하고 시뮬레이터에서 화면이 뜨는 것**이 완료 조건이다.

- [ ] **Step 1: 업로드 화면**

`WooriHaru/Views/Dispatch/DispatchUploadView.swift`

```swift
import PhotosUI
import SwiftUI

/// 연월과 사진을 골라 인식을 요청한다.
///
/// **사진을 축소하지 않는다.** `PhotosPickerItem`에서 받은 원본 `Data`를 그대로 넘긴다 —
/// 식단처럼 `downsampledJPEG`를 거치면 표가 뭉개져 인식이 망가진다.
struct DispatchUploadView: View {
    @State private var vm = DispatchUploadViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var recognizeTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearMonthField
                photoSection
                guideText

                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    recognizeTask?.cancel()
                    recognizeTask = Task { await vm.recognize() }
                } label: {
                    if vm.phase == .recognizing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("인식하기").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canRecognize)
            }
            .padding()
        }
        .navigationTitle("배차표 등록")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { recognizeTask?.cancel() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                vm.setImage(data)
                previewImage = UIImage(data: data)
            }
        }
        .navigationDestination(item: Binding(
            get: { vm.phase == .completed ? vm.recognition : nil },
            set: { if $0 == nil { vm.setImage(vm.imageData ?? Data()) } }
        )) { recognition in
            DispatchReviewView(recognition: recognition, photo: previewImage)
        }
    }

    private var yearMonthField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("연월").font(.footnote).foregroundStyle(.secondary)
            TextField("2026-08", text: $vm.yearMonth)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(previewImage == nil ? "사진 고르기" : "사진 바꾸기", systemImage: "photo")
            }
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var guideText: some View {
        Text("""
        시간표만 확대해서 찍은 사진이 가장 잘 읽힙니다. \
        첫 장은 성명 컬럼이 보이게 왼쪽부터 찍어 주세요. \
        기사 줄이 잘리면 순번이 어긋납니다.
        """)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
```

> `navigationDestination(item:)`이 이 저장소의 다른 화면과 다른 방식이면, `MealCaptureSheet`가 `MealConfirmView`로 넘어가는 방식(`showConfirm` + `navigationDestination(isPresented:)` 등)을 그대로 따라라. **화면 전환 방식보다 중요한 건 인식 결과와 원본 사진이 검수 화면에 함께 전달되는 것이다.**

- [ ] **Step 2: 검수 화면**

`WooriHaru/Views/Dispatch/DispatchReviewView.swift`

```swift
import SwiftUI

/// 사진과 인식 결과를 나란히 놓고 고친 뒤 확정한다.
struct DispatchReviewView: View {
    @State private var vm: DispatchReviewViewModel
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// 확대 배율과 이동. 놓아도 유지한다(위 주석 참고). 두 번 탭하면 원래대로 돌아간다.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let photo: UIImage?

    init(recognition: DispatchRecognition, photo: UIImage?) {
        _vm = State(initialValue: DispatchReviewViewModel(recognition: recognition))
        self.photo = photo
    }

    var body: some View {
        List {
            if let photo {
                Section {
                    // **확대와 이동이 있어야 대조가 된다.** 배차표는 한 칸이 몇 픽셀이라
                    // 축소된 미리보기로는 사진과 목록을 맞춰 볼 수 없다. 놓아도 배율을
                    // 유지한다 — 한 곳을 들여다보다 손을 떼면 튕겨 나가는 것이 더 답답하다.
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxHeight: 220)
                        .clipped()
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = min(max(lastScale * value.magnification, 1), 6)
                                }
                                .onEnded { _ in lastScale = scale }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        .onTapGesture(count: 2) {
                            scale = 1; lastScale = 1
                            offset = .zero; lastOffset = .zero
                        }
                }
            }

            if vm.needsRowIndexWarning {
                Section {
                    Label(
                        "성명 컬럼이 없어 저장된 줄 위치로 맞췄습니다. 사진과 대조해 주세요.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            if !vm.warningMessages.isEmpty {
                Section {
                    ForEach(vm.warningMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("날짜별 근무") {
                ForEach(vm.entries) { entry in
                    dayRow(entry)
                }
            }

            if let message = vm.errorMessage {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("인식 결과 확인")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    saveTask?.cancel()
                    saveTask = Task {
                        await vm.save()
                        if vm.didSave { dismiss() }
                    }
                }
                .disabled(vm.isSaving)
            }
        }
        .onDisappear { saveTask?.cancel() }
    }

    private func dayRow(_ entry: DispatchReviewViewModel.DayEntry) -> some View {
        HStack {
            Text("\(entry.day)일")
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(entry.recognized ? .primary : .secondary)

            if entry.conflict {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()

            Menu {
                Button("휴무") { vm.setWorking(day: entry.day, working: false, slot: nil) }
                ForEach(1...4, id: \.self) { slot in
                    Button("\(slot)번") { vm.setWorking(day: entry.day, working: true, slot: slot) }
                }
                Button("순번 없이 근무") { vm.setWorking(day: entry.day, working: true, slot: nil) }
                Divider()
                Button("미인식으로 두기", role: .destructive) { vm.markUnrecognized(day: entry.day) }
            } label: {
                Text(label(for: entry))
                    .foregroundStyle(entry.recognized ? .primary : .secondary)
            }
        }
    }

    private func label(for entry: DispatchReviewViewModel.DayEntry) -> String {
        guard entry.recognized else { return "미인식" }
        if let note = entry.note, !note.isEmpty { return note }
        // 판정은 working만 본다. slot이 nil이어도 근무일 수 있다.
        guard entry.working else { return "휴무" }
        if let slot = entry.slot { return "\(slot)번" }
        return "근무"
    }
}
```

- [ ] **Step 3: 진입점 연결**

`WooriHaru/ContentView.swift`의 `AppDestination`에 케이스를 더한다.

```swift
    case dispatch
```

그리고 `navigationDestination`의 `switch`에 라우팅을 더한다. 기존 `case .diet: ...` 옆에 둔다.

```swift
                    case .dispatch: DispatchUploadView()
```

`WooriHaru/Views/Components/SideDrawerView.swift`의 메뉴에 항목을 더한다. 「식단」 항목 아래에 둔다.

```swift
                drawerItem(icon: "bus", label: "배차표 등록") {
                    isOpen = false
                    navPath.append(AppDestination.dispatch)
                }
```

- [ ] **Step 4: 앱 타겟에 등록하고 빌드·전체 테스트**

```bash
export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
ruby scripts/xcode-add-files.rb \
  WooriHaru/Views/Dispatch/DispatchUploadView.swift \
  WooriHaru/Views/Dispatch/DispatchReviewView.swift
```

Run:
```bash
xcodebuild build -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

Run:
```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: TEST SUCCEEDED — 기존 테스트가 하나도 깨지지 않아야 한다

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Dispatch WooriHaru.xcodeproj WooriHaru/ContentView.swift \
        WooriHaru/Views/Components/SideDrawerView.swift
git commit -m "feat: 배차표 업로드·검수 화면을 연다

업로드 화면에서 연월과 사진을 고르고, 검수 화면이 사진과 날짜 목록을 나란히
놓는다. 행 위치로 매칭한 경우와 서버 경고를 상단에 띄워 사진과 대조하게 한다.

미인식 날짜는 목록에 보이되 저장에서 빠진다. 사람이 직접 값을 정하면 그때
저장 대상이 된다."
```

---

## 수동 검증

시뮬레이터로는 실제 인식을 확인할 수 없다. 서버가 배포된 뒤 실기기나 시뮬레이터에서 한 번 돌린다.

- [ ] 사이드 메뉴 → 「배차표 등록」이 열린다.
- [ ] 연월이 이번 달로 채워져 있다.
- [ ] 앨범에서 배차표 스크린샷을 고르면 미리보기가 뜬다.
- [ ] 「인식하기」를 누르면 검수 화면으로 넘어가고, **빈 칸이 「휴무」로 나온다**(전부 숫자면 서버 전처리나 모델이 잘못된 것이다).
- [ ] 성명 컬럼이 보이는 전체본 → 상단 배너가 **없다**.
- [ ] 오른쪽만 잘린 사진 → 상단에 「저장된 줄 위치로 맞췄습니다」 배너가 **뜬다**.
- [ ] 대상 기사가 없는 표 → 「대상 기사를 찾지 못했습니다」가 업로드 화면에 뜬다.
- [ ] 검수 화면에서 사진을 핀치로 확대·이동해 표와 목록을 대조할 수 있다. 두 번 탭하면 원래대로 돌아간다.
- [ ] 값을 고치고 저장하면 화면이 닫힌다.
- [ ] 웹 달력(`?yearMonth=`)에서 저장한 값이 보인다.
- [ ] 잘린 사진으로 일부만 저장한 뒤, **저장하지 않은 날짜의 기존 값이 그대로 남아 있다.**

## 다음 계획

웹 조회 달력(`toy-repo/apps/daily-record`)이 남았다. 조회 계약은 `GET /dispatch/shifts?yearMonth=2026-08`이다.
