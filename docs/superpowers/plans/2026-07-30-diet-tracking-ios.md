# 식단 사진 기록·점수·피드백 (iOS) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사이드 드로어의 「식단」 메뉴 안에서 사진 업로드 → 인식 → 확인·수정 → 저장 → 점수·근거·피드백 조회, 사진 없는 기록, 자주 먹는 음식, 주의 영양소, 기간 통계까지 자기완결적으로 끝나는 화면군을 만든다.

**Architecture:** 인식·매칭·점수·피드백은 전부 백엔드가 한다. 앱은 ① 사진을 장변 1024px로 줄여 순차 업로드하고 ② 인식·피드백을 폴링하며 ③ **인식 결과를 사용자가 확인·수정한 최종본을 확정 요청으로 보내고** ④ 서버가 준 `status`·`penalty`·`standardText`를 재판정 없이 표시한다. 유일하게 앱이 계산하는 것은 식품DB 검색·직접 입력 경로의 100g당 → 수량 환산(`NutritionMath`)이며, 서버 공식(`per100g × quantityG / 100`, 반올림 없음)과 일치해야 한다.

**Tech Stack:** SwiftUI (iOS 26), `@Observable` ViewModel, Swift Testing(`@Test`/`#expect`), `APIClientProtocol` 주입, PhotosPicker + ImageIO 다운샘플, HealthKit(`activeEnergyBurned` 읽기 전용).

## Global Constraints

- **짝 스펙:** `docs/superpowers/specs/2026-07-27-diet-tracking-ios-design.md`. 백엔드는 **이미 구현 완료**이며 실제 계약은 `~/Documents/moonjm/toy-back/apps/daily-record/src/main/kotlin/com/toy/backend/diet/` 의 DTO다. 필드명이 스펙과 어긋나면 **백엔드 코드가 이긴다.**
- **베이스 URL:** `APIConfig.baseURL = "https://daily.eunji.shop/api"`. 이 계획의 모든 경로는 여기에 이어 붙는다(`/diet/...`, `/files`).
- **응답 봉투:** 조회는 `DataResponse<T>`(`{"data": ...}`), 생성은 201 + `Location: /diet/xxx/{id}` (→ `postCreated`), 수정·삭제는 204.
- **날짜는 문자열이다.** 서버 `LocalDate`는 `"yyyy-MM-dd"` 문자열로 주고받는다. 모델 필드는 `String`으로 두고 화면에서 `Date.dateString` / `Date.from(_:)`으로 변환한다 (`Extensions/Date+Extensions.swift`). `JSONEncoder`에 날짜 전략을 설정하지 않는다.
- **enum rawValue는 서버 대문자 그대로다** — `"BREAKFAST"`, `"LLM_ESTIMATED"`, `"IN_RANGE"`, `"WARN"`, `"PROCESSED"`.
- **수치 타입** — 영양소·몸무게·키·비율은 `Double`, 목표치·점수·`activeEnergyKcal`·`count`는 `Int`.
- **ViewModel은 `@MainActor @Observable final class`**, 서비스는 프로토콜로 주입한다(`SwimWorkoutFetching` 패턴). 늦게 도착한 응답은 `generation` 카운터로 버린다(`SwimRecordViewModel` 참고).
- **폴링은 2초 간격, 최대 60초.** 타임아웃은 실패가 아니라 "지연"이다. `status == FAILED`로 확인된 경우에만 재시도 버튼을 보여준다. 폴링 간격·타임아웃은 ViewModel `init` 파라미터로 주입해 테스트에서 밀리초로 줄인다.
- **앱은 판정하지 않는다.** `MacroBasis.status`/`penalty`, `NutrientLimit.status`/`standardText`는 서버 값을 그대로 표시한다.
- **`POST /diet/meals/{id}/retry`(피드백 재생성)는 앱이 부르지 않는다.** 누락이 아니라 결정이다. 사진 인식 재시도(`/diet/analyses/{id}/retry`)와 혼동하지 말 것.
- **UI는 `Views/Components/Glass`의 기존 컴포넌트를 쓴다** — `GlassCard`, `.glassScreenBackground()`, `.appGlassProminentButton()`, `.appGlassButton()`, `.glassInputField()`, 색은 `Color.slate*`/`blue*`/`red*`/`green*`/`orange*`.
- **주석·커밋 메시지는 한국어**(저장소 관례). 커밋은 `feat:`/`test:`/`refactor:` 접두어.

### 실행 순서

번호순이 아니다. 의존 방향을 따라 **1 → 2 → 4 → 3 → 5 → 6 → 7 → 10 → 9 → 8 → 11 → 12 → 13 → 14**로
실행한다. 두 곳이 번호와 다르다:

- **4(HealthKit)를 3(DietService)보다 먼저** — 3이 만드는 `DietFakes.swift`가 4의
  `ActiveEnergyFetching`을 채택하는 대역을 담는다.
- **10(항목 편집) → 9(확인 화면) → 8(사진 촬영)** — `MealCaptureSheet`가 `MealConfirmView`를 열고
  `MealConfirmView`가 `MealItemEditView`를 연다. 번호순으로 하면 자리표시 코드를 넣었다 빼야 한다.

각 태스크의 「Interfaces — Consumes」가 이 순서를 전제한다.

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
   `		DT10001 /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = DT20001 /* Foo.swift */; };`
2. `/* Begin PBXFileReference section */` 아래에 한 줄:
   `		DT20001 /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };`
3. 해당 그룹의 `children = (` 안에 `				DT20001 /* Foo.swift */,`
   그룹 ID — `B40001` Models · `B40002` Services · `B40003` ViewModels · `B40004` Views · `B40015` Extensions.
4. 앱 타깃 Sources 빌드 페이즈 `A60001 /* Sources */`의 `files = (` 안에 `				DT10001 /* Foo.swift in Sources */,`

`Views/Diet`·`Views/Diet/Components`는 새 그룹이라 Task 7에서 `DT40001`·`DT40002`로 만들고 `B40004 /* Views */`의 children에 `DT40001`을 넣는다.

### 테스트 파일 배치

스펙은 `WooriHaruTests/DietTests.swift` 한 파일을 말하지만, 30개가 넘는 테스트와 공용 대역이 한 파일에 들어가면 다루기 어렵다. **영역별로 나누되 접두어를 `Diet`로 맞춘다** — `DietFakes.swift`(공용 대역·픽스처), `DietTests.swift`(모델·환산·표시), `DietCaptureTests.swift`, `DietConfirmTests.swift`, `DietDayTests.swift`, `DietStatsTests.swift`.

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `Extensions/UIImage+Extensions.swift` | 업로드 전 다운샘플 (ImageIO) |
| `Services/APIClient.swift` (수정) | multipart 업로드 1개 추가 |
| `Services/HealthKitService.swift` (수정) | `ActiveEnergyFetching` 채택 |
| `Models/DietErrorCode.swift` | 서버 `error` 필드 → 도메인 에러 분기 |
| `Models/Diet.swift` | `Meal`·`MealPhoto`·`MealItem`·`DailyDiet`·근거 타입·Request 타입·enum |
| `Models/MealAnalysis.swift` | 확정 전 인식 결과 |
| `Models/NutritionProfile.swift` | 프로필·목표, `ActivityLevel`·`DietGoal` |
| `Models/Food.swift` | 식품DB 검색 결과 (`dataset`·`servingSizeKnown`) |
| `Models/FrequentItem.swift` | 자주 먹는 음식 |
| `Models/DietStats.swift` | 기간 통계 |
| `Models/NutritionMath.swift` | **100g당 → 수량 환산 한 곳.** 서버 공식과 같아야 한다 |
| `Services/DietService.swift` | `DietServing` 프로토콜 + API 구현 |
| `ViewModels/NutritionProfileViewModel.swift` | 프로필 입력·저장 |
| `ViewModels/DietDayViewModel.swift` | 하루 요약·끼니 목록·하루 피드백 폴링·몸무게·활동에너지 |
| `ViewModels/MealCaptureViewModel.swift` | 순차 업로드 → 인식 요청 → 인식 폴링·재시도 |
| `ViewModels/MealConfirmViewModel.swift` | 사진별 항목 묶음 편집·확정 |
| `ViewModels/MealDetailViewModel.swift` | 항목 수정·삭제·끼니 삭제·끼니 피드백 폴링 |
| `ViewModels/DietStatsViewModel.swift` | 주/월 토글 |
| `Views/Diet/DietHomeView.swift` | 진입점 |
| `Views/Diet/MealCaptureSheet.swift` | 사진 선택·업로드·인식 중 |
| `Views/Diet/MealConfirmView.swift` | 확인·수정 후 저장 (사진 없는 모드 겸용) |
| `Views/Diet/MealDetailView.swift` | 사진·항목·점수·근거·피드백·삭제 |
| `Views/Diet/MealItemEditView.swift` | 자주 먹는 음식 + 식품 검색 + 직접 입력 |
| `Views/Diet/NutritionProfileView.swift` | 키·몸무게·활동량·목표 |
| `Views/Diet/DietStatsView.swift` | 일별 점수 추이·평균·자주 먹은 음식 |
| `Views/Diet/Components/DietScoreRing.swift` | 점수 링 |
| `Views/Diet/Components/MacroBar.swift` | 목표 대비 탄단지 막대 |
| `Views/Diet/Components/ScoreBasisCard.swift` | 점수 근거 |
| `Views/Diet/Components/NutrientLimitRow.swift` | 주의 영양소 한 줄 |
| `Views/Diet/Components/PhotoStrip.swift` | 사진 가로 스트립 |
| `Views/Diet/Components/FrequentItemList.swift` | 자주 먹는 음식 목록 |
| `ContentView.swift` (수정) | `AppDestination.diet` |
| `Views/Components/SideDrawerView.swift` (수정) | 드로어 「식단」 |
| `WooriHaru/Info.plist` (수정) | `NSCameraUsageDescription` |

---

## Task 1: 업로드 토대 — multipart · 다운샘플 · 목 확장

사진 한 장을 줄여서 올리는 경로를 먼저 세운다. 이 태스크가 끝나면 `APIClient`가 `/files`에 파일을 올려 `fileId`를 받을 수 있고, 테스트 대역이 나머지 태스크 전부를 받칠 수 있다.

**Files:**
- Create: `WooriHaru/Extensions/UIImage+Extensions.swift`
- Modify: `WooriHaru/Services/APIClient.swift`
- Modify: `WooriHaruTests/MockAPIClient.swift`
- Test: `WooriHaruTests/DietTests.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (등록 ID — `DT10001`/`DT20001` = `UIImage+Extensions.swift`, 그룹 `B40015`)

**Interfaces:**
- Produces: `UIImage.downsampledJPEG(from:maxDimension:quality:) -> Data?`,
  `APIClientProtocol.postMultipartCreated(_:fileData:fileName:mimeType:) async throws -> Int`,
  `MockAPIClient.stubPostCreated(_:result:)` · `.stubMultipartCreated(_:)` · `.postCreatedCalls` · `.multipartCalls` · `.stubPutVoid` 기록 · `.stubDeleteVoid` 기록 · `.setError(for:)`

- [ ] **Step 1: 다운샘플 실패 테스트를 쓴다**

`WooriHaruTests/DietTests.swift`를 새로 만든다.

```swift
import Foundation
import Testing
import UIKit
@testable import WooriHaru

/// 지정한 크기의 단색 JPEG을 만든다. 다운샘플이 실제로 픽셀을 줄이는지 보려면 원본이 커야 한다.
private func makeJPEG(width: Int, height: Int) -> Data {
    let size = CGSize(width: width, height: height)
    let image = UIGraphicsImageRenderer(size: size).image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    return image.jpegData(compressionQuality: 1.0)!
}

struct ImageDownsampleTests {
    @Test func 장변이_상한_이하로_줄어든다() throws {
        let original = makeJPEG(width: 2400, height: 1200)
        let data = try #require(UIImage.downsampledJPEG(from: original, maxDimension: 1024, quality: 0.8))
        let image = try #require(UIImage(data: data))

        #expect(max(image.size.width, image.size.height) <= 1024)
        #expect(data.count < original.count)
    }

    @Test func 상한보다_작은_이미지는_키우지_않는다() throws {
        let original = makeJPEG(width: 400, height: 300)
        let data = try #require(UIImage.downsampledJPEG(from: original, maxDimension: 1024, quality: 0.8))
        let image = try #require(UIImage(data: data))

        #expect(max(image.size.width, image.size.height) <= 400)
    }

    @Test func 이미지가_아닌_데이터는_nil() {
        #expect(UIImage.downsampledJPEG(from: Data("not an image".utf8), maxDimension: 1024, quality: 0.8) == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/ImageDownsampleTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `type 'UIImage' has no member 'downsampledJPEG'`

- [ ] **Step 3: 다운샘플을 구현한다**

`WooriHaru/Extensions/UIImage+Extensions.swift`:

```swift
import ImageIO
import UIKit
import UniformTypeIdentifiers

extension UIImage {
    /// 업로드 전에 장변을 `maxDimension`으로 줄인 JPEG 데이터.
    ///
    /// `UIImage(data:)`로 통째로 디코드하지 않고 ImageIO 썸네일로 만든다 — PhotosPicker 원본은
    /// 12MP급이라 5장을 동시에 들고 있으면 메모리가 튄다. 서버(라즈베리파이)가 재인코딩하지
    /// 않도록 앱에서 줄이는 것이고, 장변 1024px에서 음식 인식 정확도 손실은 사실상 없다.
    ///
    /// 원본이 상한보다 작으면 `kCGImageSourceCreateThumbnailFromImageAlways`가 확대하지 않도록
    /// 상한을 원본 장변으로 낮춘다.
    static func downsampledJPEG(from data: Data, maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let originalMax = max(
            (properties[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0,
            (properties[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        )
        guard originalMax > 0 else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxDimension, originalMax)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

파일을 「파일 등록 절차」대로 등록한다(`DT10001`/`DT20001`, 그룹 `B40015`).

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/ImageDownsampleTests 2>&1 | tail -30`
Expected: 3개 PASS

- [ ] **Step 5: multipart 메서드를 추가한다**

`WooriHaru/Services/APIClient.swift` — 프로토콜(`APIClientProtocol`, 36행 `deleteVoid` 아래)에 선언을 넣는다:

```swift
    /// `/files` 단건 업로드. 201 + Location에서 fileId를 파싱해 돌려준다.
    /// **multipart를 쓰는 곳은 여기 한 군데뿐이고 나머지 식단 API는 전부 JSON이다.**
    /// 여러 장은 이 메서드를 순차로 여러 번 부르는 것으로 처리한다 — 서버 `/files`가 단건이고,
    /// 병렬로 밀어넣으면 실패했을 때 어디까지 올라갔는지 추적이 지저분해진다.
    func postMultipartCreated(_ path: String, fileData: Data, fileName: String, mimeType: String) async throws -> Int
```

구현부(`APIClient`의 `postCreated` 아래, 102행 뒤)에 추가한다:

```swift
    func postMultipartCreated(_ path: String, fileData: Data, fileName: String, mimeType: String) async throws -> Int {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        // 서버 `FileController.upload`의 @RequestParam("file")과 이름이 맞아야 한다.
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (_, response) = try await rawMultipartFetch(path, body: body, boundary: boundary)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let idString = location.split(separator: "/").last,
              let id = Int(idString) else {
            throw APIError.serverError(statusCode: response.statusCode, message: "Location 헤더에서 ID를 찾을 수 없습니다")
        }
        return id
    }
```

`rawFetchWithResponse` 아래(217행 뒤, `APIClient`의 마지막 `}` 앞)에 전송부를 둔다. **`rawFetchWithResponse`를 재사용하지 않는 이유는 그쪽이 본문을 `JSONEncoder`로 인코딩하기 때문이다.** 401 재시도·취소 변환은 같은 모양으로 복제한다:

```swift
    private func rawMultipartFetch(
        _ path: String,
        body: Data,
        boundary: String,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let session = SessionManager.shared.urlSession

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 && !isRetry {
            let shouldRetry = await SessionManager.shared.handleUnauthorized()
            if shouldRetry {
                return try await rawMultipartFetch(path, body: body, boundary: boundary, isRetry: true)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8))
        }

        return (data, httpResponse)
    }
```

- [ ] **Step 6: `MockAPIClient`를 확장한다**

`WooriHaruTests/MockAPIClient.swift`를 통째로 다시 쓴다. 기존 `stubGet`·`setPutVoidError`·`putVoidCalls`는 `SwimRecordTests`·`CalendarMonthTests`가 쓰고 있으므로 **이름을 그대로 유지한다.**

```swift
import Foundation
@testable import WooriHaru

/// 경로별 응답을 미리 등록해 두고 호출을 기록하는 테스트 대역.
/// 등록되지 않은 경로 호출은 unstubbed 에러로 실패한다.
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    enum MockAPIError: Error {
        case unstubbed(String)
        case forced
    }

    private let lock = NSLock()

    private var getResults: [String: Any] = [:]
    private var postResults: [String: Any] = [:]
    private var postCreatedResults: [String: Int] = [:]
    private var multipartResults: [Int] = []
    private var errors: [String: Error] = [:]
    private var putVoidError: Error?

    private var recordedGetCalls: [(path: String, query: [String: String])] = []
    private var recordedPostCalls: [(path: String, body: (any Encodable)?)] = []
    private var recordedPostCreatedCalls: [(path: String, body: (any Encodable)?)] = []
    private var recordedMultipartCalls: [(path: String, byteCount: Int)] = []
    private var recordedPutVoidCalls: [(path: String, body: (any Encodable)?)] = []
    private var recordedDeleteCalls: [String] = []

    // MARK: - Stub

    /// GET 경로에 대한 응답 등록
    func stubGet(_ path: String, result: Any) {
        lock.lock(); defer { lock.unlock() }
        getResults[path] = result
    }

    func stubPost(_ path: String, result: Any) {
        lock.lock(); defer { lock.unlock() }
        postResults[path] = result
    }

    func stubPostCreated(_ path: String, result: Int) {
        lock.lock(); defer { lock.unlock() }
        postCreatedResults[path] = result
    }

    /// 업로드가 돌려줄 fileId를 올린 순서대로 등록한다. 등록한 수보다 많이 부르면 unstubbed다.
    func stubMultipart(fileIds: [Int]) {
        lock.lock(); defer { lock.unlock() }
        multipartResults = fileIds
    }

    /// `"POST /diet/analyses"`처럼 `메서드 경로` 키로 던질 에러를 등록한다.
    /// nil을 주면 해제한다 — 재시도 테스트에서 "한 번 실패한 뒤 성공"을 만들 때 쓴다.
    func setError(_ error: Error?, for key: String) {
        lock.lock(); defer { lock.unlock() }
        errors[key] = error
    }

    /// putVoid가 던질 에러 설정 (롤백 테스트용)
    func setPutVoidError(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        putVoidError = error
    }

    // MARK: - 기록

    var getCalls: [(path: String, query: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return recordedGetCalls
    }

    var postCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPostCalls
    }

    var postCreatedCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPostCreatedCalls
    }

    var multipartCalls: [(path: String, byteCount: Int)] {
        lock.lock(); defer { lock.unlock() }
        return recordedMultipartCalls
    }

    var putVoidCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPutVoidCalls
    }

    var deleteCalls: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedDeleteCalls
    }

    // MARK: - APIClientProtocol

    func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        lock.lock()
        recordedGetCalls.append((path, query))
        let error = errors["GET \(path)"]
        let result = getResults[path]
        lock.unlock()
        if let error { throw error }
        guard let value = result as? T else { throw MockAPIError.unstubbed("GET \(path)") }
        return value
    }

    func post<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        lock.lock()
        recordedPostCalls.append((path, body))
        let error = errors["POST \(path)"]
        let result = postResults[path]
        lock.unlock()
        if let error { throw error }
        guard let value = result as? T else { throw MockAPIError.unstubbed("POST \(path)") }
        return value
    }

    func postVoid(_ path: String, body: (any Encodable)?) async throws {
        lock.lock()
        recordedPostCalls.append((path, body))
        let error = errors["POST \(path)"]
        lock.unlock()
        if let error { throw error }
    }

    func postCreated(_ path: String, body: (any Encodable)?) async throws -> Int {
        lock.lock()
        recordedPostCreatedCalls.append((path, body))
        let error = errors["POST \(path)"]
        let result = postCreatedResults[path]
        lock.unlock()
        if let error { throw error }
        guard let id = result else { throw MockAPIError.unstubbed("POST \(path)") }
        return id
    }

    func postMultipartCreated(_ path: String, fileData: Data, fileName: String, mimeType: String) async throws -> Int {
        lock.lock()
        let index = recordedMultipartCalls.count
        recordedMultipartCalls.append((path, fileData.count))
        let error = errors["POST \(path)"]
        // 장별로 다른 에러를 주려면 "POST /files#2"처럼 인덱스를 붙인 키를 쓴다.
        let indexedError = errors["POST \(path)#\(index)"]
        let result = index < multipartResults.count ? multipartResults[index] : nil
        lock.unlock()
        if let indexedError { throw indexedError }
        if let error { throw error }
        guard let id = result else { throw MockAPIError.unstubbed("POST \(path) #\(index)") }
        return id
    }

    func put<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        throw MockAPIError.unstubbed("PUT \(path)")
    }

    func putVoid(_ path: String, body: (any Encodable)?) async throws {
        lock.lock()
        recordedPutVoidCalls.append((path, body))
        let error = putVoidError ?? errors["PUT \(path)"]
        lock.unlock()
        if let error { throw error }
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        throw MockAPIError.unstubbed("PATCH \(path)")
    }

    func patchVoid(_ path: String, body: (any Encodable)?) async throws {
        throw MockAPIError.unstubbed("PATCH \(path)")
    }

    func deleteVoid(_ path: String) async throws {
        lock.lock()
        recordedDeleteCalls.append(path)
        let error = errors["DELETE \(path)"]
        lock.unlock()
        if let error { throw error }
    }
}
```

- [ ] **Step 7: 기존 테스트가 안 깨졌는지 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30`
Expected: 기존 테스트 전부 PASS + `ImageDownsampleTests` 3개 PASS

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/Extensions/UIImage+Extensions.swift WooriHaru/Services/APIClient.swift \
        WooriHaruTests/MockAPIClient.swift WooriHaruTests/DietTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 사진 업로드 토대를 만든다 — multipart 업로드와 다운샘플"
```

---

## Task 2: 모델과 영양소 환산

서버 DTO를 그대로 옮기고, **앱이 유일하게 계산하는 값**인 100g당 → 수량 환산을 한 곳에 모아 테스트로 고정한다. 이 태스크의 `NutritionMath` 테스트가 이 계획에서 가장 중요하다 — 환산식이 서버와 앱 두 곳에 살게 되므로 어긋나면 저장된 수치가 조용히 틀린다.

**Files:**
- Create: `WooriHaru/Models/DietErrorCode.swift`, `Models/Diet.swift`, `Models/MealAnalysis.swift`, `Models/NutritionProfile.swift`, `Models/Food.swift`, `Models/FrequentItem.swift`, `Models/DietStats.swift`, `Models/NutritionMath.swift`
- Test: `WooriHaruTests/DietTests.swift` (추가)
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — 등록 ID: `DT10002`/`DT20002` `DietErrorCode.swift`, `DT10003`/`DT20003` `Diet.swift`, `DT10004`/`DT20004` `MealAnalysis.swift`, `DT10005`/`DT20005` `NutritionProfile.swift`, `DT10006`/`DT20006` `Food.swift`, `DT10007`/`DT20007` `FrequentItem.swift`, `DT10008`/`DT20008` `DietStats.swift`, `DT10009`/`DT20009` `NutritionMath.swift` — 전부 그룹 `B40001`

**Interfaces:**
- Consumes: 없음
- Produces: `MealType`·`AnalysisStatus`·`NutritionSource`·`MacroStatus`·`NutrientStatus`·`FoodDataset`·`ActivityLevel`·`DietGoal`, `Meal`·`MealPhoto`·`MealItem`·`MealItemRequest`·`MealConfirmRequest`·`MealItemsRequest`·`DailyDiet`·`NutrientLimit`·`MealScoreBasis`·`MacroBasis`·`DayScoreBasis`·`CalorieBasis`·`MacroAmountBasis`, `MealAnalysis`·`AnalyzedPhoto`·`AnalyzedItem`, `NutritionProfile`·`NutritionProfileRequest`·`WeightUpdateRequest`, `Food`, `FrequentItem`, `DietStats`·`DailyScore`·`NutritionTotals`·`NutritionTargets`, `DietErrorCode`·`Error.dietErrorCode`, `NutritionMath.scale(per100g:quantityG:)`·`.item(from:quantityG:)`·`.rescaled(_:to:)`·`.defaultQuantity(for:)`·`.request(from:)`·`.request(from:)`(AnalyzedItem)

- [ ] **Step 1: 환산 테스트를 먼저 쓴다**

`WooriHaruTests/DietTests.swift` 끝에 붙인다:

```swift
private func makeFood(
    code: String = "D000001",
    name: String = "제육볶음",
    dataset: FoodDataset = .dish,
    servingSizeG: Double = 250,
    servingSizeKnown: Bool = true,
    kcal: Double = 150,
    carbs: Double = 12,
    protein: Double = 10,
    fat: Double = 7,
    sugar: Double = 3,
    sodium: Double = 400,
    fiber: Double = 1.5
) -> Food {
    Food(
        code: code, name: name, dataset: dataset,
        servingSizeG: servingSizeG, servingSizeKnown: servingSizeKnown,
        kcalPer100g: kcal, carbsPer100g: carbs, proteinPer100g: protein, fatPer100g: fat,
        sugarPer100g: sugar, sodiumMgPer100g: sodium, fiberPer100g: fiber
    )
}

struct NutritionMathTests {
    /// 서버 `Food.nutritionFor`와 같은 식이어야 한다 — `per100g × (quantityG / 100)`, 반올림 없음.
    @Test func 백그램당_값을_수량으로_환산한다() {
        #expect(NutritionMath.scale(per100g: 150, quantityG: 150) == 225)
        #expect(NutritionMath.scale(per100g: 150, quantityG: 100) == 150)
        #expect(NutritionMath.scale(per100g: 0, quantityG: 300) == 0)
        #expect(NutritionMath.scale(per100g: 150, quantityG: 0) == 0)
    }

    @Test func 검색_결과를_항목으로_옮기면_일곱_값이_모두_환산된다() {
        let item = NutritionMath.item(from: makeFood(), quantityG: 150)

        #expect(item.foodName == "제육볶음")
        #expect(item.foodCode == "D000001")
        #expect(item.quantityG == 150)
        #expect(item.kcal == 225)
        #expect(item.carbsG == 18)
        #expect(item.proteinG == 15)
        #expect(item.fatG == 10.5)
        #expect(item.sugarG == 4.5)
        #expect(item.sodiumMg == 600)
        #expect(item.fiberG == 2.25)
        #expect(item.source == .dbMatched)
    }

    /// 「1인분 300g·100g당 150kcal을 150g 먹으면 225kcal」 — 스펙의 기준 예시.
    @Test func 스펙의_기준_예시가_맞는다() {
        let item = NutritionMath.item(from: makeFood(servingSizeG: 300), quantityG: 150)
        #expect(item.kcal == 225)
    }

    @Test func 수량을_바꾸면_일곱_값이_비례해서_따라온다() {
        let original = NutritionMath.item(from: makeFood(), quantityG: 100)
        let doubled = NutritionMath.rescaled(original, to: 200)

        #expect(doubled.quantityG == 200)
        #expect(doubled.kcal == 300)
        #expect(doubled.carbsG == 24)
        #expect(doubled.proteinG == 20)
        #expect(doubled.fatG == 14)
        #expect(doubled.sugarG == 6)
        #expect(doubled.sodiumMg == 800)
        #expect(doubled.fiberG == 3)
        #expect(doubled.id == original.id)
    }

    /// 수량 0인 항목(직접 입력 도중)에서 0으로 나누지 않는다.
    @Test func 원래_수량이_0이면_수량만_바꾸고_영양소는_그대로_둔다() {
        var item = NutritionMath.item(from: makeFood(), quantityG: 100)
        item.quantityG = 0
        let changed = NutritionMath.rescaled(item, to: 50)

        #expect(changed.quantityG == 50)
        #expect(changed.kcal == item.kcal)
    }

    /// `servingSizeKnown == false`면 서버가 채운 200g 자리채움값이라 기본 수량으로 쓰면 안 된다.
    @Test func 일인분_미상이면_기본_수량이_없다() {
        #expect(NutritionMath.defaultQuantity(for: makeFood(servingSizeG: 250, servingSizeKnown: true)) == 250)
        #expect(NutritionMath.defaultQuantity(for: makeFood(servingSizeG: 200, servingSizeKnown: false)) == nil)
    }

    /// 인식 결과와 자주 먹는 음식은 **다시 계산하지 않고** 값을 그대로 옮긴다.
    @Test func 인식_결과와_자주_먹는_음식은_값을_그대로_옮긴다() {
        let analyzed = AnalyzedItem(
            foodName: "김치찌개", foodCode: nil, quantityG: 400,
            kcal: 320, carbsG: 20, proteinG: 18, fatG: 19,
            sugarG: 5, sodiumMg: 1800, fiberG: 3, source: .llmEstimated
        )
        let fromAnalyzed = NutritionMath.request(from: analyzed)
        #expect(fromAnalyzed.sodiumMg == 1800)
        #expect(fromAnalyzed.source == .llmEstimated)
        #expect(fromAnalyzed.foodCode == nil)

        let frequent = FrequentItem(
            foodName: "사과", foodCode: "R000012", quantityG: 200,
            kcal: 104, carbsG: 28, proteinG: 0.6, fatG: 0.4,
            sugarG: 21, sodiumMg: 2, fiberG: 4.8, source: .dbMatched,
            count: 7, lastEatenOn: "2026-07-29"
        )
        let fromFrequent = NutritionMath.request(from: frequent)
        #expect(fromFrequent.quantityG == 200)
        #expect(fromFrequent.kcal == 104)
        #expect(fromFrequent.fiberG == 4.8)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/NutritionMathTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'Food' in scope`

- [ ] **Step 3: `Models/Diet.swift`를 만든다**

```swift
import Foundation

// MARK: - Enum (rawValue는 서버 값 그대로)

enum MealType: String, Codable, CaseIterable, Identifiable, Hashable {
    case breakfast = "BREAKFAST"
    case lunch = "LUNCH"
    case dinner = "DINNER"
    case snack = "SNACK"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "아침"
        case .lunch: "점심"
        case .dinner: "저녁"
        case .snack: "간식"
        }
    }

    var iconName: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "cup.and.saucer"
        }
    }
}

/// `MealAnalysis`에서는 인식 진행 상태, `Meal`에서는 피드백 생성 상태를 뜻한다.
enum AnalysisStatus: String, Codable, Hashable {
    case pending = "PENDING"
    case completed = "COMPLETED"
    case failed = "FAILED"
}

enum NutritionSource: String, Codable, Hashable {
    case dbMatched = "DB_MATCHED"
    case llmEstimated = "LLM_ESTIMATED"
}

enum MacroStatus: String, Codable, Hashable {
    case under = "UNDER"
    case inRange = "IN_RANGE"
    case over = "OVER"
}

enum NutrientStatus: String, Codable, Hashable {
    case ok = "OK"
    case warn = "WARN"
}

// MARK: - 점수 근거 (서버가 판정한 값을 그대로 표시한다)

struct MacroBasis: Codable, Hashable, Identifiable {
    let name: String
    let percent: Double
    let rangeMin: Int
    let rangeMax: Int
    let status: MacroStatus
    let penalty: Double

    var id: String { name }
}

struct MealScoreBasis: Codable, Hashable {
    let standard: String
    let macros: [MacroBasis]
}

struct CalorieBasis: Codable, Hashable {
    let intakeKcal: Double
    let targetKcal: Int
    let ratio: Double
    let calorieScore: Int
}

struct MacroAmountBasis: Codable, Hashable, Identifiable {
    let name: String
    let intakeG: Double
    let targetG: Int
    let ratio: Double
    let score: Int

    var id: String { name }
}

/// 하루 점수 근거. `standard`가 자체 기준이라고 밝히므로 국가 기준과 같은 무게로 제시하지 않는다.
struct DayScoreBasis: Codable, Hashable {
    let standard: String
    let calorie: CalorieBasis
    let macros: [MacroAmountBasis]
    let calorieWeight: Double
    let macroWeight: Double
}

// MARK: - 끼니

struct MealItem: Codable, Hashable, Identifiable {
    let id: Int
    let foodName: String
    let foodCode: String?
    let quantityG: Double
    let kcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
    let source: NutritionSource
}

struct MealPhoto: Codable, Hashable, Identifiable {
    let fileId: Int
    /// presigned URL — 10분 만료라 오래 캐시하지 않는다. 화면을 다시 열 때 조회한다.
    let url: String?
    let sortOrder: Int

    var id: Int { fileId }
}

struct Meal: Codable, Hashable, Identifiable {
    let id: Int
    /// "yyyy-MM-dd"
    let date: String
    let mealType: MealType
    /// **피드백 생성 상태**다. 점수는 확정 시점에 이미 계산돼 있다.
    let status: AnalysisStatus
    let score: Int?
    let scoreBasis: MealScoreBasis?
    let totalKcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
    let feedback: String?
    /// 확정 시점 스냅샷 — 몸무게를 고쳐도 과거 점수가 흔들리지 않는 근거다.
    let weightKg: Double
    let targetKcal: Int
    /// 사진 없이 기록한 끼니는 **빈 배열**이다.
    let photos: [MealPhoto]
    let items: [MealItem]
}

// MARK: - 하루

/// **앱이 판정하지 않는다.** `status`가 `WARN`이면 강조하고 `OK`면 평범하게 둔다.
/// `standardText`는 서버 문구를 그대로 쓴다(기준이 개정되면 앱 배포 없이 따라간다).
struct NutrientLimit: Codable, Hashable, Identifiable {
    let name: String
    let intake: Double
    let unit: String
    let standardText: String
    let status: NutrientStatus

    var id: String { name }
}

struct DailyDiet: Codable, Hashable {
    /// "yyyy-MM-dd"
    let date: String
    let dayScore: Int?
    let scoreBasis: DayScoreBasis?
    /// `null`이면 서버가 뒤에서 만들고 있다는 뜻이다 — 폴링 대상이지 실패가 아니다.
    let feedback: String?
    let totalKcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let activeEnergyKcal: Int?
    /// `mealType` 순(아침→점심→저녁→간식)으로 온다. **앱이 다시 정렬하지 않는다.**
    let meals: [Meal]
    let nutrientLimits: [NutrientLimit]
    /// 그날 LLM 추정 항목 수. 0보다 크면 「추정 N건 포함」을 단다. 기록이 없는 날도 0이다.
    let estimatedItemCount: Int
}

// MARK: - Request

/// 확인 화면에서 편집하는 단위이자 서버로 보내는 본문. `id`는 로컬 식별용이라 전송하지 않는다
/// (`CodingKeys`에 없다) — 같은 음식이 여러 사진에서 중복으로 잡혀도 행을 구분해야 한다.
struct MealItemRequest: Codable, Hashable, Identifiable {
    var id = UUID()
    var foodName: String
    /// **직접 입력에는 `""`가 아니라 `nil`을 넣는다.** 서버 검증(`@Size(max=30)`)이 빈 문자열을
    /// 막지 않고, 자주 먹는 음식 집계가 코드로 묶으므로 애초에 안 보내는 편이 안전하다.
    var foodCode: String?
    var quantityG: Double
    var kcal: Double
    var carbsG: Double
    var proteinG: Double
    var fatG: Double
    /// 주의 영양소 3필드. **여기가 빠지면 서버가 검증 오류 없이 0으로 저장한다.**
    var sugarG: Double
    var sodiumMg: Double
    var fiberG: Double
    var source: NutritionSource

    private enum CodingKeys: String, CodingKey {
        case foodName, foodCode, quantityG, kcal, carbsG, proteinG, fatG, sugarG, sodiumMg, fiberG, source
    }
}

/// `analysisId`가 `nil`이면 사진 없이 기록한다 — `encodeIfPresent`라 키 자체가 빠진다.
struct MealConfirmRequest: Encodable {
    let date: String
    let mealType: MealType
    let analysisId: Int?
    let items: [MealItemRequest]
}

struct MealItemsRequest: Encodable {
    let items: [MealItemRequest]
}

struct ActivityUpsertRequest: Encodable {
    let date: String
    let activeEnergyKcal: Int
}

struct AnalysisCreateRequest: Encodable {
    let fileIds: [Int]
}

// MARK: - 정책 상수

enum DietPolicy {
    /// 서버가 사진마다 LLM을 호출하므로 장수가 곧 비용·대기시간이다.
    static let maxPhotos = 5
    static let pollInterval: Duration = .seconds(2)
    static let pollTimeout: Duration = .seconds(60)
}
```

- [ ] **Step 4: 나머지 모델 파일을 만든다**

`WooriHaru/Models/MealAnalysis.swift`:

```swift
import Foundation

/// 확정 전 인식 결과. 저장하지 않고 나가면 아무것도 남지 않는다 — 서버가 24시간 뒤 정리한다.
struct MealAnalysis: Codable, Hashable, Identifiable {
    let id: Int
    let status: AnalysisStatus
    let photos: [AnalyzedPhoto]

    /// 사진 일부만 실패한 상태. 그 사진만 다시 시도할 수 있다.
    var hasFailedPhoto: Bool { photos.contains(where: \.failed) }
}

struct AnalyzedPhoto: Codable, Hashable, Identifiable {
    let fileId: Int
    let url: String?
    /// 실패한 사진도 **감추지 않는다** — 5장 올린 사용자가 4장 분량만 보면 나머지를 찾을 수 없다.
    let failed: Bool
    let items: [AnalyzedItem]

    var id: Int { fileId }
}

struct AnalyzedItem: Codable, Hashable {
    let foodName: String
    let foodCode: String?
    let quantityG: Double
    let kcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
    let source: NutritionSource
}
```

`WooriHaru/Models/NutritionProfile.swift`:

```swift
import Foundation

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case sedentary = "SEDENTARY"
    case light = "LIGHT"
    case moderate = "MODERATE"
    case active = "ACTIVE"
    case veryActive = "VERY_ACTIVE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedentary: "거의 안 움직임"
        case .light: "가벼운 활동"
        case .moderate: "보통 활동"
        case .active: "활발한 활동"
        case .veryActive: "매우 활발함"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "종일 앉아서 지냄"
        case .light: "주 1~3회 가벼운 운동"
        case .moderate: "주 3~5회 운동"
        case .active: "주 6~7회 운동"
        case .veryActive: "매일 고강도 운동 또는 육체노동"
        }
    }
}

enum DietGoal: String, Codable, CaseIterable, Identifiable, Hashable {
    case lose = "LOSE"
    case maintain = "MAINTAIN"
    case gain = "GAIN"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lose: "감량"
        case .maintain: "유지"
        case .gain: "증량"
        }
    }
}

/// 목표는 서버가 계산해 저장한다 — 앱은 표시만 한다.
struct NutritionProfile: Codable, Hashable {
    let heightCm: Double
    let weightKg: Double
    let activityLevel: ActivityLevel
    let goal: DietGoal
    let targetKcal: Int
    let targetCarbsG: Int
    let targetProteinG: Int
    let targetFatG: Int
    let targetSugarG: Int
    let targetSodiumMg: Int
    let targetFiberG: Int
}

struct NutritionProfileRequest: Encodable {
    let heightCm: Double
    let weightKg: Double
    let activityLevel: ActivityLevel
    let goal: DietGoal
}

/// 몸무게는 매일 재는 값이라 프로필 전체를 다시 보내지 않는다.
struct WeightUpdateRequest: Encodable {
    let weightKg: Double
}
```

`WooriHaru/Models/Food.swift`:

```swift
import Foundation

enum FoodDataset: String, Codable, Hashable {
    case dish = "DISH"
    case raw = "RAW"
    case processed = "PROCESSED"

    /// 목록에서 구분해 보여줄 배지 문구. 조리 음식은 기본값이라 배지를 달지 않는다.
    var badge: String? {
        switch self {
        case .dish: nil
        case .raw: "원재료"
        case .processed: "가공식품"
        }
    }
}

/// `GET /diet/foods` 결과. 값은 전부 **100g당**이라 담을 때 `NutritionMath`로 환산해야 한다.
struct Food: Codable, Hashable, Identifiable {
    let code: String
    let name: String
    let dataset: FoodDataset
    let servingSizeG: Double
    /// **false면 `servingSizeG`(200g)는 서버가 채운 자리채움값이다** — 기본 수량으로 쓰면
    /// 달걀 한 개가 4배로 담긴다. 검색 결과 중 원재료 전부·가공식품 31%·음식 21%가 여기 걸린다.
    let servingSizeKnown: Bool
    let kcalPer100g: Double
    let carbsPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let sugarPer100g: Double
    let sodiumMgPer100g: Double
    let fiberPer100g: Double

    /// 코드는 데이터셋 안에서만 유일하다.
    var id: String { "\(dataset.rawValue)-\(code)" }
}
```

`WooriHaru/Models/FrequentItem.swift`:

```swift
import Foundation

/// 내가 실제로 저장했던 항목. **응답 한 건이 그대로 `MealItemRequest`가 되므로 앱이 다시
/// 계산하지 않는다** — 수량과 영양소가 딸려 온다.
struct FrequentItem: Codable, Hashable, Identifiable {
    let foodName: String
    let foodCode: String?
    let quantityG: Double
    let kcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
    let source: NutritionSource
    /// 기간 내 먹은 횟수
    let count: Int
    /// "yyyy-MM-dd"
    let lastEatenOn: String

    /// 서버가 코드 없는 항목을 정규화한 이름으로 묶으므로 코드가 없으면 이름이 키다.
    var id: String { foodCode ?? foodName }

    var countText: String { "\(count)회" }
}
```

`WooriHaru/Models/DietStats.swift`:

```swift
import Foundation

struct DailyScore: Codable, Hashable, Identifiable {
    /// "yyyy-MM-dd"
    let date: String
    let dayScore: Int

    var id: String { date }
}

struct NutritionTotals: Codable, Hashable {
    let kcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
}

struct NutritionTargets: Codable, Hashable {
    let kcal: Int
    let carbsG: Int
    let proteinG: Int
    let fatG: Int
    let sugarG: Int
    let sodiumMg: Int
    let fiberG: Int
}

/// 기록이 0건이면 `averageDayScore`·`averageIntake`·`averageTargets`가 `null`이고
/// `dailyScores`는 빈 배열이다. `recordedDays`만 0으로 온다.
struct DietStats: Codable, Hashable {
    let from: String
    let to: String
    /// 평균의 분모. **안 적은 날을 0으로 세지 않으므로 화면에 함께 보여줘야 평균이 읽힌다.**
    let recordedDays: Int
    let averageDayScore: Int?
    /// **기록한 날만 들어간다** — 추이 차트의 x축을 배열 인덱스로 잡으면 날짜 간격이 뭉개진다.
    let dailyScores: [DailyScore]
    let averageIntake: NutritionTotals?
    let averageTargets: NutritionTargets?
    /// `FrequentItem`과 같은 모양이라 자주 먹는 음식 목록 컴포넌트를 그대로 쓴다.
    let topFoods: [FrequentItem]
}
```

`WooriHaru/Models/DietErrorCode.swift`:

```swift
import Foundation

/// 식단 도메인 에러. **분기 기준은 응답 바디의 `error` 필드다** —
/// `code`는 HTTP 상태를 문자열로 담을 뿐이라(`"400"`) 종류를 가르지 못한다.
enum DietErrorCode: String {
    case profileNotFound = "PROFILE_NOT_FOUND"
    case photoLimitExceeded = "PHOTO_LIMIT_EXCEEDED"
    case llmUnavailable = "LLM_UNAVAILABLE"
    case analysisNotConfirmable = "ANALYSIS_NOT_CONFIRMABLE"
    case analysisNotRetryable = "ANALYSIS_NOT_RETRYABLE"
    case analysisInProgress = "ANALYSIS_IN_PROGRESS"
    case resourceNotFound = "RESOURCE_NOT_FOUND"
    case invalidRequest = "INVALID_REQUEST"
}

private struct DietErrorBody: Decodable {
    let error: String
}

extension Error {
    /// `APIError.serverError`의 message에 실려 온 JSON 본문에서 `error`를 읽는다.
    /// 본문이 JSON이 아니거나 아는 코드가 아니면 nil — 호출부는 일반 오류로 다룬다.
    var dietErrorCode: DietErrorCode? {
        // `extension Error` 안에서는 `self`가 제네릭 `Self`라 `case let APIError.serverError = self`가
        // 컴파일되지 않는다 — 먼저 캐스팅해야 한다.
        guard let apiError = self as? APIError,
              case let .serverError(_, message) = apiError,
              let data = message?.data(using: .utf8),
              let body = try? JSONDecoder().decode(DietErrorBody.self, from: data) else {
            return nil
        }
        return DietErrorCode(rawValue: body.error)
    }
}
```

`WooriHaru/Models/NutritionMath.swift`:

```swift
import Foundation

/// **100g당 값 → 수량 기준 환산을 여기 한 곳에 모은다.** 서버 `Food.nutritionFor`와 같은 식이며
/// (`per100g × quantityG / 100`, 반올림 없음), 다르면 저장된 수치가 조용히 틀린다.
///
/// 환산 대상은 **7개 전부**다 — 열량·탄단지에 더해 당류·나트륨·식이섬유까지. 넷만 채워 보내면
/// 서버가 나머지를 `0.0`으로 받아 말없이 저장하고, 증상은 「나트륨이 매일 기준 이하」로만 나타난다.
enum NutritionMath {
    static func scale(per100g: Double, quantityG: Double) -> Double {
        per100g * (quantityG / 100.0)
    }

    /// 식품DB 검색 결과를 수량만큼 담는다.
    static func item(from food: Food, quantityG: Double) -> MealItemRequest {
        MealItemRequest(
            foodName: food.name,
            foodCode: food.code,
            quantityG: quantityG,
            kcal: scale(per100g: food.kcalPer100g, quantityG: quantityG),
            carbsG: scale(per100g: food.carbsPer100g, quantityG: quantityG),
            proteinG: scale(per100g: food.proteinPer100g, quantityG: quantityG),
            fatG: scale(per100g: food.fatPer100g, quantityG: quantityG),
            sugarG: scale(per100g: food.sugarPer100g, quantityG: quantityG),
            sodiumMg: scale(per100g: food.sodiumMgPer100g, quantityG: quantityG),
            fiberG: scale(per100g: food.fiberPer100g, quantityG: quantityG),
            source: .dbMatched
        )
    }

    /// 확인 화면에서 수량을 고칠 때. 100g당 값이 남아 있지 않으므로 **현재 수량 대비 비례**로 옮긴다.
    /// 원래 수량이 0이면 비율을 만들 수 없어 수량만 바꾼다(0으로 나누지 않는다).
    static func rescaled(_ item: MealItemRequest, to quantityG: Double) -> MealItemRequest {
        guard item.quantityG > 0 else {
            var changed = item
            changed.quantityG = quantityG
            return changed
        }
        let ratio = quantityG / item.quantityG
        var changed = item
        changed.quantityG = quantityG
        changed.kcal = item.kcal * ratio
        changed.carbsG = item.carbsG * ratio
        changed.proteinG = item.proteinG * ratio
        changed.fatG = item.fatG * ratio
        changed.sugarG = item.sugarG * ratio
        changed.sodiumMg = item.sodiumMg * ratio
        changed.fiberG = item.fiberG * ratio
        return changed
    }

    /// 검색 결과를 담을 때 채워 줄 기본 수량. **`servingSizeKnown`이 false면 없다** —
    /// 서버가 채운 200g 자리채움값이라 그대로 넣으면 그럴듯하게 틀린 수치가 기록된다.
    static func defaultQuantity(for food: Food) -> Double? {
        food.servingSizeKnown ? food.servingSizeG : nil
    }

    /// 인식 결과를 확정 요청으로 옮긴다. **다시 계산하지 않는다** — 서버가 이미 환산한 값이다.
    static func request(from item: AnalyzedItem) -> MealItemRequest {
        MealItemRequest(
            foodName: item.foodName,
            foodCode: item.foodCode,
            quantityG: item.quantityG,
            kcal: item.kcal,
            carbsG: item.carbsG,
            proteinG: item.proteinG,
            fatG: item.fatG,
            sugarG: item.sugarG,
            sodiumMg: item.sodiumMg,
            fiberG: item.fiberG,
            source: item.source
        )
    }

    /// 자주 먹는 음식은 수량과 영양소가 딸려 오므로 **탭 한 번으로 그대로 담긴다.**
    static func request(from item: FrequentItem) -> MealItemRequest {
        MealItemRequest(
            foodName: item.foodName,
            foodCode: item.foodCode,
            quantityG: item.quantityG,
            kcal: item.kcal,
            carbsG: item.carbsG,
            proteinG: item.proteinG,
            fatG: item.fatG,
            sugarG: item.sugarG,
            sodiumMg: item.sodiumMg,
            fiberG: item.fiberG,
            source: item.source
        )
    }

    /// 직접 입력 — 식품DB에도 없고 포장지 영양성분표를 보고 넣는 최후 수단.
    /// **`foodCode`는 빈 문자열이 아니라 `nil`이고 `source`는 `.llmEstimated`다**(식품DB 값이 아니다).
    static func manualItem(
        name: String,
        quantityG: Double,
        kcal: Double,
        carbsG: Double,
        proteinG: Double,
        fatG: Double,
        sugarG: Double,
        sodiumMg: Double,
        fiberG: Double
    ) -> MealItemRequest {
        MealItemRequest(
            foodName: name,
            foodCode: nil,
            quantityG: quantityG,
            kcal: kcal,
            carbsG: carbsG,
            proteinG: proteinG,
            fatG: fatG,
            sugarG: sugarG,
            sodiumMg: sodiumMg,
            fiberG: fiberG,
            source: .llmEstimated
        )
    }
}
```

- [ ] **Step 5: 등록하고 통과를 확인한다**

8개 파일을 「파일 등록 절차」대로 `B40001` 그룹에 등록한다.

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/NutritionMathTests 2>&1 | tail -30`
Expected: 7개 PASS

- [ ] **Step 6: 디코딩·에러 파싱 테스트를 추가한다**

`WooriHaruTests/DietTests.swift` 끝에 붙인다:

```swift
struct DietDecodingTests {
    /// 서버가 실제로 내려주는 모양 그대로 디코드된다.
    @Test func 하루_응답을_디코드한다() throws {
        let json = """
        {"data":{"date":"2026-07-29","dayScore":74,"scoreBasis":null,"feedback":null,
        "totalKcal":1980.0,"carbsG":250.1,"proteinG":78.4,"fatG":62.0,"activeEnergyKcal":2400,
        "meals":[],"nutrientLimits":[{"name":"나트륨","intake":2850.0,"unit":"mg",
        "standardText":"2,300mg 이하","status":"WARN"}],"estimatedItemCount":2}}
        """
        let response = try JSONDecoder().decode(DataResponse<DailyDiet>.self, from: Data(json.utf8))
        let day = try #require(response.data)

        #expect(day.feedback == nil)
        #expect(day.estimatedItemCount == 2)
        #expect(day.nutrientLimits.first?.status == .warn)
        #expect(day.nutrientLimits.first?.standardText == "2,300mg 이하")
    }

    /// 기록 0건인 기간 — 세 값이 null로 와도 깨지지 않는다.
    @Test func 기록이_없는_기간_통계를_디코드한다() throws {
        let json = """
        {"data":{"from":"2026-07-22","to":"2026-07-28","recordedDays":0,"averageDayScore":null,
        "dailyScores":[],"averageIntake":null,"averageTargets":null,"topFoods":[]}}
        """
        let stats = try #require(try JSONDecoder().decode(DataResponse<DietStats>.self, from: Data(json.utf8)).data)

        #expect(stats.recordedDays == 0)
        #expect(stats.averageDayScore == nil)
        #expect(stats.averageIntake == nil)
        #expect(stats.dailyScores.isEmpty)
    }

    /// 사진 없이 기록한 끼니는 `photos`가 빈 배열이다.
    @Test func 사진_없는_끼니를_디코드한다() throws {
        let json = """
        {"data":{"id":7,"date":"2026-07-29","mealType":"SNACK","status":"COMPLETED","score":62,
        "scoreBasis":null,"totalKcal":180.0,"carbsG":24.0,"proteinG":2.0,"fatG":8.0,
        "sugarG":12.0,"sodiumMg":150.0,"fiberG":1.0,"feedback":null,"weightKg":70.0,
        "targetKcal":2509,"photos":[],"items":[]}}
        """
        let meal = try #require(try JSONDecoder().decode(DataResponse<Meal>.self, from: Data(json.utf8)).data)

        #expect(meal.photos.isEmpty)
        #expect(meal.mealType == .snack)
    }

    /// `analysisId`가 nil이면 키 자체가 빠진다 — 서버가 「사진 없는 기록」으로 받는다.
    @Test func 사진_없는_확정_요청에는_analysisId가_없다() throws {
        let request = MealConfirmRequest(date: "2026-07-29", mealType: .snack, analysisId: nil, items: [])
        let json = try #require(String(data: try JSONEncoder().encode(request), encoding: .utf8))

        #expect(!json.contains("analysisId"))
    }

    /// 로컬 식별자는 전송하지 않는다.
    @Test func 항목_요청에_로컬_id가_실리지_않는다() throws {
        let item = NutritionMath.manualItem(
            name: "새우깡", quantityG: 40, kcal: 220, carbsG: 27,
            proteinG: 3, fatG: 11, sugarG: 2, sodiumMg: 280, fiberG: 1
        )
        let json = try #require(String(data: try JSONEncoder().encode(item), encoding: .utf8))

        #expect(!json.contains("\"id\""))
        #expect(!json.contains("foodCode"))
        #expect(json.contains("\"sodiumMg\":280"))
    }
}

struct DietErrorCodeTests {
    private func serverError(_ code: String, status: Int = 400) -> Error {
        APIError.serverError(
            statusCode: status,
            message: #"{"status":\#(status),"message":"...","code":"\#(status)","error":"\#(code)"}"#
        )
    }

    /// **`code`가 아니라 `error` 필드를 본다** — `code`는 `"400"` 같은 상태 문자열이다.
    @Test func error_필드로_분기한다() {
        #expect(serverError("ANALYSIS_IN_PROGRESS").dietErrorCode == .analysisInProgress)
        #expect(serverError("ANALYSIS_NOT_RETRYABLE").dietErrorCode == .analysisNotRetryable)
        #expect(serverError("LLM_UNAVAILABLE", status: 503).dietErrorCode == .llmUnavailable)
        #expect(serverError("PROFILE_NOT_FOUND", status: 404).dietErrorCode == .profileNotFound)
    }

    @Test func 모르는_코드나_JSON이_아니면_nil() {
        #expect(serverError("SOMETHING_ELSE").dietErrorCode == nil)
        #expect(APIError.serverError(statusCode: 500, message: "Internal Server Error").dietErrorCode == nil)
        #expect(APIError.unauthorized.dietErrorCode == nil)
    }
}
```

- [ ] **Step 7: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietDecodingTests -only-testing:WooriHaruTests/DietErrorCodeTests 2>&1 | tail -30`
Expected: 7개 PASS

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/Models WooriHaruTests/DietTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 식단 모델과 영양소 환산을 만든다"
```

---

## Task 3: `DietService` — 엔드포인트 전부

화면이 부를 API 표면을 한 번에 만든다. 프로토콜로 분리해 이후 모든 ViewModel 테스트가 이 대역을 쓴다.

**Files:**
- Create: `WooriHaru/Services/DietService.swift`
- Create: `WooriHaruTests/DietFakes.swift`
- Test: `WooriHaruTests/DietTests.swift` (추가)
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10010`/`DT20010` `DietService.swift`, 그룹 `B40002`

**Interfaces:**
- Consumes: Task 1의 `postMultipartCreated`, Task 2의 모델 전부
- Produces: `DietServing` 프로토콜(아래 메서드 전부), `DietService(api:)`, 테스트용 `FakeDietService`

- [ ] **Step 1: 경로·쿼리 테스트를 먼저 쓴다**

`WooriHaruTests/DietTests.swift` 끝에 붙인다:

```swift
struct DietServiceTests {
    @Test func 프로필이_없으면_nil을_돌려준다() async throws {
        let api = MockAPIClient()
        api.setError(
            APIError.serverError(statusCode: 404, message: #"{"status":404,"code":"404","error":"PROFILE_NOT_FOUND"}"#),
            for: "GET /diet/profile"
        )

        #expect(try await DietService(api: api).fetchProfile() == nil)
    }

    @Test func 식품_검색은_q와_size를_붙인다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/foods", result: DataResponse<[Food]>(data: []))

        _ = try await DietService(api: api).searchFoods(query: "제육")

        #expect(api.getCalls.first?.path == "/diet/foods")
        #expect(api.getCalls.first?.query["q"] == "제육")
        #expect(api.getCalls.first?.query["size"] == "20")
    }

    @Test func 자주_먹는_음식은_days와_size를_붙인다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/items/frequent", result: DataResponse<[FrequentItem]>(data: []))

        _ = try await DietService(api: api).fetchFrequentItems()

        #expect(api.getCalls.first?.query == ["days": "30", "size": "20"])
    }

    @Test func 기간_통계는_from과_to를_붙인다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/stats", result: DataResponse<DietStats>(data: DietStats(
            from: "2026-07-22", to: "2026-07-28", recordedDays: 0, averageDayScore: nil,
            dailyScores: [], averageIntake: nil, averageTargets: nil, topFoods: []
        )))

        _ = try await DietService(api: api).fetchStats(from: "2026-07-22", to: "2026-07-28")

        #expect(api.getCalls.first?.query == ["from": "2026-07-22", "to": "2026-07-28"])
    }

    @Test func 사진_업로드는_files로_간다() async throws {
        let api = MockAPIClient()
        api.stubMultipart(fileIds: [11])

        let fileId = try await DietService(api: api).uploadPhoto(Data(repeating: 0xFF, count: 128))

        #expect(fileId == 11)
        #expect(api.multipartCalls.map(\.path) == ["/files"])
        #expect(api.multipartCalls.first?.byteCount == 128)
    }

    @Test func 끼니_삭제는_DELETE로_간다() async throws {
        let api = MockAPIClient()

        try await DietService(api: api).deleteMeal(id: 42)

        #expect(api.deleteCalls == ["/diet/meals/42"])
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietServiceTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'DietService' in scope`

- [ ] **Step 3: `Services/DietService.swift`를 만든다**

```swift
import Foundation

/// 식단 API. 테스트에서 대체할 수 있도록 프로토콜로 분리한다.
protocol DietServing: Sendable {
    /// 프로필이 없으면 nil — 서버는 `PROFILE_NOT_FOUND`(404)로 답한다.
    func fetchProfile() async throws -> NutritionProfile?
    func saveProfile(_ request: NutritionProfileRequest) async throws
    func updateWeight(_ weightKg: Double) async throws

    /// **한 장 단위다.** 여러 장은 호출부가 순차로 여러 번 부른다 — 진행률을 보여줄 수 있고,
    /// 중간에 실패했을 때 어디까지 올라갔는지가 흐려지지 않는다.
    func uploadPhoto(_ jpegData: Data) async throws -> Int
    func createAnalysis(fileIds: [Int]) async throws -> Int
    func fetchAnalysis(id: Int) async throws -> MealAnalysis
    /// 실패한 사진만 다시 인식한다.
    func retryAnalysis(id: Int) async throws

    func confirmMeal(_ request: MealConfirmRequest) async throws -> Int
    func fetchMeal(id: Int) async throws -> Meal
    func updateMealItems(id: Int, items: [MealItemRequest]) async throws
    func deleteMeal(id: Int) async throws

    func fetchDay(date: String) async throws -> DailyDiet
    func upsertActivity(date: String, activeEnergyKcal: Int) async throws

    func searchFoods(query: String) async throws -> [Food]
    func fetchFrequentItems() async throws -> [FrequentItem]
    func fetchStats(from: String, to: String) async throws -> DietStats
}

/// **`POST /diet/meals/{id}/retry`(피드백 재생성)는 여기 없다.** 서버에 있지만 앱은 부르지 않는다 —
/// 생성이 실패하면 서버가 끼니가 바뀔 때까지 다시 부르지 않으므로(비용 방어) 사용자가 끼니를
/// 추가·수정하면 자연히 다시 만들어진다.
struct DietService: DietServing {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    // MARK: - 프로필

    func fetchProfile() async throws -> NutritionProfile? {
        do {
            let response: DataResponse<NutritionProfile> = try await api.get("/diet/profile")
            return response.data
        } catch {
            guard error.dietErrorCode == .profileNotFound else { throw error }
            return nil
        }
    }

    func saveProfile(_ request: NutritionProfileRequest) async throws {
        try await api.putVoid("/diet/profile", body: request)
    }

    func updateWeight(_ weightKg: Double) async throws {
        try await api.putVoid("/diet/profile/weight", body: WeightUpdateRequest(weightKg: weightKg))
    }

    // MARK: - 인식

    func uploadPhoto(_ jpegData: Data) async throws -> Int {
        try await api.postMultipartCreated(
            "/files",
            fileData: jpegData,
            fileName: "meal.jpg",
            mimeType: "image/jpeg"
        )
    }

    func createAnalysis(fileIds: [Int]) async throws -> Int {
        try await api.postCreated("/diet/analyses", body: AnalysisCreateRequest(fileIds: fileIds))
    }

    func fetchAnalysis(id: Int) async throws -> MealAnalysis {
        let response: DataResponse<MealAnalysis> = try await api.get("/diet/analyses/\(id)")
        guard let analysis = response.data else {
            throw APIError.serverError(statusCode: 200, message: "인식 응답이 비어 있습니다")
        }
        return analysis
    }

    func retryAnalysis(id: Int) async throws {
        try await api.postVoid("/diet/analyses/\(id)/retry")
    }

    // MARK: - 끼니

    func confirmMeal(_ request: MealConfirmRequest) async throws -> Int {
        try await api.postCreated("/diet/meals", body: request)
    }

    func fetchMeal(id: Int) async throws -> Meal {
        let response: DataResponse<Meal> = try await api.get("/diet/meals/\(id)")
        guard let meal = response.data else {
            throw APIError.serverError(statusCode: 200, message: "끼니 응답이 비어 있습니다")
        }
        return meal
    }

    func updateMealItems(id: Int, items: [MealItemRequest]) async throws {
        try await api.putVoid("/diet/meals/\(id)/items", body: MealItemsRequest(items: items))
    }

    func deleteMeal(id: Int) async throws {
        try await api.deleteVoid("/diet/meals/\(id)")
    }

    // MARK: - 하루

    func fetchDay(date: String) async throws -> DailyDiet {
        let response: DataResponse<DailyDiet> = try await api.get("/diet/days/\(date)")
        guard let day = response.data else {
            throw APIError.serverError(statusCode: 200, message: "하루 응답이 비어 있습니다")
        }
        return day
    }

    func upsertActivity(date: String, activeEnergyKcal: Int) async throws {
        try await api.putVoid("/diet/activity", body: ActivityUpsertRequest(date: date, activeEnergyKcal: activeEnergyKcal))
    }

    // MARK: - 식품·통계

    func searchFoods(query: String) async throws -> [Food] {
        let response: DataResponse<[Food]> = try await api.get("/diet/foods", query: ["q": query, "size": "20"])
        return response.data ?? []
    }

    func fetchFrequentItems() async throws -> [FrequentItem] {
        let response: DataResponse<[FrequentItem]> =
            try await api.get("/diet/items/frequent", query: ["days": "30", "size": "20"])
        return response.data ?? []
    }

    func fetchStats(from: String, to: String) async throws -> DietStats {
        let response: DataResponse<DietStats> =
            try await api.get("/diet/stats", query: ["from": from, "to": to])
        guard let stats = response.data else {
            throw APIError.serverError(statusCode: 200, message: "통계 응답이 비어 있습니다")
        }
        return stats
    }
}
```

- [ ] **Step 4: 등록하고 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietServiceTests 2>&1 | tail -30`
Expected: 6개 PASS

- [ ] **Step 5: 이후 태스크 전부가 쓸 테스트 대역을 만든다**

`WooriHaruTests/DietFakes.swift`:

```swift
import Foundation
@testable import WooriHaru

/// 호출을 기록하고 미리 넣어 둔 값을 돌려주는 식단 서비스 대역.
/// **응답을 배열로 넣으면 부를 때마다 다음 것을 준다** — 폴링 전이(PENDING → COMPLETED)를 만드는 데 쓴다.
/// 마지막 값에 도달하면 그 값을 계속 돌려준다(폴링이 몇 번 돌지 테스트가 알 필요 없게).
final class FakeDietService: DietServing, @unchecked Sendable {
    enum FakeError: Error { case unstubbed(String) }

    private let lock = NSLock()

    // 응답
    var profile: NutritionProfile?
    var analyses: [MealAnalysis] = []
    var meals: [Meal] = []
    var days: [DailyDiet] = []
    var foods: [Food] = []
    var frequentItems: [FrequentItem] = []
    var stats: DietStats?
    var uploadFileIds: [Int] = []
    var createdAnalysisId = 100
    var confirmedMealId = 200

    // 던질 에러 — 키는 메서드 이름
    var errors: [String: Error] = [:]
    /// `retryAnalysis`가 첫 호출에만 던지게 한다(연타 테스트).
    var retryErrorOnce: Error?

    // 기록
    private(set) var uploadedByteCounts: [Int] = []
    private(set) var createdFileIds: [[Int]] = []
    private(set) var fetchedAnalysisIds: [Int] = []
    private(set) var retriedAnalysisIds: [Int] = []
    private(set) var confirmRequests: [MealConfirmRequest] = []
    private(set) var fetchedMealIds: [Int] = []
    private(set) var updatedItems: [(id: Int, items: [MealItemRequest])] = []
    private(set) var deletedMealIds: [Int] = []
    private(set) var fetchedDates: [String] = []
    private(set) var activityCalls: [(date: String, kcal: Int)] = []
    private(set) var searchQueries: [String] = []
    private(set) var frequentCallCount = 0
    private(set) var statsRanges: [(from: String, to: String)] = []
    private(set) var savedProfiles: [NutritionProfileRequest] = []
    private(set) var savedWeights: [Double] = []

    private var analysisCursor = 0
    private var mealCursor = 0
    private var dayCursor = 0

    private func next<T>(_ values: [T], cursor: inout Int, label: String) throws -> T {
        guard !values.isEmpty else { throw FakeError.unstubbed(label) }
        let value = values[min(cursor, values.count - 1)]
        cursor += 1
        return value
    }

    private func check(_ key: String) throws {
        if let error = errors[key] { throw error }
    }

    // MARK: - DietServing

    func fetchProfile() async throws -> NutritionProfile? {
        try check("fetchProfile")
        return profile
    }

    func saveProfile(_ request: NutritionProfileRequest) async throws {
        lock.lock(); savedProfiles.append(request); lock.unlock()
        try check("saveProfile")
    }

    func updateWeight(_ weightKg: Double) async throws {
        lock.lock(); savedWeights.append(weightKg); lock.unlock()
        try check("updateWeight")
    }

    func uploadPhoto(_ jpegData: Data) async throws -> Int {
        lock.lock()
        let index = uploadedByteCounts.count
        uploadedByteCounts.append(jpegData.count)
        lock.unlock()
        try check("uploadPhoto#\(index)")
        try check("uploadPhoto")
        guard index < uploadFileIds.count else { throw FakeError.unstubbed("uploadPhoto #\(index)") }
        return uploadFileIds[index]
    }

    func createAnalysis(fileIds: [Int]) async throws -> Int {
        lock.lock(); createdFileIds.append(fileIds); lock.unlock()
        try check("createAnalysis")
        return createdAnalysisId
    }

    func fetchAnalysis(id: Int) async throws -> MealAnalysis {
        lock.lock(); fetchedAnalysisIds.append(id); lock.unlock()
        try check("fetchAnalysis")
        lock.lock(); defer { lock.unlock() }
        return try next(analyses, cursor: &analysisCursor, label: "fetchAnalysis")
    }

    func retryAnalysis(id: Int) async throws {
        lock.lock(); retriedAnalysisIds.append(id); lock.unlock()
        if let once = retryErrorOnce {
            retryErrorOnce = nil
            throw once
        }
        try check("retryAnalysis")
    }

    func confirmMeal(_ request: MealConfirmRequest) async throws -> Int {
        lock.lock(); confirmRequests.append(request); lock.unlock()
        try check("confirmMeal")
        return confirmedMealId
    }

    func fetchMeal(id: Int) async throws -> Meal {
        lock.lock(); fetchedMealIds.append(id); lock.unlock()
        try check("fetchMeal")
        lock.lock(); defer { lock.unlock() }
        return try next(meals, cursor: &mealCursor, label: "fetchMeal")
    }

    func updateMealItems(id: Int, items: [MealItemRequest]) async throws {
        lock.lock(); updatedItems.append((id, items)); lock.unlock()
        try check("updateMealItems")
    }

    func deleteMeal(id: Int) async throws {
        lock.lock(); deletedMealIds.append(id); lock.unlock()
        try check("deleteMeal")
    }

    func fetchDay(date: String) async throws -> DailyDiet {
        lock.lock(); fetchedDates.append(date); lock.unlock()
        try check("fetchDay")
        lock.lock(); defer { lock.unlock() }
        return try next(days, cursor: &dayCursor, label: "fetchDay")
    }

    func upsertActivity(date: String, activeEnergyKcal: Int) async throws {
        lock.lock(); activityCalls.append((date, activeEnergyKcal)); lock.unlock()
        try check("upsertActivity")
    }

    func searchFoods(query: String) async throws -> [Food] {
        lock.lock(); searchQueries.append(query); lock.unlock()
        try check("searchFoods")
        return foods
    }

    func fetchFrequentItems() async throws -> [FrequentItem] {
        lock.lock(); frequentCallCount += 1; lock.unlock()
        try check("fetchFrequentItems")
        return frequentItems
    }

    func fetchStats(from: String, to: String) async throws -> DietStats {
        lock.lock(); statsRanges.append((from, to)); lock.unlock()
        try check("fetchStats")
        guard let stats else { throw FakeError.unstubbed("fetchStats") }
        return stats
    }
}

/// 하루 활동 에너지 대역.
final class FakeActiveEnergyFetcher: ActiveEnergyFetching, @unchecked Sendable {
    var kcal: Double = 2400
    var errorToThrow: Error?
    private(set) var requestedDates: [Date] = []

    func fetchActiveEnergy(on date: Date) async throws -> Double {
        requestedDates.append(date)
        if let errorToThrow { throw errorToThrow }
        return kcal
    }
}

// MARK: - 픽스처

func makeMealItem(
    id: Int = 1,
    name: String = "제육볶음",
    code: String? = "D000001",
    quantityG: Double = 250,
    kcal: Double = 375,
    carbs: Double = 30,
    protein: Double = 25,
    fat: Double = 17,
    sugar: Double = 7,
    sodium: Double = 1000,
    fiber: Double = 3,
    source: NutritionSource = .dbMatched
) -> MealItem {
    MealItem(
        id: id, foodName: name, foodCode: code, quantityG: quantityG, kcal: kcal,
        carbsG: carbs, proteinG: protein, fatG: fat,
        sugarG: sugar, sodiumMg: sodium, fiberG: fiber, source: source
    )
}

func makeMeal(
    id: Int = 1,
    date: String = "2026-07-29",
    mealType: MealType = .lunch,
    status: AnalysisStatus = .completed,
    score: Int? = 76,
    feedback: String? = "단백질이 조금 부족합니다.",
    photos: [MealPhoto] = [MealPhoto(fileId: 11, url: "https://example.com/1.jpg", sortOrder: 0)],
    items: [MealItem] = [makeMealItem()]
) -> Meal {
    Meal(
        id: id, date: date, mealType: mealType, status: status, score: score,
        scoreBasis: MealScoreBasis(standard: "2025 한국인 영양소 섭취기준(KDRIs) 에너지적정비율", macros: [
            MacroBasis(name: "탄수화물", percent: 75, rangeMin: 50, rangeMax: 65, status: .over, penalty: 20),
            MacroBasis(name: "단백질", percent: 8, rangeMin: 10, rangeMax: 20, status: .under, penalty: 4),
            MacroBasis(name: "지방", percent: 17, rangeMin: 15, rangeMax: 30, status: .inRange, penalty: 0)
        ]),
        totalKcal: items.reduce(0) { $0 + $1.kcal },
        carbsG: items.reduce(0) { $0 + $1.carbsG },
        proteinG: items.reduce(0) { $0 + $1.proteinG },
        fatG: items.reduce(0) { $0 + $1.fatG },
        sugarG: items.reduce(0) { $0 + $1.sugarG },
        sodiumMg: items.reduce(0) { $0 + $1.sodiumMg },
        fiberG: items.reduce(0) { $0 + $1.fiberG },
        feedback: feedback, weightKg: 70, targetKcal: 2509,
        photos: photos, items: items
    )
}

func makeDay(
    date: String = "2026-07-29",
    dayScore: Int? = 74,
    feedback: String? = "오늘은 나트륨이 많았습니다.",
    meals: [Meal] = [makeMeal()],
    nutrientLimits: [NutrientLimit] = [
        NutrientLimit(name: "나트륨", intake: 2850, unit: "mg", standardText: "2,300mg 이하", status: .warn),
        NutrientLimit(name: "식이섬유", intake: 14.8, unit: "g", standardText: "30g 이상", status: .warn),
        NutrientLimit(name: "당류", intake: 44.2, unit: "g", standardText: "125g 이하", status: .ok)
    ],
    estimatedItemCount: Int = 0,
    activeEnergyKcal: Int? = 2400
) -> DailyDiet {
    DailyDiet(
        date: date, dayScore: dayScore,
        scoreBasis: DayScoreBasis(
            standard: "자체 기준(칼로리 40% + 매크로 60%)",
            calorie: CalorieBasis(intakeKcal: 1980, targetKcal: 2509, ratio: 0.789, calorieScore: 78),
            macros: [
                MacroAmountBasis(name: "탄수화물", intakeG: 250.1, targetG: 345, ratio: 0.72, score: 72),
                MacroAmountBasis(name: "단백질", intakeG: 78.4, targetG: 94, ratio: 0.83, score: 83),
                MacroAmountBasis(name: "지방", intakeG: 62, targetG: 84, ratio: 0.74, score: 74)
            ],
            calorieWeight: 0.4, macroWeight: 0.6
        ),
        feedback: feedback, totalKcal: 1980, carbsG: 250.1, proteinG: 78.4, fatG: 62,
        activeEnergyKcal: activeEnergyKcal, meals: meals,
        nutrientLimits: nutrientLimits, estimatedItemCount: estimatedItemCount
    )
}

func makeProfile(weightKg: Double = 70) -> NutritionProfile {
    NutritionProfile(
        heightCm: 175, weightKg: weightKg, activityLevel: .moderate, goal: .maintain,
        targetKcal: 2509, targetCarbsG: 345, targetProteinG: 94, targetFatG: 84,
        targetSugarG: 125, targetSodiumMg: 2300, targetFiberG: 30
    )
}

func makeAnalysis(
    id: Int = 100,
    status: AnalysisStatus = .completed,
    photos: [AnalyzedPhoto] = [
        AnalyzedPhoto(fileId: 11, url: "https://example.com/1.jpg", failed: false, items: [
            AnalyzedItem(
                foodName: "제육볶음", foodCode: "D000001", quantityG: 250, kcal: 375,
                carbsG: 30, proteinG: 25, fatG: 17, sugarG: 7, sodiumMg: 1000, fiberG: 3,
                source: .dbMatched
            )
        ])
    ]
) -> MealAnalysis {
    MealAnalysis(id: id, status: status, photos: photos)
}

func dietServerError(_ code: String, status: Int = 400) -> Error {
    APIError.serverError(
        statusCode: status,
        message: #"{"status":\#(status),"message":"...","code":"\#(status)","error":"\#(code)"}"#
    )
}
```

> `FakeActiveEnergyFetcher`가 참조하는 `ActiveEnergyFetching`은 **Task 4에서 이미 만들어져 있다**
> (실행 순서가 Task 4 → Task 3이다 — 「실행 순서」 참조).

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Services/DietService.swift WooriHaruTests/DietFakes.swift \
        WooriHaruTests/DietTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 식단 API 서비스를 만든다"
```

---

## Task 4: 하루 활동 에너지 (HealthKit)

`DietHomeView`가 진입할 때마다 그날 소모 칼로리를 올린다. **추가 권한 요청이 필요 없다** —
`activeEnergyBurned` 읽기 권한이 이미 `readTypes`에 있다(수영 소모 칼로리용).

> **Task 3보다 먼저 실행한다.** Task 3의 `DietFakes.swift`가 `ActiveEnergyFetching`을 채택하는
> 대역을 담고 있어, 순서를 뒤집으면 그 대역을 지웠다 되살리는 군더더기가 생긴다.

**Files:**
- Modify: `WooriHaru/Services/HealthKitService.swift`

**Interfaces:**
- Produces: `protocol ActiveEnergyFetching { func fetchActiveEnergy(on date: Date) async throws -> Double }`, `HealthKitService: ActiveEnergyFetching`

- [ ] **Step 1: 프로토콜과 구현을 넣는다**

`WooriHaru/Services/HealthKitService.swift` — `SwimWorkoutFetching` 프로토콜 선언 아래(36행 뒤)에 추가한다:

```swift
/// 하루 활동 에너지 조회. 서버가 **하루 마감 피드백** 프롬프트의 맥락으로 쓴다.
/// 목표 칼로리에는 반영하지 않는다 — 활동량에 따라 목표가 매일 흔들리면 점수를 설명할 수 없다.
protocol ActiveEnergyFetching: Sendable {
    /// 그날 0시~24시의 `activeEnergyBurned` 합계(kcal). 데이터가 없으면 0.
    func fetchActiveEnergy(on date: Date) async throws -> Double
}
```

`final class HealthKitService: SwimWorkoutFetching {` 선언을 다음으로 바꾼다:

```swift
final class HealthKitService: SwimWorkoutFetching, ActiveEnergyFetching {
```

`fetchEffortScore` 아래(139행 뒤)에 구현을 넣는다:

```swift
    func fetchActiveEnergy(on date: Date) async throws -> Double {
        guard isHealthDataAvailable else { throw SwimWorkoutError.healthDataUnavailable }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        // 워크아웃마다 합산하지 않고 HKStatisticsQuery로 한 번에 구한다 — 걷기처럼 운동으로
        // 기록되지 않은 소모도 포함해야 "오늘 얼마나 썼는지"가 맞는다.
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.activeEnergyBurned),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                }
            }
            store.execute(query)
        }
    }
```

- [ ] **Step 2: 빌드를 확인한다**

이 태스크에는 새 단위 테스트가 없다 — `HKStatisticsQuery`는 실기기·시뮬레이터의 건강 데이터에
의존해 목으로 대체할 수 없고, 프로토콜을 소비하는 쪽(`DietDayViewModel`)의 테스트가 Task 6에
있다. 여기서는 프로토콜 채택이 컴파일되는지만 확인한다.

Run: `xcodebuild build -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Services/HealthKitService.swift
git commit -m "feat: 하루 활동 에너지 조회를 붙인다"
```

---

## Task 5: 프로필 — 목표가 없으면 점수가 없다

프로필이 먼저다. 목표가 없으면 서버가 확정을 `PROFILE_NOT_FOUND`로 거절하므로, 업로드를 허용해도 결과가 비어 있게 된다.

**Files:**
- Create: `WooriHaru/ViewModels/NutritionProfileViewModel.swift`, `WooriHaru/Views/Diet/NutritionProfileView.swift`
- Test: `WooriHaruTests/DietDayTests.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10011`/`DT20011` `NutritionProfileViewModel.swift`(그룹 `B40003`), `DT10012`/`DT20012` `NutritionProfileView.swift`(그룹 `DT40001` — Task 7에서 만드는 `Views/Diet` 그룹. **이 태스크에서 먼저 만든다**)

`Views/Diet` 그룹을 여기서 만든다 — `/* End PBXGroup section */` 앞에 넣고 `B40004 /* Views */`의 children에 `DT40001 /* Diet */,`를 추가한다:

```
		DT40001 /* Diet */ = {
			isa = PBXGroup;
			children = (
				DT20012 /* NutritionProfileView.swift */,
			);
			path = Diet;
			sourceTree = "<group>";
		};
```

**Interfaces:**
- Consumes: `DietServing`, `NutritionProfile`·`NutritionProfileRequest`
- Produces: `NutritionProfileViewModel(service:)` — `profile`·`heightText`·`weightText`·`activityLevel`·`goal`·`isSaving`·`canSave`·`didSave`·`errorMessage`·`load()`·`save()`, `NutritionProfileView(onSaved:)`

- [ ] **Step 1: 저장 테스트를 쓴다**

`WooriHaruTests/DietDayTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct NutritionProfileViewModelTests {
    @Test func 기존_프로필을_읽어_입력란을_채운다() async {
        let service = FakeDietService()
        service.profile = makeProfile(weightKg: 68.5)
        let vm = NutritionProfileViewModel(service: service)

        await vm.load()

        #expect(vm.heightText == "175")
        #expect(vm.weightText == "68.5")
        #expect(vm.activityLevel == .moderate)
        #expect(vm.goal == .maintain)
        #expect(vm.profile?.targetKcal == 2509)
    }

    @Test func 프로필이_없어도_오류가_아니다() async {
        let service = FakeDietService()
        service.profile = nil
        let vm = NutritionProfileViewModel(service: service)

        await vm.load()

        #expect(vm.profile == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func 저장하면_서버가_계산한_목표를_다시_읽어_보여준다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        let vm = NutritionProfileViewModel(service: service)
        vm.heightText = "175"
        vm.weightText = "70"
        vm.activityLevel = .active
        vm.goal = .lose

        await vm.save()

        #expect(service.savedProfiles.count == 1)
        #expect(service.savedProfiles.first?.heightCm == 175)
        #expect(service.savedProfiles.first?.weightKg == 70)
        #expect(service.savedProfiles.first?.activityLevel == .active)
        #expect(service.savedProfiles.first?.goal == .lose)
        #expect(vm.didSave)
        #expect(vm.profile?.targetKcal == 2509)
    }

    @Test func 키나_몸무게가_비면_저장할_수_없다() {
        let vm = NutritionProfileViewModel(service: FakeDietService())

        vm.heightText = ""
        vm.weightText = "70"
        #expect(!vm.canSave)

        vm.heightText = "175"
        vm.weightText = "abc"
        #expect(!vm.canSave)

        vm.weightText = "70"
        #expect(vm.canSave)
    }

    /// 성별·생년월일이 없으면 서버가 `INVALID_REQUEST`로 거절한다 — 「내 정보」로 안내해야 한다.
    @Test func 성별_생년월일이_없으면_내_정보로_안내한다() async {
        let service = FakeDietService()
        service.errors["saveProfile"] = dietServerError("INVALID_REQUEST")
        let vm = NutritionProfileViewModel(service: service)
        vm.heightText = "175"
        vm.weightText = "70"

        await vm.save()

        #expect(!vm.didSave)
        #expect(vm.needsUserInfo)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/NutritionProfileViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'NutritionProfileViewModel' in scope`

- [ ] **Step 3: ViewModel을 만든다**

`WooriHaru/ViewModels/NutritionProfileViewModel.swift`:

```swift
import Foundation

/// 키·몸무게·활동량·목표 입력. **목표치는 서버가 계산해 돌려준다** — 앱은 표시만 한다.
/// 성별·생년월일은 기존 `User` 값을 쓰므로 여기서 입력하지 않는다.
@MainActor
@Observable
final class NutritionProfileViewModel {
    private(set) var profile: NutritionProfile?
    var heightText = ""
    var weightText = ""
    var activityLevel: ActivityLevel = .moderate
    var goal: DietGoal = .maintain

    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var didSave = false
    /// 서버가 성별·생년월일 결측으로 거절했을 때. 「내 정보」로 보내야 한다.
    private(set) var needsUserInfo = false
    var errorMessage: String?

    private let service: any DietServing

    init(service: any DietServing = DietService()) {
        self.service = service
    }

    var canSave: Bool {
        guard let height = Double(heightText), let weight = Double(weightText) else { return false }
        return height > 0 && weight > 0 && !isSaving
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await service.fetchProfile()
            profile = loaded
            if let loaded {
                heightText = Self.text(loaded.heightCm)
                weightText = Self.text(loaded.weightKg)
                activityLevel = loaded.activityLevel
                goal = loaded.goal
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        guard let height = Double(heightText), let weight = Double(weightText), !isSaving else { return }
        isSaving = true
        didSave = false
        needsUserInfo = false
        defer { isSaving = false }

        do {
            try await service.saveProfile(NutritionProfileRequest(
                heightCm: height, weightKg: weight, activityLevel: activityLevel, goal: goal
            ))
            // 목표는 서버가 계산하므로 저장 뒤 다시 읽어야 화면에 새 목표가 보인다.
            profile = try await service.fetchProfile()
            didSave = true
        } catch is CancellationError {
            return
        } catch {
            // 성별·생년월일 중 하나라도 없으면 BMR을 계산할 수 없어 서버가 거절한다.
            if error.dietErrorCode == .invalidRequest {
                needsUserInfo = true
                errorMessage = "성별과 생년월일이 있어야 목표를 계산할 수 있습니다. 「내 정보」에서 먼저 입력해 주세요."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 175.0 → "175", 68.5 → "68.5"
    private static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/NutritionProfileViewModelTests 2>&1 | tail -30`
Expected: 5개 PASS

- [ ] **Step 5: 화면을 만든다**

`WooriHaru/Views/Diet/NutritionProfileView.swift`:

```swift
import SwiftUI

/// 키·몸무게·활동량·목표를 입력하고 서버가 계산한 목표 섭취량을 확인한다.
/// 체중은 수동 입력이다 — HealthKit에서 자동으로 가져오지 않는다.
struct NutritionProfileView: View {
    @State private var vm = NutritionProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    /// 저장이 끝났을 때 호출. 하루 화면이 목표를 다시 읽는 데 쓴다.
    var onSaved: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                inputCard
                activityCard
                goalCard
                if let profile = vm.profile { targetCard(profile) }
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle("식단 프로필")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var inputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("몸")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                HStack(spacing: 12) {
                    labeledField("키", unit: "cm", text: $vm.heightText)
                    labeledField("몸무게", unit: "kg", text: $vm.weightText)
                }

                Text("성별·생년월일은 「내 정보」 값을 씁니다.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private func labeledField(_ label: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            HStack(spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.body.weight(.medium))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassInputField()
        }
    }

    private var activityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("활동량")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                ForEach(ActivityLevel.allCases) { level in
                    Button {
                        vm.activityLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.label)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.slate700)
                                Text(level.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Color.slate400)
                            }
                            Spacer()
                            if vm.activityLevel == level {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.blue500)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var goalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                Picker("목표", selection: $vm.goal) {
                    ForEach(DietGoal.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func targetCard(_ profile: NutritionProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("하루 목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                targetRow("칼로리", "\(profile.targetKcal)kcal")
                targetRow("탄수화물", "\(profile.targetCarbsG)g")
                targetRow("단백질", "\(profile.targetProteinG)g")
                targetRow("지방", "\(profile.targetFatG)g")

                Divider()

                targetRow("당류", "\(profile.targetSugarG)g 이하")
                targetRow("나트륨", "\(profile.targetSodiumMg)mg 이하")
                targetRow("식이섬유", "\(profile.targetFiberG)g 이상")

                Text("2025 한국인 영양소 섭취기준(KDRIs)을 바탕으로 서버가 계산합니다.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private func targetRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate700)
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                await vm.save()
                if vm.didSave {
                    onSaved?()
                    dismiss()
                }
            }
        } label: {
            HStack {
                if vm.isSaving { ProgressView().tint(.white) }
                Text("저장")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .appGlassProminentButton()
        .disabled(!vm.canSave)
    }
}
```

- [ ] **Step 6: 등록하고 빌드를 확인한다**

`Views/Diet` 그룹(`DT40001`)을 만들고 두 파일을 등록한다.

Run: `xcodebuild build -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/ViewModels/NutritionProfileViewModel.swift WooriHaru/Views/Diet/NutritionProfileView.swift \
        WooriHaruTests/DietDayTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 식단 프로필 입력 화면을 만든다"
```

---

## Task 6: `DietDayViewModel` — 하루 요약과 피드백 폴링

폴링 셋 중 하나가 여기 있다. **하루 피드백은 화면을 붙잡지 않고, 실패해도 재시도 버튼을 두지 않는다** — 서버가 끼니가 바뀔 때까지 다시 부르지 않으므로 "잠시 후 다시 확인해 주세요" 수준의 안내만 한다.

**Files:**
- Create: `WooriHaru/ViewModels/DietDayViewModel.swift`
- Test: `WooriHaruTests/DietDayTests.swift` (추가)
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10013`/`DT20013`, 그룹 `B40003`

**Interfaces:**
- Consumes: `DietServing`, `ActiveEnergyFetching`, `DailyDiet`, `NutritionProfile`
- Produces: `DietDayViewModel(service:energyFetcher:pollInterval:pollTimeout:)` — `selectedDate`·`day`·`profile`·`weekDates`·`isLoading`·`hasLoaded`·`needsProfile`·`isFeedbackPending`·`isFeedbackDelayed`·`errorMessage`·`load()`·`select(_:)`·`reload()`·`syncActivity()`·`updateWeight(_:)`

- [ ] **Step 1: 테스트를 쓴다**

`WooriHaruTests/DietDayTests.swift` 끝에 붙인다:

```swift
@MainActor
struct DietDayViewModelTests {
    private func makeVM(_ service: FakeDietService, energy: FakeActiveEnergyFetcher = .init()) -> DietDayViewModel {
        DietDayViewModel(
            service: service,
            energyFetcher: energy,
            pollInterval: .milliseconds(1),
            pollTimeout: .milliseconds(30)
        )
    }

    @Test func 하루_요약을_읽는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.day?.dayScore == 74)
        #expect(vm.day?.meals.count == 1)
        #expect(vm.profile?.targetKcal == 2509)
        #expect(!vm.needsProfile)
        #expect(vm.hasLoaded)
    }

    /// 목표가 없으면 점수를 낼 수 없으므로 프로필을 먼저 띄운다.
    @Test func 프로필이_없으면_프로필_화면을_먼저_띄운다() async {
        let service = FakeDietService()
        service.profile = nil
        service.days = [makeDay(dayScore: nil, feedback: nil, meals: [])]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.needsProfile)
    }

    /// **화면을 붙잡지 않는다** — 점수와 끼니는 이미 보이고 피드백 영역만 로딩이다.
    @Test func 피드백이_null이면_화면을_붙잡지_않고_뒤에서_채운다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(feedback: nil), makeDay(feedback: nil), makeDay(feedback: "다 채웠습니다.")]
        let vm = makeVM(service)

        await vm.load()
        // 첫 응답 시점에 점수는 이미 있고 피드백만 비어 있다.
        #expect(vm.day?.dayScore == 74)
        #expect(vm.isFeedbackPending)

        await vm.waitForFeedbackPolling()

        #expect(vm.day?.feedback == "다 채웠습니다.")
        #expect(!vm.isFeedbackPending)
        #expect(!vm.isFeedbackDelayed)
    }

    /// 타임아웃은 실패가 아니다. **재시도 버튼을 두지 않는다.**
    @Test func 피드백이_안_오면_지연으로_두고_재시도_버튼을_두지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(feedback: nil)]
        let vm = makeVM(service)

        await vm.load()
        await vm.waitForFeedbackPolling()

        #expect(vm.day?.feedback == nil)
        #expect(vm.isFeedbackDelayed)
        #expect(!vm.isFeedbackPending)
    }

    /// 끼니가 없는 날은 서버가 피드백을 만들지 않으므로 폴링하지 않는다.
    @Test func 끼니가_없으면_폴링하지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(dayScore: nil, feedback: nil, meals: [])]
        let vm = makeVM(service)

        await vm.load()
        await vm.waitForFeedbackPolling()

        #expect(!vm.isFeedbackPending)
        #expect(!vm.isFeedbackDelayed)
        #expect(service.fetchedDates.count == 1)
    }

    /// 날짜를 바꾸면 이전 날짜의 늦은 응답을 버린다.
    @Test func 날짜를_바꾸면_이전_응답을_버린다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(date: "2026-07-29"), makeDay(date: "2026-07-28", dayScore: 55)]
        let vm = makeVM(service)

        await vm.load()
        await vm.select(Date.from("2026-07-28")!)

        #expect(vm.day?.date == "2026-07-28")
        #expect(vm.day?.dayScore == 55)
        #expect(service.fetchedDates.contains("2026-07-28"))
    }

    /// 진입할 때마다 편하게 올려도 된다 — 서버가 이 값으로 피드백을 재생성하지 않는다.
    @Test func 활동_에너지를_올린다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let energy = FakeActiveEnergyFetcher()
        energy.kcal = 2412.6
        let vm = makeVM(service, energy: energy)

        await vm.load()
        await vm.syncActivity()

        #expect(service.activityCalls.count == 1)
        #expect(service.activityCalls.first?.kcal == 2413)
    }

    /// HealthKit이 없는 기기에서도 하루 화면은 정상이어야 한다.
    @Test func 활동_에너지_실패는_화면을_막지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay()]
        let energy = FakeActiveEnergyFetcher()
        energy.errorToThrow = SwimWorkoutError.healthDataUnavailable
        let vm = makeVM(service, energy: energy)

        await vm.load()
        await vm.syncActivity()

        #expect(vm.errorMessage == nil)
        #expect(service.activityCalls.isEmpty)
    }

    /// 몸무게만 고치고 목표를 다시 읽는다. **과거 점수는 바뀌지 않는다**(서버가 스냅샷을 남긴다).
    @Test func 몸무게를_고치면_목표를_다시_읽는다() async {
        let service = FakeDietService()
        service.profile = makeProfile(weightKg: 70)
        service.days = [makeDay(), makeDay()]
        let vm = makeVM(service)
        await vm.load()

        service.profile = makeProfile(weightKg: 68)
        await vm.updateWeight(68)

        #expect(service.savedWeights == [68])
        #expect(vm.profile?.weightKg == 68)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietDayViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'DietDayViewModel' in scope`

- [ ] **Step 3: ViewModel을 만든다**

`WooriHaru/ViewModels/DietDayViewModel.swift`:

```swift
import Foundation

/// 날짜별 하루 요약·끼니 목록·마감 피드백 폴링.
///
/// **피드백 폴링은 화면을 붙잡지 않는다.** 조회는 즉시 돌아오고 `feedback`이 `null`이면 서버가
/// 뒤에서 만들고 있다는 뜻이라 그 영역만 로딩으로 두었다가 채운다. **실패해도 재시도 버튼을
/// 두지 않는다** — 서버가 끼니가 바뀔 때까지 다시 부르지 않으므로(비용 방어) 사용자가 끼니를
/// 추가·수정하면 자연히 다시 만들어진다.
@MainActor
@Observable
final class DietDayViewModel {
    private(set) var selectedDate: Date
    private(set) var day: DailyDiet?
    private(set) var profile: NutritionProfile?

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// 프로필이 없어 점수를 낼 수 없는 상태. 업로드보다 프로필 입력이 먼저다.
    private(set) var needsProfile = false
    private(set) var isFeedbackPending = false
    /// 60초 안에 안 왔다. **실패가 아니다** — 서버는 계속 처리 중일 수 있다.
    private(set) var isFeedbackDelayed = false
    var errorMessage: String?

    /// 진행 중인 조회·폴링을 무효화하는 표식. 날짜를 바꾸거나 새로고침이 끼어들면 값을 올려
    /// 뒤늦게 돌아온 이전 결과를 버린다.
    private var generation = 0
    private var feedbackTask: Task<Void, Never>?

    private let service: any DietServing
    private let energyFetcher: any ActiveEnergyFetching
    private let pollInterval: Duration
    private let pollTimeout: Duration

    init(
        service: any DietServing = DietService(),
        energyFetcher: any ActiveEnergyFetching = HealthKitService(),
        date: Date = Date(),
        pollInterval: Duration = DietPolicy.pollInterval,
        pollTimeout: Duration = DietPolicy.pollTimeout
    ) {
        self.service = service
        self.energyFetcher = energyFetcher
        self.selectedDate = date
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    /// 선택 날짜가 든 주(일~토).
    var weekDates: [Date] {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return [selectedDate] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var dateString: String { selectedDate.dateString }

    /// 서버가 `mealType` 순으로 정렬해 주므로 **앱이 다시 정렬하지 않는다.**
    var meals: [Meal] { day?.meals ?? [] }

    var estimatedNoticeText: String? {
        guard let count = day?.estimatedItemCount, count > 0 else { return nil }
        return "추정 \(count)건 포함"
    }

    // MARK: - Load

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        errorMessage = nil
        feedbackTask?.cancel()
        isFeedbackDelayed = false

        do {
            async let profileResult = service.fetchProfile()
            async let dayResult = service.fetchDay(date: selectedDate.dateString)
            let (loadedProfile, loadedDay) = try await (profileResult, dayResult)
            guard token == generation else { return }

            profile = loadedProfile
            needsProfile = loadedProfile == nil
            day = loadedDay
            startFeedbackPollingIfNeeded(token: token)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
        }
        guard token == generation else { return }
        hasLoaded = true
        isLoading = false
    }

    func select(_ date: Date) async {
        guard !Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return }
        selectedDate = date
        await load()
    }

    /// 끼니를 저장·수정·삭제한 뒤. 점수·합계·`nutrientLimits`가 전부 달라지고 피드백은 다시 생성에 걸린다.
    func reload() async {
        await load()
    }

    // MARK: - 피드백 폴링

    private func startFeedbackPollingIfNeeded(token: Int) {
        // 끼니가 0건인 날은 서버가 피드백을 만들지 않는다 — 폴링하면 영원히 기다린다.
        guard let day, day.feedback == nil, !day.meals.isEmpty else {
            isFeedbackPending = false
            return
        }
        isFeedbackPending = true

        feedbackTask = Task { [weak self] in
            guard let self else { return }
            await self.pollFeedback(token: token)
        }
    }

    private func pollFeedback(token: Int) async {
        let deadline = ContinuousClock.now + pollTimeout

        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
                let refreshed = try await service.fetchDay(date: selectedDate.dateString)
                guard token == generation else { return }

                if refreshed.feedback != nil {
                    day = refreshed
                    isFeedbackPending = false
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                // 폴링 중 실패는 알리지 않는다 — 점수는 이미 보이고 있고 다음 회차가 있다.
                continue
            }
        }

        guard token == generation else { return }
        isFeedbackPending = false
        isFeedbackDelayed = true
    }

    /// 테스트에서 폴링이 끝나기를 기다린다.
    func waitForFeedbackPolling() async {
        await feedbackTask?.value
    }

    // MARK: - 활동 에너지

    /// 진입할 때마다 올린다. **서버가 이 값으로 마감 피드백을 재생성하지 않으므로 비용이 늘지 않는다.**
    /// 목표 칼로리에는 반영되지 않고 표시·피드백 맥락으로만 쓰인다.
    func syncActivity() async {
        do {
            let kcal = try await energyFetcher.fetchActiveEnergy(on: selectedDate)
            try await service.upsertActivity(
                date: selectedDate.dateString,
                activeEnergyKcal: Int(kcal.rounded())
            )
        } catch {
            // HealthKit을 못 쓰는 기기이거나 권한이 없을 수 있다. 하루 화면은 이것 없이도 정상이다.
            return
        }
    }

    // MARK: - 몸무게

    /// 몸무게만 갱신한다. **과거 점수는 바뀌지 않는다** — 서버가 확정 시점의 몸무게·목표를
    /// 끼니에 스냅샷으로 남기고, 하루 점수는 그날 첫 끼니의 스냅샷을 기준으로 계산한다.
    func updateWeight(_ weightKg: Double) async {
        do {
            try await service.updateWeight(weightKg)
            profile = try await service.fetchProfile()
            needsProfile = profile == nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietDayViewModelTests 2>&1 | tail -30`
Expected: 9개 PASS

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/DietDayViewModel.swift WooriHaruTests/DietDayTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 하루 요약과 마감 피드백 폴링을 만든다"
```

---

## Task 7: 하루 화면 — 앱에서 식단이 열린다

이 태스크가 끝나면 드로어에서 「식단」을 눌러 하루 요약을 볼 수 있다. 점수 근거·주의 영양소·추정 표시가 여기서 처음 화면에 나온다.

**Files:**
- Create: `Views/Diet/Components/DietScoreRing.swift`, `MacroBar.swift`, `ScoreBasisCard.swift`, `NutrientLimitRow.swift`
- Create: `Views/Diet/DietHomeView.swift`
- Modify: `WooriHaru/ContentView.swift`, `WooriHaru/Views/Components/SideDrawerView.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10014`/`DT20014` `DietScoreRing.swift`, `DT10015`/`DT20015` `MacroBar.swift`, `DT10016`/`DT20016` `ScoreBasisCard.swift`, `DT10017`/`DT20017` `NutrientLimitRow.swift` (전부 새 그룹 `DT40002` — `Views/Diet/Components`), `DT10018`/`DT20018` `DietHomeView.swift`(그룹 `DT40001`)

`DT40002` 그룹을 만들고 `DT40001 /* Diet */`의 children 맨 앞에 `DT40002 /* Components */,`를 넣는다:

```
		DT40002 /* Components */ = {
			isa = PBXGroup;
			children = (
				DT20014 /* DietScoreRing.swift */,
				DT20015 /* MacroBar.swift */,
				DT20016 /* ScoreBasisCard.swift */,
				DT20017 /* NutrientLimitRow.swift */,
			);
			path = Components;
			sourceTree = "<group>";
		};
```

**Interfaces:**
- Consumes: `DietDayViewModel`, `MealScoreBasis`·`DayScoreBasis`·`NutrientLimit`
- Produces: `DietScoreRing(score:size:)`, `MacroBar(name:intakeG:targetG:tint:)`, `ScoreBasisCard(title:score:basis:)`(끼니용) / `ScoreBasisCard(title:score:dayBasis:)`(하루용), `NutrientLimitRow(limit:)`, `DietHomeView()`, `AppDestination.diet`

- [ ] **Step 1: 목표 대비 비율 테스트를 쓴다**

`WooriHaruTests/DietTests.swift` 끝에 붙인다:

```swift
struct MacroBarTests {
    /// 목표가 0이면 0으로 나누지 않는다 — 프로필 저장 전에도 화면이 그려져야 한다.
    @Test func 목표가_0이면_비율이_0이다() {
        #expect(MacroBar.ratio(intakeG: 50, targetG: 0) == 0)
        #expect(MacroBar.ratio(intakeG: 0, targetG: 0) == 0)
    }

    @Test func 비율은_목표_대비값이고_초과해도_잘리지_않는다() {
        #expect(MacroBar.ratio(intakeG: 50, targetG: 100) == 0.5)
        #expect(MacroBar.ratio(intakeG: 120, targetG: 100) == 1.2)
    }

    /// 막대 길이는 넘쳐도 화면 밖으로 나가지 않게 1로 자른다(비율 표시는 자르지 않는다).
    @Test func 막대_길이는_1을_넘지_않는다() {
        #expect(MacroBar.fill(intakeG: 120, targetG: 100) == 1.0)
        #expect(MacroBar.fill(intakeG: 50, targetG: 100) == 0.5)
    }
}

@MainActor
struct DietDisplayTests {
    /// **0이면 아무것도 그리지 않는다** — 항목 단위 「추정」 배지와 달리 여기서는 없음이 기본이다.
    @Test func 추정_건수는_0이면_표시하지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(estimatedItemCount: 0)]
        let vm = DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher())
        await vm.load()

        #expect(vm.estimatedNoticeText == nil)
    }

    @Test func 추정_건수가_있으면_몇_건인지_보여준다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(estimatedItemCount: 2)]
        let vm = DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher())
        await vm.load()

        #expect(vm.estimatedNoticeText == "추정 2건 포함")
    }

    /// **앱이 판정을 다시 하지 않는다** — 섭취량이 기준을 넘어도 서버가 `OK`라고 하면 `OK`다.
    /// 기준 문구도 서버 값을 그대로 쓴다.
    @Test func 주의_영양소는_서버_판정을_그대로_쓴다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(nutrientLimits: [
            NutrientLimit(name: "나트륨", intake: 9999, unit: "mg", standardText: "2,300mg 이하", status: .ok)
        ])]
        let vm = DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher())
        await vm.load()

        let limit = try! #require(vm.day?.nutrientLimits.first)
        #expect(limit.status == .ok)
        #expect(limit.standardText == "2,300mg 이하")
    }

    /// 점수 근거도 마찬가지다 — 앱이 `percent`와 범위로 재판정하지 않는다.
    @Test func 점수_근거는_서버_status와_penalty를_그대로_쓴다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = MealDetailViewModel(mealId: 1, service: service)
        await vm.load()

        let macros = try! #require(vm.meal?.scoreBasis?.macros)
        #expect(macros[0].status == .over)
        #expect(macros[0].penalty == 20)
        #expect(macros[2].status == .inRange)
        #expect(macros[2].penalty == 0)
        #expect(vm.meal?.scoreBasis?.standard == "2025 한국인 영양소 섭취기준(KDRIs) 에너지적정비율")
    }
}
```

> 마지막 테스트(`점수_근거는_서버_status와_penalty를_그대로_쓴다`)만 Task 11의 `MealDetailViewModel`을
> 참조한다. **Task 7 시점에는 그 하나를 빼고 커밋하고, Task 11 Step 7에서 되살린다.**

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MacroBarTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'MacroBar' in scope`

- [ ] **Step 3: 컴포넌트 4개를 만든다**

`WooriHaru/Views/Diet/Components/DietScoreRing.swift`:

```swift
import SwiftUI

/// 점수 링. `score`가 nil이면(물·커피처럼 매크로가 0인 끼니) 「–」를 그린다.
struct DietScoreRing: View {
    let score: Int?
    var size: CGFloat = 96
    var caption: String?

    private var progress: Double { Double(score ?? 0) / 100.0 }

    private var tint: Color {
        guard let score else { return .slate300 }
        switch score {
        case 80...: return .green600
        case 60..<80: return .blue500
        default: return .orange400
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.slate200, lineWidth: size * 0.09)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)

            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                if let caption {
                    Text(caption)
                        .font(.system(size: size * 0.11))
                        .foregroundStyle(Color.slate400)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(score.map { "점수 \($0)점" } ?? "점수 없음")
    }
}
```

`WooriHaru/Views/Diet/Components/MacroBar.swift`:

```swift
import SwiftUI

/// 목표 대비 탄단지 막대.
struct MacroBar: View {
    let name: String
    let intakeG: Double
    let targetG: Int
    var tint: Color = .blue500

    /// 목표가 0이면 0으로 나누지 않는다.
    static func ratio(intakeG: Double, targetG: Int) -> Double {
        guard targetG > 0 else { return 0 }
        return intakeG / Double(targetG)
    }

    /// 막대 길이는 1을 넘지 않는다. 비율 자체(`ratio`)는 자르지 않는다.
    static func fill(intakeG: Double, targetG: Int) -> Double {
        min(1.0, ratio(intakeG: intakeG, targetG: targetG))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                Text("\(Int(intakeG.rounded()))g / \(targetG)g")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.slate700)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.slate200)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * Self.fill(intakeG: intakeG, targetG: targetG))
                }
            }
            .frame(height: 6)
        }
    }
}
```

`WooriHaru/Views/Diet/Components/ScoreBasisCard.swift`:

```swift
import SwiftUI

/// 점수의 근거를 보여준다. **앱은 계산하지 않는다** — 서버가 준 `status`·`penalty`·`standard`를
/// 그대로 쓴다. 앱이 비율과 범위만 받아 직접 판정하면 감점 규칙이 두 곳에 생기고, 서버가
/// 기울기를 바꿨을 때 화면의 설명과 실제 점수가 어긋난다.
struct ScoreBasisCard: View {
    let title: String
    let score: Int?
    /// 끼니 근거(매크로 비율). 하루 카드에서는 nil이다.
    var basis: MealScoreBasis?
    /// 하루 점수에는 칼로리 항목과 매크로 g 목표가 붙는다. 끼니 카드에서는 nil이다.
    var dayBasis: DayScoreBasis?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Spacer()
                    Text(score.map { "\($0)점" } ?? "점수 없음")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.slate900)
                }

                Text(standardText)
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)

                if let calorie = dayBasis?.calorie {
                    calorieRow(calorie)
                    Divider()
                }

                ForEach(basis?.macros ?? []) { macro in
                    macroRow(macro)
                }

                ForEach(dayBasis?.macros ?? []) { macro in
                    MacroBar(name: macro.name, intakeG: macro.intakeG, targetG: macro.targetG)
                }
            }
        }
    }

    private var standardText: String {
        dayBasis?.standard ?? basis?.standard ?? ""
    }

    private func calorieRow(_ calorie: CalorieBasis) -> some View {
        HStack {
            Text("칼로리")
                .font(.caption)
                .foregroundStyle(Color.slate500)
            Spacer()
            Text("\(Int(calorie.intakeKcal.rounded()))kcal / \(calorie.targetKcal)kcal")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate700)
            Text("\(Int((calorie.ratio * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(Color.slate400)
        }
    }

    /// `status`와 `penalty`는 서버 값이다. 앱은 색과 문구만 고른다.
    private func macroRow(_ macro: MacroBasis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(macro.name)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                Text("\(Int(macro.percent.rounded()))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.slate700)
                Text("권장 \(macro.rangeMin)~\(macro.rangeMax)%")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }

            HStack(spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.slate200)
                        Capsule()
                            .fill(tint(for: macro.status))
                            .frame(width: geometry.size.width * min(1.0, macro.percent / 100.0))
                    }
                }
                .frame(height: 6)

                Text(statusText(macro))
                    .font(.caption2)
                    .foregroundStyle(tint(for: macro.status))
                    .frame(width: 76, alignment: .trailing)
            }
        }
    }

    private func tint(for status: MacroStatus) -> Color {
        switch status {
        case .inRange: .green600
        case .over: .orange400
        case .under: .blue400
        }
    }

    private func statusText(_ macro: MacroBasis) -> String {
        switch macro.status {
        case .inRange: "범위 안"
        case .over: "+\(Int((macro.percent - Double(macro.rangeMax)).rounded()))%p 초과"
        case .under: "-\(Int((Double(macro.rangeMin) - macro.percent).rounded()))%p 부족"
        }
    }
}
```

`WooriHaru/Views/Diet/Components/NutrientLimitRow.swift`:

```swift
import SwiftUI

/// 주의 영양소 한 줄. **앱은 판정하지 않는다** — `status`가 `WARN`이면 강조하고 `OK`면 평범하게
/// 둔다. `standardText`는 서버 문구를 그대로 쓴다(기준이 개정되면 앱 배포 없이 따라간다).
///
/// **점수와 무관하다는 게 화면에서 드러나야 한다.** 점수는 탄단지 비율만 보므로 이 줄을 점수 링
/// 옆에 붙여 감점 요인처럼 보이게 하면 안 된다.
struct NutrientLimitRow: View {
    let limit: NutrientLimit

    private var isWarning: Bool { limit.status == .warn }

    var body: some View {
        HStack(spacing: 8) {
            Text(limit.name)
                .font(.caption)
                .foregroundStyle(isWarning ? Color.orange400 : Color.slate500)

            Spacer()

            Text(intakeText)
                .font(.caption.weight(isWarning ? .bold : .medium))
                .foregroundStyle(isWarning ? Color.orange400 : Color.slate700)

            Text(limit.standardText)
                .font(.caption2)
                .foregroundStyle(Color.slate400)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(limit.name) \(intakeText), 기준 \(limit.standardText)\(isWarning ? ", 주의" : "")")
    }

    /// 나트륨은 mg이라 소수가 의미 없고 g 단위는 소수 한 자리까지 보여준다.
    private var intakeText: String {
        limit.unit == "mg"
            ? "\(Int(limit.intake.rounded()))\(limit.unit)"
            : String(format: "%.1f%@", limit.intake, limit.unit)
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

4개 파일을 `DT40002` 그룹에 등록한다.

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MacroBarTests -only-testing:WooriHaruTests/DietDisplayTests 2>&1 | tail -30`
Expected: MacroBarTests 3개 + DietDisplayTests 3개 PASS (마지막 하나는 Task 11에서 되살린다)

- [ ] **Step 5: `DietHomeView`를 만든다**

`WooriHaru/Views/Diet/DietHomeView.swift`. 끼니 추가 시트와 상세 이동은 Task 8·11에서 채우므로 지금은 **끼니 카드 목록까지** 만든다.

```swift
import SwiftUI

/// 식단 진입점 — 주간 날짜 스트립 + 하루 요약 카드 + 끼니 목록 + 추가 버튼.
struct DietHomeView: View {
    @State private var vm = DietDayViewModel()
    @State private var showProfile = false
    @State private var showWeightSheet = false
    @State private var weightText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                weekStrip
                summaryCard

                // 하루 점수에도 같은 카드를 쓴다 — 칼로리 항목이 하나 더 붙는다.
                if let basis = vm.day?.scoreBasis {
                    ScoreBasisCard(title: "하루 점수", score: vm.day?.dayScore, dayBasis: basis)
                }

                mealList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .glassScreenBackground()
        .navigationTitle("식단")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("식단 프로필")
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            NutritionProfileView { Task { await vm.reload() } }
        }
        .sheet(isPresented: $showWeightSheet) { weightSheet }
        .task {
            await vm.load()
            await vm.syncActivity()
            // 목표가 없으면 점수를 낼 수 없으므로 프로필 입력이 먼저다.
            if vm.needsProfile { showProfile = true }
        }
        .refreshable { await vm.reload() }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - 날짜 스트립

    private var weekStrip: some View {
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

    private func weekdayText(_ date: Date) -> String {
        ["일", "월", "화", "수", "목", "금", "토"][date.weekday - 1]
    }

    // MARK: - 하루 요약

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    DietScoreRing(score: vm.day?.dayScore, caption: "하루 점수")

                    VStack(alignment: .leading, spacing: 8) {
                        if let profile = vm.profile, let day = vm.day {
                            MacroBar(name: "탄수화물", intakeG: day.carbsG, targetG: profile.targetCarbsG)
                            MacroBar(name: "단백질", intakeG: day.proteinG, targetG: profile.targetProteinG, tint: .green600)
                            MacroBar(name: "지방", intakeG: day.fatG, targetG: profile.targetFatG, tint: .orange400)
                        }
                    }
                }

                energyRow
                Divider()
                nutrientLimitSection
                Divider()
                feedbackSection
            }
        }
    }

    /// 활동 에너지는 **목표 칼로리에 반영하지 않는다** — 보조 표시일 뿐이다.
    private var energyRow: some View {
        HStack {
            Text("섭취 \(Int((vm.day?.totalKcal ?? 0).rounded()))kcal")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate700)
            if let burned = vm.day?.activeEnergyKcal {
                Text("/ 소모 \(burned)kcal")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
            Spacer()
            Button {
                weightText = vm.profile.map { String($0.weightKg) } ?? ""
                showWeightSheet = true
            } label: {
                Label(vm.profile.map { "\(String(format: "%.1f", $0.weightKg))kg" } ?? "몸무게", systemImage: "scalemass")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
        }
    }

    /// **점수 링 옆이 아니라 별도 줄이다** — 주의 영양소는 점수에 들어가지 않는다.
    @ViewBuilder
    private var nutrientLimitSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.day?.nutrientLimits ?? []) { NutrientLimitRow(limit: $0) }

            // 값이 0이면 아무것도 그리지 않는다 — 항목 단위 「추정」 배지와 달리 없음이 기본이다.
            if let notice = vm.estimatedNoticeText {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    /// 피드백이 안 와도 **재시도 버튼을 두지 않는다** — 끼니를 추가·수정하면 자연히 다시 만들어진다.
    @ViewBuilder
    private var feedbackSection: some View {
        if let feedback = vm.day?.feedback {
            Text(feedback)
                .font(.footnote)
                .foregroundStyle(Color.slate700)
                .fixedSize(horizontal: false, vertical: true)
        } else if vm.isFeedbackPending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("마감 피드백을 만들고 있어요")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
        } else if vm.isFeedbackDelayed {
            Text("피드백 생성이 지연되고 있어요. 잠시 후 다시 확인해 주세요.")
                .font(.caption)
                .foregroundStyle(Color.slate400)
        } else if vm.meals.isEmpty {
            Text("아직 기록한 끼니가 없어요.")
                .font(.caption)
                .foregroundStyle(Color.slate400)
        }
    }

    // MARK: - 끼니 목록

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
            }
        }
    }

    // MARK: - 몸무게 시트

    /// 몸무게만 고친다. **과거 점수는 바뀌지 않는다** — 서버가 끼니마다 스냅샷을 남긴다.
    private var weightSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Text("kg").foregroundStyle(Color.slate400)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassInputField()

                Text("몸무게를 고쳐도 지난 기록의 점수는 바뀌지 않아요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)

                Spacer()
            }
            .padding(16)
            .glassScreenBackground()
            .navigationTitle("몸무게")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showWeightSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        guard let weight = Double(weightText) else { return }
                        showWeightSheet = false
                        Task {
                            await vm.updateWeight(weight)
                            await vm.reload()
                        }
                    }
                    .disabled(Double(weightText) == nil)
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}
```

- [ ] **Step 6: 드로어와 네비게이션에 붙인다**

`WooriHaru/ContentView.swift` — `AppDestination`에 `case diet`를 추가하고(19행 `case swimRecords` 아래), `navigationDestination` switch에 분기를 넣는다(50행 아래):

```swift
                    case .diet: DietHomeView()
```

`WooriHaru/Views/Components/SideDrawerView.swift` — 83행 「수영 기록」 아래에 넣는다:

```swift
                drawerItem(icon: "fork.knife", label: "식단") { isOpen = false; navPath.append(AppDestination.diet) }
```

- [ ] **Step 7: 앱에서 열리는지 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전체 PASS

시뮬레이터에서 앱을 띄워 드로어 → 「식단」 → 하루 화면이 열리고, 프로필이 없으면 프로필 화면이 먼저 뜨는지 눈으로 확인한다.

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/Views/Diet WooriHaru/ContentView.swift WooriHaru/Views/Components/SideDrawerView.swift \
        WooriHaruTests/DietTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 식단 하루 화면과 드로어 진입을 만든다"
```

---

## Task 8: 사진 업로드와 인식 폴링

폴링 셋 중 둘째. **이쪽은 기다려야 확인 화면으로 갈 수 있다** — 하루 피드백 폴링과 성격이 다르다.

**Files:**
- Create: `WooriHaru/ViewModels/MealCaptureViewModel.swift`, `WooriHaru/Views/Diet/MealCaptureSheet.swift`
- Test: `WooriHaruTests/DietCaptureTests.swift`
- Modify: `WooriHaru/Info.plist`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10019`/`DT20019`(그룹 `B40003`), `DT10020`/`DT20020`(그룹 `DT40001`)

**Interfaces:**
- Consumes: `DietServing`, `UIImage.downsampledJPEG`, `MealAnalysis`
- Produces: `MealCaptureViewModel(service:pollInterval:pollTimeout:)` — `phase`·`mealType`·`photoDataList`·`uploadedCount`·`analysis`·`canRetry`·`isRetrying`·`errorMessage`·`append(_:)`·`start()`·`retry()`, `MealCaptureSheet(date:onConfirmed:)`

- [ ] **Step 1: 테스트를 쓴다**

`WooriHaruTests/DietCaptureTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct MealCaptureViewModelTests {
    private func makeVM(_ service: FakeDietService) -> MealCaptureViewModel {
        MealCaptureViewModel(service: service, pollInterval: .milliseconds(1), pollTimeout: .milliseconds(30))
    }

    private func photos(_ count: Int) -> [Data] {
        (0..<count).map { Data(repeating: UInt8($0), count: 100) }
    }

    @Test func 사진_N장을_순차로_올리고_인식을_요청한다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12, 13]
        service.analyses = [makeAnalysis(status: .pending), makeAnalysis(status: .completed)]
        let vm = makeVM(service)
        vm.append(photos(3))

        await vm.start()

        #expect(service.uploadedByteCounts.count == 3)
        #expect(service.createdFileIds == [[11, 12, 13]])
        #expect(vm.phase == .completed)
        #expect(vm.analysis?.status == .completed)
    }

    /// 중간에 실패하면 **이미 올린 파일을 되돌리려 하지 않는다** — 확정되지 않은 파일은 서버가 수거한다.
    @Test func 업로드_중_실패하면_중단하고_되돌리지_않는다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12, 13]
        service.errors["uploadPhoto#1"] = APIError.networkError(URLError(.timedOut))
        let vm = makeVM(service)
        vm.append(photos(3))

        await vm.start()

        #expect(service.uploadedByteCounts.count == 2)
        #expect(service.createdFileIds.isEmpty)
        #expect(vm.phase == .failed)
        #expect(vm.errorMessage != nil)
        #expect(service.deletedMealIds.isEmpty)
    }

    @Test func 업로드_진행률이_보인다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12]
        service.analyses = [makeAnalysis()]
        let vm = makeVM(service)
        vm.append(photos(2))

        #expect(vm.progressText == nil)
        await vm.start()

        #expect(vm.uploadedCount == 2)
    }

    /// 사진은 최대 5장이다 — 서버가 사진마다 LLM을 호출하므로 장수가 곧 비용·대기시간이다.
    @Test func 다섯_장을_넘겨_담지_않는다() {
        let vm = makeVM(FakeDietService())
        vm.append(photos(7))

        #expect(vm.photoDataList.count == 5)
        #expect(vm.remainingSlots == 0)
    }

    /// 전부 실패했을 때만 확인 화면 대신 실패 상태다.
    @Test func 전부_실패하면_실패_상태다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [makeAnalysis(status: .failed, photos: [
            AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])
        ])]
        let vm = makeVM(service)
        vm.append(photos(1))

        await vm.start()

        #expect(vm.phase == .failed)
        #expect(vm.canRetry)
    }

    /// 사진 일부만 실패하면 나머지 결과로 확인 화면을 띄운다. **실패한 사진을 감추지 않는다.**
    @Test func 일부만_실패하면_확인_화면으로_가되_재시도를_열어_둔다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11, 12]
        service.analyses = [makeAnalysis(status: .completed, photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: []),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: true, items: [])
        ])]
        let vm = makeVM(service)
        vm.append(photos(2))

        await vm.start()

        #expect(vm.phase == .completed)
        #expect(vm.analysis?.photos.count == 2)
        #expect(vm.canRetry)
    }

    /// 60초 타임아웃은 실패가 아니다 — 서버는 계속 처리 중일 수 있다.
    @Test func 타임아웃은_실패가_아니라_지연이다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [makeAnalysis(status: .pending)]
        let vm = makeVM(service)
        vm.append(photos(1))

        await vm.start()

        #expect(vm.phase == .delayed)
        #expect(!vm.canRetry)
    }

    /// **재시도 버튼은 누르는 즉시 잠근다.** 연타해도 호출이 한 번만 나간다.
    @Test func 재시도_연타는_한_번만_나간다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])]),
            makeAnalysis(status: .completed)
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()

        async let first: Void = vm.retry()
        async let second: Void = vm.retry()
        _ = await (first, second)

        #expect(service.retriedAnalysisIds.count == 1)
    }

    /// `ANALYSIS_IN_PROGRESS`는 **실패가 아니다** — 알럿 대신 폴링을 다시 시작한다.
    @Test func 진행중_응답이면_알럿_대신_폴링을_재개한다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])]),
            makeAnalysis(status: .completed)
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()

        service.retryErrorOnce = dietServerError("ANALYSIS_IN_PROGRESS")
        await vm.retry()

        #expect(vm.errorMessage == nil)
        #expect(vm.phase == .completed)
    }

    /// `ANALYSIS_NOT_RETRYABLE`은 재시도할 것이 없다는 뜻이라 버튼을 감춘다.
    @Test func 재시도할_것이_없으면_버튼을_감춘다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])]),
            makeAnalysis(status: .completed)
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()

        service.retryErrorOnce = dietServerError("ANALYSIS_NOT_RETRYABLE")
        await vm.retry()

        #expect(!vm.canRetry)
        #expect(vm.errorMessage == nil)
    }

    /// **재시도 버튼에서도 503이 온다** — 눌러도 안 되니 버튼을 감추고 같은 안내로 바꾼다.
    @Test func 재시도도_LLM이_없으면_버튼을_감추고_같은_안내로_바꾼다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.analyses = [
            makeAnalysis(status: .completed, photos: [AnalyzedPhoto(fileId: 11, url: nil, failed: true, items: [])])
        ]
        let vm = makeVM(service)
        vm.append(photos(1))
        await vm.start()
        #expect(vm.canRetry)

        service.retryErrorOnce = dietServerError("LLM_UNAVAILABLE", status: 503)
        await vm.retry()

        #expect(!vm.canRetry)
        #expect(vm.phase == .llmUnavailable)
        #expect(vm.errorMessage == nil)
    }

    /// 503이면 **나머지 기능은 전부 정상이다** — "사진 인식만 지금 안 된다"고 안내하고 직접 추가로 유도한다.
    @Test func LLM이_없으면_사진_인식만_막혔다고_안내한다() async {
        let service = FakeDietService()
        service.uploadFileIds = [11]
        service.errors["createAnalysis"] = dietServerError("LLM_UNAVAILABLE", status: 503)
        let vm = makeVM(service)
        vm.append(photos(1))

        await vm.start()

        #expect(vm.phase == .llmUnavailable)
        #expect(vm.errorMessage == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealCaptureViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'MealCaptureViewModel' in scope`

- [ ] **Step 3: ViewModel을 만든다**

`WooriHaru/ViewModels/MealCaptureViewModel.swift`:

```swift
import Foundation

/// 사진 여러 장 업로드 → 인식 요청 → 인식 폴링.
///
/// **이 폴링은 하루 피드백 폴링과 성격이 다르다** — 기다려야 확인 화면으로 갈 수 있고,
/// 실패하면 재시도 없이는 진행이 막히므로 버튼을 둔다.
@MainActor
@Observable
final class MealCaptureViewModel {
    enum Phase: Equatable {
        case idle
        case uploading
        case analyzing
        /// 확인 화면으로 갈 수 있다(사진 일부가 실패했어도 나머지 결과가 있다).
        case completed
        /// 전부 실패했거나 업로드가 끊겼다.
        case failed
        /// 60초 안에 안 끝났다. **실패로 단정하지 않는다.**
        case delayed
        /// 서버에 LLM 키가 없다. 나머지 기능은 전부 정상이다.
        case llmUnavailable
    }

    var mealType: MealType = .lunch
    private(set) var photoDataList: [Data] = []
    private(set) var uploadedCount = 0
    private(set) var phase: Phase = .idle
    private(set) var analysis: MealAnalysis?
    /// 실패한 사진이 있을 때만 재시도할 것이 있다.
    private(set) var canRetry = false
    private(set) var isRetrying = false
    var errorMessage: String?

    private let service: any DietServing
    private let pollInterval: Duration
    private let pollTimeout: Duration

    init(
        service: any DietServing = DietService(),
        pollInterval: Duration = DietPolicy.pollInterval,
        pollTimeout: Duration = DietPolicy.pollTimeout
    ) {
        self.service = service
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    var remainingSlots: Int { max(0, DietPolicy.maxPhotos - photoDataList.count) }

    /// "3장 중 2장 올리는 중" — 사진 수만큼 시간이 늘어나므로 진행 상황이 안 보이면 멈춘 것처럼 느껴진다.
    var progressText: String? {
        switch phase {
        case .uploading: "\(photoDataList.count)장 중 \(uploadedCount + 1)장 올리는 중"
        case .analyzing: "음식을 인식하고 있어요"
        default: nil
        }
    }

    var isBusy: Bool { phase == .uploading || phase == .analyzing }

    /// **상한을 넘겨 담지 않는다.** `PhotosPicker`의 `maxSelectionCount`로도 막지만 카메라 경로가 있다.
    func append(_ dataList: [Data]) {
        photoDataList = Array((photoDataList + dataList).prefix(DietPolicy.maxPhotos))
    }

    func remove(at index: Int) {
        guard photoDataList.indices.contains(index) else { return }
        photoDataList.remove(at: index)
    }

    // MARK: - 업로드 → 인식

    func start() async {
        guard !photoDataList.isEmpty, !isBusy else { return }
        phase = .uploading
        uploadedCount = 0
        errorMessage = nil

        // **순차로 올린다.** 병렬로 5장을 밀어넣으면 라즈베리파이에서 멀티파트 5개가 동시에
        // 처리되고, 어느 하나가 실패했을 때 어디까지 올라갔는지 추적이 지저분해진다.
        var fileIds: [Int] = []
        for data in photoDataList {
            do {
                fileIds.append(try await service.uploadPhoto(data))
                uploadedCount += 1
            } catch is CancellationError {
                return
            } catch {
                // **이미 올린 파일은 그대로 둔다** — 확정되지 않은 파일은 서버가 24시간 뒤 수거한다.
                phase = .failed
                errorMessage = "사진을 올리지 못했습니다. 다시 시도해 주세요."
                return
            }
        }

        do {
            let analysisId = try await service.createAnalysis(fileIds: fileIds)
            phase = .analyzing
            await poll(analysisId: analysisId)
        } catch is CancellationError {
            return
        } catch {
            if error.dietErrorCode == .llmUnavailable {
                // 나머지 기능은 전부 정상이다 — "서버 오류"로 뭉뚱그리지 않는다.
                phase = .llmUnavailable
            } else {
                phase = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    private func poll(analysisId: Int) async {
        let deadline = ContinuousClock.now + pollTimeout

        while ContinuousClock.now < deadline {
            do {
                let result = try await service.fetchAnalysis(id: analysisId)
                analysis = result

                switch result.status {
                case .pending:
                    try await Task.sleep(for: pollInterval)
                case .completed:
                    // 일부 사진만 실패했으면 나머지 결과로 확인 화면을 띄우고 그 사진만 다시 시도한다.
                    canRetry = result.hasFailedPhoto
                    phase = .completed
                    return
                case .failed:
                    canRetry = true
                    phase = .failed
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                phase = .failed
                errorMessage = error.localizedDescription
                return
            }
        }

        // 타임아웃은 실패가 아니다 — 서버는 계속 처리 중일 수 있다.
        phase = .delayed
        canRetry = false
    }

    // MARK: - 재시도

    /// **누르는 즉시 잠근다.** 서버가 `PENDING`인 동안 들어온 재시도를 `ANALYSIS_IN_PROGRESS`로
    /// 거절하므로 중복 유료 호출은 안 나가지만, 잠그지 않으면 연타할 때마다 오류 알럿이 뜬다.
    func retry() async {
        guard let analysis, canRetry, !isRetrying else { return }
        isRetrying = true
        errorMessage = nil
        defer { isRetrying = false }

        do {
            try await service.retryAnalysis(id: analysis.id)
        } catch is CancellationError {
            return
        } catch {
            switch error.dietErrorCode {
            case .analysisInProgress:
                // 이미 서버가 처리 중이라는 뜻이지 실패가 아니다 — 알럿 대신 폴링을 다시 시작한다.
                break
            case .analysisNotRetryable:
                // 재시도할 것이 없다 — 버튼을 감춘다.
                canRetry = false
                return
            case .llmUnavailable:
                // 서버에 키가 없으면 재시도도 503으로 거절된다 — 눌러도 안 되니 버튼을 감추고
                // 인식 요청과 같은 안내로 바꾼다.
                canRetry = false
                phase = .llmUnavailable
                return
            default:
                errorMessage = error.localizedDescription
                return
            }
        }

        phase = .analyzing
        await poll(analysisId: analysis.id)
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealCaptureViewModelTests 2>&1 | tail -30`
Expected: 12개 PASS

- [ ] **Step 5: `MealCaptureSheet`을 만든다**

`WooriHaru/Views/Diet/MealCaptureSheet.swift`:

```swift
import PhotosUI
import SwiftUI

/// 카메라/앨범에서 1~5장 선택 → 끼니 종류 선택 → 업로드 → 인식 진행 표시.
/// 인식이 끝나면 시트를 닫지 않고 **`MealConfirmView`로 이어진다.**
struct MealCaptureSheet: View {
    let date: Date
    /// 확정이 끝났을 때 mealId를 넘긴다.
    var onConfirmed: (Int) -> Void

    @State private var vm = MealCaptureViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GlassTokens.cardSpacing) {
                    mealTypePicker
                    photoSection
                    statusSection
                }
                .padding(16)
            }
            .glassScreenBackground()
            .navigationTitle("사진으로 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .navigationDestination(isPresented: .init(
                get: { vm.phase == .completed },
                set: { if !$0 && vm.phase == .completed { vm.reset() } }
            )) {
                if let analysis = vm.analysis {
                    MealConfirmView(date: date, mealType: vm.mealType, analysis: analysis) { mealId in
                        onConfirmed(mealId)
                        dismiss()
                    } onRetryPhoto: {
                        await vm.retry()
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPicked(items) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    if let downsampled = UIImage.downsampledJPEG(from: data) {
                        vm.append([downsampled])
                    }
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

    private var mealTypePicker: some View {
        Picker("끼니", selection: $vm.mealType) {
            ForEach(MealType.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(vm.isBusy)
    }

    private var photoSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.photoDataList.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 88, height: 88)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                if !vm.isBusy {
                                    Button {
                                        vm.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, Color.slate500)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    // **상한 5장을 애초에 더 못 고르게 한다.**
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: vm.remainingSlots,
                        matching: .images
                    ) {
                        Label("앨범", systemImage: "photo.on.rectangle")
                            .font(.caption)
                    }
                    .disabled(vm.remainingSlots == 0 || vm.isBusy)

                    Button {
                        showCamera = true
                    } label: {
                        Label("카메라", systemImage: "camera")
                            .font(.caption)
                    }
                    .disabled(vm.remainingSlots == 0 || vm.isBusy)

                    Spacer()

                    Text("최대 \(DietPolicy.maxPhotos)장")
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch vm.phase {
        case .idle, .failed, .delayed, .llmUnavailable:
            if vm.phase == .llmUnavailable {
                // 인식만 못 쓴다 — 나머지 기능은 전부 정상이다.
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("지금은 사진 인식을 쓸 수 없어요")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.slate700)
                        Text("음식을 검색하거나 직접 입력해서 기록할 수 있어요. 하루 요약 화면의 「직접 추가」를 눌러 주세요.")
                            .font(.caption)
                            .foregroundStyle(Color.slate400)
                    }
                }
            }

            if vm.phase == .delayed {
                Text("인식이 지연되고 있어요. 잠시 후 새로고침해 주세요.")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }

            if vm.canRetry {
                Button("다시 인식") { Task { await vm.retry() } }
                    .appGlassButton()
                    .disabled(vm.isRetrying)
            }

            Button {
                Task { await vm.start() }
            } label: {
                Text("인식 시작")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .appGlassProminentButton()
            .disabled(vm.photoDataList.isEmpty)

        case .uploading, .analyzing:
            HStack(spacing: 10) {
                ProgressView()
                Text(vm.progressText ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

        case .completed:
            EmptyView()
        }
    }

    /// **다운샘플이 업로드 앞에 온다** — 원본은 12MP·수 MB급이라 그대로 올리면 느리고
    /// 서버가 큰 이미지를 LLM에 넘겨 토큰 비용이 몇 배로 뛴다.
    private func loadPicked(_ items: [PhotosPickerItem]) async {
        var downsampled: [Data] = []
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let jpeg = UIImage.downsampledJPEG(from: raw) else { continue }
            downsampled.append(jpeg)
        }
        vm.append(downsampled)
        pickerItems = []
    }
}

/// `UIImagePickerController` 래퍼 — SwiftUI에 카메라 캡처가 없다.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1.0) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

`MealCaptureViewModel`에 `reset()`을 추가한다(`retry()` 아래):

```swift
    /// 확인 화면에서 뒤로 나왔을 때. 인식 결과는 살려 두고 상태만 되돌린다.
    func reset() {
        phase = analysis == nil ? .idle : .completed
    }
```

- [ ] **Step 6: 카메라 권한 문구를 넣는다**

`WooriHaru/Info.plist`의 `NSHealthShareUsageDescription` 위에 추가한다:

```xml
	<key>NSCameraUsageDescription</key>
	<string>식사 사진을 찍어 식단을 기록하는 데 사용합니다.</string>
```

- [ ] **Step 7: 빌드를 확인한다**

`MealConfirmView`는 **이미 만들어져 있다**(실행 순서가 Task 10 → 9 → 8이다 — 「실행 순서」 참조).

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealCaptureViewModelTests 2>&1 | tail -30`
Expected: 12개 PASS, BUILD SUCCEEDED

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/MealCaptureViewModel.swift WooriHaru/Views/Diet/MealCaptureSheet.swift \
        WooriHaru/Info.plist WooriHaruTests/DietCaptureTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 사진 업로드와 인식 폴링을 만든다"
```

---

## Task 9: `MealConfirmView` — 이번 설계의 핵심 화면

인식 결과를 사용자가 확인·수정하고 저장한다. **저장하기 전에는 `Meal`이 만들어지지 않는다.**
가장 큰 리스크는 확인 단계가 이탈 지점이 되는 것이다 — **기본값을 그대로 저장하는 게 1탭**이어야 하고, 수정은 하고 싶은 사람만 한다.

**Files:**
- Create: `Views/Diet/Components/PhotoStrip.swift`, `ViewModels/MealConfirmViewModel.swift`, `Views/Diet/MealConfirmView.swift`
- Test: `WooriHaruTests/DietConfirmTests.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10021`/`DT20021` `PhotoStrip.swift`(그룹 `DT40002`), `DT10022`/`DT20022` `MealConfirmViewModel.swift`(그룹 `B40003`), `DT10023`/`DT20023` `MealConfirmView.swift`(그룹 `DT40001`)

**Interfaces:**
- Consumes: `DietServing`, `MealAnalysis`·`AnalyzedPhoto`, `NutritionMath`, `MealConfirmRequest`
- Produces: `PhotoStrip(photos:failedIds:)`(`photos`는 `(id: Int, url: String?)` 배열), `MealConfirmViewModel(date:mealType:analysis:service:)` — `groups`·`allItems`·`totalKcal`·`totalCarbsG`·`totalProteinG`·`totalFatG`·`hasChanges`·`isSaving`·`savedMealID`·`errorMessage`·`needsProfile`·`removeItem(_:in:)`·`updateQuantity(_:of:in:)`·`replaceItem(_:with:in:)`·`addItem(_:to:)`·`save()`, `MealConfirmView(date:mealType:analysis:onSaved:onRetryPhoto:)`

- [ ] **Step 1: 테스트를 쓴다**

`WooriHaruTests/DietConfirmTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct MealConfirmViewModelTests {
    private func analyzedItem(_ name: String, kcal: Double = 300, sodium: Double = 900) -> AnalyzedItem {
        AnalyzedItem(
            foodName: name, foodCode: "D1", quantityG: 200, kcal: kcal,
            carbsG: 30, proteinG: 20, fatG: 10, sugarG: 5, sodiumMg: sodium, fiberG: 2,
            source: .dbMatched
        )
    }

    private func twoPhotoAnalysis() -> MealAnalysis {
        makeAnalysis(photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [analyzedItem("제육볶음")]),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: false, items: [analyzedItem("제육볶음"), analyzedItem("공기밥")])
        ])
    }

    private func makeVM(_ analysis: MealAnalysis?, service: FakeDietService = .init()) -> MealConfirmViewModel {
        MealConfirmViewModel(date: Date.from("2026-07-29")!, mealType: .lunch, analysis: analysis, service: service)
    }

    /// **항목을 사진별로 묶어 보여준다** — "2번 사진의 제육볶음"과 "3번 사진의 제육볶음"이 따로
    /// 보여야 사용자가 같은 접시인지 판단할 수 있다.
    @Test func 항목이_사진별로_묶인다() {
        let vm = makeVM(twoPhotoAnalysis())

        #expect(vm.groups.count == 2)
        #expect(vm.groups[0].items.count == 1)
        #expect(vm.groups[1].items.count == 2)
        #expect(vm.allItems.count == 3)
    }

    @Test func 합계가_항목에서_계산된다() {
        let vm = makeVM(twoPhotoAnalysis())

        #expect(vm.totalKcal == 900)
        #expect(vm.totalCarbsG == 90)
    }

    /// **저장한 items가 전송된다 — 인식 원본이 아니다.**
    @Test func 삭제하고_수량을_바꾼_결과가_전송된다() async {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), service: service)
        let duplicated = vm.groups[1].items[0]
        vm.removeItem(duplicated, in: vm.groups[1].id)
        let remaining = vm.groups[0].items[0]
        vm.updateQuantity(400, of: remaining, in: vm.groups[0].id)

        await vm.save()

        let request = try! #require(service.confirmRequests.first)
        #expect(request.items.count == 2)
        #expect(request.analysisId == 100)
        #expect(request.date == "2026-07-29")
        #expect(request.mealType == .lunch)
        let changed = try! #require(request.items.first { $0.foodName == "제육볶음" })
        #expect(changed.quantityG == 400)
        #expect(changed.kcal == 600)
        #expect(changed.sodiumMg == 1800)
        #expect(vm.savedMealID == 200)
    }

    /// **주의 영양소 3필드가 인식 경로 끝까지 살아 있어야 한다.** 서버가 0을 조용히 받는다.
    @Test func 인식_경로의_주의_영양소가_요청까지_살아_있다() async {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), service: service)

        await vm.save()

        let items = try! #require(service.confirmRequests.first?.items)
        #expect(items.allSatisfy { $0.sodiumMg > 0 })
        #expect(items.allSatisfy { $0.sugarG > 0 })
        #expect(items.allSatisfy { $0.fiberG > 0 })
    }

    /// 사진 없는 기록 — `analysisId`가 빠지고 그룹이 하나뿐이며 `PhotoStrip`이 그릴 게 없다.
    @Test func 사진_없는_기록은_analysisId를_보내지_않는다() async {
        let service = FakeDietService()
        let vm = makeVM(nil, service: service)
        vm.addItem(NutritionMath.manualItem(
            name: "새우깡", quantityG: 40, kcal: 220, carbsG: 27,
            proteinG: 3, fatG: 11, sugarG: 2, sodiumMg: 280, fiberG: 1
        ), to: vm.groups[0].id)

        await vm.save()

        let request = try! #require(service.confirmRequests.first)
        #expect(request.analysisId == nil)
        #expect(request.items.count == 1)
        #expect(vm.photoURLs.isEmpty)
        #expect(!vm.hasPhotos)
    }

    /// 항목이 하나도 없으면 저장할 수 없다 — 서버가 빈 배열을 거절한다.
    @Test func 항목이_없으면_저장할_수_없다() {
        let vm = makeVM(nil)
        #expect(!vm.canSave)

        vm.addItem(NutritionMath.manualItem(
            name: "사과", quantityG: 200, kcal: 104, carbsG: 28,
            proteinG: 1, fatG: 0, sugarG: 21, sodiumMg: 2, fiberG: 5
        ), to: vm.groups[0].id)
        #expect(vm.canSave)
    }

    /// 저장 없이 이탈하면 `Meal` 생성 요청이 나가지 않는다. 확인 알럿을 띄울지는 화면이 정한다.
    @Test func 저장하지_않으면_생성_요청이_나가지_않는다() {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), service: service)
        vm.removeItem(vm.groups[0].items[0], in: vm.groups[0].id)

        #expect(service.confirmRequests.isEmpty)
        #expect(vm.hasChanges)
    }

    /// 프로필이 없으면 서버가 확정을 거절한다 — 프로필 화면으로 보낸다.
    @Test func 프로필이_없으면_프로필_화면으로_보낸다() async {
        let service = FakeDietService()
        service.errors["confirmMeal"] = dietServerError("PROFILE_NOT_FOUND", status: 404)
        let vm = makeVM(twoPhotoAnalysis(), service: service)

        await vm.save()

        #expect(vm.needsProfile)
        #expect(vm.savedMealID == nil)
    }

    /// 인식이 끝나기 전에는 저장 버튼을 잠근다 — 뜨면 앱 분기가 빠진 것이다.
    @Test func 확정_불가_응답은_안내로_바꾼다() async {
        let service = FakeDietService()
        service.errors["confirmMeal"] = dietServerError("ANALYSIS_NOT_CONFIRMABLE")
        let vm = makeVM(twoPhotoAnalysis(), service: service)

        await vm.save()

        #expect(vm.errorMessage != nil)
        #expect(vm.savedMealID == nil)
    }

    /// 실패한 사진도 그룹으로 남는다 — 감추면 사용자가 나머지가 어디 갔는지 알 수 없다.
    @Test func 실패한_사진도_그룹으로_남는다() {
        let vm = makeVM(makeAnalysis(photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [analyzedItem("제육볶음")]),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: true, items: [])
        ]))

        #expect(vm.groups.count == 2)
        #expect(vm.groups[1].failed)
        #expect(vm.groups[1].items.isEmpty)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealConfirmViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'MealConfirmViewModel' in scope`

- [ ] **Step 3: ViewModel을 만든다**

`WooriHaru/ViewModels/MealConfirmViewModel.swift`:

```swift
import Foundation

/// 인식 결과를 확인·수정하고 확정한다. **저장하기 전에는 `Meal`이 만들어지지 않는다.**
///
/// `analysis`가 `nil`이면 **사진 없는 기록**이다 — 검색·직접 입력으로 만든 항목만 저장한다.
@MainActor
@Observable
final class MealConfirmViewModel {
    /// 사진 하나에서 나온 항목 묶음. 사진 없는 기록에서는 `fileId`가 nil인 그룹 하나뿐이다.
    struct PhotoGroup: Identifiable {
        let id: Int
        let fileId: Int?
        let url: String?
        let failed: Bool
        var items: [MealItemRequest]
    }

    let date: Date
    var mealType: MealType
    private(set) var groups: [PhotoGroup]
    private(set) var isSaving = false
    private(set) var savedMealID: Int?
    /// 확정을 서버가 `PROFILE_NOT_FOUND`로 거절했다 — 프로필 화면으로 보내야 한다.
    private(set) var needsProfile = false
    /// 인식 원본에서 하나라도 달라졌는지. 저장 없이 나갈 때 알럿을 띄울지 판단한다.
    private(set) var hasChanges = false
    var errorMessage: String?

    private let analysisId: Int?
    private let service: any DietServing

    init(
        date: Date,
        mealType: MealType,
        analysis: MealAnalysis?,
        service: any DietServing = DietService()
    ) {
        self.date = date
        self.mealType = mealType
        self.analysisId = analysis?.id
        self.service = service

        if let analysis {
            self.groups = analysis.photos.enumerated().map { index, photo in
                PhotoGroup(
                    id: index,
                    fileId: photo.fileId,
                    url: photo.url,
                    failed: photo.failed,
                    items: photo.items.map(NutritionMath.request(from:))
                )
            }
        } else {
            // 사진 없는 기록 — 담을 자리 하나만 둔다.
            self.groups = [PhotoGroup(id: 0, fileId: nil, url: nil, failed: false, items: [])]
        }
    }

    var hasPhotos: Bool { groups.contains { $0.fileId != nil } }
    var photoURLs: [String] { groups.compactMap(\.url) }
    var failedFileIds: Set<Int> { Set(groups.filter(\.failed).compactMap(\.fileId)) }

    var allItems: [MealItemRequest] { groups.flatMap(\.items) }

    var totalKcal: Double { allItems.reduce(0) { $0 + $1.kcal } }
    var totalCarbsG: Double { allItems.reduce(0) { $0 + $1.carbsG } }
    var totalProteinG: Double { allItems.reduce(0) { $0 + $1.proteinG } }
    var totalFatG: Double { allItems.reduce(0) { $0 + $1.fatG } }

    /// 서버가 빈 배열을 거절한다.
    var canSave: Bool { !allItems.isEmpty && !isSaving }

    // MARK: - 편집

    func removeItem(_ item: MealItemRequest, in groupId: Int) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].items.removeAll { $0.id == item.id }
        hasChanges = true
    }

    /// 수량을 바꾸면 영양소 7개가 함께 비례한다 — 서버와 같은 환산이 `NutritionMath`에 있다.
    func updateQuantity(_ quantityG: Double, of item: MealItemRequest, in groupId: Int) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              let itemIndex = groups[groupIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
        groups[groupIndex].items[itemIndex] = NutritionMath.rescaled(item, to: quantityG)
        hasChanges = true
    }

    /// 식품 검색으로 교체.
    func replaceItem(_ item: MealItemRequest, with replacement: MealItemRequest, in groupId: Int) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              let itemIndex = groups[groupIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
        groups[groupIndex].items[itemIndex] = replacement
        hasChanges = true
    }

    /// 인식이 놓친 음식 추가.
    func addItem(_ item: MealItemRequest, to groupId: Int) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].items.append(item)
        hasChanges = true
    }

    // MARK: - 저장

    func save() async {
        guard canSave else { return }
        isSaving = true
        needsProfile = false
        errorMessage = nil
        defer { isSaving = false }

        do {
            // **인식 원본이 아니라 사용자가 고친 최종본을 보낸다.** 서버는 대조하지 않고 그대로 신뢰한다.
            savedMealID = try await service.confirmMeal(MealConfirmRequest(
                date: date.dateString,
                mealType: mealType,
                analysisId: analysisId,
                items: allItems
            ))
        } catch is CancellationError {
            return
        } catch {
            switch error.dietErrorCode {
            case .profileNotFound:
                needsProfile = true
            case .analysisNotConfirmable:
                errorMessage = "인식이 아직 끝나지 않았습니다. 잠시 후 다시 시도해 주세요."
            default:
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealConfirmViewModelTests 2>&1 | tail -30`
Expected: 10개 PASS

- [ ] **Step 5: `PhotoStrip`을 만든다**

`WooriHaru/Views/Diet/Components/PhotoStrip.swift`:

```swift
import SwiftUI

/// 사진 여러 장 가로 스트립 (확인·상세 공용).
/// **사진이 없으면 아무것도 그리지 않는다** — 사진 없이 기록한 끼니는 `photos`가 빈 배열이다.
struct PhotoStrip: View {
    /// (fileId, presigned URL). URL은 10분 만료라 오래 캐시하지 않는다.
    let photos: [(id: Int, url: String?)]
    /// 인식에 실패한 사진. **감추지 않고 배지를 단다.**
    var failedIds: Set<Int> = []

    var body: some View {
        if photos.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos, id: \.id) { photo in
                        ZStack(alignment: .bottomLeading) {
                            thumbnail(photo.url)

                            if failedIds.contains(photo.id) {
                                Text("인식 실패")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.red500, in: Capsule())
                                    .padding(6)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ url: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(Color.slate300)
                default:
                    ProgressView()
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(shape)
        } else {
            shape
                .fill(Color.slate100)
                .frame(width: 110, height: 110)
                .overlay(Image(systemName: "photo").foregroundStyle(Color.slate300))
        }
    }
}
```

- [ ] **Step 6: `MealConfirmView`를 만든다**

`WooriHaru/Views/Diet/MealConfirmView.swift`:

```swift
import SwiftUI

/// 인식 결과를 확인·수정하고 저장한다. 사진 없는 기록에서도 같은 화면을 쓴다 —
/// 항목 목록·합계·저장 버튼이 그대로 필요하고 `PhotoStrip`만 그릴 게 없다.
///
/// **저장 버튼이 1탭이어야 한다.** 확인 화면이 번거로우면 저장하지 않고 나가고, 그러면
/// LLM 비용은 나갔는데 기록은 남지 않는다. "검수 과업"이 아니라 "저장 전 미리보기"로 느껴져야 한다.
struct MealConfirmView: View {
    let date: Date
    let analysis: MealAnalysis?
    var onSaved: (Int) -> Void
    /// 실패한 사진만 다시 인식. 사진 없는 기록에서는 nil이다.
    var onRetryPhoto: (() async -> Void)?

    @State private var vm: MealConfirmViewModel
    @State private var showDiscardAlert = false
    @State private var editTarget: EditTarget?
    @State private var showProfile = false
    @Environment(\.dismiss) private var dismiss

    /// 어느 그룹에 무엇을 하려는지. 새 항목이면 `item`이 nil이다.
    private struct EditTarget: Identifiable {
        let groupId: Int
        let item: MealItemRequest?
        var id: String { "\(groupId)-\(item?.id.uuidString ?? "new")" }
    }

    init(
        date: Date,
        mealType: MealType,
        analysis: MealAnalysis?,
        service: any DietServing = DietService(),
        onSaved: @escaping (Int) -> Void,
        onRetryPhoto: (() async -> Void)? = nil
    ) {
        self.date = date
        self.analysis = analysis
        self.onSaved = onSaved
        self.onRetryPhoto = onRetryPhoto
        _vm = State(initialValue: MealConfirmViewModel(
            date: date, mealType: mealType, analysis: analysis, service: service
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                Picker("끼니", selection: $vm.mealType) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if vm.hasPhotos {
                    PhotoStrip(
                        photos: vm.groups.compactMap { group in
                            group.fileId.map { (id: $0, url: group.url) }
                        },
                        failedIds: vm.failedFileIds
                    )

                    if !vm.failedFileIds.isEmpty, let onRetryPhoto {
                        Button("실패한 사진 다시 인식") { Task { await onRetryPhoto() } }
                            .appGlassButton()
                            .font(.caption)
                    }
                }

                ForEach(vm.groups) { group in
                    groupCard(group)
                }

                totalCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle("확인")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    // 여기까지 오는 데 LLM 비용과 대기시간이 이미 들었다 — 실수로 이탈하지 않게 확인한다.
                    if vm.hasChanges || analysis != nil {
                        showDiscardAlert = true
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") { Task { await save() } }
                    .disabled(!vm.canSave)
            }
        }
        .sheet(item: $editTarget) { target in
            MealItemEditView(current: target.item) { edited in
                if let original = target.item {
                    vm.replaceItem(original, with: edited, in: target.groupId)
                } else {
                    vm.addItem(edited, to: target.groupId)
                }
                editTarget = nil
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            NutritionProfileView()
        }
        .alert("저장하지 않고 나갈까요?", isPresented: $showDiscardAlert) {
            Button("나가기", role: .destructive) { dismiss() }
            Button("계속 확인", role: .cancel) {}
        } message: {
            Text("저장하지 않으면 이 기록은 남지 않아요.")
        }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .onChange(of: vm.needsProfile) { _, needs in
            if needs { showProfile = true }
        }
    }

    private func save() async {
        await vm.save()
        if let mealId = vm.savedMealID { onSaved(mealId) }
    }

    /// **항목을 사진별로 묶어 보여주는 게 중요하다** — 같은 음식이 여러 사진에서 중복으로 잡힐 때
    /// 출처가 보여야 사용자가 같은 접시인지 진짜 2인분인지 판단할 수 있다.
    private func groupCard(_ group: MealConfirmViewModel.PhotoGroup) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if vm.hasPhotos {
                    HStack {
                        Text("사진 \(group.id + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.slate500)
                        if group.failed {
                            Text("인식 실패")
                                .font(.caption2)
                                .foregroundStyle(Color.red500)
                        }
                        Spacer()
                    }
                }

                ForEach(group.items) { item in
                    itemRow(item, in: group.id)
                }

                Button {
                    editTarget = EditTarget(groupId: group.id, item: nil)
                } label: {
                    Label("음식 추가", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.blue500)
            }
        }
    }

    private func itemRow(_ item: MealItemRequest, in groupId: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.foodName)
                        .font(.subheadline)
                        .foregroundStyle(Color.slate700)

                    // 확인 화면에서 특히 중요하다 — 어느 값을 우선 검토해야 하는지 알려준다.
                    if item.source == .llmEstimated {
                        Text("추정")
                            .font(.caption2)
                            .foregroundStyle(Color.orange400)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange100, in: Capsule())
                    }
                }
                Text("\(Int(item.quantityG.rounded()))g · \(Int(item.kcal.rounded()))kcal")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }

            Spacer()

            Stepper("") {
                vm.updateQuantity(item.quantityG + 50, of: item, in: groupId)
            } onDecrement: {
                vm.updateQuantity(max(0, item.quantityG - 50), of: item, in: groupId)
            }
            .labelsHidden()

            Button {
                editTarget = EditTarget(groupId: groupId, item: item)
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.blue500)
            }
            .buttonStyle(.plain)

            Button {
                vm.removeItem(item, in: groupId)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.red400)
            }
            .buttonStyle(.plain)
        }
    }

    private var totalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("합계")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Spacer()
                    Text("\(Int(vm.totalKcal.rounded()))kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.slate900)
                }
                HStack(spacing: 12) {
                    macroText("탄", vm.totalCarbsG)
                    macroText("단", vm.totalProteinG)
                    macroText("지", vm.totalFatG)
                }
            }
        }
    }

    private func macroText(_ label: String, _ grams: Double) -> some View {
        Text("\(label) \(Int(grams.rounded()))g")
            .font(.caption)
            .foregroundStyle(Color.slate500)
    }
}
```

- [ ] **Step 7: 빌드를 확인한다**

`MealItemEditView`는 **이미 만들어져 있다**(실행 순서가 Task 10 → 9 → 8이다 — 「실행 순서」 참조).

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealConfirmViewModelTests 2>&1 | tail -30`
Expected: 10개 PASS, BUILD SUCCEEDED

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/MealConfirmViewModel.swift WooriHaru/Views/Diet/MealConfirmView.swift \
        WooriHaru/Views/Diet/Components/PhotoStrip.swift \
        WooriHaruTests/DietConfirmTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 인식 결과 확인·수정 화면을 만든다"
```

---

## Task 10: 항목 편집 — 자주 먹는 음식 · 검색 · 직접 입력

**놓는 순서가 중요하다.** 자주 먹는 음식이 **검색창보다 먼저** 보여야 한다 — 매일 먹는 것을 매번 검색하게 만들면 사진 없는 기록을 만든 이유가 사라진다.

**Files:**
- Create: `Views/Diet/Components/FrequentItemList.swift`, `Views/Diet/MealItemEditView.swift`
- Test: `WooriHaruTests/DietConfirmTests.swift` (추가)
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10024`/`DT20024` `FrequentItemList.swift`(그룹 `DT40002`), `DT10025`/`DT20025` `MealItemEditView.swift`(그룹 `DT40001`)

**Interfaces:**
- Consumes: `DietServing`, `Food`, `FrequentItem`, `NutritionMath`
- Produces: `FrequentItemList(items:onSelect:)`, `MealItemEditViewModel(service:)` — `frequentItems`·`searchResults`·`query`·`isSearching`·`load()`·`search()`, `MealItemEditView(current:service:onCommit:)`

- [ ] **Step 1: 테스트를 쓴다**

`WooriHaruTests/DietConfirmTests.swift` 끝에 붙인다:

```swift
@MainActor
struct MealItemEditViewModelTests {
    private func food(_ name: String, known: Bool = true, serving: Double = 250) -> Food {
        Food(
            code: "D9", name: name, dataset: .dish,
            servingSizeG: serving, servingSizeKnown: known,
            kcalPer100g: 150, carbsPer100g: 12, proteinPer100g: 10, fatPer100g: 7,
            sugarPer100g: 3, sodiumMgPer100g: 400, fiberPer100g: 1.5
        )
    }

    /// **검색창보다 먼저** 자주 먹는 음식이 보여야 한다 — 화면 진입 시 함께 읽는다.
    @Test func 진입하면_자주_먹는_음식을_먼저_읽는다() async {
        let service = FakeDietService()
        service.frequentItems = [
            FrequentItem(
                foodName: "사과", foodCode: "R1", quantityG: 200, kcal: 104,
                carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
                source: .dbMatched, count: 7, lastEatenOn: "2026-07-29"
            )
        ]
        let vm = MealItemEditViewModel(service: service)

        await vm.load()

        #expect(vm.frequentItems.count == 1)
        #expect(service.frequentCallCount == 1)
        #expect(service.searchQueries.isEmpty)
    }

    /// **탭 한 번으로 담긴다** — 수량과 영양소가 딸려 오므로 앱이 다시 계산하지 않는다.
    @Test func 자주_먹는_음식은_계산_없이_그대로_담긴다() {
        let frequent = FrequentItem(
            foodName: "사과", foodCode: "R1", quantityG: 200, kcal: 104,
            carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
            source: .dbMatched, count: 7, lastEatenOn: "2026-07-29"
        )

        let request = NutritionMath.request(from: frequent)

        #expect(request.quantityG == 200)
        #expect(request.kcal == 104)
        #expect(request.sodiumMg == 2)
        #expect(request.fiberG == 4.8)
    }

    @Test func 검색어를_넣으면_식품DB를_찾는다() async {
        let service = FakeDietService()
        service.foods = [food("제육볶음")]
        let vm = MealItemEditViewModel(service: service)
        vm.query = "제육"

        await vm.search()

        #expect(service.searchQueries == ["제육"])
        #expect(vm.searchResults.count == 1)
    }

    /// `servingSizeKnown == true`면 1인분이 기본 수량이다.
    @Test func 일인분을_알면_기본_수량이_채워진다() {
        #expect(NutritionMath.defaultQuantity(for: food("제육볶음", known: true, serving: 250)) == 250)
    }

    /// **false면 수량 칸을 비운다** — 서버가 채운 200g을 그대로 넣으면 그럴듯하게 틀린 값이 기록된다.
    @Test func 일인분_미상이면_수량_칸이_비어_있다() {
        let unknown = food("달걀", known: false, serving: 200)

        #expect(NutritionMath.defaultQuantity(for: unknown) == nil)

        let vm = MealItemEditViewModel(service: FakeDietService())
        vm.select(unknown)

        #expect(vm.quantityText.isEmpty)
        #expect(vm.servingSizeUnknownHint != nil)
    }

    @Test func 일인분을_알면_수량_칸이_채워진다() {
        let vm = MealItemEditViewModel(service: FakeDietService())
        vm.select(food("제육볶음", known: true, serving: 250))

        #expect(vm.quantityText == "250")
        #expect(vm.servingSizeUnknownHint == nil)
    }

    /// 검색 경로의 주의 영양소도 끝까지 살아 있어야 한다.
    @Test func 검색_결과를_담으면_주의_영양소가_환산된다() {
        let vm = MealItemEditViewModel(service: FakeDietService())
        vm.select(food("제육볶음", known: true, serving: 250))

        let built = try! #require(vm.buildItem())

        #expect(built.quantityG == 250)
        #expect(built.sodiumMg == 1000)
        #expect(built.sugarG == 7.5)
        #expect(built.fiberG == 3.75)
        #expect(built.source == .dbMatched)
    }

    /// 직접 입력 — `foodCode`는 `""`가 아니라 `nil`이고 `source`는 `.llmEstimated`다.
    @Test func 직접_입력은_코드를_보내지_않는다() {
        let vm = MealItemEditViewModel(service: FakeDietService())
        vm.startManualInput()
        vm.manualName = "포장 김밥"
        vm.quantityText = "230"
        vm.manualKcal = "430"
        vm.manualCarbs = "60"
        vm.manualProtein = "12"
        vm.manualFat = "15"
        vm.manualSugar = "4"
        vm.manualSodium = "980"
        vm.manualFiber = "3"

        let built = try! #require(vm.buildItem())

        #expect(built.foodCode == nil)
        #expect(built.source == .llmEstimated)
        #expect(built.sodiumMg == 980)
        #expect(built.fiberG == 3)
    }

    /// 직접 입력에도 세 칸이 있어야 한다 — 넷만 채워 보내면 서버가 나머지를 0으로 말없이 저장한다.
    @Test func 직접_입력에_이름이나_수량이_없으면_담을_수_없다() {
        let vm = MealItemEditViewModel(service: FakeDietService())
        vm.startManualInput()

        #expect(vm.buildItem() == nil)

        vm.manualName = "포장 김밥"
        #expect(vm.buildItem() == nil)

        vm.quantityText = "230"
        #expect(vm.buildItem() != nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealItemEditViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'MealItemEditViewModel' in scope`

- [ ] **Step 3: `FrequentItemList`를 만든다**

`WooriHaru/Views/Diet/Components/FrequentItemList.swift`:

```swift
import SwiftUI

/// 자주 먹는 음식 — **탭하면 바로 담긴다.** 수량과 영양소가 딸려 오므로 앱이 계산하지 않는다.
struct FrequentItemList: View {
    let items: [FrequentItem]
    var onSelect: (FrequentItem) -> Void

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("자주 먹는 음식")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.slate500)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.foodName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Color.slate700)
                                        .lineLimit(1)
                                    Text("\(Int(item.quantityG.rounded()))g · \(item.countText)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.slate400)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassInputField(cornerRadius: 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: `MealItemEditView`와 ViewModel을 만든다**

`WooriHaru/Views/Diet/MealItemEditView.swift` (ViewModel을 같은 파일에 둔다 — 이 화면 전용이고 함께 바뀐다):

```swift
import SwiftUI

/// 자주 먹는 음식 · 식품DB 검색 · 직접 입력. 확인 화면과 상세 화면이 공용으로 쓴다.
@MainActor
@Observable
final class MealItemEditViewModel {
    enum Mode: Equatable { case pick, manual }

    private(set) var frequentItems: [FrequentItem] = []
    private(set) var searchResults: [Food] = []
    private(set) var isSearching = false
    private(set) var mode: Mode = .pick
    private(set) var selectedFood: Food?

    var query = ""
    var quantityText = ""

    // 직접 입력 — 포장지 영양성분표를 보고 채운다.
    var manualName = ""
    var manualKcal = ""
    var manualCarbs = ""
    var manualProtein = ""
    var manualFat = ""
    var manualSugar = ""
    var manualSodium = ""
    var manualFiber = ""

    var errorMessage: String?

    private let service: any DietServing

    init(service: any DietServing = DietService()) {
        self.service = service
    }

    /// `servingSizeKnown`이 false면 왜 수량이 비었는지 읽히게 힌트를 단다.
    var servingSizeUnknownHint: String? {
        guard let food = selectedFood, !food.servingSizeKnown else { return nil }
        return "1인분 정보 없음 — 드신 양을 넣어 주세요"
    }

    func load() async {
        do {
            frequentItems = try await service.fetchFrequentItems()
        } catch is CancellationError {
            return
        } catch {
            // 자주 먹는 음식이 없어도 검색은 되어야 한다 — 화면을 막지 않는다.
            frequentItems = []
        }
    }

    func search() async {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await service.searchFoods(query: keyword)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 검색 결과를 고른다. **`servingSizeKnown`이 false면 수량 칸을 비워 사용자가 직접 넣게 한다.**
    func select(_ food: Food) {
        mode = .pick
        selectedFood = food
        quantityText = NutritionMath.defaultQuantity(for: food).map { Self.text($0) } ?? ""
    }

    func startManualInput() {
        mode = .manual
        selectedFood = nil
        quantityText = ""
    }

    /// 현재 입력에서 담을 항목을 만든다. 채워지지 않았으면 nil.
    func buildItem() -> MealItemRequest? {
        guard let quantity = Double(quantityText), quantity > 0 else { return nil }

        switch mode {
        case .pick:
            guard let food = selectedFood else { return nil }
            return NutritionMath.item(from: food, quantityG: quantity)
        case .manual:
            let name = manualName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
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
    }

    private static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

struct MealItemEditView: View {
    /// 교체 대상. nil이면 새로 담는다.
    var current: MealItemRequest?
    var onCommit: (MealItemRequest) -> Void

    @State private var vm: MealItemEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        current: MealItemRequest? = nil,
        service: any DietServing = DietService(),
        onCommit: @escaping (MealItemRequest) -> Void
    ) {
        self.current = current
        self.onCommit = onCommit
        _vm = State(initialValue: MealItemEditViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassTokens.cardSpacing) {
                    // **검색창보다 먼저** 보여야 한다 — 매일 먹는 것을 매번 검색하게 만들면 안 된다.
                    FrequentItemList(items: vm.frequentItems) { item in
                        onCommit(NutritionMath.request(from: item))
                        dismiss()
                    }

                    searchSection

                    if vm.mode == .manual {
                        manualSection
                    } else if vm.selectedFood != nil {
                        quantitySection
                    }
                }
                .padding(16)
            }
            .glassScreenBackground()
            .navigationTitle(current == nil ? "음식 추가" : "음식 교체")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("담기") {
                        guard let item = vm.buildItem() else { return }
                        onCommit(item)
                        dismiss()
                    }
                    .disabled(vm.buildItem() == nil)
                }
            }
            .task { await vm.load() }
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

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            ForEach(vm.searchResults) { food in
                Button {
                    vm.select(food)
                } label: {
                    HStack(spacing: 6) {
                        Text(food.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.slate700)

                        // 조리 음식과 포장 제품이 섞여 나오므로 목록에서 구분해 보여준다.
                        if let badge = food.dataset.badge {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(Color.slate500)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.slate100, in: Capsule())
                        }

                        Spacer()

                        if vm.selectedFood?.id == food.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.blue500)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                vm.startManualInput()
            } label: {
                Label("직접 입력", systemImage: "square.and.pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
        }
    }

    private var quantitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("수량")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.slate500)

                HStack {
                    TextField("0", text: $vm.quantityText)
                        .keyboardType(.decimalPad)
                    Text("g").foregroundStyle(Color.slate400)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassInputField()

                if let hint = vm.servingSizeUnknownHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Color.orange400)
                }
            }
        }
    }

    /// 포장지 영양성분표를 보고 채우는 자리. **당류·나트륨·식이섬유 칸이 반드시 있어야 한다** —
    /// 넷만 채워 보내면 서버가 나머지를 0.0으로 받아 말없이 저장한다.
    private var manualSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("직접 입력")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.slate500)

                TextField("음식 이름", text: $vm.manualName)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .glassInputField()

                HStack(spacing: 8) {
                    numberField("수량", unit: "g", text: $vm.quantityText)
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
            }
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
}
```

- [ ] **Step 5: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealItemEditViewModelTests 2>&1 | tail -30`
Expected: 9개 PASS

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Views/Diet/MealItemEditView.swift WooriHaru/Views/Diet/Components/FrequentItemList.swift \
        WooriHaruTests/DietConfirmTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 항목 편집에 자주 먹는 음식·검색·직접 입력을 넣는다"
```

---

## Task 11: `MealDetailView` — 점수·근거·피드백·삭제

**끼니 통째로 지우기가 여기 있어야 한다.** `PUT /items`가 빈 배열을 거절하므로 이 동선이 없으면 잘못 찍은 끼니를 지울 방법이 아예 없다 — 항목을 하나씩 지워도 마지막 하나가 남는다.

**Files:**
- Create: `WooriHaru/ViewModels/MealDetailViewModel.swift`, `WooriHaru/Views/Diet/MealDetailView.swift`
- Test: `WooriHaruTests/DietDayTests.swift` (추가)
- Modify: `WooriHaru/Views/Diet/DietHomeView.swift` (끼니 카드 → 상세 이동, 추가 버튼)
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10026`/`DT20026`(그룹 `B40003`), `DT10027`/`DT20027`(그룹 `DT40001`)

**Interfaces:**
- Consumes: `DietServing`, `Meal`, `MealItemRequest`, `NutritionMath`, `PhotoStrip`, `ScoreBasisCard`, `MealItemEditView`
- Produces: `MealDetailViewModel(mealId:service:pollInterval:pollTimeout:)` — `meal`·`isLoading`·`isFeedbackPending`·`isFeedbackDelayed`·`didDelete`·`errorMessage`·`editableItems`·`load()`·`replaceItems(_:)`·`replaceItem(_:with:)`·`deleteItem(_:)`·`deleteMeal()`, `MealDetailView(mealId:service:onChanged:)`

- [ ] **Step 1: 테스트를 쓴다**

`WooriHaruTests/DietDayTests.swift` 끝에 붙인다:

```swift
@MainActor
struct MealDetailViewModelTests {
    private func makeVM(_ service: FakeDietService) -> MealDetailViewModel {
        MealDetailViewModel(
            mealId: 1, service: service,
            pollInterval: .milliseconds(1), pollTimeout: .milliseconds(30)
        )
    }

    @Test func 끼니를_읽는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.meal?.score == 76)
        #expect(vm.meal?.scoreBasis?.macros.count == 3)
        #expect(!vm.isFeedbackPending)
    }

    /// **확정 직후 피드백 폴링이 화면을 붙잡지 않는다** — 점수는 이미 표시된다.
    @Test func 피드백_대기중에도_점수는_보인다() async {
        let service = FakeDietService()
        service.meals = [
            makeMeal(status: .pending, feedback: nil),
            makeMeal(status: .completed, feedback: "잘 드셨어요.")
        ]
        let vm = makeVM(service)

        await vm.load()
        #expect(vm.meal?.score == 76)
        #expect(vm.isFeedbackPending)

        await vm.waitForFeedbackPolling()

        #expect(vm.meal?.feedback == "잘 드셨어요.")
        #expect(!vm.isFeedbackPending)
    }

    /// 끼니 피드백은 실패하면 재시도 여지가 있다 — 다만 앱은 `POST /meals/{id}/retry`를 부르지 않는다.
    @Test func 피드백_생성_실패는_점수를_지우지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(status: .failed, feedback: nil)]
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.meal?.score == 76)
        #expect(vm.meal?.feedback == nil)
        #expect(!vm.isFeedbackPending)
    }

    @Test func 항목을_교체하면_재계산_결과를_다시_읽는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(), makeMeal(score: 88)]
        let vm = makeVM(service)
        await vm.load()

        let items = [NutritionMath.manualItem(
            name: "닭가슴살", quantityG: 150, kcal: 165, carbsG: 0,
            proteinG: 31, fatG: 3.6, sugarG: 0, sodiumMg: 74, fiberG: 0
        )]
        await vm.replaceItems(items)

        #expect(service.updatedItems.count == 1)
        #expect(service.updatedItems.first?.items.first?.sodiumMg == 74)
        #expect(vm.meal?.score == 88)
    }

    /// **삭제 뒤에는 하루 요약을 다시 조회해야 한다** — 점수·합계·`nutrientLimits`가 전부 달라지고
    /// 피드백은 `null`로 돌아와 다시 생성이 걸린다. 화면이 그 신호로 쓸 `didDelete`를 세운다.
    @Test func 끼니를_삭제하면_삭제_표식을_남긴다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()

        await vm.deleteMeal()

        #expect(service.deletedMealIds == [1])
        #expect(vm.didDelete)
    }

    /// 타인 소유 리소스는 404다 — "찾을 수 없습니다"로 같게 다룬다.
    @Test func 없는_끼니는_찾을_수_없다고_안내한다() async {
        let service = FakeDietService()
        service.errors["fetchMeal"] = dietServerError("RESOURCE_NOT_FOUND", status: 404)
        let vm = makeVM(service)

        await vm.load()

        #expect(vm.meal == nil)
        #expect(vm.errorMessage != nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealDetailViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'MealDetailViewModel' in scope`

- [ ] **Step 3: ViewModel을 만든다**

`WooriHaru/ViewModels/MealDetailViewModel.swift`:

```swift
import Foundation

/// 끼니 상세 — 항목 수정·항목 삭제·**끼니 삭제**, 그리고 끼니 피드백 폴링.
///
/// **피드백 폴링은 화면을 붙잡지 않는다.** 확정 응답 시점에 점수·항목은 이미 확정돼 있다.
@MainActor
@Observable
final class MealDetailViewModel {
    let mealId: Int

    private(set) var meal: Meal?
    private(set) var isLoading = false
    private(set) var isFeedbackPending = false
    private(set) var isFeedbackDelayed = false
    /// 끼니가 삭제됐다. 화면은 이 신호로 하루 요약을 다시 조회하고 뒤로 나간다.
    private(set) var didDelete = false
    var errorMessage: String?

    private var generation = 0
    private var feedbackTask: Task<Void, Never>?

    private let service: any DietServing
    private let pollInterval: Duration
    private let pollTimeout: Duration

    init(
        mealId: Int,
        service: any DietServing = DietService(),
        pollInterval: Duration = DietPolicy.pollInterval,
        pollTimeout: Duration = DietPolicy.pollTimeout
    ) {
        self.mealId = mealId
        self.service = service
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    /// 편집 화면으로 넘길 현재 항목들.
    var editableItems: [MealItemRequest] {
        (meal?.items ?? []).map { item in
            MealItemRequest(
                foodName: item.foodName, foodCode: item.foodCode, quantityG: item.quantityG,
                kcal: item.kcal, carbsG: item.carbsG, proteinG: item.proteinG, fatG: item.fatG,
                sugarG: item.sugarG, sodiumMg: item.sodiumMg, fiberG: item.fiberG, source: item.source
            )
        }
    }

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        feedbackTask?.cancel()
        isFeedbackDelayed = false
        defer { isLoading = false }

        do {
            // presigned URL은 10분 만료라 화면을 다시 열 때 조회한다 —
            // 사진이 여러 장이어도 만료 시각이 같으니 한 번에 다시 받는다.
            let loaded = try await service.fetchMeal(id: mealId)
            guard token == generation else { return }
            meal = loaded
            startFeedbackPollingIfNeeded(token: token)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            errorMessage = error.dietErrorCode == .resourceNotFound
                ? "찾을 수 없습니다."
                : error.localizedDescription
        }
    }

    private func startFeedbackPollingIfNeeded(token: Int) {
        guard meal?.status == .pending else {
            isFeedbackPending = false
            return
        }
        isFeedbackPending = true
        feedbackTask = Task { [weak self] in
            await self?.pollFeedback(token: token)
        }
    }

    private func pollFeedback(token: Int) async {
        let deadline = ContinuousClock.now + pollTimeout

        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
                let refreshed = try await service.fetchMeal(id: mealId)
                guard token == generation else { return }

                if refreshed.status != .pending {
                    meal = refreshed
                    isFeedbackPending = false
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }

        guard token == generation else { return }
        isFeedbackPending = false
        isFeedbackDelayed = true
    }

    func waitForFeedbackPolling() async {
        await feedbackTask?.value
    }

    /// 항목 전체 교체 → 서버가 영양소·점수·피드백을 재계산한다.
    func replaceItems(_ items: [MealItemRequest]) async {
        guard !items.isEmpty else {
            // 서버가 빈 배열을 거절한다 — 다 지우고 싶으면 끼니를 삭제해야 한다.
            errorMessage = "항목을 모두 지우려면 끼니를 삭제해 주세요."
            return
        }

        do {
            try await service.updateMealItems(id: mealId, items: items)
            await load()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// **id로 자리를 찾는다.** 이름·수량으로 거르면 같은 음식을 두 번 담은 끼니에서 둘 다 지워진다.
    func deleteItem(_ item: MealItem) async {
        guard let items = meal?.items, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var remaining = editableItems
        remaining.remove(at: index)
        await replaceItems(remaining)
    }

    /// 항목 하나를 교체한다. `editableItems`가 `meal.items`와 같은 순서라 인덱스를 그대로 쓴다.
    func replaceItem(_ item: MealItem, with replacement: MealItemRequest) async {
        guard let items = meal?.items, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var changed = editableItems
        changed[index] = replacement
        await replaceItems(changed)
    }

    /// 되돌릴 수 없다. 서버는 사진을 `TEMP`로 되돌리고 그날 하루 피드백 캐시를 지운다 —
    /// **그래서 삭제 뒤에는 하루 요약을 다시 조회해야 한다.**
    func deleteMeal() async {
        do {
            try await service.deleteMeal(id: mealId)
            didDelete = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/MealDetailViewModelTests 2>&1 | tail -30`
Expected: 6개 PASS

- [ ] **Step 5: 화면을 만든다**

`WooriHaru/Views/Diet/MealDetailView.swift`:

```swift
import SwiftUI

/// 사진 여러 장·항목 목록·끼니 점수·점수 근거·피드백. 항목 수정과 **끼니 삭제**가 여기 있다.
struct MealDetailView: View {
    let mealId: Int
    /// 항목 수정·삭제로 하루 집계가 달라졌을 때. 하루 화면이 다시 조회한다.
    var onChanged: () -> Void

    @State private var vm: MealDetailViewModel
    @State private var showDeleteAlert = false
    @State private var editingItem: MealItem?
    @State private var showAddItem = false
    @Environment(\.dismiss) private var dismiss

    init(mealId: Int, service: any DietServing = DietService(), onChanged: @escaping () -> Void) {
        self.mealId = mealId
        self.onChanged = onChanged
        _vm = State(initialValue: MealDetailViewModel(mealId: mealId, service: service))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                if let meal = vm.meal {
                    PhotoStrip(photos: meal.photos.map { (id: $0.fileId, url: $0.url) })
                    itemsCard(meal)
                    ScoreBasisCard(title: "끼니 점수", score: meal.score, basis: meal.scoreBasis)
                    feedbackCard(meal)
                    deleteButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle(vm.meal?.mealType.label ?? "끼니")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .overlay { if vm.isLoading && vm.meal == nil { ProgressView() } }
        .sheet(item: $editingItem) { item in
            MealItemEditView(current: nil) { replacement in
                Task {
                    await vm.replaceItem(item, with: replacement)
                    onChanged()
                }
                editingItem = nil
            }
        }
        .sheet(isPresented: $showAddItem) {
            MealItemEditView { added in
                Task {
                    await vm.replaceItems(vm.editableItems + [added])
                    onChanged()
                }
                showAddItem = false
            }
        }
        .alert("끼니를 삭제할까요?", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) {
                Task {
                    await vm.deleteMeal()
                    if vm.didDelete {
                        onChanged()
                        dismiss()
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제하면 되돌릴 수 없어요.")
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

    private func itemsCard(_ meal: Meal) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("먹은 것")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Spacer()
                    Text("\(Int(meal.totalKcal.rounded()))kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.slate900)
                }

                ForEach(meal.items) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.foodName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.slate700)

                                // 식품DB 매칭이 안 됐음을 알린다.
                                if item.source == .llmEstimated {
                                    Text("추정")
                                        .font(.caption2)
                                        .foregroundStyle(Color.orange400)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color.orange100, in: Capsule())
                                }
                            }
                            Text("\(Int(item.quantityG.rounded()))g · \(Int(item.kcal.rounded()))kcal")
                                .font(.caption2)
                                .foregroundStyle(Color.slate400)
                        }

                        Spacer()

                        Button {
                            editingItem = item
                        } label: {
                            Image(systemName: "pencil").foregroundStyle(Color.blue500)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task {
                                await vm.deleteItem(item)
                                onChanged()
                            }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(Color.red400)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showAddItem = true
                } label: {
                    Label("음식 추가", systemImage: "plus").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.blue500)
            }
        }
    }

    /// 이 피드백은 **그 끼니의 균형에 대해서만** 말한다 — 하루 맥락 조언은 하루 요약 카드에 있다.
    @ViewBuilder
    private func feedbackCard(_ meal: Meal) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("피드백")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                if let feedback = meal.feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(Color.slate700)
                        .fixedSize(horizontal: false, vertical: true)
                } else if vm.isFeedbackPending {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("피드백을 만들고 있어요")
                            .font(.caption)
                            .foregroundStyle(Color.slate400)
                    }
                } else {
                    Text("피드백을 만들지 못했어요. 항목을 고치면 다시 만들어져요.")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Text("끼니 삭제")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .appGlassButton()
        .foregroundStyle(Color.red500)
    }
}
```

- [ ] **Step 6: 하루 화면에서 상세로 잇는다**

`WooriHaru/Views/Diet/DietHomeView.swift` — `mealList`의 `GlassCard`를 `NavigationLink`로 감싼다:

```swift
    private var mealList: some View {
        VStack(spacing: 12) {
            ForEach(vm.meals) { meal in
                NavigationLink(value: meal.id) {
                    GlassCard {
                        // (기존 HStack 내용 그대로)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
```

`body`의 `.navigationDestination(isPresented: $showProfile)` 아래에 추가한다:

```swift
        .navigationDestination(for: Int.self) { mealId in
            MealDetailView(mealId: mealId) { Task { await vm.reload() } }
        }
```

- [ ] **Step 7: Task 7에서 미뤄 둔 테스트를 되살리고 통과를 확인한다**

Task 7 Step 1의 `DietDisplayTests`에서 빼 뒀던 `점수_근거는_서버_status와_penalty를_그대로_쓴다`를
`WooriHaruTests/DietTests.swift`에 되돌린다.

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전체 PASS (`DietDisplayTests` 4개 포함)

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/MealDetailViewModel.swift WooriHaru/Views/Diet/MealDetailView.swift \
        WooriHaruTests/DietTests.swift \
        WooriHaru/Views/Diet/DietHomeView.swift WooriHaruTests/DietDayTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 끼니 상세와 삭제 동선을 만든다"
```

---

## Task 12: 사진 없는 기록 동선

지금은 사진을 찍지 않으면 끼니를 만들 수 없다. **과자 하나, 사과 한 개를 기록하려고 사진을 찍게 만들면 기록을 안 하게 된다.** 화면은 이미 다 있다 — `MealConfirmView`가 `analysis: nil`을 받으면 사진 없는 모드로 돌고, 진입만 열어 주면 된다.

**Files:**
- Modify: `WooriHaru/Views/Diet/DietHomeView.swift`
- Test: `WooriHaruTests/DietConfirmTests.swift` (추가)

**Interfaces:**
- Consumes: Task 9의 `MealConfirmView(date:mealType:analysis:onSaved:)`, Task 8의 `MealCaptureSheet`
- Produces: `DietHomeView`의 추가 버튼 — 「사진으로 추가」 / 「직접 추가」

- [ ] **Step 1: 사진 없는 모드가 `PhotoStrip`을 깨지 않는지 테스트를 쓴다**

`WooriHaruTests/DietConfirmTests.swift` 끝에 붙인다:

```swift
@MainActor
struct PhotolessMealTests {
    /// `photos`가 비어 있어도 화면이 그릴 것이 없을 뿐 깨지지 않는다.
    @Test func 사진이_없으면_그릴_것이_없다() {
        let vm = MealConfirmViewModel(date: Date(), mealType: .snack, analysis: nil, service: FakeDietService())

        #expect(vm.groups.count == 1)
        #expect(vm.groups[0].fileId == nil)
        #expect(vm.photoURLs.isEmpty)
        #expect(vm.failedFileIds.isEmpty)
        #expect(!vm.hasPhotos)
    }

    /// 확정 응답의 `photos`가 빈 배열이어도 상세가 깨지지 않는다.
    @Test func 사진_없는_끼니_상세도_깨지지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(photos: [], items: [makeMealItem(name: "새우깡", code: nil, source: .llmEstimated)])]
        let vm = MealDetailViewModel(mealId: 1, service: service)

        await vm.load()

        #expect(vm.meal?.photos.isEmpty == true)
        #expect(vm.meal?.items.first?.source == .llmEstimated)
    }

    /// 직접 입력 경로의 주의 영양소가 확정 요청까지 살아 있다.
    @Test func 직접_입력_경로의_주의_영양소가_요청까지_살아_있다() async {
        let service = FakeDietService()
        let vm = MealConfirmViewModel(date: Date.from("2026-07-29")!, mealType: .snack, analysis: nil, service: service)
        vm.addItem(NutritionMath.manualItem(
            name: "포장 김밥", quantityG: 230, kcal: 430, carbsG: 60,
            proteinG: 12, fatG: 15, sugarG: 4, sodiumMg: 980, fiberG: 3
        ), to: vm.groups[0].id)

        await vm.save()

        let item = try! #require(service.confirmRequests.first?.items.first)
        #expect(item.sodiumMg == 980)
        #expect(item.sugarG == 4)
        #expect(item.fiberG == 3)
        #expect(item.foodCode == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/PhotolessMealTests 2>&1 | tail -30`
Expected: 3개 PASS (ViewModel은 이미 두 모드를 지원한다 — 이 테스트는 회귀 방지용이다)

> 여기서 실패하면 Task 9의 `MealConfirmViewModel`이 `analysis == nil`을 처리하지 않는 것이므로
> 그쪽을 고친다.

- [ ] **Step 3: 하루 화면에 추가 버튼을 넣는다**

`WooriHaru/Views/Diet/DietHomeView.swift` — `@State` 목록에 추가한다:

```swift
    @State private var showCapture = false
    @State private var showManualEntry = false
```

`body`의 `.toolbar` 블록에 추가 버튼을 넣는다:

```swift
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button {
                        showCapture = true
                    } label: {
                        Label("사진으로 추가", systemImage: "camera")
                    }
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("직접 추가", systemImage: "square.and.pencil")
                    }
                } label: {
                    Label("끼니 추가", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            }
```

시트 두 개를 `body`의 `.sheet(isPresented: $showWeightSheet)` 아래에 붙인다:

```swift
        .sheet(isPresented: $showCapture) {
            MealCaptureSheet(date: vm.selectedDate) { _ in
                Task { await vm.reload() }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            // 사진 없는 기록 — `MealConfirmView`를 그대로 재사용한다. `PhotoStrip`만 그릴 게 없다.
            NavigationStack {
                MealConfirmView(date: vm.selectedDate, mealType: .snack, analysis: nil) { _ in
                    showManualEntry = false
                    Task { await vm.reload() }
                }
            }
        }
```

- [ ] **Step 4: 눈으로 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전체 PASS

시뮬레이터에서 「직접 추가」 → 자주 먹는 음식이 검색창 위에 보이는지 → 직접 입력으로 담아 저장 → 하루 요약에 반영되는지 확인한다.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Diet/DietHomeView.swift WooriHaruTests/DietConfirmTests.swift
git commit -m "feat: 사진 없이 끼니를 기록하는 동선을 연다"
```

---

## Task 13: 기간 통계

LLM 조언이 없어서 폴링도 로딩 상태도 필요 없다. 한 번 부르면 끝이다.

**Files:**
- Create: `WooriHaru/ViewModels/DietStatsViewModel.swift`, `WooriHaru/Views/Diet/DietStatsView.swift`
- Test: `WooriHaruTests/DietStatsTests.swift`
- Modify: `WooriHaru/Views/Diet/DietHomeView.swift` (툴바에 통계 진입)
- Modify: `WooriHaru.xcodeproj/project.pbxproj` — `DT10028`/`DT20028`(그룹 `B40003`), `DT10029`/`DT20029`(그룹 `DT40001`)

**Interfaces:**
- Consumes: `DietServing`, `DietStats`, `FrequentItemList`
- Produces: `DietStatsViewModel(service:today:)` — `range`·`stats`·`isLoading`·`errorMessage`·`isEmpty`·`load()`·`select(_:)`, `DietStatsView()`

- [ ] **Step 1: 테스트를 쓴다**

`WooriHaruTests/DietStatsTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct DietStatsViewModelTests {
    private let today = Date.from("2026-07-30")!

    private func stats(recordedDays: Int, scores: [DailyScore] = []) -> DietStats {
        DietStats(
            from: "2026-07-24", to: "2026-07-30", recordedDays: recordedDays,
            averageDayScore: recordedDays == 0 ? nil : 74,
            dailyScores: scores,
            averageIntake: recordedDays == 0 ? nil : NutritionTotals(
                kcal: 1980, carbsG: 250.1, proteinG: 78.4, fatG: 62,
                sugarG: 44.2, sodiumMg: 2610, fiberG: 14.8
            ),
            averageTargets: recordedDays == 0 ? nil : NutritionTargets(
                kcal: 2509, carbsG: 345, proteinG: 94, fatG: 84,
                sugarG: 125, sodiumMg: 2300, fiberG: 30
            ),
            topFoods: []
        )
    }

    /// 주 토글은 7일치(양 끝 포함)를 부른다.
    @Test func 주간_범위를_계산한다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 6)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(service.statsRanges.first?.from == "2026-07-24")
        #expect(service.statsRanges.first?.to == "2026-07-30")
    }

    /// 월 토글은 30일치를 부른다. **최대 366일 상한에 걸리지 않는다.**
    @Test func 월간_범위를_계산한다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 20)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.select(.month)

        #expect(service.statsRanges.last?.from == "2026-07-01")
        #expect(service.statsRanges.last?.to == "2026-07-30")
    }

    /// 기록이 0건이면 세 값이 null이다 — 옵셔널로 받아 빈 상태를 그린다.
    @Test func 기록이_0건이면_빈_상태다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 0)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(vm.isEmpty)
        #expect(vm.stats?.averageDayScore == nil)
        #expect(vm.stats?.averageIntake == nil)
        #expect(vm.errorMessage == nil)
    }

    /// **평균은 기록한 날로만 낸 값이다** — "6일 기록"을 함께 보여줘야 평균이 무슨 뜻인지 읽힌다.
    @Test func 기록한_날_수를_함께_보여준다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 6)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(vm.recordedDaysText == "6일 기록")
        #expect(!vm.isEmpty)
    }

    /// `dailyScores`에는 **기록한 날만** 들어간다 — x축을 배열 인덱스로 잡으면 간격이 뭉개진다.
    @Test func 추이는_날짜로_배치한다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 3, scores: [
            DailyScore(date: "2026-07-24", dayScore: 81),
            DailyScore(date: "2026-07-27", dayScore: 65),
            DailyScore(date: "2026-07-30", dayScore: 74)
        ])
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        let points = vm.trendPoints
        #expect(points.count == 3)
        // 24일과 27일 사이가 27일과 30일 사이와 같은 간격이어야 한다(3일씩).
        #expect(abs((points[1].x - points[0].x) - (points[2].x - points[1].x)) < 0.001)
        #expect(points[0].x == 0)
        #expect(points[2].x == 1)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietStatsViewModelTests 2>&1 | tail -30`
Expected: 컴파일 실패 — `cannot find 'DietStatsViewModel' in scope`

- [ ] **Step 3: ViewModel을 만든다**

`WooriHaru/ViewModels/DietStatsViewModel.swift`:

```swift
import Foundation

/// 기간 통계 — 주·월 토글로 `from`~`to`만 바꿔 같은 엔드포인트를 부른다.
/// **LLM 조언이 없어서 폴링도 로딩 상태도 필요 없다.** 한 번 부르면 끝이다.
@MainActor
@Observable
final class DietStatsViewModel {
    enum Range: String, CaseIterable, Identifiable {
        case week, month

        var id: String { rawValue }
        var label: String { self == .week ? "주" : "월" }
        /// 양 끝을 포함한 일수. 서버 상한(366일)에 한참 못 미친다.
        var days: Int { self == .week ? 7 : 30 }
    }

    private(set) var range: Range = .week
    private(set) var stats: DietStats?
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: any DietServing
    private let today: Date

    init(service: any DietServing = DietService(), today: Date = Date()) {
        self.service = service
        self.today = today
    }

    var isEmpty: Bool { (stats?.recordedDays ?? 0) == 0 }

    /// 평균의 분모를 함께 보여줘야 "평균 1,980kcal"이 무슨 뜻인지 읽힌다.
    var recordedDaysText: String { "\(stats?.recordedDays ?? 0)일 기록" }

    /// 추이 차트용 좌표. **x는 날짜 간격을 반영한다** — 안 적은 날이 빠져 있으므로
    /// 배열 인덱스로 잡으면 3일 공백과 1일 공백이 같은 폭이 된다.
    var trendPoints: [(x: Double, y: Double, score: DailyScore)] {
        let scores = stats?.dailyScores ?? []
        let dates = scores.compactMap { Date.from($0.date) }
        guard dates.count == scores.count, let first = dates.first, let last = dates.last else { return [] }

        let span = last.timeIntervalSince(first)
        return zip(scores, dates).map { score, date in
            let x = span > 0 ? date.timeIntervalSince(first) / span : 0
            return (x: x, y: Double(score.dayScore) / 100.0, score: score)
        }
    }

    func select(_ newRange: Range) async {
        range = newRange
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let calendar = Calendar.current
        // between이라 양 끝을 포함한다 — days만큼 빼면 days+1일이 잡히므로 1을 뺀다.
        guard let from = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) else { return }

        do {
            stats = try await service.fetchStats(from: from.dateString, to: today.dateString)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/DietStatsViewModelTests 2>&1 | tail -30`
Expected: 5개 PASS

- [ ] **Step 5: 화면을 만든다**

`WooriHaru/Views/Diet/DietStatsView.swift`:

```swift
import SwiftUI

/// 일별 점수 추이·평균 섭취량과 목표 대비·자주 먹은 음식.
struct DietStatsView: View {
    @State private var vm = DietStatsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                rangePicker

                if vm.isEmpty {
                    emptyState
                } else if let stats = vm.stats {
                    summaryCard(stats)
                    trendCard
                    averageCard(stats)
                    topFoodsCard(stats)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle("식단 통계")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .overlay { if vm.isLoading && vm.stats == nil { ProgressView() } }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var rangePicker: some View {
        Picker("기간", selection: .init(
            get: { vm.range },
            set: { newValue in Task { await vm.select(newValue) } }
        )) {
            ForEach(DietStatsViewModel.Range.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.largeTitle)
                    .foregroundStyle(Color.slate300)
                Text("이 기간에 기록한 끼니가 없어요")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate500)
            }
            .padding(.vertical, 20)
        }
    }

    private func summaryCard(_ stats: DietStats) -> some View {
        GlassCard {
            HStack(spacing: 16) {
                DietScoreRing(score: stats.averageDayScore, caption: "평균 점수")

                VStack(alignment: .leading, spacing: 4) {
                    // 평균은 기록한 날로만 낸 값이라 분모를 함께 보여준다.
                    Text(vm.recordedDaysText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Text("안 적은 날은 평균에 들어가지 않아요.")
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }

                Spacer()
            }
        }
    }

    /// **x축을 날짜로 배치한다** — 기록한 날만 오므로 인덱스로 그리면 간격이 뭉개진다.
    private var trendCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("일별 점수")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                GeometryReader { geometry in
                    ZStack {
                        Path { path in
                            for (index, point) in vm.trendPoints.enumerated() {
                                let position = CGPoint(
                                    x: point.x * geometry.size.width,
                                    y: (1 - point.y) * geometry.size.height
                                )
                                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            }
                        }
                        .stroke(Color.blue500, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                        ForEach(vm.trendPoints, id: \.score.id) { point in
                            Circle()
                                .fill(Color.blue500)
                                .frame(width: 6, height: 6)
                                .position(
                                    x: point.x * geometry.size.width,
                                    y: (1 - point.y) * geometry.size.height
                                )
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private func averageCard(_ stats: DietStats) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("하루 평균")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                if let intake = stats.averageIntake, let targets = stats.averageTargets {
                    HStack {
                        Text("칼로리")
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                        Spacer()
                        Text("\(Int(intake.kcal.rounded()))kcal / \(targets.kcal)kcal")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.slate700)
                    }

                    MacroBar(name: "탄수화물", intakeG: intake.carbsG, targetG: targets.carbsG)
                    MacroBar(name: "단백질", intakeG: intake.proteinG, targetG: targets.proteinG, tint: .green600)
                    MacroBar(name: "지방", intakeG: intake.fatG, targetG: targets.fatG, tint: .orange400)

                    Divider()

                    MacroBar(name: "당류", intakeG: intake.sugarG, targetG: targets.sugarG, tint: .orange400)
                    MacroBar(name: "나트륨(mg)", intakeG: intake.sodiumMg, targetG: targets.sodiumMg, tint: .orange400)
                    MacroBar(name: "식이섬유", intakeG: intake.fiberG, targetG: targets.fiberG, tint: .green600)
                }
            }
        }
    }

    /// `topFoods`는 `FrequentItem`과 같은 모양이라 같은 컴포넌트를 쓴다.
    private func topFoodsCard(_ stats: DietStats) -> some View {
        GlassCard {
            FrequentItemList(items: stats.topFoods) { _ in }
        }
    }
}
```

- [ ] **Step 6: 하루 화면에서 통계로 잇는다**

`WooriHaru/Views/Diet/DietHomeView.swift` — `@State`에 추가:

```swift
    @State private var showStats = false
```

`.toolbar`의 프로필 버튼 옆에 추가:

```swift
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showStats = true
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .accessibilityLabel("식단 통계")
            }
```

`.navigationDestination(isPresented: $showProfile)` 아래에 추가:

```swift
        .navigationDestination(isPresented: $showStats) {
            DietStatsView()
        }
```

- [ ] **Step 7: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20`
Expected: 전체 PASS

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/DietStatsViewModel.swift WooriHaru/Views/Diet/DietStatsView.swift \
        WooriHaru/Views/Diet/DietHomeView.swift WooriHaruTests/DietStatsTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 식단 기간 통계 화면을 만든다"
```

---

## Task 14: 주의 영양소 종단 검증과 실기동 확인

**서버는 이 누락을 잡아 주지 못한다.** `MealItemRequest`의 세 필드가 `0.0` 기본값이라 앱이 안 보내면 검증 오류 없이 0으로 저장되고, 증상은 「나트륨이 매일 기준 이하」로만 나타난다. 네 경로를 각각 담아 확인 요청까지 값이 살아 있는지 한 자리에서 고정한다.

**Files:**
- Test: `WooriHaruTests/DietTests.swift` (추가)

**Interfaces:**
- Consumes: 앞선 모든 태스크

- [ ] **Step 1: 네 경로 종단 테스트를 쓴다**

`WooriHaruTests/DietTests.swift` 끝에 붙인다:

```swift
/// **주의 영양소 3필드가 경로 끝까지 살아 있는지.** 값이 *표시되는* 자리만 세고 *흘러가는*
/// 자리를 안 세면 「사진으로 기록한 모든 끼니가 나트륨 0」이 재현된다.
@MainActor
struct NutrientPassthroughTests {
    private func assertNutrientsSurvive(
        _ item: MealItemRequest,
        sugar: Double,
        sodium: Double,
        fiber: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let service = FakeDietService()
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .lunch, analysis: nil, service: service
        )
        vm.addItem(item, to: vm.groups[0].id)

        await vm.save()

        let sent = service.confirmRequests.first?.items.first
        #expect(sent?.sugarG == sugar, sourceLocation: sourceLocation)
        #expect(sent?.sodiumMg == sodium, sourceLocation: sourceLocation)
        #expect(sent?.fiberG == fiber, sourceLocation: sourceLocation)
    }

    /// ① 식품DB 검색 경로 — 100g당 값을 앱이 환산한다.
    @Test func 검색_경로() async {
        let food = Food(
            code: "D1", name: "제육볶음", dataset: .dish,
            servingSizeG: 250, servingSizeKnown: true,
            kcalPer100g: 150, carbsPer100g: 12, proteinPer100g: 10, fatPer100g: 7,
            sugarPer100g: 3, sodiumMgPer100g: 400, fiberPer100g: 1.5
        )
        await assertNutrientsSurvive(
            NutritionMath.item(from: food, quantityG: 250),
            sugar: 7.5, sodium: 1000, fiber: 3.75
        )
    }

    /// ② 직접 입력 경로 — 포장지 영양성분표 값을 그대로 담는다.
    @Test func 직접_입력_경로() async {
        await assertNutrientsSurvive(
            NutritionMath.manualItem(
                name: "포장 김밥", quantityG: 230, kcal: 430, carbsG: 60,
                proteinG: 12, fatG: 15, sugarG: 4, sodiumMg: 980, fiberG: 3
            ),
            sugar: 4, sodium: 980, fiber: 3
        )
    }

    /// ③ 자주 먹는 음식 경로 — 서버가 준 값을 다시 계산하지 않는다.
    @Test func 자주_먹는_음식_경로() async {
        let frequent = FrequentItem(
            foodName: "사과", foodCode: "R1", quantityG: 200, kcal: 104,
            carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
            source: .dbMatched, count: 7, lastEatenOn: "2026-07-29"
        )
        await assertNutrientsSurvive(
            NutritionMath.request(from: frequent),
            sugar: 21, sodium: 2, fiber: 4.8
        )
    }

    /// ④ 인식 결과 경로 — 미매칭 항목도 LLM 추정값이 들어온다. 0으로 덮으면 안 된다.
    @Test func 인식_결과_경로() async {
        let analyzed = AnalyzedItem(
            foodName: "김치찌개", foodCode: nil, quantityG: 400, kcal: 320,
            carbsG: 20, proteinG: 18, fatG: 19, sugarG: 5, sodiumMg: 1800, fiberG: 3,
            source: .llmEstimated
        )
        await assertNutrientsSurvive(
            NutritionMath.request(from: analyzed),
            sugar: 5, sodium: 1800, fiber: 3
        )
    }

    /// 수량을 고쳐도 세 필드가 함께 따라온다.
    @Test func 수량_변경_뒤에도_살아_있다() async {
        let analyzed = AnalyzedItem(
            foodName: "김치찌개", foodCode: nil, quantityG: 400, kcal: 320,
            carbsG: 20, proteinG: 18, fatG: 19, sugarG: 5, sodiumMg: 1800, fiberG: 3,
            source: .llmEstimated
        )
        let service = FakeDietService()
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .lunch, analysis: nil, service: service
        )
        vm.addItem(NutritionMath.request(from: analyzed), to: vm.groups[0].id)
        let item = vm.groups[0].items[0]
        vm.updateQuantity(200, of: item, in: vm.groups[0].id)

        await vm.save()

        let sent = try! #require(service.confirmRequests.first?.items.first)
        #expect(sent.sodiumMg == 900)
        #expect(sent.sugarG == 2.5)
        #expect(sent.fiberG == 1.5)
    }

    /// `MealItemRequest`가 7개 필드를 전부 직렬화하는지 — 하나라도 빠지면 서버가 0으로 받는다.
    @Test func 요청_본문에_일곱_필드가_모두_실린다() throws {
        let item = NutritionMath.manualItem(
            name: "테스트", quantityG: 100, kcal: 200, carbsG: 20,
            proteinG: 10, fatG: 5, sugarG: 3, sodiumMg: 400, fiberG: 2
        )
        let json = try #require(String(data: try JSONEncoder().encode(item), encoding: .utf8))

        for key in ["kcal", "carbsG", "proteinG", "fatG", "sugarG", "sodiumMg", "fiberG"] {
            #expect(json.contains("\"\(key)\""), "\(key)가 빠졌다")
        }
    }
}
```

- [ ] **Step 2: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/NutrientPassthroughTests 2>&1 | tail -30`
Expected: 6개 PASS

- [ ] **Step 3: 전체 테스트를 돌린다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30`
Expected: 전체 PASS

- [ ] **Step 4: 실기동으로 확인한다**

**단위 테스트가 잡지 못하는 지점들이다.** 실제 서버에 붙여 확인한다:

1. 사진 2장을 올려 인식 → 확인 화면에 사진별로 항목이 묶여 나오는지
2. 확인 화면에서 중복 항목을 지우고 수량을 바꿔 저장 → 상세의 점수·근거가 **고친 값 기준**인지
3. 하루 요약의 나트륨이 **0이 아닌지** (이 계획에서 가장 중요한 실기동 확인이다)
4. 「직접 추가」로 포장지 값을 넣어 저장 → 하루 나트륨에 반영되는지
5. 검색에서 `servingSizeKnown == false`인 항목(달걀·바나나 등)을 골랐을 때 **수량 칸이 비어 있고 힌트가 뜨는지**
6. 끼니를 삭제한 뒤 하루 요약의 점수·합계·주의 영양소가 갱신되고 피드백이 다시 생성에 걸리는지
7. 몸무게를 고친 뒤 **지난 날짜의 하루 점수가 그대로인지**
8. 서버에 `OPENROUTER_API_KEY`가 없는 환경에서 인식 요청 → "사진 인식만 지금 안 된다" 안내가 뜨고 직접 추가는 정상인지

- [ ] **Step 5: 커밋**

```bash
git add WooriHaruTests/DietTests.swift
git commit -m "test: 주의 영양소가 네 경로 끝까지 살아 있는지 고정한다"
```

---

## 남은 것 (이번 범위 밖)

- **개인정보 처리방침** — 식사 사진이 서버를 거쳐 외부 AI 서비스(OpenRouter 및 하위 프로바이더)로 전송된다. **출시 전 처리방침에 명시가 필요하다.** 코드 작업이 아니므로 태스크로 두지 않았지만 출시 차단 항목이다.
- **사진 상한 조정** — 5장은 서버와 맞춘 초기값이다. 출시 후 평균 장수를 보고 상한과 UI를 조정한다.
- 배우자 공유 · 캘린더 연동 · 과식 수준 통합 표시 · HealthKit 영양 데이터 쓰기 · 체중 자동 동기화 · 바코드·영수증 인식 · 물 섭취 기록 · 식단 추천 · 기간 조언(LLM).
