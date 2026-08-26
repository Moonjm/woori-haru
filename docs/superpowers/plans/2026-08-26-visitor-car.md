# 방문차량 미니앱 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아파트 주차관제 웹(`nxpmsc`)에 앱에서 바로 방문차량을 등록하고, 등록 내역과 입출차 현황을 보는 미니앱을 드로어에 단다.

**Architecture:** 남의 세션 기반 웹사이트를 두드리는 계층을 새로 세운다 — `VisitorCarTransport`(HTTP·쿠키·302)와 `VisitorCarService`(재로그인 직렬화·도메인 변환)로 나누고, 기존 `APIClient`와는 한 줄도 섞지 않는다. JSON API가 없는 잔여시간·동/호는 `VisitorCarHTMLParser`가 순수 함수로 긁는다. 화면 껍데기는 차량·관리비 미니앱(`vehicleDarkTheme`·`GlassCard`)을 그대로 물려받는다.

**Tech Stack:** SwiftUI (iOS 26), `@Observable`, `actor`, Swift Testing (`import Testing`/`@Test`/`#expect`), `Security`(Keychain), `NSRegularExpression`.

**Spec:** `docs/superpowers/specs/2026-08-26-visitor-car-design.md`

## Global Constraints

- **서버는 우리 것이 아니다.** 엔드포인트를 바꿀 수 없다. 스펙에 적힌 규격에서 벗어난 것이 필요해지면 멈추고 보고한다.
- **응답이 302면 세션 만료다 — 401이 아니다.** 리다이렉트를 따라가지 않는다. 따라가면 로그인 HTML이 200으로 돌아와 「파싱 오류」로 둔갑한다.
- **재로그인은 한 번만.** 두 번째도 로그인으로 튕기면 `sessionExpired`를 던진다. 되풀이하면 계정이 잠길 수 있다.
- **날짜 포맷이 엔드포인트별로 다르다.** 등록 내역·등록 폼은 `yyyy-MM-dd`, 진입 현황은 `yyyy-MM-dd HH:mm:ss`. 진입 현황에 날짜만 보내면 **500**이다. 포맷터를 공유하지 않는다.
- **서버가 준 한국어는 다시 쓰지 않는다.** `result` 쿼리·`message` 필드를 그대로 띄운다.
- **비밀번호를 로그에 남기지 않는다.** 요청 바디를 통째로 찍는 코드를 두지 않는다.
- **테스트는 Swift Testing이다** — `import Testing`, `@Test`, `#expect`, `try #require`. XCTest를 새로 쓰지 않는다.
- **네트워크를 타는 테스트를 만들지 않는다.** 남의 서버에 붙는 테스트는 CI에서 죽고, 죽으면 지워진다.
- **주석은 한국어로 「왜」를 적는다.** 코드가 이미 말하는 「무엇」을 반복하지 않는다.
- **시뮬레이터로 앱을 띄우지 않는다.** UI 확인은 사용자가 실기기로 한다. `xcodebuild test`만 실행한다.
- **신규 `.swift`는 프로젝트 등록이 필요 없다.** 앱 타깃·테스트 타깃 모두 폴더 동기화(`6759fbb`)다.
- **문서에 실제 동·호·차량번호·계정을 적지 않는다.** 예시는 `1001`/`0101`/`12가3456`/`10010101`을 쓴다.
- 커밋은 태스크마다. 메시지는 저장소 관례(한국어 한 줄, `feat:`/`refactor:`/`docs:`).
- 브랜치는 `feat/visitor-car` (스펙 커밋 `75a1ac6`이 이미 올라가 있다).

### 테스트 실행

```bash
cd /Users/youngminmoon/Documents/moonjm/woori-haru
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/<SuiteName> 2>&1 | tail -30
```

빌드만 확인할 때:

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

## 파일 구성

| 파일 | 책임 |
|---|---|
| `WooriHaru/Models/VisitorCarModels.swift` | 도메인 타입·디코딩·오류·날짜 포맷 |
| `WooriHaru/Models/VisitorCarValidation.swift` | 차량번호·기간 검증 (순수 함수) |
| `WooriHaru/Services/VisitorCarHTMLParser.swift` | 잔여시간·동/호·로그인 오류 메시지 추출 |
| `WooriHaru/Services/VisitorCarTransport.swift` | 프로토콜 + `URLSession` 구현 (302·쿠키·form 인코딩) |
| `WooriHaru/Services/VisitorCarCredentialStore.swift` | Keychain |
| `WooriHaru/Services/VisitorCarService.swift` | `VisitorCarServing` + 재로그인 직렬화 |
| `WooriHaru/Stores/FrequentCarStore.swift` | 자주 쓰는 차량 (UserDefaults) |
| `WooriHaru/ViewModels/VisitorCarHomeViewModel.swift` | 홈 — 로그인 상태·잔여시간 |
| `WooriHaru/ViewModels/VisitorCarRegisterViewModel.swift` | 등록 |
| `WooriHaru/ViewModels/VisitorCarBookingsViewModel.swift` | 등록 내역 |
| `WooriHaru/ViewModels/VisitorCarEntriesViewModel.swift` | 진입 현황 |
| `WooriHaru/Views/VisitorCar/VisitorCarView.swift` | 홈 |
| `WooriHaru/Views/VisitorCar/VisitorCarLoginCard.swift` | 로그인 카드 |
| `WooriHaru/Views/VisitorCar/VisitorCarRegisterView.swift` | 신규 등록 |
| `WooriHaru/Views/VisitorCar/VisitorCarBookingsView.swift` | 등록 내역 + 상세 시트 |
| `WooriHaru/Views/VisitorCar/VisitorCarEntriesView.swift` | 진입 현황 |
| `WooriHaru/Views/VisitorCar/VisitorCarSettingsView.swift` | 설정 — 자주 쓰는 차량·로그아웃 |
| `WooriHaru/Info.plist` | ATS 예외 |
| `WooriHaru/ContentView.swift` · `Views/Components/SideDrawerView.swift` | 진입점 |

---

## Task 1: 도메인 모델과 JSON 디코딩

**Files:**
- Create: `WooriHaru/Models/VisitorCarModels.swift`
- Test: `WooriHaruTests/VisitorCarModelTests.swift`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `VisitorCarHousehold`, `VisitorCarInsertType`, `VisitorCarEntryStatus`, `VisitorCarBooking`, `VisitorCarEntry`, `VisitorCarPage<T>`, `VisitorCarPageResponse<T>`, `VisitorCarResult`, `VisitorCarError`, `VisitorCarDateFormat.day`, `VisitorCarDateFormat.second`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarModelTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarModelTests {

    /// 실제 `/nxpmsc/web/book-car/pageList` 응답을 그대로 옮긴 것.
    /// 필드가 하나라도 어긋나면 디코딩이 깨진다.
    ///
    /// **유닉스 초를 눈으로 읽지 말 것.** `1784300400` = 2026-07-18 00:00:00 KST,
    /// `1784386799` = 같은 날 23:59:59다. 기대값을 고칠 일이 생기면 `date -r`로 먼저 검산한다.
    static let bookingJSON = """
    {"data":{"content":[{"id":25752,"compName":"1001","deptName":"0101","name":"",
      "carNo":"12가3456","tel":"","startDate":1784300400,"endDate":1784386799,
      "updateDate":1784356046,"userName":"10010101","insertType":"W","address":"택배"}],
      "totalElements":1,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
    """

    /// 실제 `/nxpmsc/web/car/reserved-vehicle-entry-status-by-generation-page` 응답.
    /// **`message: "200"`이 붙는다** — 등록 내역 쪽에는 없다. 읽지 않고 흘린다.
    static let entryJSON = """
    {"message":"200","data":{"content":[
      {"id":354751,"inDate":1784357197,"outDate":1784374505,"outChk":2,
       "carNo":"12가3456","name":"","startDate":1784300400,"endDate":1784386799,
       "updateDate":1784356046},
      {"id":354752,"inDate":1784380000,"outDate":null,"outChk":0,
       "carNo":"12가3456","name":"","startDate":1784300400,"endDate":1784386799,
       "updateDate":1784356046}],
      "totalElements":2,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
    """

    @Test func 등록_내역을_디코딩한다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarBooking>.self, from: Data(Self.bookingJSON.utf8))
            .data
        let booking = try #require(page.content.first)

        #expect(page.totalElements == 1)
        #expect(booking.id == 25752)
        #expect(booking.carNo == "12가3456")
        #expect(booking.dong == "1001")
        #expect(booking.ho == "0101")
        #expect(booking.registrant == "10010101")
        #expect(booking.insertType == .preVisit)
        // `address`가 방문사유다. 이름이 어긋나 있어 모델에서 바꿔 받는다.
        #expect(booking.visitReason == "택배")
        #expect(booking.startDate == Date(timeIntervalSince1970: 1784300400))
        #expect(booking.updateDate == Date(timeIntervalSince1970: 1784356046))
    }

    /// 사이트가 새 등록구분을 늘려도 화면이 죽지 않아야 한다.
    @Test func 모르는_등록구분은_unknown이다() {
        #expect(VisitorCarInsertType(rawValue: "Z") == nil)
        #expect(VisitorCarInsertType.from("Z") == .unknown)
        #expect(VisitorCarInsertType.from("K") == .kiosk)
        #expect(VisitorCarInsertType.kiosk.label == "키오스크")
    }

    @Test func 진입_현황을_디코딩한다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(Self.entryJSON.utf8))
            .data

        #expect(page.content.count == 2)
        #expect(page.content[0].status == .exited)
        #expect(page.content[0].outDate == Date(timeIntervalSince1970: 1784374505))
    }

    /// **아직 안 나간 차는 `outDate`가 `null`이다.** 0으로 접으면 1970년에 나간 차가 된다.
    @Test func 출차_전이면_outDate가_nil이다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(Self.entryJSON.utf8))
            .data
        let parked = page.content[1]

        #expect(parked.outDate == nil)
        #expect(parked.status == .entered)
    }

    /// 주차시간은 저장하지 않고 그릴 때 센다 — 안 나간 차는 계속 흘러야 한다.
    @Test func 주차시간은_출차_전이면_지금까지_센다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(Self.entryJSON.utf8))
            .data
        let now = Date(timeIntervalSince1970: 1784383600)

        #expect(page.content[0].parkingSeconds(now: now) == 1784374505 - 1784357197)
        #expect(page.content[1].parkingSeconds(now: now) == 1784383600 - 1784380000)
    }

    /// `outChk`가 0~5 밖이면 화면에 빈칸을 둔다 — 웹의 `default` 분기와 같게.
    @Test func 모르는_차량상태는_nil이다() throws {
        let json = """
        {"data":{"content":[{"id":1,"inDate":1784357197,"outDate":null,"outChk":9,
          "carNo":"12가3456","name":"","startDate":1,"endDate":2,"updateDate":3}],
          "totalElements":1,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
        """
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(json.utf8))
            .data

        #expect(page.content[0].status == nil)
    }

    @Test func 등록_응답의_성공을_가른다() throws {
        let ok = try JSONDecoder().decode(
            VisitorCarResult.self,
            from: Data(#"{"result":"success","message":"성공적으로 등록되었습니다."}"#.utf8)
        )
        let ng = try JSONDecoder().decode(
            VisitorCarResult.self,
            from: Data(#"{"result":"fail","message":"입차 후 수정/삭제 불가능합니다."}"#.utf8)
        )

        #expect(ok.isSuccess)
        #expect(!ng.isSuccess)
        #expect(ng.message == "입차 후 수정/삭제 불가능합니다.")
    }

    /// **두 엔드포인트의 날짜 형식이 다르다.** 진입 현황에 날짜만 보내면 500이 떨어진다.
    @Test func 날짜_포맷이_엔드포인트별로_갈린다() {
        let date = Date(timeIntervalSince1970: 1784300400) // 2026-07-18 00:00:00 KST

        #expect(VisitorCarDateFormat.day.string(from: date) == "2026-07-18")
        #expect(VisitorCarDateFormat.second.string(from: date) == "2026-07-18 00:00:00")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarModelTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarPageResponse' in scope`.

- [ ] **Step 3: 모델을 만든다**

`WooriHaru/Models/VisitorCarModels.swift`:

```swift
import Foundation

// MARK: - 날짜

/// 사이트가 요구하는 날짜 문자열. **엔드포인트별로 형식이 다르다** —
/// 등록 내역·등록 폼은 날짜만, 진입 현황은 시각까지다. 날짜만 보내면 진입 현황이 500으로 죽는다.
/// 하나로 합치려는 순간 한쪽이 조용히 깨지므로 둘로 나눠 둔다.
enum VisitorCarDateFormat {
    static let day = make("yyyy-MM-dd")
    static let second = make("yyyy-MM-dd HH:mm:ss")

    /// 서버는 한국 시각으로만 말한다. 기기 시간대에 끌려가면 자정 근처에서 하루가 어긋난다.
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - 세대

/// 등록 폼에 **되돌려 보내야** 하는 값들. 사이트가 등록 모달 HTML에 박아서 준다.
struct VisitorCarHousehold: Codable, Equatable, Sendable {
    let dong: String
    let ho: String
    let parkingLot: String
    let parkingZone: String
}

// MARK: - 등록 내역

enum VisitorCarInsertType: String, Sendable, Equatable {
    case kiosk = "K"
    case preVisit = "W"
    case visit = "L"
    case booking = "B"
    case approvedVisit = "N"
    case unknown = "?"

    /// 사이트가 새 구분을 늘려도 디코딩이 죽지 않게 한다 — 화면에 한 줄 덜 보일 뿐이다.
    static func from(_ raw: String) -> VisitorCarInsertType {
        VisitorCarInsertType(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .kiosk: "키오스크"
        case .preVisit: "사전방문"
        case .visit: "방문"
        case .booking: "예약차량"
        case .approvedVisit: "방문차량(승인)"
        case .unknown: ""
        }
    }
}

struct VisitorCarBooking: Identifiable, Equatable, Sendable {
    let id: Int
    let carNo: String
    let name: String
    let tel: String
    let dong: String
    let ho: String
    let startDate: Date
    let endDate: Date
    let updateDate: Date?
    let registrant: String
    let insertType: VisitorCarInsertType
    /// 서버 필드 이름은 `address`다. **주소가 아니라 방문사유다.**
    let visitReason: String
}

extension VisitorCarBooking: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, carNo, name, tel, compName, deptName
        case startDate, endDate, updateDate, userName, insertType, address
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        // 이름·전화·사유는 **빈 문자열로 오거나 아예 빠진다.** 세대 계정이 채우지 않는 칸이다.
        carNo = try c.decodeIfPresent(String.self, forKey: .carNo) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        tel = try c.decodeIfPresent(String.self, forKey: .tel) ?? ""
        dong = try c.decodeIfPresent(String.self, forKey: .compName) ?? ""
        ho = try c.decodeIfPresent(String.self, forKey: .deptName) ?? ""
        startDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .startDate))
        endDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .endDate))
        updateDate = try c.decodeIfPresent(TimeInterval.self, forKey: .updateDate)
            .map(Date.init(timeIntervalSince1970:))
        registrant = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        insertType = .from(try c.decodeIfPresent(String.self, forKey: .insertType) ?? "")
        visitReason = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
    }
}

// MARK: - 진입 현황

enum VisitorCarEntryStatus: Int, Sendable, Equatable {
    case entered = 0
    case readyToExit = 1
    case exited = 2
    case forcedExit = 3
    case unidentifiedExit = 4
    case faultExit = 5

    var label: String {
        switch self {
        case .entered: "입차"
        case .readyToExit: "출차대기"
        case .exited: "출차"
        case .forcedExit: "강제출차"
        case .unidentifiedExit: "미확인출차"
        case .faultExit: "장애출차"
        }
    }

    /// 아직 주차장 안에 있는가. 진입 현황이 「몇 시간째」를 흘려보낼지 가른다.
    var isParked: Bool { self == .entered || self == .readyToExit }
}

struct VisitorCarEntry: Identifiable, Equatable, Sendable {
    let id: Int
    let inDate: Date
    /// **아직 안 나갔으면 `nil`이다.** 0으로 접으면 1970년에 나간 차가 된다.
    let outDate: Date?
    /// `outChk`가 0~5 밖이면 `nil`. 화면은 빈칸을 둔다 — 웹의 `default` 분기와 같다.
    let status: VisitorCarEntryStatus?
    let carNo: String
    let name: String
    let startDate: Date
    let endDate: Date
    let updateDate: Date?

    /// 주차시간. 서버 응답에 `parkingTime` 필드가 있지만 **웹도 쓰지 않는다** — 렌더러가
    /// 매번 다시 센다. 안 나간 차는 화면이 떠 있는 동안 계속 늘어야 해서 저장할 수가 없다.
    func parkingSeconds(now: Date) -> TimeInterval {
        (outDate ?? now).timeIntervalSince(inDate)
    }
}

extension VisitorCarEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, inDate, outDate, outChk, carNo, name, startDate, endDate, updateDate
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        inDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .inDate))
        outDate = try c.decodeIfPresent(TimeInterval.self, forKey: .outDate)
            .map(Date.init(timeIntervalSince1970:))
        status = try c.decodeIfPresent(Int.self, forKey: .outChk).flatMap(VisitorCarEntryStatus.init(rawValue:))
        carNo = try c.decodeIfPresent(String.self, forKey: .carNo) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        startDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .startDate))
        endDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .endDate))
        updateDate = try c.decodeIfPresent(TimeInterval.self, forKey: .updateDate)
            .map(Date.init(timeIntervalSince1970:))
    }
}

// MARK: - 페이지

/// 스프링 `Page` 껍데기. 두 목록이 같은 모양이라 하나로 받는다.
struct VisitorCarPage<T: Decodable & Sendable>: Decodable, Sendable {
    let content: [T]
    let totalElements: Int
    let totalPages: Int
    let number: Int
    let last: Bool
}

/// **진입 현황 응답에는 `message: "200"`이 더 붙는다.** 읽지 않는다 —
/// 두 엔드포인트를 같은 디코더로 다루기 위해서다.
struct VisitorCarPageResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let data: VisitorCarPage<T>
}

// MARK: - 등록·수정·삭제 응답

struct VisitorCarResult: Decodable, Sendable {
    let result: String
    let message: String?

    var isSuccess: Bool { result == "success" }
}

// MARK: - 오류

enum VisitorCarError: Error, LocalizedError, Equatable {
    /// 저장된 자격증명이 없다. 화면이 로그인 카드로 되돌아간다.
    case notLoggedIn
    /// 로그인 시도가 거절됐다. 문자열은 **서버가 준 한국어 그대로**다.
    case loginFailed(String)
    /// 재로그인까지 했는데도 로그인 페이지로 튕겼다.
    case sessionExpired
    /// `result != "success"`. 문자열은 서버 `message` 그대로.
    case rejected(String)
    case remainingTimeUnavailable
    case householdUnavailable
    case server(Int)
    case network(String)
    case keychain(Int)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "로그인이 필요합니다."
        case .loginFailed(let message): message
        case .sessionExpired: "다시 로그인해 주세요."
        case .rejected(let message): message
        case .remainingTimeUnavailable: "잔여시간을 불러오지 못했습니다."
        case .householdUnavailable: "세대 정보를 불러오지 못했습니다."
        case .server(let code): "서버에 연결하지 못했습니다. (\(code))"
        // **실린 문구를 그대로 쓴다.** 버리면 `network(String)`의 값이 죽은 짐이 되고,
        // 「연결 실패」와 「응답을 못 읽음」이 화면에서 같은 말이 된다.
        case .network(let message): message
        case .keychain(let status): "계정을 저장하지 못했습니다. (\(status))"
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarModelTests 2>&1 | tail -30`

Expected: 8개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/VisitorCarModels.swift WooriHaruTests/VisitorCarModelTests.swift
git commit -m "feat: 방문차량 도메인 모델과 응답 디코딩을 만든다"
```

---

## Task 2: HTML 파서

JSON API가 없는 잔여시간·동/호를 페이지에서 긁는다. **이 기능에서 가장 부서지기 쉬운 자리다** — 사이트가 마크업을 바꾸면 죽는다. 그래서 순수 함수로 떼어내 실제 HTML 조각으로 테스트를 건다.

**Files:**
- Create: `WooriHaru/Services/VisitorCarHTMLParser.swift`
- Test: `WooriHaruTests/VisitorCarHTMLParserTests.swift`

**Interfaces:**
- Consumes: `VisitorCarHousehold` (Task 1)
- Produces: `VisitorCarHTMLParser.remainingMinutes(html:) -> Int?`, `VisitorCarHTMLParser.household(html:) -> VisitorCarHousehold?`, `VisitorCarHTMLParser.loginErrorMessage(location:) -> String?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarHTMLParserTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarHTMLParserTests {

    /// 실제 `/nxpmsc/book-car` 응답에서 잘라 온 조각. 앞뒤 잡동사니를 남겨 둔 이유는
    /// **파서가 페이지 통째에서 찾아내야** 하기 때문이다 — 깔끔한 한 줄만 주면 시험이 안 된다.
    static let bookCarHTML = """
    <li class="nav-item" data-toggle="tooltip" title="충전 잔여시간">
      <a class="nav-link" href="#"> <i class="fa fa-fw fa-money"></i>
        <span class="nav-link-text">100시 0분 남음</span>
      </a>
    </li>
    <input type="hidden" id="bookcarSiteName" value="none">
    <input type="hidden" id="reservedVehiclePointValue" value="6000"/>
    <table id="bookCarTable" width="100%"></table>
    """

    /// 실제 `/nxpmsc/book-car/getOriginal` 응답에서 잘라 온 조각.
    /// **`parkingZone`의 `<option>`은 줄바꿈으로 쪼개져 있다** — 실제 응답이 그렇다.
    static let registerFormHTML = """
    <form method="post" class="col-lg-12" id="bookCar" action="/nxpmsc/book-car/add">
      <input type="hidden" name="id" id="id" value="" />
      <input type="hidden" name="siteName" id="siteName" value="none" />
      <select class="form-control" name="parkingLot" id="parkingLot">
        <option value="">선택</option>
        <option value="1" selected="selected">○○아파트</option>
      </select>
      <select class="form-control" name="parkingZone" id="parkingZone">
        <option value="">전체</option>
        <option
            value="2"
            selected="selected">기본 구역</option>
      </select>
      <input class="form-control" type="text" name="name" id="name" value="" />
      <input class="form-control" type="text" name="compName" id="compName" value="1001" readonly="readonly" />
      <input class="form-control" type="text" name="deptName" id="deptName" value="0101" readonly="readonly" />
    </form>
    """

    // MARK: - 잔여시간

    /// **화면에 보이는 「100시 0분 남음」이 아니라 이 숫자를 읽는다.**
    /// 문구는 현장마다 갈리지만 히든 필드는 값 하나다.
    @Test func 잔여시간을_분으로_읽는다() {
        #expect(VisitorCarHTMLParser.remainingMinutes(html: Self.bookCarHTML) == 6000)
    }

    /// 잔여시간이 바닥나면 음수가 온다. 웹은 「N분 초과 사용하였습니다」 모달을 띄운다.
    @Test func 초과_사용은_음수로_온다() {
        let html = #"<input type="hidden" id="reservedVehiclePointValue" value="-120"/>"#
        #expect(VisitorCarHTMLParser.remainingMinutes(html: html) == -120)
    }

    /// 속성 순서는 보장되지 않는다 — `value`가 `id`보다 앞설 수도 있다.
    @Test func 속성_순서가_뒤바뀌어도_읽는다() {
        let html = #"<input value="30" type="hidden" id="reservedVehiclePointValue"/>"#
        #expect(VisitorCarHTMLParser.remainingMinutes(html: html) == 30)
    }

    /// **마크업이 바뀌면 크래시가 아니라 nil이다.** 화면은 「잔여시간을 불러오지 못했습니다」를 띄운다.
    @Test func 필드가_없으면_nil이다() {
        #expect(VisitorCarHTMLParser.remainingMinutes(html: "<html><body>로그인</body></html>") == nil)
    }

    // MARK: - 세대 정보

    @Test func 동_호_주차장_구역을_읽는다() throws {
        let household = try #require(VisitorCarHTMLParser.household(html: Self.registerFormHTML))

        #expect(household.dong == "1001")
        #expect(household.ho == "0101")
        #expect(household.parkingLot == "1")
        // 선택된 `<option>`을 골라야 한다 — 첫 번째(빈 값 "전체")를 집으면 등록이 엉뚱한 구역으로 간다.
        #expect(household.parkingZone == "2")
    }

    /// **동·호를 못 읽으면 등록을 막는다** — 빈 동·호로 보내면 다른 세대 이름으로 예약이 들어갈 수 있다.
    @Test func 동이_없으면_nil이다() {
        let html = #"<input name="deptName" value="0101" />"#
        #expect(VisitorCarHTMLParser.household(html: html) == nil)
    }

    /// 주차장·구역은 사이트가 하나뿐이면 `<select>` 없이 올 수도 있다. 그때는 `1`로 둔다 —
    /// 등록 폼이 이 값을 반드시 요구하고, 실제 응답의 기본값이 `1`이다.
    @Test func 주차장_select가_없으면_1로_둔다() throws {
        let html = """
        <input name="compName" value="1001" />
        <input name="deptName" value="0101" />
        """
        let household = try #require(VisitorCarHTMLParser.household(html: html))

        #expect(household.parkingLot == "1")
        #expect(household.parkingZone == "1")
    }

    // MARK: - 로그인 오류

    /// 로그인 성공·실패가 **둘 다 302**다. `Location`으로 갈라야 하고,
    /// 실패 쪽 `result`에는 **이미 사용자용 한국어**가 실려 온다.
    @Test func 로그인_실패_메시지를_뽑는다() {
        let location = "http://example.org/nxpmsc/login;jsessionid=ABC?result="
            + "%EC%95%84%EC%9D%B4%EB%94%94+%EB%98%90%EB%8A%94+"
            + "%EB%B9%84%EB%B0%80%EB%B2%88%ED%98%B8%EA%B0%80+"
            + "%EC%9E%98%EB%AA%BB%EB%90%98%EC%97%88%EC%8A%B5%EB%8B%88%EB%8B%A4."

        #expect(VisitorCarHTMLParser.loginErrorMessage(location: location)
                == "아이디 또는 비밀번호가 잘못되었습니다.")
    }

    /// 성공 쪽 `Location`에는 `result`가 없다.
    @Test func 성공_리다이렉트에는_메시지가_없다() {
        #expect(VisitorCarHTMLParser.loginErrorMessage(location: "http://example.org/nxpmsc/book-car") == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarHTMLParserTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarHTMLParser' in scope`.

- [ ] **Step 3: 파서를 만든다**

`WooriHaru/Services/VisitorCarHTMLParser.swift`:

```swift
import Foundation

/// 사이트가 JSON으로 주지 않는 값을 페이지에서 긁는다.
///
/// **여기가 이 기능에서 가장 부서지기 쉬운 자리다.** 남의 사이트 마크업에 기대고 있어서
/// 저쪽이 화면을 손보면 조용히 죽는다. 그래서 서비스에서 떼어내 순수 함수로 두고
/// 실제 응답 조각으로 테스트를 건다 — 깨졌을 때 어디가 깨졌는지 테스트가 먼저 말하게 한다.
///
/// **HTML 파서를 의존성으로 들이지 않는다.** 찾는 게 히든 인풋 넷뿐이라 정규식으로 족하다.
enum VisitorCarHTMLParser {

    /// 충전 잔여시간(분). 바닥나면 **음수로 온다.**
    static func remainingMinutes(html: String) -> Int? {
        let id = "reservedVehiclePointValue"
        // 속성 순서가 보장되지 않아 양쪽을 다 본다.
        let patterns = [
            #"id="\#(id)"[^>]*?value="(-?\d+)""#,
            #"value="(-?\d+)"[^>]*?id="\#(id)""#,
        ]
        for pattern in patterns {
            if let raw = firstCapture(in: html, pattern: pattern) { return Int(raw) }
        }
        return nil
    }

    /// 등록 폼에 되돌려 보낼 세대 정보.
    ///
    /// **동·호가 하나라도 없으면 `nil`이다.** 빈 값으로 등록하면 다른 세대 이름으로
    /// 예약이 들어갈 수 있어, 반쯤 읽은 결과를 돌려주느니 실패를 알리는 편이 낫다.
    static func household(html: String) -> VisitorCarHousehold? {
        guard let dong = inputValue(in: html, name: "compName"), !dong.isEmpty,
              let ho = inputValue(in: html, name: "deptName"), !ho.isEmpty
        else { return nil }

        return VisitorCarHousehold(
            dong: dong,
            ho: ho,
            // 사이트가 하나뿐이면 `<select>`가 통째로 빠질 수 있다. 실제 응답의 기본값이 `1`이다.
            parkingLot: selectedOptionValue(in: html, name: "parkingLot") ?? "1",
            parkingZone: selectedOptionValue(in: html, name: "parkingZone") ?? "1"
        )
    }

    /// 로그인 실패 리다이렉트의 `result` 쿼리. **이미 사용자용 한국어라 그대로 띄운다.**
    static func loginErrorMessage(location: String) -> String? {
        guard let components = URLComponents(string: location),
              let raw = components.queryItems?.first(where: { $0.name == "result" })?.value,
              !raw.isEmpty
        else { return nil }

        // `URLComponents`는 퍼센트 인코딩만 되돌린다 — 폼 인코딩의 `+`는 직접 공백으로 바꾼다.
        return raw.replacingOccurrences(of: "+", with: " ")
    }

    // MARK: - Private

    private static func inputValue(in html: String, name: String) -> String? {
        firstCapture(in: html, pattern: #"name="\#(name)"[^>]*?value="([^"]*)""#)
    }

    /// `<select name="…">` 블록 안에서 `selected`가 붙은 `<option>`의 값.
    /// **첫 번째 옵션을 집으면 안 된다** — 그 자리는 「선택」·「전체」 같은 빈 값이다.
    private static func selectedOptionValue(in html: String, name: String) -> String? {
        guard let block = firstMatch(in: html, pattern: #"<select[^>]*name="\#(name)"[\s\S]*?</select>"#)
        else { return nil }

        // 실제 응답은 `<option`과 `value=` 사이가 줄바꿈으로 쪼개져 있다 — `[\s\S]`로 받는다.
        return firstCapture(in: block, pattern: #"<option[\s\S]*?value="([^"]*)"[\s\S]*?selected"#)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarHTMLParserTests 2>&1 | tail -30`

Expected: 9개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/VisitorCarHTMLParser.swift WooriHaruTests/VisitorCarHTMLParserTests.swift
git commit -m "feat: 잔여시간과 세대 정보를 페이지에서 긁는 파서를 만든다"
```

---

## Task 3: 입력 검증과 폼 인코딩

**Files:**
- Create: `WooriHaru/Models/VisitorCarValidation.swift`
- Test: `WooriHaruTests/VisitorCarValidationTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `VisitorCarValidation.carNoError(_:) -> String?`, `VisitorCarValidation.periodError(start:end:) -> String?`, `VisitorCarFormEncoder.encode(_:) -> Data`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarValidationTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarValidationTests {

    // MARK: - 차량번호

    /// 웹 JS(`book-car2.js`)와 같은 규칙. **서버가 뭘 막는지 확인하지 않았으므로 앱이 먼저 막는다.**
    @Test func 멀쩡한_차량번호는_통과한다() {
        #expect(VisitorCarValidation.carNoError("12가3456") == nil)
        #expect(VisitorCarValidation.carNoError("123가4567") == nil)
    }

    @Test func 빈_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("") == "차량번호를 입력해 주세요.")
    }

    @Test func 공백이_든_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("12가 3456") == "차량번호에 공백을 넣을 수 없습니다.")
    }

    @Test func 특수문자가_든_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("12가/3456") == "차량번호에 특수문자를 넣을 수 없습니다.")
        #expect(VisitorCarValidation.carNoError("12가3456!") == "차량번호에 특수문자를 넣을 수 없습니다.")
    }

    @Test func 아홉_자를_넘는_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("1234가5678") == nil)          // 9자
        #expect(VisitorCarValidation.carNoError("12345가6789") == "차량번호는 9자를 넘을 수 없습니다.")
    }

    // MARK: - 기간

    @Test func 같은_날은_통과한다() {
        let day = Date(timeIntervalSince1970: 1784300400)
        #expect(VisitorCarValidation.periodError(start: day, end: day) == nil)
    }

    @Test func 종료일이_시작일보다_앞서면_막는다() {
        let start = Date(timeIntervalSince1970: 1784300400)
        let end = start.addingTimeInterval(-86_400)
        #expect(VisitorCarValidation.periodError(start: start, end: end) == "종료일이 시작일보다 앞설 수 없습니다.")
    }

    /// **날짜만 견준다.** 서버가 시각을 00:00:00/23:59:59로 채우므로 같은 날 안의 시각 차이는 뜻이 없다.
    @Test func 같은_날이면_시각이_거꾸로여도_통과한다() {
        let start = Date(timeIntervalSince1970: 1784300400 + 3600 * 20)
        let end = Date(timeIntervalSince1970: 1784300400 + 3600)
        #expect(VisitorCarValidation.periodError(start: start, end: end) == nil)
    }

    // MARK: - 폼 인코딩

    /// **`+`·`&`·`=`를 반드시 인코딩한다** — 안 하면 값에 든 문자가 필드 구분자로 읽힌다.
    @Test func 폼_바디를_인코딩한다() {
        let body = String(decoding: VisitorCarFormEncoder.encode(["b": "2", "a": "1"]), as: UTF8.self)
        // 키 순서를 정렬해 고정한다 — 그래야 테스트가 붙잡을 수 있다.
        #expect(body == "a=1&b=2")
    }

    @Test func 한글과_구분자를_퍼센트로_인코딩한다() {
        let body = String(decoding: VisitorCarFormEncoder.encode(["carNo": "12가3456"]), as: UTF8.self)
        #expect(body == "carNo=12%EA%B0%803456")
    }

    @Test func 값에_든_구분자가_필드를_쪼개지_않는다() {
        let body = String(decoding: VisitorCarFormEncoder.encode(["x": "a&b=c+d"]), as: UTF8.self)
        #expect(body == "x=a%26b%3Dc%2Bd")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarValidationTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarValidation' in scope`.

- [ ] **Step 3: 구현한다**

`WooriHaru/Models/VisitorCarValidation.swift`:

```swift
import Foundation

/// 등록 폼 입력 검증. 웹 JS(`book-car2.js`)의 규칙을 그대로 옮겼다.
///
/// **서버가 무엇을 막는지 확인하지 않았다.** 등록 한 건을 실제로 넣어 본 것이 전부라
/// 거절 규칙을 모른다. 그래서 앱이 먼저 막는다 — 왕복 한 번을 아끼고, 무엇이 잘못됐는지도
/// 서버의 알 수 없는 메시지 대신 이쪽 문구로 말한다.
enum VisitorCarValidation {
    /// 웹 JS의 `checkSpecial` 정규식과 같은 집합.
    private static let forbidden = CharacterSet(charactersIn: #"`~!@#$%^&*|\'";:/?"#)

    static func carNoError(_ value: String) -> String? {
        if value.isEmpty { return "차량번호를 입력해 주세요." }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return "차량번호에 공백을 넣을 수 없습니다."
        }
        if value.rangeOfCharacter(from: forbidden) != nil {
            return "차량번호에 특수문자를 넣을 수 없습니다."
        }
        if value.count > 9 { return "차량번호는 9자를 넘을 수 없습니다." }
        return nil
    }

    /// **날짜만 견준다.** 서버가 시각을 00:00:00/23:59:59로 채우므로 같은 날 안의 시각 차이는 뜻이 없다.
    static func periodError(start: Date, end: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        if calendar.startOfDay(for: end) < calendar.startOfDay(for: start) {
            return "종료일이 시작일보다 앞설 수 없습니다."
        }
        return nil
    }
}

/// `application/x-www-form-urlencoded` 바디를 만든다.
///
/// **`URLComponents`를 쓰지 않는다.** 그쪽은 `+`·`&`·`=`를 값 안에서 살려 두는데,
/// 그러면 차량번호나 방문사유에 든 문자가 필드 구분자로 읽힌다.
enum VisitorCarFormEncoder {
    /// 퍼센트 인코딩에서 살려 둘 문자. RFC 3986의 unreserved 집합이다.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ fields: [String: String]) -> Data {
        let body = fields
            // 키 순서를 정렬해 고정한다 — 딕셔너리 순서는 실행마다 달라 테스트가 붙잡을 수 없다.
            .sorted { $0.key < $1.key }
            .map { key, value in "\(escape(key))=\(escape(value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarValidationTests 2>&1 | tail -30`

Expected: 11개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/VisitorCarValidation.swift WooriHaruTests/VisitorCarValidationTests.swift
git commit -m "feat: 차량번호·기간 검증과 폼 인코더를 만든다"
```

---

## Task 4: 저수준 통신 계층과 ATS 예외

302를 응답 그대로 손에 쥐는 것이 이 태스크의 전부다. **리다이렉트를 따라가면 이 기능은 조용히 틀린다.**

**Files:**
- Create: `WooriHaru/Services/VisitorCarTransport.swift`
- Modify: `WooriHaru/Info.plist`
- Test: `WooriHaruTests/VisitorCarTransportTests.swift`

**Interfaces:**
- Consumes: `VisitorCarError`(Task 1), `VisitorCarFormEncoder`(Task 3)
- Produces:
  - `struct VisitorCarHTTPResponse { let status: Int; let location: String?; let body: Data; var text: String; var isLoginRedirect: Bool }`
  - `protocol VisitorCarTransport: Sendable` — `form(path:fields:)`, `json(path:body:)`, `page(path:)`, `clearCookies()`
  - `final class VisitorCarHTTPTransport: VisitorCarTransport`
  - `enum VisitorCarSite { static let host: String; static let base: String }`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarTransportTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarTransportTests {

    private func response(status: Int, location: String?) -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: status, location: location, body: Data())
    }

    /// **세션 만료가 401로 오지 않는다.** 302 + `Location: …/nxpmsc/login`이다.
    /// 이걸 못 가리면 로그인 HTML을 JSON으로 읽으려다 「파싱 오류」로 둔갑한다.
    @Test func 로그인_리다이렉트를_알아본다() {
        let expired = response(
            status: 302,
            location: "http://dasanesesang.iptime.org/nxpmsc/login;jsessionid=ABC?result=x"
        )
        #expect(expired.isLoginRedirect)
    }

    /// 로그인 **성공**도 302다. 여기로 가면 세션이 살아 있다는 뜻이다.
    @Test func 성공_리다이렉트는_로그인이_아니다() {
        let ok = response(status: 302, location: "http://dasanesesang.iptime.org/nxpmsc/book-car")
        #expect(!ok.isLoginRedirect)
    }

    @Test func 이백_응답은_로그인이_아니다() {
        #expect(!response(status: 200, location: nil).isLoginRedirect)
    }

    /// `Location`이 상대 경로로 올 수도 있다 — 스프링 버전에 따라 갈린다.
    @Test func 상대경로_리다이렉트도_알아본다() {
        #expect(response(status: 302, location: "/nxpmsc/login").isLoginRedirect)
    }

    /// `book-car`가 경로 **뒤쪽**에 들어간 주소를 로그인으로 오해하면 안 된다.
    @Test func 로그인이_아닌_경로를_오해하지_않는다() {
        #expect(!response(status: 302, location: "/nxpmsc/book-car/login-history").isLoginRedirect)
    }

    @Test func 본문을_문자열로_읽는다() {
        let html = VisitorCarHTTPResponse(status: 200, location: nil, body: Data("<html>가</html>".utf8))
        #expect(html.text == "<html>가</html>")
    }

    /// 경로를 컨텍스트에 붙여 절대 URL을 만든다. `/web` 갈래도 같은 규칙이다.
    @Test func 사이트_경로를_만든다() {
        #expect(VisitorCarSite.url(path: "/do-login")?.absoluteString
                == "http://dasanesesang.iptime.org/nxpmsc/do-login")
        #expect(VisitorCarSite.url(path: "/web/book-car/pageList")?.absoluteString
                == "http://dasanesesang.iptime.org/nxpmsc/web/book-car/pageList")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarTransportTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarHTTPResponse' in scope`.

- [ ] **Step 3: 통신 계층을 만든다**

`WooriHaru/Services/VisitorCarTransport.swift`:

```swift
import Foundation

/// 대상 사이트 주소. **HTTP다** — `Info.plist`의 ATS 예외가 이 호스트에 걸려 있다.
enum VisitorCarSite {
    static let host = "dasanesesang.iptime.org"
    static let base = "http://\(host)/nxpmsc"

    static func url(path: String) -> URL? {
        URL(string: base + path)
    }
}

/// 한 번의 왕복 결과. **302를 그대로 들고 온다** — 따라가지 않는 것이 이 계층의 요점이다.
struct VisitorCarHTTPResponse: Sendable {
    let status: Int
    let location: String?
    let body: Data

    var text: String { String(decoding: body, as: UTF8.self) }

    /// 세션이 끊겼는가. 사이트는 **401을 주지 않는다** — JSON 엔드포인트까지
    /// 302로 로그인 페이지를 가리킨다. 상대 경로로 올 수도 있어 경로만 본다.
    var isLoginRedirect: Bool {
        guard status == 302, let location else { return false }
        let path = URLComponents(string: location)?.path ?? location
        // `;jsessionid=…`가 경로에 붙어 오므로 정확히 같기를 요구하지 않는다.
        // 다만 `book-car/login-history` 같은 것을 삼키지 않도록 접두만 본다.
        return path == "/nxpmsc/login" || path.hasPrefix("/nxpmsc/login;")
    }
}

/// 사이트를 두드리는 저수준 계층. **테스트는 이 자리를 가짜로 바꾼다.**
protocol VisitorCarTransport: Sendable {
    /// `application/x-www-form-urlencoded` POST. 로그인·등록·수정·삭제가 이 모양이다.
    func form(path: String, fields: [String: String]) async throws -> VisitorCarHTTPResponse
    /// JSON POST. 목록 조회 둘이 이 모양이다.
    func json(path: String, body: any Encodable & Sendable) async throws -> VisitorCarHTTPResponse
    /// HTML GET. 잔여시간을 긁을 때 쓴다.
    func page(path: String) async throws -> VisitorCarHTTPResponse
    /// 로그아웃 — 쿠키를 버린다.
    func clearCookies() async
}

/// **리다이렉트를 따라가지 않게 막는 델리게이트. 이게 이 계층의 핵심이다.**
///
/// `URLSession`은 기본으로 302를 따라가는데, 그러면 세션이 끊겼을 때 로그인 **HTML이
/// 200으로** 돌아온다. JSON 디코딩이 실패하면서 「파싱 오류」로 보이고 진짜 원인은
/// 어디에도 안 남는다. `nil`을 돌려주면 302가 응답 그대로 손에 들어온다.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

final class VisitorCarHTTPTransport: VisitorCarTransport {
    private let session: URLSession
    private let delegate = NoRedirectDelegate()

    init() {
        // **`.ephemeral`이다.** 쿠키가 이 세션 안에만 살아서 앱 공용 저장소
        // (`SessionManager`가 쓰는 `.shared`)와 자동으로 갈린다 — 남의 사이트
        // `JSESSIONID`가 거기 섞이면 두 세션의 수명이 서로 얽힌다.
        // 앱을 껐다 켜면 쿠키가 사라지지만, 자격증명이 Keychain에 있어 조용히 다시 붙는다.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func form(path: String, fields: [String: String]) async throws -> VisitorCarHTTPResponse {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = VisitorCarFormEncoder.encode(fields)
        // **바디를 로그에 찍지 않는다** — 로그인 필드에 비밀번호가 들어 있다.
        return try await send(request)
    }

    func json(path: String, body: any Encodable & Sendable) async throws -> VisitorCarHTTPResponse {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    func page(path: String) async throws -> VisitorCarHTTPResponse {
        var request = try makeRequest(path: path)
        request.httpMethod = "GET"
        return try await send(request)
    }

    func clearCookies() async {
        guard let storage = session.configuration.httpCookieStorage else { return }
        storage.removeCookies(since: .distantPast)
    }

    // MARK: - Private

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = VisitorCarSite.url(path: path) else {
            throw VisitorCarError.network("주소가 잘못되었습니다.")
        }
        var request = URLRequest(url: url)
        // 서버가 `X-Requested-With`를 보고 갈래를 바꾸지는 않지만, DataTables가
        // 보내는 것과 같은 모양을 유지해 두면 나중에 갈렸을 때 원인을 좁히기 쉽다.
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return request
    }

    private func send(_ request: URLRequest) async throws -> VisitorCarHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw VisitorCarError.network("응답을 읽지 못했습니다.")
            }
            return VisitorCarHTTPResponse(
                status: http.statusCode,
                location: http.value(forHTTPHeaderField: "Location"),
                body: data
            )
        } catch let error as VisitorCarError {
            throw error
        } catch {
            throw VisitorCarError.network(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: ATS 예외를 넣는다**

`WooriHaru/Info.plist`의 `<dict>` 안(`ITSAppUsesNonExemptEncryption` 바로 위)에 넣는다.

```xml
	<key>NSAppTransportSecurity</key>
	<dict>
		<!-- 아파트 주차관제 웹이 http로만 뜬다. 전역(NSAllowsArbitraryLoads)으로 열면
		     https인 우리 서버 쪽 보호까지 같이 내려가므로 이 호스트만 연다. -->
		<key>NSExceptionDomains</key>
		<dict>
			<key>dasanesesang.iptime.org</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
				<key>NSIncludesSubdomains</key>
				<true/>
			</dict>
		</dict>
	</dict>
```

검증: `plutil -lint WooriHaru/Info.plist` → `OK`.

- [ ] **Step 5: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarTransportTests 2>&1 | tail -30`

Expected: 7개 테스트 전부 PASS.

- [ ] **Step 6: 커밋**

```bash
plutil -lint WooriHaru/Info.plist
git add WooriHaru/Services/VisitorCarTransport.swift WooriHaru/Info.plist \
        WooriHaruTests/VisitorCarTransportTests.swift
git commit -m "feat: 방문차량 사이트 통신 계층을 만들고 ATS 예외를 연다"
```

---

## Task 5: 자격증명 Keychain 저장소

**Files:**
- Create: `WooriHaru/Services/VisitorCarCredentialStore.swift`
- Test: `WooriHaruTests/VisitorCarCredentialTests.swift`

**Interfaces:**
- Consumes: `VisitorCarError`(Task 1)
- Produces:
  - `struct VisitorCarCredentials: Sendable, Equatable { let id: String; let password: String }`
  - `protocol VisitorCarCredentialStoring: Sendable` — `load() -> VisitorCarCredentials?`, `save(_:) throws`, `clear()`
  - `struct VisitorCarKeychainStore: VisitorCarCredentialStoring`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarCredentialTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

/// **직렬로 돌린다.** 셋 다 같은 Keychain 항목 하나를 건드려서, 나란히 돌면 서로를 지운다.
@Suite(.serialized)
struct VisitorCarCredentialTests {

    /// 테스트끼리 부딪히지 않게 서비스 이름을 따로 쓴다.
    private func makeStore() -> VisitorCarKeychainStore {
        VisitorCarKeychainStore(service: "com.woori.haru.visitorcar.tests")
    }

    @Test func 저장하고_다시_읽는다() throws {
        let store = makeStore()
        defer { store.clear() }

        try store.save(VisitorCarCredentials(id: "10010101", password: "비밀"))

        #expect(store.load() == VisitorCarCredentials(id: "10010101", password: "비밀"))
    }

    /// 계정을 바꿔 다시 저장하면 **덮어써야** 한다 — 두 벌이 남으면 어느 쪽으로 붙을지 알 수 없다.
    @Test func 다시_저장하면_덮어쓴다() throws {
        let store = makeStore()
        defer { store.clear() }

        try store.save(VisitorCarCredentials(id: "10010101", password: "옛것"))
        try store.save(VisitorCarCredentials(id: "20020202", password: "새것"))

        #expect(store.load()?.id == "20020202")
        #expect(store.load()?.password == "새것")
    }

    /// 로그아웃하면 자국이 남지 않아야 한다.
    @Test func 지우면_사라진다() throws {
        let store = makeStore()

        try store.save(VisitorCarCredentials(id: "10010101", password: "비밀"))
        store.clear()

        #expect(store.load() == nil)
    }

    @Test func 저장한_적이_없으면_nil이다() {
        let store = VisitorCarKeychainStore(service: "com.woori.haru.visitorcar.tests.empty")
        store.clear()

        #expect(store.load() == nil)
    }
}
```

> **막히면:** 시뮬레이터 테스트에서 `errSecMissingEntitlement`(-34018)가 나면 테스트 호스트에
> Keychain 접근 권한이 없다는 뜻이다. `WooriHaru.entitlements`에
> `keychain-access-groups`로 `$(AppIdentifierPrefix)com.woori.haru`를 추가하고 다시 돌린다.
> 그래도 안 되면 멈추고 보고한다 — Keychain을 포기하고 `UserDefaults`에 비밀번호를 넣는
> 것은 **선택지가 아니다.**

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarCredentialTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarKeychainStore' in scope`.

- [ ] **Step 3: 저장소를 만든다**

`WooriHaru/Services/VisitorCarCredentialStore.swift`:

```swift
import Foundation
import Security

struct VisitorCarCredentials: Codable, Sendable, Equatable {
    let id: String
    let password: String
}

/// 자격증명 보관. **테스트는 이 자리를 메모리 대역으로 바꾼다** —
/// 서비스 테스트가 Keychain에 붙을 이유가 없다.
protocol VisitorCarCredentialStoring: Sendable {
    func load() -> VisitorCarCredentials?
    func save(_ credentials: VisitorCarCredentials) throws
    func clear()
}

/// Keychain 한 항목에 아이디·비밀번호를 JSON으로 담는다.
///
/// **항목을 하나만 쓴다.** 계정을 여러 벌 다루지 않기로 했고(스펙 비목표),
/// 아이디를 `kSecAttrAccount`로 쪼개면 「어느 아이디로 저장했는지」를 어딘가 또 적어 둬야 한다.
struct VisitorCarKeychainStore: VisitorCarCredentialStoring {
    private let service: String
    private let account = "credentials"

    init(service: String = "com.woori.haru.visitorcar") {
        self.service = service
    }

    func load() -> VisitorCarCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return try? JSONDecoder().decode(VisitorCarCredentials.self, from: data)
    }

    func save(_ credentials: VisitorCarCredentials) throws {
        let data = try JSONEncoder().encode(credentials)

        // **먼저 지우고 넣는다.** `SecItemUpdate`로 갈래를 나누면 「없을 때 추가」
        // 경로가 따로 생기고, 둘 중 하나만 틀려도 항목이 두 벌 남는다.
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        // 잠긴 기기에서 백그라운드로 붙을 일이 없다 — 화면을 열어야 쓰는 기능이다.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw VisitorCarError.keychain(Int(status)) }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarCredentialTests 2>&1 | tail -30`

Expected: 4개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/VisitorCarCredentialStore.swift WooriHaruTests/VisitorCarCredentialTests.swift
git commit -m "feat: 방문차량 계정을 Keychain에 보관한다"
```

---

## Task 6: 서비스 — 재로그인 직렬화와 도메인 변환

**Files:**
- Create: `WooriHaru/Services/VisitorCarService.swift`
- Test: `WooriHaruTests/VisitorCarFakes.swift`, `WooriHaruTests/VisitorCarSessionTests.swift`

**Interfaces:**
- Consumes: Task 1~5 전부
- Produces:
  - `struct VisitorCarRegisterRequest: Sendable, Equatable { var carNo: String; var startDate: Date; var endDate: Date; var visitReason: String }` + `func fields(household:id:) -> [String: String]`
  - `protocol VisitorCarServing: Sendable` — `login(id:password:)`, `logout()`, `remainingMinutes()`, `household()`, `register(_:)`, `update(id:_:)`, `delete(id:)`, `bookings(from:to:carNo:page:size:)`, `entries(from:to:carNo:page:size:)`
  - `actor VisitorCarService: VisitorCarServing` + `static let shared`

- [ ] **Step 1: 대역과 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarFakes.swift`:

```swift
import Foundation
@testable import WooriHaru

/// 경로별 응답을 미리 쌓아 두고 호출을 기록하는 통신 대역.
/// 같은 경로에 여러 응답을 넣으면 부른 순서대로 하나씩 꺼내 준다 —
/// 「처음엔 302, 재로그인 뒤엔 200」을 그려야 해서 큐가 필요하다.
final class FakeVisitorCarTransport: VisitorCarTransport, @unchecked Sendable {
    enum FakeError: Error { case unstubbed(String) }

    private let lock = NSLock()
    private var queues: [String: [VisitorCarHTTPResponse]] = [:]
    private var lastResponses: [String: VisitorCarHTTPResponse] = [:]
    private var sessionAware = false
    private var loggedIn = false
    private(set) var calls: [String] = []
    private(set) var formFields: [(path: String, fields: [String: String])] = []
    private(set) var jsonBodies: [(path: String, body: Data)] = []
    private(set) var clearCookiesCount = 0

    /// 부를 때마다 하나씩 꺼낸다. 큐가 비면 마지막 응답을 되풀이한다.
    func enqueue(_ path: String, _ response: VisitorCarHTTPResponse) {
        lock.withLock { queues[path, default: []].append(response) }
    }

    /// 몇 번을 불러도 같은 응답.
    func stub(_ path: String, _ response: VisitorCarHTTPResponse) {
        lock.withLock { lastResponses[path] = response }
    }

    /// **세션을 흉내 낸다.** 켜 두면 로그인 전에는 무엇을 불러도 302로 튕기고,
    /// `/do-login`이 성공한 뒤에는 등록된 응답이 나간다 — 실제 사이트가 그렇게 움직인다.
    /// 동시성 테스트는 이 모드로만 뜻이 있다: 큐에 302를 넷 쌓아 두면 「로그인했는데도
    /// 여전히 튕기는」, 서버에서는 일어나지 않는 상황을 시험하게 된다.
    func enableSession() {
        lock.withLock { sessionAware = true }
    }

    static func ok(_ body: String) -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: 200, location: nil, body: Data(body.utf8))
    }

    static func loginRedirect() -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/login", body: Data())
    }

    static func loginSuccess() -> VisitorCarHTTPResponse {
        VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/book-car", body: Data())
    }

    static func loginFailure(message: String) -> VisitorCarHTTPResponse {
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? message
        return VisitorCarHTTPResponse(
            status: 302,
            location: "/nxpmsc/login;jsessionid=ABC?result=\(encoded)",
            body: Data()
        )
    }

    func form(path: String, fields: [String: String]) async throws -> VisitorCarHTTPResponse {
        lock.withLock { formFields.append((path, fields)) }
        return try next(path)
    }

    func json(path: String, body: any Encodable & Sendable) async throws -> VisitorCarHTTPResponse {
        let data = try JSONEncoder().encode(body)
        lock.withLock { jsonBodies.append((path, data)) }
        return try next(path)
    }

    func page(path: String) async throws -> VisitorCarHTTPResponse {
        try next(path)
    }

    func clearCookies() async {
        lock.withLock { clearCookiesCount += 1 }
    }

    private func next(_ path: String) throws -> VisitorCarHTTPResponse {
        try lock.withLock {
            calls.append(path)
            if sessionAware {
                if path == "/do-login" {
                    loggedIn = true
                } else if !loggedIn {
                    return Self.loginRedirect()
                }
            }
            if var queue = queues[path], !queue.isEmpty {
                let head = queue.removeFirst()
                queues[path] = queue
                lastResponses[path] = head
                return head
            }
            guard let last = lastResponses[path] else { throw FakeError.unstubbed(path) }
            return last
        }
    }

    func callCount(_ path: String) -> Int {
        lock.withLock { calls.filter { $0 == path }.count }
    }
}

/// 메모리 자격증명 대역 — 서비스 테스트가 Keychain에 붙을 이유가 없다.
final class FakeCredentialStore: VisitorCarCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: VisitorCarCredentials?
    private(set) var saveCount = 0

    init(stored: VisitorCarCredentials? = nil) { self.stored = stored }

    func load() -> VisitorCarCredentials? { lock.withLock { stored } }

    func save(_ credentials: VisitorCarCredentials) throws {
        lock.withLock { stored = credentials; saveCount += 1 }
    }

    func clear() { lock.withLock { stored = nil } }
}

enum VisitorCarFixture {
    static let bookCarPage = #"<input type="hidden" id="reservedVehiclePointValue" value="6000"/>"#

    static let registerForm = """
    <input name="compName" value="1001" readonly />
    <input name="deptName" value="0101" readonly />
    <select name="parkingLot"><option value="1" selected="selected">○○아파트</option></select>
    <select name="parkingZone"><option value="1" selected="selected">기본 구역</option></select>
    """

    static let emptyBookingPage = """
    {"data":{"content":[],"totalElements":0,"totalPages":0,"number":0,"size":10,
      "first":true,"last":true}}
    """

    static let successResult = #"{"result":"success","message":"성공적으로 등록되었습니다."}"#
}
```

`WooriHaruTests/VisitorCarSessionTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarSessionTests {

    private func makeService(
        transport: FakeVisitorCarTransport,
        credentials: VisitorCarCredentials? = VisitorCarCredentials(id: "10010101", password: "비밀")
    ) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: credentials),
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )
    }

    // MARK: - 로그인

    @Test func 성공_리다이렉트면_로그인이_끝난다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        try await service.login(id: "10010101", password: "비밀")

        #expect(store.saveCount == 1)
        #expect(store.load()?.id == "10010101")
    }

    /// **서버가 준 한국어를 그대로 띄운다.** 앱이 문구를 새로 짓지 않는다.
    @Test func 실패_리다이렉트의_메시지를_그대로_올린다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginFailure(message: "아이디 또는 비밀번호가 잘못되었습니다."))
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginFailed("아이디 또는 비밀번호가 잘못되었습니다.")) {
            try await service.login(id: "10010101", password: "틀린것")
        }
        // 실패한 자격증명을 저장하면 다음 재로그인이 영원히 실패한다.
        #expect(store.saveCount == 0)
    }

    // MARK: - 세션 만료

    /// 302를 만나면 **다시 로그인하고 원 요청을 한 번 더** 보낸다.
    @Test func 만료되면_재로그인하고_다시_보낸다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.enqueue("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.enqueue("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        let minutes = try await service.remainingMinutes()

        #expect(minutes == 6000)
        #expect(transport.callCount("/do-login") == 1)
        #expect(transport.callCount("/book-car") == 2)
    }

    /// **되풀이하지 않는다.** 두 번째도 튕기면 자격증명이 틀린 것이고,
    /// 무한히 다시 붙으면 계정이 잠길 수 있다.
    @Test func 재로그인_후에도_튕기면_포기한다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        await #expect(throws: VisitorCarError.sessionExpired) {
            _ = try await service.remainingMinutes()
        }
        #expect(transport.callCount("/do-login") == 1)
        #expect(transport.callCount("/book-car") == 2)
    }

    @Test func 저장된_계정이_없으면_로그인이_필요하다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        let service = makeService(transport: transport, credentials: nil)

        await #expect(throws: VisitorCarError.notLoggedIn) {
            _ = try await service.remainingMinutes()
        }
        #expect(transport.callCount("/do-login") == 0)
    }

    /// 화면 넷이 동시에 뜨면 만료를 동시에 만난다. **로그인은 하나여야 한다.**
    ///
    /// **세션 대역을 켜고 시험한다.** 큐에 302를 넷 쌓아 두는 방식으로는 이 성질을 잴 수
    /// 없다 — 그건 「로그인에 성공했는데도 여전히 튕기는」 상황이고, 그때는 로그인을 네 번
    /// 하는 것이 오히려 맞다. 우리가 붙잡고 싶은 것은 **한 번 붙고 나면 나머지는 그냥 통과**다.
    @Test func 동시_요청이_로그인을_하나만_던진다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.enableSession()
        transport.stub("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { _ = try? await service.remainingMinutes() }
            }
        }

        #expect(transport.callCount("/do-login") == 1)
    }

    // MARK: - 잔여시간·세대

    /// 마크업이 바뀌면 크래시가 아니라 「불러오지 못했습니다」다.
    @Test func 잔여시간_필드가_없으면_오류다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.ok("<html>바뀐 화면</html>"))
        let service = makeService(transport: transport)

        await #expect(throws: VisitorCarError.remainingTimeUnavailable) {
            _ = try await service.remainingMinutes()
        }
    }

    /// 동·호는 계정이 바뀌지 않는 한 그대로다 — **두 번째부터는 캐시를 쓴다.**
    @Test func 세대_정보를_한_번만_읽는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        let service = makeService(transport: transport)

        let first = try await service.household()
        let second = try await service.household()

        #expect(first == second)
        #expect(first.dong == "1001")
        #expect(transport.callCount("/book-car/getOriginal") == 1)
    }

    // MARK: - 등록

    /// 등록 폼은 필드 **열셋**을 다 실어야 한다. 하나라도 빠지면 서버가 조용히 다르게 저장한다.
    @Test func 등록_폼에_열세_필드를_싣는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/post", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let service = makeService(transport: transport)
        let day = Date(timeIntervalSince1970: 1784300400)

        try await service.register(
            VisitorCarRegisterRequest(carNo: "12가3456", startDate: day, endDate: day, visitReason: "택배")
        )

        let sent = try #require(transport.formFields.last(where: { $0.path == "/book-car/post" })?.fields)
        #expect(sent.count == 13)
        #expect(sent["carNo"] == "12가3456")
        #expect(sent["compName"] == "1001")
        #expect(sent["deptName"] == "0101")
        #expect(sent["parkingLot"] == "1")
        #expect(sent["bookStartDate"] == "2026-07-18")
        #expect(sent["bookEndDate"] == "2026-07-18")
        #expect(sent["address"] == "택배")
        #expect(sent["id"] == "")
        #expect(sent["siteName"] == "none")
        #expect(sent["selectParkingZone"] == "true")
        // **휴대폰은 빈 값으로 보낸다** — 서버가 요구하지 않는 것을 확인했다.
        #expect(sent["tel"] == "")
        #expect(sent["name"] == "")
    }

    @Test func 수정은_id를_채워_보낸다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/put", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let service = makeService(transport: transport)
        let day = Date(timeIntervalSince1970: 1784300400)

        try await service.update(
            id: 25752,
            VisitorCarRegisterRequest(carNo: "12가3456", startDate: day, endDate: day, visitReason: "")
        )

        let sent = try #require(transport.formFields.last(where: { $0.path == "/book-car/put" })?.fields)
        #expect(sent["id"] == "25752")
    }

    /// `result != "success"`면 **서버 `message`를 그대로** 올린다.
    @Test func 거절되면_서버_메시지를_그대로_올린다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub(
            "/book-car/delete",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"입차 후 삭제 불가능합니다."}"#)
        )
        let service = makeService(transport: transport)

        await #expect(throws: VisitorCarError.rejected("입차 후 삭제 불가능합니다.")) {
            try await service.delete(id: 25752)
        }
    }

    // MARK: - 조회

    /// **날짜 포맷이 엔드포인트별로 갈린다.** 진입 현황에 날짜만 보내면 500이다.
    @Test func 조회_바디의_날짜_포맷이_갈린다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/web/book-car/pageList", FakeVisitorCarTransport.ok(VisitorCarFixture.emptyBookingPage))
        transport.stub("/web/car/reserved-vehicle-entry-status-by-generation-page",
                       FakeVisitorCarTransport.ok(VisitorCarFixture.emptyBookingPage))
        let service = makeService(transport: transport)
        let from = Date(timeIntervalSince1970: 1784300400)
        let to = Date(timeIntervalSince1970: 1784386799)

        _ = try await service.bookings(from: from, to: to, carNo: "", page: 0, size: 10)
        _ = try await service.entries(from: from, to: to, carNo: "", page: 0, size: 10)

        let bookingBody = try #require(transport.jsonBodies.first { $0.path == "/web/book-car/pageList" }?.body)
        let entryBody = try #require(
            transport.jsonBodies.first { $0.path == "/web/car/reserved-vehicle-entry-status-by-generation-page" }?.body
        )
        let booking = try #require(try JSONSerialization.jsonObject(with: bookingBody) as? [String: Any])
        let entry = try #require(try JSONSerialization.jsonObject(with: entryBody) as? [String: Any])

        #expect(booking["startDate"] as? String == "2026-07-18")
        #expect(booking["userId"] as? String == "10010101")
        #expect(entry["startDate"] as? String == "2026-07-18 00:00:00")
        #expect(entry["endDate"] as? String == "2026-07-18 23:59:59")
    }

    @Test func 로그아웃하면_계정과_쿠키를_버린다() async throws {
        let transport = FakeVisitorCarTransport()
        let store = FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀"))
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await service.logout()

        #expect(store.load() == nil)
        #expect(transport.clearCookiesCount == 1)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarSessionTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarService' in scope`.

- [ ] **Step 3: 서비스를 만든다**

`WooriHaru/Services/VisitorCarService.swift`:

```swift
import Foundation

// MARK: - 등록 요청

struct VisitorCarRegisterRequest: Sendable, Equatable {
    var carNo: String
    var startDate: Date
    var endDate: Date
    var visitReason: String = ""

    /// 등록 폼이 요구하는 **열세 필드**. 하나라도 빠지면 서버가 조용히 다르게 저장한다.
    /// 값이 필요 없는 칸(`name`·`tel`)도 빈 문자열로 실어 보낸다 — 웹 폼이 그렇게 보낸다.
    func fields(household: VisitorCarHousehold, id: Int?) -> [String: String] {
        [
            "id": id.map(String.init) ?? "",
            "siteName": "none",
            "selectParkingZone": "true",
            "parkingLot": household.parkingLot,
            "parkingZone": household.parkingZone,
            "name": "",
            "carNo": carNo,
            // **빈 값으로 통과한다.** 웹 JS는 막지만 서버는 요구하지 않는다 —
            // 폼 HTML에 「필수입력항목에서 휴대폰 제거」 주석이 남아 있고, 실제로 등록해 확인했다.
            "tel": "",
            "compName": household.dong,
            "deptName": household.ho,
            "address": visitReason,
            "bookStartDate": VisitorCarDateFormat.day.string(from: startDate),
            "bookEndDate": VisitorCarDateFormat.day.string(from: endDate),
        ]
    }
}

// MARK: - 조회 요청

private struct VisitorCarBookingQuery: Encodable, Sendable {
    let page: Int
    let size: Int
    let sort = "desc"
    let sortName = "startDate"
    let userId: String
    /// **`yyyy-MM-dd`** — 이쪽은 날짜만 받는다.
    let startDate: String
    let endDate: String
    let carNo1: String
    let insertType = ""
    let visitReason = ""
    let otherInfo = ""
}

private struct VisitorCarEntryQuery: Encodable, Sendable {
    let page: Int
    let size: Int
    let sort = "desc"
    let sortName = "updateDate"
    let userId: String
    let parkingZoneIdCode = ""
    let carNo: String
    /// **`yyyy-MM-dd HH:mm:ss`** — 날짜만 보내면 500이 떨어진다.
    let startDate: String
    let endDate: String
}

// MARK: - 서비스

protocol VisitorCarServing: Sendable {
    func login(id: String, password: String) async throws
    func logout() async
    func remainingMinutes() async throws -> Int
    func household() async throws -> VisitorCarHousehold
    func register(_ request: VisitorCarRegisterRequest) async throws
    func update(id: Int, _ request: VisitorCarRegisterRequest) async throws
    func delete(id: Int) async throws
    func bookings(from: Date, to: Date, carNo: String, page: Int, size: Int) async throws
        -> VisitorCarPage<VisitorCarBooking>
    func entries(from: Date, to: Date, carNo: String, page: Int, size: Int) async throws
        -> VisitorCarPage<VisitorCarEntry>
}

/// 방문차량 사이트를 다루는 문. **`actor`인 이유는 재로그인을 하나로 모으기 위해서다** —
/// 화면 넷이 동시에 뜨면 세션 만료를 동시에 만나고, 그대로 두면 로그인을 넷 던진다.
actor VisitorCarService: VisitorCarServing {
    static let shared = VisitorCarService()

    private let transport: any VisitorCarTransport
    private let credentials: any VisitorCarCredentialStoring
    private let defaults: UserDefaults
    private let householdKey = "visitorCar.household"

    /// 진행 중인 로그인. 뒤늦게 온 요청은 새로 던지지 않고 이것을 기다린다.
    private var loginTask: Task<Void, any Error>?

    init(
        transport: any VisitorCarTransport = VisitorCarHTTPTransport(),
        credentials: any VisitorCarCredentialStoring = VisitorCarKeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.credentials = credentials
        self.defaults = defaults
    }

    // MARK: - 로그인

    func login(id: String, password: String) async throws {
        try await performLogin(id: id, password: password)
        // **성공한 뒤에 저장한다.** 틀린 자격증명을 넣어 두면 이후 재로그인이 영원히 실패한다.
        try credentials.save(VisitorCarCredentials(id: id, password: password))
    }

    func logout() async {
        credentials.clear()
        defaults.removeObject(forKey: householdKey)
        await transport.clearCookies()
    }

    // MARK: - 조회

    func remainingMinutes() async throws -> Int {
        let response = try await send { try await self.transport.page(path: "/book-car") }
        guard let minutes = VisitorCarHTMLParser.remainingMinutes(html: response.text) else {
            throw VisitorCarError.remainingTimeUnavailable
        }
        return minutes
    }

    /// 동·호는 계정이 바뀌지 않는 한 그대로다. **한 번 읽고 담아 둔다** —
    /// 매번 부르면 등록 한 번에 왕복이 둘이 된다.
    func household() async throws -> VisitorCarHousehold {
        if let data = defaults.data(forKey: householdKey),
           let cached = try? JSONDecoder().decode(VisitorCarHousehold.self, from: data) {
            return cached
        }

        let response = try await send {
            try await self.transport.form(path: "/book-car/getOriginal", fields: ["id": ""])
        }
        guard let household = VisitorCarHTMLParser.household(html: response.text) else {
            // **빈 동·호로 등록하면 다른 세대 이름으로 예약이 들어간다.** 여기서 막는다.
            throw VisitorCarError.householdUnavailable
        }

        if let data = try? JSONEncoder().encode(household) {
            defaults.set(data, forKey: householdKey)
        }
        return household
    }

    func bookings(
        from: Date, to: Date, carNo: String, page: Int, size: Int
    ) async throws -> VisitorCarPage<VisitorCarBooking> {
        let query = VisitorCarBookingQuery(
            page: page,
            size: size,
            userId: try userId(),
            startDate: VisitorCarDateFormat.day.string(from: from),
            endDate: VisitorCarDateFormat.day.string(from: to),
            carNo1: carNo
        )
        let response = try await send {
            try await self.transport.json(path: "/web/book-car/pageList", body: query)
        }
        return try decodePage(response.body)
    }

    func entries(
        from: Date, to: Date, carNo: String, page: Int, size: Int
    ) async throws -> VisitorCarPage<VisitorCarEntry> {
        let query = VisitorCarEntryQuery(
            page: page,
            size: size,
            userId: try userId(),
            carNo: carNo,
            startDate: VisitorCarDateFormat.second.string(from: from),
            endDate: VisitorCarDateFormat.second.string(from: to)
        )
        let response = try await send {
            try await self.transport.json(
                path: "/web/car/reserved-vehicle-entry-status-by-generation-page",
                body: query
            )
        }
        return try decodePage(response.body)
    }

    // MARK: - 등록·수정·삭제

    func register(_ request: VisitorCarRegisterRequest) async throws {
        let fields = request.fields(household: try await household(), id: nil)
        try await submit(path: "/book-car/post", fields: fields)
    }

    func update(id: Int, _ request: VisitorCarRegisterRequest) async throws {
        let fields = request.fields(household: try await household(), id: id)
        try await submit(path: "/book-car/put", fields: fields)
    }

    func delete(id: Int) async throws {
        try await submit(path: "/book-car/delete", fields: ["id": String(id)])
    }

    // MARK: - Private

    /// 302를 만나면 **한 번만** 다시 로그인하고 원 요청을 재시도한다.
    ///
    /// 두 번째도 튕기면 포기한다 — 자격증명이 틀렸다는 뜻이고, 무한히 다시 붙으면
    /// 계정이 잠길 수 있다.
    private func send(
        _ perform: () async throws -> VisitorCarHTTPResponse
    ) async throws -> VisitorCarHTTPResponse {
        let first = try await perform()
        guard first.isLoginRedirect else { return first }

        try await reLogin()

        let second = try await perform()
        if second.isLoginRedirect { throw VisitorCarError.sessionExpired }
        return second
    }

    /// 진행 중인 로그인이 있으면 **그것을 기다린다.** 동시에 만료를 만난 요청들이
    /// 로그인을 각자 던지지 않게 하는 자리다.
    private func reLogin() async throws {
        if let existing = loginTask {
            return try await existing.value
        }
        guard let saved = credentials.load() else { throw VisitorCarError.notLoggedIn }

        let task = Task { [transport] in
            try await Self.performLogin(
                transport: transport,
                id: saved.id,
                password: saved.password
            )
        }
        loginTask = task
        defer { loginTask = nil }
        try await task.value
    }

    private func performLogin(id: String, password: String) async throws {
        try await Self.performLogin(transport: transport, id: id, password: password)
    }

    /// **성공과 실패가 둘 다 302다.** 상태코드로 가를 수 없어 `Location`을 본다.
    private static func performLogin(
        transport: any VisitorCarTransport,
        id: String,
        password: String
    ) async throws {
        let response = try await transport.form(
            path: "/do-login",
            fields: ["id": id, "password": password, "loginUserLogout": "N"]
        )

        if response.isLoginRedirect {
            let message = VisitorCarHTMLParser.loginErrorMessage(location: response.location ?? "")
            throw VisitorCarError.loginFailed(message ?? "아이디 또는 비밀번호를 확인해 주세요.")
        }
        guard response.status == 302 else { throw VisitorCarError.server(response.status) }
    }

    private func userId() throws -> String {
        guard let id = credentials.load()?.id else { throw VisitorCarError.notLoggedIn }
        return id
    }

    private func decodePage<T: Decodable & Sendable>(_ data: Data) throws -> VisitorCarPage<T> {
        do {
            return try JSONDecoder().decode(VisitorCarPageResponse<T>.self, from: data).data
        } catch {
            // 여기까지 왔는데 디코딩이 깨지면 사이트가 바뀐 것이다.
            // **원문을 실어 올리지 않는다** — 로그인 페이지 HTML이 통째로 담겨 올 수 있고,
            // 거기에는 세션 값이 섞여 있다. 무엇이 깨졌는지는 파서 테스트가 말한다.
            throw VisitorCarError.network("응답을 읽지 못했습니다.")
        }
    }

    /// 등록·수정·삭제의 공통 꼬리. `result != "success"`면 **서버 `message`를 그대로** 올린다.
    private func submit(path: String, fields: [String: String]) async throws {
        let response = try await send {
            try await self.transport.form(path: path, fields: fields)
        }
        let result = try JSONDecoder().decode(VisitorCarResult.self, from: response.body)
        guard result.isSuccess else {
            throw VisitorCarError.rejected(result.message ?? "요청이 거절되었습니다.")
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarSessionTests 2>&1 | tail -40`

Expected: 13개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/VisitorCarService.swift \
        WooriHaruTests/VisitorCarFakes.swift WooriHaruTests/VisitorCarSessionTests.swift
git commit -m "feat: 방문차량 서비스와 재로그인 직렬화를 만든다"
```

---

## Task 7: 자주 쓰는 차량 저장소

**Files:**
- Create: `WooriHaru/Stores/FrequentCarStore.swift`
- Test: `WooriHaruTests/FrequentCarTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `struct FrequentCar: Identifiable, Codable, Equatable, Sendable { let id: UUID; var nickname: String; var carNo: String }`, `@Observable final class FrequentCarStore` — `cars`, `add(nickname:carNo:) -> String?`, `remove(id:)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/FrequentCarTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct FrequentCarTests {

    private func makeStore() -> FrequentCarStore {
        FrequentCarStore(defaults: UserDefaults(suiteName: "frequentcar.tests.\(UUID().uuidString)")!)
    }

    @Test func 처음에는_비어_있다() {
        #expect(makeStore().cars.isEmpty)
    }

    @Test func 추가하면_목록에_들어온다() {
        let store = makeStore()

        #expect(store.add(nickname: "아빠차", carNo: "12가3456") == nil)

        #expect(store.cars.count == 1)
        #expect(store.cars[0].nickname == "아빠차")
        #expect(store.cars[0].carNo == "12가3456")
    }

    /// 차량번호 규칙은 등록 화면과 같은 것을 쓴다 — 저장해 놓고 등록할 때 튕기면 늦다.
    @Test func 잘못된_차량번호는_거절한다() {
        let store = makeStore()

        #expect(store.add(nickname: "아빠차", carNo: "12가 3456") == "차량번호에 공백을 넣을 수 없습니다.")
        #expect(store.cars.isEmpty)
    }

    @Test func 별칭이_비면_거절한다() {
        let store = makeStore()

        #expect(store.add(nickname: "  ", carNo: "12가3456") == "별칭을 입력해 주세요.")
        #expect(store.cars.isEmpty)
    }

    /// 같은 번호를 두 번 담으면 고를 때 어느 쪽인지 알 수 없다.
    @Test func 같은_차량번호는_한_번만_담는다() {
        let store = makeStore()

        #expect(store.add(nickname: "아빠차", carNo: "12가3456") == nil)
        #expect(store.add(nickname: "엄마차", carNo: "12가3456") == "이미 저장된 차량번호입니다.")
        #expect(store.cars.count == 1)
    }

    @Test func 지우면_사라진다() throws {
        let store = makeStore()
        _ = store.add(nickname: "아빠차", carNo: "12가3456")
        let id = try #require(store.cars.first?.id)

        store.remove(id: id)

        #expect(store.cars.isEmpty)
    }

    /// **서버로 보내지 않는다** — 이 기기에만 남는다. 앱을 다시 띄워도 살아 있어야 한다.
    @Test func 다시_띄워도_남아_있다() {
        let suite = "frequentcar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        _ = FrequentCarStore(defaults: defaults).add(nickname: "아빠차", carNo: "12가3456")

        #expect(FrequentCarStore(defaults: defaults).cars.count == 1)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/FrequentCarTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'FrequentCarStore' in scope`.

- [ ] **Step 3: 저장소를 만든다**

`WooriHaru/Stores/FrequentCarStore.swift`:

```swift
import Foundation
import Observation

struct FrequentCar: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var nickname: String
    var carNo: String

    init(id: UUID = UUID(), nickname: String, carNo: String) {
        self.id = id
        self.nickname = nickname
        self.carNo = carNo
    }
}

/// 자주 등록하는 차량번호를 **이 기기에만** 담아 둔다.
///
/// **서버로 보내지 않는다.** 방문차량 사이트에 그럴 자리가 없고, 우리 서버에 올리면
/// 남의 차량번호를 우리가 보관하는 일이 된다. 화면에도 그 사실을 적어 둔다.
@MainActor @Observable
final class FrequentCarStore {
    static let shared = FrequentCarStore()

    private let defaults: UserDefaults
    private let key = "visitorCar.frequentCars"

    private(set) var cars: [FrequentCar] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FrequentCar].self, from: data) {
            cars = decoded
        }
    }

    /// - Returns: 문제가 있으면 사용자에게 보여줄 문구, 없으면 `nil`.
    @discardableResult
    func add(nickname: String, carNo: String) -> String? {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCarNo = carNo.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedNickname.isEmpty { return "별칭을 입력해 주세요." }
        // **등록 화면과 같은 규칙을 쓴다** — 저장해 놓고 등록할 때 튕기면 늦다.
        if let error = VisitorCarValidation.carNoError(trimmedCarNo) { return error }
        if cars.contains(where: { $0.carNo == trimmedCarNo }) { return "이미 저장된 차량번호입니다." }

        cars.append(FrequentCar(nickname: trimmedNickname, carNo: trimmedCarNo))
        persist()
        return nil
    }

    func remove(id: UUID) {
        cars.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cars) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/FrequentCarTests 2>&1 | tail -30`

Expected: 7개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Stores/FrequentCarStore.swift WooriHaruTests/FrequentCarTests.swift
git commit -m "feat: 자주 쓰는 차량을 기기에 담아 둔다"
```

---

## Task 8: 홈 화면과 드로어 연결

여기서 처음으로 화면이 눈에 보인다. 드로어 → 홈 → (아직 빈) 하위 화면까지 길을 뚫는다.

**Files:**
- Create: `WooriHaru/ViewModels/VisitorCarHomeViewModel.swift`
- Create: `WooriHaru/Views/VisitorCar/VisitorCarView.swift`
- Create: `WooriHaru/Views/VisitorCar/VisitorCarLoginCard.swift`
- Modify: `WooriHaru/ContentView.swift` (`AppDestination` enum, `navigationDestination` switch)
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift` (`drawerItem` 목록)
- Test: `WooriHaruTests/VisitorCarHomeTests.swift`

**Interfaces:**
- Consumes: `VisitorCarServing`, `VisitorCarError`(Task 1·6)
- Produces:
  - `@MainActor @Observable final class VisitorCarHomeViewModel` — `state: VisitorCarHomeViewModel.State`, `load() async`, `login(id:password:) async`, `logout() async`, `loginError: String?`, `isSubmitting: Bool`
  - `enum VisitorCarHomeViewModel.State: Equatable { case loading, needsLogin, ready(minutes: Int), failed(String) }`
  - `struct VisitorCarView: View`, `struct VisitorCarLoginCard: View`
  - `AppDestination.visitorCar`, `.visitorCarRegister`, `.visitorCarBookings`, `.visitorCarEntries`, `.visitorCarSettings`
  - `VisitorCarHomeViewModel.remainingText(minutes:) -> String` (static)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarHomeTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarHomeTests {

    private func makeService(
        transport: FakeVisitorCarTransport,
        credentials: VisitorCarCredentials? = VisitorCarCredentials(id: "10010101", password: "비밀")
    ) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: credentials),
            defaults: UserDefaults(suiteName: "visitorcar.home.\(UUID().uuidString)")!
        )
    }

    // MARK: - 문구

    /// 참고 화면의 「100시간 0분 남음」과 같은 꼴.
    @Test func 잔여시간을_시간과_분으로_적는다() {
        #expect(VisitorCarHomeViewModel.remainingText(minutes: 6000) == "100시간 0분 남음")
        #expect(VisitorCarHomeViewModel.remainingText(minutes: 90) == "1시간 30분 남음")
        #expect(VisitorCarHomeViewModel.remainingText(minutes: 0) == "0시간 0분 남음")
    }

    /// **음수는 「남음」이 아니다.** 웹도 「N분 초과 사용하였습니다」로 갈라 말한다.
    @Test func 초과분은_다르게_적는다() {
        #expect(VisitorCarHomeViewModel.remainingText(minutes: -120) == "2시간 0분 초과")
        #expect(VisitorCarHomeViewModel.remainingText(minutes: -5) == "0시간 5분 초과")
    }

    // MARK: - 상태

    @Test func 저장된_계정이_없으면_로그인이_필요하다() async {
        let transport = FakeVisitorCarTransport()
        // 쿠키가 없으면 사이트는 **302로 로그인 페이지를 가리킨다.** 여기까지 와야
        // 서비스가 「저장된 계정이 없다」를 알아챈다.
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        let viewModel = VisitorCarHomeViewModel(
            service: makeService(transport: transport, credentials: nil)
        )

        await viewModel.load()

        #expect(viewModel.state == .needsLogin)
    }

    @Test func 잔여시간을_읽어_보여준다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        let viewModel = VisitorCarHomeViewModel(service: makeService(transport: transport))

        await viewModel.load()

        #expect(viewModel.state == .ready(minutes: 6000))
    }

    /// 세션이 끊겼는데 재로그인도 안 되면 **로그인 카드로 되돌린다.**
    @Test func 세션이_끊기면_로그인_카드로_되돌린다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let viewModel = VisitorCarHomeViewModel(service: makeService(transport: transport))

        await viewModel.load()

        #expect(viewModel.state == .needsLogin)
    }

    /// 마크업이 바뀐 경우는 로그인 문제가 아니다 — 카드를 지우지 않고 오류만 띄운다.
    @Test func 파싱이_깨지면_실패로_남는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.ok("<html>바뀐 화면</html>"))
        let viewModel = VisitorCarHomeViewModel(service: makeService(transport: transport))

        await viewModel.load()

        #expect(viewModel.state == .failed("잔여시간을 불러오지 못했습니다."))
    }

    // MARK: - 로그인

    @Test func 로그인에_성공하면_잔여시간을_읽는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        transport.stub("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        let viewModel = VisitorCarHomeViewModel(
            service: makeService(transport: transport, credentials: nil)
        )

        await viewModel.login(id: "10010101", password: "비밀")

        #expect(viewModel.state == .ready(minutes: 6000))
        #expect(viewModel.loginError == nil)
    }

    /// **서버가 준 한국어를 그대로 띄운다.**
    @Test func 로그인_실패_문구를_그대로_띄운다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginFailure(message: "아이디 또는 비밀번호가 잘못되었습니다."))
        let viewModel = VisitorCarHomeViewModel(
            service: makeService(transport: transport, credentials: nil)
        )

        await viewModel.login(id: "10010101", password: "틀린것")

        #expect(viewModel.loginError == "아이디 또는 비밀번호가 잘못되었습니다.")
        #expect(viewModel.state == .needsLogin)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarHomeTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarHomeViewModel' in scope`.

- [ ] **Step 3: 뷰모델을 만든다**

`WooriHaru/ViewModels/VisitorCarHomeViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor @Observable
final class VisitorCarHomeViewModel {
    enum State: Equatable {
        case loading
        case needsLogin
        case ready(minutes: Int)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var loginError: String?
    private(set) var isSubmitting = false

    private let service: any VisitorCarServing

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service
    }

    /// 참고 화면과 같은 꼴로 적는다. **음수는 「남음」이 아니라 「초과」다** —
    /// 웹도 갈라 말하고, 「-120분 남음」은 읽는 사람을 헷갈리게 한다.
    static func remainingText(minutes: Int) -> String {
        let magnitude = abs(minutes)
        let text = "\(magnitude / 60)시간 \(magnitude % 60)분"
        return minutes < 0 ? "\(text) 초과" : "\(text) 남음"
    }

    func load() async {
        state = .loading
        do {
            state = .ready(minutes: try await service.remainingMinutes())
        } catch VisitorCarError.notLoggedIn, VisitorCarError.sessionExpired {
            // 로그인이 풀린 것은 「실패」가 아니라 「다시 붙어야 한다」다.
            state = .needsLogin
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func login(id: String, password: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        loginError = nil
        defer { isSubmitting = false }

        do {
            try await service.login(id: id, password: password)
            await load()
        } catch {
            loginError = error.localizedDescription
            state = .needsLogin
        }
    }

    func logout() async {
        await service.logout()
        loginError = nil
        state = .needsLogin
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarHomeTests 2>&1 | tail -30`

Expected: 8개 테스트 전부 PASS.

- [ ] **Step 5: 로그인 카드를 만든다**

`WooriHaru/Views/VisitorCar/VisitorCarLoginCard.swift`:

```swift
import SwiftUI

/// 자격증명이 없을 때 홈이 카드 대신 띄우는 것.
///
/// **한 번만 보이는 화면이다** — 성공하면 Keychain에 들어가고, 세션이 끊겨도
/// 서비스가 조용히 다시 붙는다. 여기까지 되돌아왔다면 계정이 바뀌었거나 지워진 것이다.
struct VisitorCarLoginCard: View {
    let error: String?
    let isSubmitting: Bool
    let onSubmit: (String, String) -> Void

    @State private var id = ""
    @State private var password = ""

    private var canSubmit: Bool {
        !id.isEmpty && !password.isEmpty && !isSubmitting
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("주차관제 로그인", systemImage: "person.badge.key")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                Text("아파트 주차관제 계정으로 한 번만 로그인하면 됩니다.")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textTertiary)

                TextField("아이디", text: $id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                SecureField("비밀번호", text: $password)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                if let error {
                    // 서버가 준 한국어를 그대로 띄운다.
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                }

                Button {
                    onSubmit(id, password)
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(VehicleTheme.background)
                        } else {
                            Text("로그인").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(
                        canSubmit ? VehicleTheme.accent : VehicleTheme.trackFill,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(canSubmit ? VehicleTheme.background : VehicleTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
    }
}
```

- [ ] **Step 6: 홈 화면을 만든다**

`WooriHaru/Views/VisitorCar/VisitorCarView.swift`:

```swift
import SwiftUI

/// 「방문차량」 미니앱의 홈. 잔여시간 카드 한 장 + 갈 곳 카드 셋.
///
/// **탭바를 두지 않는다.** 차량·관리비는 한 화면 안에서 오가는 탭이 필요했지만
/// 여기는 셋 다 「들어갔다 나오는」 일이라 목록이 맞다.
struct VisitorCarView: View {
    @Binding var navPath: NavigationPath
    @State private var viewModel = VisitorCarHomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                switch viewModel.state {
                case .needsLogin:
                    VisitorCarLoginCard(
                        error: viewModel.loginError,
                        isSubmitting: viewModel.isSubmitting
                    ) { id, password in
                        Task { await viewModel.login(id: id, password: password) }
                    }
                default:
                    remainingCard
                    menuCard(
                        icon: "plus.circle",
                        title: "신규 차량 등록",
                        detail: "방문 차량 정보와 방문 기간을 입력해 등록합니다.",
                        destination: .visitorCarRegister
                    )
                    menuCard(
                        icon: "list.bullet.rectangle",
                        title: "등록 내역 조회",
                        detail: "기간별 방문 차량 등록 내역을 확인하고 수정합니다.",
                        destination: .visitorCarBookings
                    )
                    menuCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "차량 진입 현황",
                        detail: "우리 세대의 차량 입출차 현황을 확인합니다.",
                        destination: .visitorCarEntries
                    )
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("방문차량")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { navPath.append(AppDestination.visitorCarSettings) } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("설정")
            }
        }
        // **화면에 돌아올 때마다 다시 읽는다** — 등록하고 나오면 잔여시간이 달라져 있다.
        .task { await viewModel.load() }
    }

    private var remainingCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(VehicleTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("충전 잔여 시간")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)

                    switch viewModel.state {
                    case .ready(let minutes):
                        Text(VisitorCarHomeViewModel.remainingText(minutes: minutes))
                            .font(.title3).fontWeight(.semibold)
                            // 초과분은 붉게 — 「남음」과 눈으로 갈려야 한다.
                            .foregroundStyle(minutes < 0 ? VehicleTheme.danger : VehicleTheme.textPrimary)
                    case .failed(let message):
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(VehicleTheme.danger)
                    default:
                        Text("불러오는 중")
                            .font(.footnote)
                            .foregroundStyle(VehicleTheme.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Button { Task { await viewModel.load() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(VehicleTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("잔여시간 새로고침")
            }
        }
    }

    private func menuCard(
        icon: String,
        title: String,
        detail: String,
        destination: AppDestination
    ) -> some View {
        Button { navPath.append(destination) } label: {
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(VehicleTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(VehicleTheme.textPrimary)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(VehicleTheme.textTertiary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        VisitorCarView(navPath: .constant(NavigationPath()))
    }
}
```

- [ ] **Step 7: 드로어와 라우팅을 잇는다**

`WooriHaru/ContentView.swift` — `AppDestination`에 다섯 갈래를 더한다(`case maintenance` 아래).

```swift
    case maintenance
    case visitorCar
    case visitorCarRegister
    case visitorCarBookings
    case visitorCarEntries
    case visitorCarSettings
```

같은 파일 `navigationDestination` switch에 `case .maintenance: MaintenanceView()` 아래로 더한다. **하위 넷은 Task 9~12에서 채운다 — 지금은 홈만 잇는다.**

```swift
                    case .visitorCar: VisitorCarView(navPath: $path)
                    case .visitorCarRegister: Text("준비 중")
                    case .visitorCarBookings: Text("준비 중")
                    case .visitorCarEntries: Text("준비 중")
                    case .visitorCarSettings: Text("준비 중")
```

`WooriHaru/Views/Components/SideDrawerView.swift` — `drawerItem` 목록의 「관리비」 **아래**에 한 줄. 둘 다 아파트 일이라 붙여 둔다.

```swift
                drawerItem(icon: "parkingsign", label: "방문차량") {
                    isOpen = false
                    navPath.append(AppDestination.visitorCar)
                }
```

- [ ] **Step 8: 빌드를 확인한다**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: 커밋**

```bash
git add WooriHaru/ViewModels/VisitorCarHomeViewModel.swift \
        WooriHaru/Views/VisitorCar/VisitorCarView.swift \
        WooriHaru/Views/VisitorCar/VisitorCarLoginCard.swift \
        WooriHaru/ContentView.swift WooriHaru/Views/Components/SideDrawerView.swift \
        WooriHaruTests/VisitorCarHomeTests.swift
git commit -m "feat: 방문차량 홈을 만들고 드로어에 단다"
```

---

## Task 9: 신규 차량 등록 화면

**Files:**
- Create: `WooriHaru/ViewModels/VisitorCarRegisterViewModel.swift`
- Create: `WooriHaru/Views/VisitorCar/VisitorCarRegisterView.swift`
- Modify: `WooriHaru/ContentView.swift` (`case .visitorCarRegister`의 `Text("준비 중")`을 갈아 끼운다)
- Test: `WooriHaruTests/VisitorCarRegisterTests.swift`

**Interfaces:**
- Consumes: `VisitorCarServing`, `VisitorCarRegisterRequest`, `VisitorCarValidation`, `FrequentCarStore`
- Produces:
  - `@MainActor @Observable final class VisitorCarRegisterViewModel` — `carNo`, `startDate`, `endDate`, `visitReason`, `errorMessage: String?`, `isSubmitting: Bool`, `didSucceed: Bool`, `validationError: String?`, `canSubmit: Bool`, `submit() async`, `apply(_ car: FrequentCar)`
  - `struct VisitorCarRegisterView: View` — `init(onSaved: @escaping () -> Void)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarRegisterTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarRegisterTests {

    private func makeService(transport: FakeVisitorCarTransport) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀")),
            defaults: UserDefaults(suiteName: "visitorcar.register.\(UUID().uuidString)")!
        )
    }

    private func readyTransport() -> FakeVisitorCarTransport {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/post", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        return transport
    }

    @Test func 차량번호가_비면_보낼_수_없다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))

        #expect(!viewModel.canSubmit)
        // 아직 아무것도 안 쳤을 때는 붉은 글씨를 띄우지 않는다 — 처음부터 혼내지 않는다.
        #expect(viewModel.validationError == nil)
    }

    @Test func 잘못된_차량번호를_짚어준다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))
        viewModel.carNo = "12가 3456"

        #expect(viewModel.validationError == "차량번호에 공백을 넣을 수 없습니다.")
        #expect(!viewModel.canSubmit)
    }

    @Test func 종료일이_앞서면_보낼_수_없다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))
        viewModel.carNo = "12가3456"
        viewModel.endDate = viewModel.startDate.addingTimeInterval(-86_400)

        #expect(viewModel.validationError == "종료일이 시작일보다 앞설 수 없습니다.")
        #expect(!viewModel.canSubmit)
    }

    @Test func 멀쩡하면_보낼_수_있다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))
        viewModel.carNo = "12가3456"

        #expect(viewModel.validationError == nil)
        #expect(viewModel.canSubmit)
    }

    @Test func 등록에_성공하면_성공_표시가_선다() async {
        let transport = readyTransport()
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        await viewModel.submit()

        #expect(viewModel.didSucceed)
        #expect(viewModel.errorMessage == nil)
        #expect(transport.callCount("/book-car/post") == 1)
    }

    /// **거절 문구는 서버 것을 그대로 띄운다.**
    @Test func 거절되면_서버_문구를_띄운다() async {
        let transport = readyTransport()
        transport.stub(
            "/book-car/post",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"잔여 시간이 없습니다."}"#)
        )
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        await viewModel.submit()

        #expect(!viewModel.didSucceed)
        #expect(viewModel.errorMessage == "잔여 시간이 없습니다.")
    }

    /// **동·호를 못 읽으면 등록을 막는다** — 빈 값으로 보내면 다른 세대 이름으로 예약이 들어간다.
    @Test func 세대_정보를_못_읽으면_보내지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok("<html>바뀐 화면</html>"))
        transport.stub("/book-car/post", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        await viewModel.submit()

        #expect(viewModel.errorMessage == "세대 정보를 불러오지 못했습니다.")
        #expect(transport.callCount("/book-car/post") == 0)
    }

    /// 두 번 눌러도 한 번만 나간다.
    @Test func 보내는_중에는_다시_보내지_않는다() async {
        let transport = readyTransport()
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: transport))
        viewModel.carNo = "12가3456"

        async let first: Void = viewModel.submit()
        async let second: Void = viewModel.submit()
        _ = await (first, second)

        #expect(transport.callCount("/book-car/post") == 1)
    }

    @Test func 자주_쓰는_차량을_고르면_번호가_채워진다() {
        let viewModel = VisitorCarRegisterViewModel(service: makeService(transport: readyTransport()))

        viewModel.apply(FrequentCar(nickname: "아빠차", carNo: "12가3456"))

        #expect(viewModel.carNo == "12가3456")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarRegisterTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarRegisterViewModel' in scope`.

- [ ] **Step 3: 뷰모델을 만든다**

`WooriHaru/ViewModels/VisitorCarRegisterViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor @Observable
final class VisitorCarRegisterViewModel {
    var carNo = ""
    var startDate = Date()
    var endDate = Date()
    var visitReason = ""

    private(set) var errorMessage: String?
    private(set) var isSubmitting = false
    private(set) var didSucceed = false

    private let service: any VisitorCarServing

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service
    }

    /// 사용자가 무언가 치기 시작한 뒤에만 짚어 준다 — **빈 화면을 처음부터 혼내지 않는다.**
    var validationError: String? {
        if carNo.isEmpty { return nil }
        if let error = VisitorCarValidation.carNoError(carNo) { return error }
        return VisitorCarValidation.periodError(start: startDate, end: endDate)
    }

    var canSubmit: Bool {
        !isSubmitting
            && VisitorCarValidation.carNoError(carNo) == nil
            && VisitorCarValidation.periodError(start: startDate, end: endDate) == nil
    }

    func apply(_ car: FrequentCar) {
        carNo = car.carNo
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await service.register(
                VisitorCarRegisterRequest(
                    carNo: carNo,
                    startDate: startDate,
                    endDate: endDate,
                    visitReason: visitReason
                )
            )
            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarRegisterTests 2>&1 | tail -30`

Expected: 9개 테스트 전부 PASS.

- [ ] **Step 5: 화면을 만든다**

`WooriHaru/Views/VisitorCar/VisitorCarRegisterView.swift`:

```swift
import SwiftUI

/// 신규 방문차량 등록. **차량번호와 기간이면 끝난다** —
/// 웹 폼에 있는 휴대폰 칸은 서버가 요구하지 않아 뺐고, 동·호는 서비스가 채운다.
struct VisitorCarRegisterView: View {
    /// 등록에 성공해 물러날 때 홈이 잔여시간을 다시 읽게 한다.
    let onSaved: () -> Void

    @State private var viewModel = VisitorCarRegisterViewModel()
    @State private var showingFrequentCars = false
    @State private var frequentCars = FrequentCarStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                carCard
                periodCard
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                submitButton
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("신규 차량 등록")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("자주 쓰는 차량", isPresented: $showingFrequentCars, titleVisibility: .visible) {
            ForEach(frequentCars.cars) { car in
                Button("\(car.nickname) · \(car.carNo)") { viewModel.apply(car) }
            }
            Button("취소", role: .cancel) {}
        }
        .onChange(of: viewModel.didSucceed) {
            guard viewModel.didSucceed else { return }
            onSaved()
            dismiss()
        }
    }

    private var carCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("차량 정보", systemImage: "car")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                TextField("차량번호", text: $viewModel.carNo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                if let error = viewModel.validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                }

                // 저장된 게 없으면 감춘다 — 눌러 봐야 빈 목록이다.
                if !frequentCars.cars.isEmpty {
                    Button {
                        showingFrequentCars = true
                    } label: {
                        Label("자주 쓰는 차량 선택", systemImage: "bookmark")
                            .font(.subheadline)
                            .foregroundStyle(VehicleTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var periodCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("방문 기간", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                DatePicker("시작일", selection: $viewModel.startDate, displayedComponents: .date)
                Divider().overlay(VehicleTheme.cardStroke)
                DatePicker("종료일", selection: $viewModel.endDate, displayedComponents: .date)

                Divider().overlay(VehicleTheme.cardStroke)

                TextField("방문사유 (선택)", text: $viewModel.visitReason)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))
                    // 서버 폼이 20자로 잘라 둔 칸이다.
                    .onChange(of: viewModel.visitReason) {
                        if viewModel.visitReason.count > 20 {
                            viewModel.visitReason = String(viewModel.visitReason.prefix(20))
                        }
                    }
            }
            .font(.subheadline)
            .foregroundStyle(VehicleTheme.textSecondary)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await viewModel.submit() }
        } label: {
            HStack {
                Spacer()
                if viewModel.isSubmitting {
                    ProgressView().tint(VehicleTheme.background)
                } else {
                    Text("방문 차량 등록").fontWeight(.semibold)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(
                viewModel.canSubmit ? VehicleTheme.accent : VehicleTheme.trackFill,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(viewModel.canSubmit ? VehicleTheme.background : VehicleTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmit)
    }
}

#Preview {
    NavigationStack {
        VisitorCarRegisterView(onSaved: {})
    }
}
```

- [ ] **Step 6: 라우팅을 갈아 끼운다**

`WooriHaru/ContentView.swift`에서 `case .visitorCarRegister: Text("준비 중")`을 바꾼다.

```swift
                    case .visitorCarRegister:
                        VisitorCarRegisterView {
                            // 홈으로 물러나면 `.task`가 다시 돌아 잔여시간을 새로 읽는다.
                        }
```

- [ ] **Step 7: 빌드를 확인한다**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/VisitorCarRegisterViewModel.swift \
        WooriHaru/Views/VisitorCar/VisitorCarRegisterView.swift \
        WooriHaru/ContentView.swift WooriHaruTests/VisitorCarRegisterTests.swift
git commit -m "feat: 방문차량 신규 등록 화면을 만든다"
```

---

## Task 10: 등록 내역 조회와 수정·삭제

**Files:**
- Create: `WooriHaru/ViewModels/VisitorCarBookingsViewModel.swift`
- Create: `WooriHaru/Views/VisitorCar/VisitorCarBookingsView.swift`
- Modify: `WooriHaru/ContentView.swift` (`case .visitorCarBookings`)
- Test: `WooriHaruTests/VisitorCarBookingsTests.swift`

**Interfaces:**
- Consumes: `VisitorCarServing`, `VisitorCarBooking`, `VisitorCarPage`
- Produces:
  - `@MainActor @Observable final class VisitorCarBookingsViewModel` — `from`, `to`, `bookings: [VisitorCarBooking]`, `errorMessage: String?`, `isLoading: Bool`, `hasMore: Bool`, `search() async`, `loadMore() async`, `delete(id:) async -> Bool`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarBookingsTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarBookingsTests {

    private static let path = "/web/book-car/pageList"

    private func page(ids: [Int], totalPages: Int, number: Int) -> String {
        let content = ids.map {
            """
            {"id":\($0),"compName":"1001","deptName":"0101","name":"","carNo":"12가3456",
             "tel":"","startDate":1784300400,"endDate":1784386799,"updateDate":1784356046,
             "userName":"10010101","insertType":"W","address":""}
            """
        }.joined(separator: ",")
        return """
        {"data":{"content":[\(content)],"totalElements":\(ids.count * totalPages),
          "totalPages":\(totalPages),"number":\(number),"size":10,
          "first":\(number == 0),"last":\(number == totalPages - 1)}}
        """
    }

    private func makeService(transport: FakeVisitorCarTransport) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀")),
            defaults: UserDefaults(suiteName: "visitorcar.bookings.\(UUID().uuidString)")!
        )
    }

    /// 기본 범위는 **오늘부터 한 달 뒤까지** — 방문 예약은 앞날을 잡는 일이다.
    @Test func 기본_조회_범위는_오늘부터_한_달이다() {
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: FakeVisitorCarTransport()))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!

        let expected = calendar.date(byAdding: .month, value: 1, to: viewModel.from)
        #expect(calendar.isDate(viewModel.to, inSameDayAs: try #require(expected)))
    }

    @Test func 조회하면_목록을_채운다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()

        #expect(viewModel.bookings.map(\.id) == [1, 2])
        #expect(!viewModel.hasMore)
        #expect(viewModel.errorMessage == nil)
    }

    /// **더 보기**는 앞의 것을 지우지 않고 뒤에 잇는다.
    @Test func 더_보기는_뒤에_잇는다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 2, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [3, 4], totalPages: 2, number: 1)))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()
        #expect(viewModel.hasMore)

        await viewModel.loadMore()

        #expect(viewModel.bookings.map(\.id) == [1, 2, 3, 4])
        #expect(!viewModel.hasMore)
    }

    /// 다시 조회하면 **처음부터** 채운다 — 이어 붙이면 조건이 바뀐 결과와 섞인다.
    @Test func 다시_조회하면_처음부터_채운다() async {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 2, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [3, 4], totalPages: 2, number: 1)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [9], totalPages: 1, number: 0)))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))

        await viewModel.search()
        await viewModel.loadMore()
        await viewModel.search()

        #expect(viewModel.bookings.map(\.id) == [9])
    }

    @Test func 삭제하면_목록에서_빠진다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.stub("/book-car/delete", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let deleted = await viewModel.delete(id: 1)

        #expect(deleted)
        #expect(viewModel.bookings.map(\.id) == [2])
    }

    /// **입차 후에는 서버가 거절한다.** 앱이 그 조건을 흉내 내지 않고, 거절 문구를 그대로 띄운다.
    @Test func 삭제가_거절되면_목록을_건드리지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.stub(
            "/book-car/delete",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"입차 후 삭제 불가능합니다."}"#)
        )
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let deleted = await viewModel.delete(id: 1)

        #expect(!deleted)
        #expect(viewModel.bookings.map(\.id) == [1, 2])
        #expect(viewModel.errorMessage == "입차 후 삭제 불가능합니다.")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarBookingsTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarBookingsViewModel' in scope`.

- [ ] **Step 3: 뷰모델을 만든다**

`WooriHaru/ViewModels/VisitorCarBookingsViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor @Observable
final class VisitorCarBookingsViewModel {
    var from: Date
    var to: Date

    private(set) var bookings: [VisitorCarBooking] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var hasMore = false

    private let service: any VisitorCarServing
    private let pageSize = 10
    private var loadedPage = 0

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let today = Date()
        // 방문 예약은 앞날을 잡는 일이다 — 지난 달을 기본으로 보여줄 이유가 없다.
        self.from = today
        self.to = calendar.date(byAdding: .month, value: 1, to: today) ?? today
    }

    func search() async {
        // **처음부터 채운다.** 이어 붙이면 조건이 바뀐 결과와 섞인다.
        loadedPage = 0
        bookings = []
        await fetch(page: 0)
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await fetch(page: loadedPage + 1)
    }

    /// - Returns: 실제로 지워졌으면 `true`. 서버가 거절하면 `false`이고 문구는 `errorMessage`에 남는다.
    func delete(id: Int) async -> Bool {
        errorMessage = nil
        do {
            try await service.delete(id: id)
            bookings.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetch(page: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await service.bookings(
                from: from, to: to, carNo: "", page: page, size: pageSize
            )
            bookings.append(contentsOf: result.content)
            loadedPage = result.number
            hasMore = !result.last
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarBookingsTests 2>&1 | tail -30`

Expected: 6개 테스트 전부 PASS.

- [ ] **Step 5: 화면을 만든다**

`WooriHaru/Views/VisitorCar/VisitorCarBookingsView.swift`:

```swift
import SwiftUI

/// 등록 내역 조회. 조건 카드 + 결과 목록 + 상세 시트(수정·삭제).
struct VisitorCarBookingsView: View {
    @State private var viewModel = VisitorCarBookingsViewModel()
    @State private var selected: VisitorCarBooking?
    @State private var pendingDeletion: VisitorCarBooking?

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                conditionCard

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.bookings.isEmpty && !viewModel.isLoading {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(VehicleTheme.textTertiary)
                            Text("등록 내역이 없습니다.")
                                .font(.footnote)
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(viewModel.bookings) { booking in
                        Button { selected = booking } label: { row(booking) }
                            .buttonStyle(.plain)
                    }

                    // 무한 스크롤을 만들지 않는다 — 세대 하나가 쌓는 건수가 그만큼 되지 않는다.
                    if viewModel.hasMore {
                        Button { Task { await viewModel.loadMore() } } label: {
                            Text("더 보기")
                                .font(.subheadline)
                                .foregroundStyle(VehicleTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("등록 내역 조회")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.search() }
        .sheet(item: $selected) { booking in
            detailSheet(booking)
                .presentationDetents([.medium])
                .vehicleDarkTheme()
        }
        .alert("등록 내역 삭제", isPresented: .constant(pendingDeletion != nil)) {
            Button("삭제", role: .destructive) {
                guard let target = pendingDeletion else { return }
                pendingDeletion = nil
                Task {
                    if await viewModel.delete(id: target.id) { selected = nil }
                }
            }
            Button("취소", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("\(pendingDeletion?.carNo ?? "") 등록을 삭제할까요?")
        }
    }

    private var conditionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("조회 조건", systemImage: "line.3.horizontal.decrease")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                DatePicker("시작일", selection: $viewModel.from, displayedComponents: .date)
                Divider().overlay(VehicleTheme.cardStroke)
                DatePicker("종료일", selection: $viewModel.to, displayedComponents: .date)

                Button { Task { await viewModel.search() } } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView().tint(VehicleTheme.background)
                        } else {
                            Label("조회", systemImage: "magnifyingglass").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(VehicleTheme.background)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .font(.subheadline)
            .foregroundStyle(VehicleTheme.textSecondary)
        }
    }

    private func row(_ booking: VisitorCarBooking) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.carNo)
                        .font(.headline)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Text(periodText(booking))
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
                Spacer(minLength: 0)
                if !booking.insertType.label.isEmpty {
                    Text(booking.insertType.label)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(VehicleTheme.tileFill, in: Capsule())
                        .foregroundStyle(VehicleTheme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private func detailSheet(_ booking: VisitorCarBooking) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GlassTokens.cardSpacing) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow("차량번호", booking.carNo)
                            detailRow("방문 기간", periodText(booking))
                            detailRow("등록구분", booking.insertType.label)
                            detailRow("방문사유", booking.visitReason.isEmpty ? "—" : booking.visitReason)
                            detailRow("등록자", booking.registrant)
                        }
                    }

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(VehicleTheme.danger)
                    }

                    Button(role: .destructive) {
                        pendingDeletion = booking
                    } label: {
                        Text("삭제")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(VehicleTheme.danger.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(VehicleTheme.danger)
                    }
                    .buttonStyle(.plain)

                    // 웹 화면에 「입차 후 수정/삭제 불가능」이라 적혀 있다. **앱이 그 조건을
                    // 판정하지 않는다** — 흉내 내면 서버 규칙과 갈라진다. 보내고 거절당하면 띄운다.
                    Text("입차한 뒤에는 수정·삭제가 거절될 수 있습니다.")
                        .font(.caption2)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
                .padding(GlassTokens.cardPadding)
            }
            .glassScreenBackground()
            .navigationTitle("등록 상세")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
        }
    }

    /// 서버가 시각을 `00:00:00`/`23:59:59`로 채워 준다 — 그때는 날짜만 적는다(웹과 같다).
    private func periodText(_ booking: VisitorCarBooking) -> String {
        let start = VisitorCarDateFormat.day.string(from: booking.startDate)
        let end = VisitorCarDateFormat.day.string(from: booking.endDate)
        return start == end ? start : "\(start) ~ \(end)"
    }
}

#Preview {
    NavigationStack { VisitorCarBookingsView() }
}
```

- [ ] **Step 6: 라우팅을 갈아 끼운다**

`WooriHaru/ContentView.swift`에서 `case .visitorCarBookings: Text("준비 중")` → `case .visitorCarBookings: VisitorCarBookingsView()`.

- [ ] **Step 7: 빌드를 확인한다**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/VisitorCarBookingsViewModel.swift \
        WooriHaru/Views/VisitorCar/VisitorCarBookingsView.swift \
        WooriHaru/ContentView.swift WooriHaruTests/VisitorCarBookingsTests.swift
git commit -m "feat: 방문차량 등록 내역 조회와 삭제를 만든다"
```

---

## Task 11: 등록 내역 수정

Task 10의 상세 시트는 삭제만 한다. 수정을 붙인다.

> **주의: 스펙에서 「확인하지 않은 것」으로 남겨 둔 자리다.** `/book-car/put`은 실제로
> 호출해 본 적이 없다. **이 태스크에서 실기기로 한 건 수정해 보고**, 요청·응답이 등록과
> 다르면 멈추고 보고한 뒤 스펙 문서를 먼저 고친다.

**Files:**
- Modify: `WooriHaru/ViewModels/VisitorCarBookingsViewModel.swift` (`update` 추가)
- Modify: `WooriHaru/Views/VisitorCar/VisitorCarBookingsView.swift` (상세 시트에 수정 모드)
- Test: `WooriHaruTests/VisitorCarBookingsTests.swift` (테스트 추가)

**Interfaces:**
- Consumes: `VisitorCarServing.update(id:_:)`(Task 6)
- Produces: `VisitorCarBookingsViewModel.update(id:carNo:startDate:endDate:visitReason:) async -> Bool`

- [ ] **Step 1: 실패하는 테스트를 더한다**

`WooriHaruTests/VisitorCarBookingsTests.swift`의 `VisitorCarBookingsTests` 안에 붙인다.

```swift
    @Test func 수정에_성공하면_목록을_다시_읽는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1], totalPages: 1, number: 0)))
        transport.enqueue(Self.path, FakeVisitorCarTransport.ok(page(ids: [1, 2], totalPages: 1, number: 0)))
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/put", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let day = Date(timeIntervalSince1970: 1784300400)
        let updated = await viewModel.update(
            id: 1, carNo: "34나5678", startDate: day, endDate: day, visitReason: "택배"
        )

        #expect(updated)
        // 수정 결과를 손으로 기워 넣지 않는다 — 서버가 무엇을 바꿨는지 다시 읽어 확인한다.
        #expect(viewModel.bookings.map(\.id) == [1, 2])

        let sent = try #require(transport.formFields.last(where: { $0.path == "/book-car/put" })?.fields)
        #expect(sent["id"] == "1")
        #expect(sent["carNo"] == "34나5678")
    }

    /// **입차 후에는 서버가 거절한다.** 문구를 그대로 띄우고 목록은 건드리지 않는다.
    @Test func 수정이_거절되면_목록을_건드리지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1], totalPages: 1, number: 0)))
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub(
            "/book-car/put",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"입차 후 수정 불가능합니다."}"#)
        )
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let day = Date(timeIntervalSince1970: 1784300400)
        let updated = await viewModel.update(
            id: 1, carNo: "34나5678", startDate: day, endDate: day, visitReason: ""
        )

        #expect(!updated)
        #expect(viewModel.errorMessage == "입차 후 수정 불가능합니다.")
        #expect(viewModel.bookings.map(\.carNo) == ["12가3456"])
    }

    /// 검증은 등록 화면과 같은 규칙이다 — 잘못된 번호를 서버까지 보내지 않는다.
    @Test func 잘못된_차량번호로는_수정하지_않는다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(page(ids: [1], totalPages: 1, number: 0)))
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/put", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let viewModel = VisitorCarBookingsViewModel(service: makeService(transport: transport))
        await viewModel.search()

        let day = Date(timeIntervalSince1970: 1784300400)
        let updated = await viewModel.update(
            id: 1, carNo: "34나 5678", startDate: day, endDate: day, visitReason: ""
        )

        #expect(!updated)
        #expect(viewModel.errorMessage == "차량번호에 공백을 넣을 수 없습니다.")
        #expect(transport.callCount("/book-car/put") == 0)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarBookingsTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `value of type 'VisitorCarBookingsViewModel' has no member 'update'`.

- [ ] **Step 3: 뷰모델에 `update`를 더한다**

`WooriHaru/ViewModels/VisitorCarBookingsViewModel.swift`의 `delete(id:)` 아래.

```swift
    /// - Returns: 실제로 바뀌었으면 `true`. 검증에 걸리거나 서버가 거절하면 `false`이고
    ///   문구는 `errorMessage`에 남는다.
    func update(
        id: Int,
        carNo: String,
        startDate: Date,
        endDate: Date,
        visitReason: String
    ) async -> Bool {
        errorMessage = nil

        // 등록 화면과 같은 규칙으로 먼저 막는다 — 잘못된 번호를 서버까지 보낼 이유가 없다.
        if let error = VisitorCarValidation.carNoError(carNo) {
            errorMessage = error
            return false
        }
        if let error = VisitorCarValidation.periodError(start: startDate, end: endDate) {
            errorMessage = error
            return false
        }

        do {
            try await service.update(
                id: id,
                VisitorCarRegisterRequest(
                    carNo: carNo,
                    startDate: startDate,
                    endDate: endDate,
                    visitReason: visitReason
                )
            )
            // **결과를 손으로 기워 넣지 않는다.** 서버가 무엇을 바꿨는지(시각 보정 등)
            // 우리가 모르므로 다시 읽어 확인한다.
            await search()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarBookingsTests 2>&1 | tail -30`

Expected: 9개 테스트 전부 PASS.

- [ ] **Step 5: 상세 시트에 수정 모드를 붙인다**

`WooriHaru/Views/VisitorCar/VisitorCarBookingsView.swift` — `detailSheet(_:)`를 갈아 끼우고, 편집 상태를 들 `@State` 넷을 `VisitorCarBookingsView`에 더한다.

```swift
    @State private var isEditing = false
    @State private var editCarNo = ""
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var editReason = ""
```

`detailSheet(_:)`의 `GlassCard { … }` 자리를 아래로 바꾼다(삭제 버튼과 안내 문구는 그대로 둔다).

```swift
                    GlassCard {
                        if isEditing {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("차량번호", text: $editCarNo)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                                DatePicker("시작일", selection: $editStart, displayedComponents: .date)
                                Divider().overlay(VehicleTheme.cardStroke)
                                DatePicker("종료일", selection: $editEnd, displayedComponents: .date)

                                TextField("방문사유 (선택)", text: $editReason)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .font(.subheadline)
                            .foregroundStyle(VehicleTheme.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                detailRow("차량번호", booking.carNo)
                                detailRow("방문 기간", periodText(booking))
                                detailRow("등록구분", booking.insertType.label)
                                detailRow("방문사유", booking.visitReason.isEmpty ? "—" : booking.visitReason)
                                detailRow("등록자", booking.registrant)
                            }
                        }
                    }

                    if isEditing {
                        Button {
                            Task {
                                let ok = await viewModel.update(
                                    id: booking.id,
                                    carNo: editCarNo,
                                    startDate: editStart,
                                    endDate: editEnd,
                                    visitReason: editReason
                                )
                                if ok {
                                    isEditing = false
                                    selected = nil
                                }
                            }
                        } label: {
                            Text("저장")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(VehicleTheme.background)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            // 편집을 시작할 때 현재 값을 옮겨 담는다.
                            editCarNo = booking.carNo
                            editStart = booking.startDate
                            editEnd = booking.endDate
                            editReason = booking.visitReason
                            isEditing = true
                        } label: {
                            Text("수정")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(VehicleTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
```

시트가 닫힐 때 편집 모드를 되돌린다 — `.sheet(item: $selected)` 뒤에 붙인다.

```swift
        .onChange(of: selected) { if selected == nil { isEditing = false } }
```

`VisitorCarBooking`은 `Equatable`이므로 `onChange`가 그대로 성립한다.

- [ ] **Step 6: 빌드를 확인한다**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: 실기기로 수정 한 건을 확인한다**

`/book-car/put`은 **한 번도 호출해 본 적이 없다.** 사용자가 실기기에서 등록 한 건을 만들고, 그 건의 차량번호를 바꿔 저장해 본다.

- 성공하면 다음 스텝으로 간다.
- **응답이 `{"result":…}` 꼴이 아니거나 필드가 다르면 멈추고 보고한다.** 스펙 문서의 「확인하지 않은 것」을 먼저 고친 뒤에 코드를 손댄다.

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/VisitorCarBookingsViewModel.swift \
        WooriHaru/Views/VisitorCar/VisitorCarBookingsView.swift \
        WooriHaruTests/VisitorCarBookingsTests.swift
git commit -m "feat: 등록 내역을 상세 시트에서 수정한다"
```

---

## Task 12: 차량 진입 현황

**Files:**
- Create: `WooriHaru/ViewModels/VisitorCarEntriesViewModel.swift`
- Create: `WooriHaru/Views/VisitorCar/VisitorCarEntriesView.swift`
- Modify: `WooriHaru/ContentView.swift` (`case .visitorCarEntries`)
- Test: `WooriHaruTests/VisitorCarEntriesTests.swift`

**Interfaces:**
- Consumes: `VisitorCarServing.entries(from:to:carNo:page:size:)`, `VisitorCarEntry`
- Produces:
  - `@MainActor @Observable final class VisitorCarEntriesViewModel` — `from`, `to`, `entries: [VisitorCarEntry]`, `errorMessage: String?`, `isLoading: Bool`, `hasMore: Bool`, `now: Date`, `search() async`, `loadMore() async`, `tick()`
  - `VisitorCarEntriesViewModel.parkingText(seconds:) -> String` (static)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VisitorCarEntriesTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct VisitorCarEntriesTests {

    private static let path = "/web/car/reserved-vehicle-entry-status-by-generation-page"

    private func makeService(transport: FakeVisitorCarTransport) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀")),
            defaults: UserDefaults(suiteName: "visitorcar.entries.\(UUID().uuidString)")!
        )
    }

    private static let onePage = """
    {"message":"200","data":{"content":[
      {"id":354751,"inDate":1784357197,"outDate":1784374505,"outChk":2,
       "carNo":"12가3456","name":"","startDate":1784300400,"endDate":1784386799,
       "updateDate":1784356046}],
      "totalElements":1,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
    """

    // MARK: - 문구

    @Test func 주차시간을_시간과_분으로_적는다() {
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: 3600) == "1시간 0분")
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: 5_400) == "1시간 30분")
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: 59) == "0시간 0분")
    }

    /// 시계가 어긋나 음수가 나와도 「-1시간」을 띄우지 않는다.
    @Test func 음수_주차시간은_0으로_접는다() {
        #expect(VisitorCarEntriesViewModel.parkingText(seconds: -600) == "0시간 0분")
    }

    // MARK: - 조회

    /// 기본 범위는 **오늘 하루**다 — 지금 들어와 있는지가 이 화면의 질문이다.
    @Test func 기본_조회_범위는_오늘_하루다() {
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: FakeVisitorCarTransport()))

        #expect(VisitorCarDateFormat.second.string(from: viewModel.from).hasSuffix("00:00:00"))
        #expect(VisitorCarDateFormat.second.string(from: viewModel.to).hasSuffix("23:59:59"))
    }

    @Test func 조회하면_목록을_채운다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok(Self.onePage))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))

        await viewModel.search()

        #expect(viewModel.entries.map(\.id) == [354751])
        #expect(viewModel.entries[0].status == .exited)
        #expect(!viewModel.hasMore)
    }

    /// **아직 안 나간 차는 시간이 흘러야 한다.** `tick()`이 기준 시각을 밀어 준다.
    @Test func tick하면_기준_시각이_지금으로_바뀐다() {
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: FakeVisitorCarTransport()))
        let before = viewModel.now

        viewModel.tick()

        #expect(viewModel.now >= before)
    }

    @Test func 조회에_실패하면_문구를_남긴다() async {
        let transport = FakeVisitorCarTransport()
        transport.stub(Self.path, FakeVisitorCarTransport.ok("깨진 응답"))
        let viewModel = VisitorCarEntriesViewModel(service: makeService(transport: transport))

        await viewModel.search()

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.errorMessage == "응답을 읽지 못했습니다.")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarEntriesTests 2>&1 | tail -30`

Expected: 컴파일 실패 — `cannot find 'VisitorCarEntriesViewModel' in scope`.

- [ ] **Step 3: 뷰모델을 만든다**

`WooriHaru/ViewModels/VisitorCarEntriesViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor @Observable
final class VisitorCarEntriesViewModel {
    var from: Date
    var to: Date

    private(set) var entries: [VisitorCarEntry] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var hasMore = false
    /// 주차시간을 세는 기준. **아직 안 나간 차는 이 값이 밀릴 때마다 늘어난다.**
    private(set) var now = Date()

    private let service: any VisitorCarServing
    private let pageSize = 10
    private var loadedPage = 0

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let today = Date()
        // 「지금 들어와 있나」가 이 화면의 질문이다 — 오늘 하루로 연다.
        self.from = calendar.startOfDay(for: today)
        self.to = calendar.date(byAdding: .second, value: 86_399, to: calendar.startOfDay(for: today)) ?? today
    }

    static func parkingText(seconds: TimeInterval) -> String {
        // 기기 시계가 어긋나면 음수가 나온다. 「-1시간 주차」는 뜻이 없다.
        let total = Int(max(0, seconds))
        return "\(total / 3600)시간 \((total % 3600) / 60)분"
    }

    func tick() { now = Date() }

    func search() async {
        loadedPage = 0
        entries = []
        await fetch(page: 0)
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await fetch(page: loadedPage + 1)
    }

    private func fetch(page: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await service.entries(
                from: from, to: to, carNo: "", page: page, size: pageSize
            )
            entries.append(contentsOf: result.content)
            loadedPage = result.number
            hasMore = !result.last
            now = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VisitorCarEntriesTests 2>&1 | tail -30`

Expected: 7개 테스트 전부 PASS.

- [ ] **Step 5: 화면을 만든다**

`WooriHaru/Views/VisitorCar/VisitorCarEntriesView.swift`:

```swift
import SwiftUI

/// 우리 세대 차량의 입출차 현황.
///
/// **아직 안 나간 차는 주차시간이 흐른다** — 화면이 떠 있는 동안 1분마다 다시 그린다.
struct VisitorCarEntriesView: View {
    @State private var viewModel = VisitorCarEntriesViewModel()

    /// 1분이면 족하다. 화면에 분 단위까지만 적는다.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                conditionCard

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(VehicleTheme.textTertiary)
                            Text("입출차 내역이 없습니다.")
                                .font(.footnote)
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(viewModel.entries) { entry in
                        row(entry)
                    }
                    if viewModel.hasMore {
                        Button { Task { await viewModel.loadMore() } } label: {
                            Text("더 보기")
                                .font(.subheadline)
                                .foregroundStyle(VehicleTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("차량 진입 현황")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.search() }
        .onReceive(ticker) { _ in viewModel.tick() }
    }

    private var conditionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("조회 조건", systemImage: "line.3.horizontal.decrease")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                DatePicker("시작", selection: $viewModel.from, displayedComponents: [.date, .hourAndMinute])
                Divider().overlay(VehicleTheme.cardStroke)
                DatePicker("종료", selection: $viewModel.to, displayedComponents: [.date, .hourAndMinute])

                Button { Task { await viewModel.search() } } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView().tint(VehicleTheme.background)
                        } else {
                            Label("조회", systemImage: "magnifyingglass").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(VehicleTheme.background)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .font(.subheadline)
            .foregroundStyle(VehicleTheme.textSecondary)
        }
    }

    private func row(_ entry: VisitorCarEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.carNo)
                        .font(.headline)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Spacer(minLength: 0)
                    if let status = entry.status {
                        Text(status.label)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                // 아직 안 나간 차만 강조한다 — 나머지는 지난 일이다.
                                (status.isParked ? VehicleTheme.accent.opacity(0.20) : VehicleTheme.tileFill),
                                in: Capsule()
                            )
                            .foregroundStyle(status.isParked ? VehicleTheme.accent : VehicleTheme.textSecondary)
                    }
                }

                HStack {
                    Text("입차 \(VisitorCarDateFormat.second.string(from: entry.inDate))")
                    Spacer(minLength: 0)
                    Text(VisitorCarEntriesViewModel.parkingText(seconds: entry.parkingSeconds(now: viewModel.now)))
                }
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)

                if let outDate = entry.outDate {
                    Text("출차 \(VisitorCarDateFormat.second.string(from: outDate))")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { VisitorCarEntriesView() }
}
```

- [ ] **Step 6: 라우팅을 갈아 끼운다**

`WooriHaru/ContentView.swift`에서 `case .visitorCarEntries: Text("준비 중")` → `case .visitorCarEntries: VisitorCarEntriesView()`.

- [ ] **Step 7: 빌드를 확인한다**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/VisitorCarEntriesViewModel.swift \
        WooriHaru/Views/VisitorCar/VisitorCarEntriesView.swift \
        WooriHaru/ContentView.swift WooriHaruTests/VisitorCarEntriesTests.swift
git commit -m "feat: 차량 진입 현황 화면을 만든다"
```

---

## Task 13: 설정 — 자주 쓰는 차량과 로그아웃

**Files:**
- Create: `WooriHaru/Views/VisitorCar/VisitorCarSettingsView.swift`
- Modify: `WooriHaru/ContentView.swift` (`case .visitorCarSettings`)

**Interfaces:**
- Consumes: `FrequentCarStore`(Task 7), `VisitorCarHomeViewModel.logout()`(Task 8)
- Produces: `struct VisitorCarSettingsView: View` — `init(onLoggedOut: @escaping () -> Void)`

이 태스크에는 새 로직이 없다 — Task 7의 저장소와 Task 8의 `logout()`을 화면에 잇는 일뿐이라 별도 단위 테스트를 더하지 않는다. 저장소 규칙은 `FrequentCarTests`가 이미 붙잡고 있다.

- [ ] **Step 1: 화면을 만든다**

`WooriHaru/Views/VisitorCar/VisitorCarSettingsView.swift`:

```swift
import SwiftUI

/// 방문차량 설정 — 자주 쓰는 차량 관리와 로그아웃.
///
/// **비밀번호 변경을 넣지 않는다.** 사이트에 경로가 있지만 일 년에 한 번 쓸까 말까라
/// 브라우저로 한다(스펙 비목표).
struct VisitorCarSettingsView: View {
    /// 로그아웃하면 홈이 로그인 카드로 되돌아가야 한다.
    let onLoggedOut: () -> Void

    @State private var store = FrequentCarStore.shared
    @State private var viewModel = VisitorCarHomeViewModel()
    @State private var nickname = ""
    @State private var carNo = ""
    @State private var addError: String?
    @State private var showingLogoutConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                noticeCard
                addCard
                savedCars
                logoutButton
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("방문차량 설정")
        .navigationBarTitleDisplayMode(.inline)
        .alert("로그아웃", isPresented: $showingLogoutConfirm) {
            Button("로그아웃", role: .destructive) {
                Task {
                    await viewModel.logout()
                    onLoggedOut()
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장된 주차관제 계정을 지웁니다. 다시 쓰려면 로그인해야 합니다.")
        }
    }

    private var noticeCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(VehicleTheme.textTertiary)
                // 참고 앱과 같은 안내다. 서버에 올리지 않는다는 사실을 사용자가 알아야 한다.
                Text("자주 쓰는 차량 정보는 이 기기에만 저장됩니다. 앱을 지우거나 기기를 바꾸면 사라집니다.")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private var addCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("차량 추가", systemImage: "bookmark")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                TextField("별칭", text: $nickname)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                TextField("차량번호", text: $carNo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                if let addError {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                }

                Button {
                    addError = store.add(nickname: nickname, carNo: carNo)
                    if addError == nil {
                        nickname = ""
                        carNo = ""
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(VehicleTheme.background)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var savedCars: some View {
        if !store.cars.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("저장된 차량")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(store.cars) { car in
                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: "car")
                                .foregroundStyle(VehicleTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(car.nickname)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundStyle(VehicleTheme.textPrimary)
                                Text(car.carNo)
                                    .font(.caption)
                                    .foregroundStyle(VehicleTheme.textTertiary)
                            }

                            Spacer(minLength: 0)

                            Button { store.remove(id: car.id) } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(VehicleTheme.textTertiary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(car.nickname) 삭제")
                        }
                    }
                }
            }
        }
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            showingLogoutConfirm = true
        } label: {
            Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(VehicleTheme.danger.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(VehicleTheme.danger)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { VisitorCarSettingsView(onLoggedOut: {}) }
}
```

- [ ] **Step 2: 라우팅을 갈아 끼운다**

`WooriHaru/ContentView.swift`에서 `case .visitorCarSettings: Text("준비 중")`을 바꾼다.

```swift
                    case .visitorCarSettings:
                        VisitorCarSettingsView {
                            // 홈으로 물러나면 `.task`가 다시 돌아 로그인 카드를 띄운다.
                        }
```

- [ ] **Step 3: 남은 「준비 중」이 없는지 확인한다**

Run: `grep -n '준비 중' WooriHaru/ContentView.swift`

Expected: 아무것도 안 나온다.

- [ ] **Step 4: 빌드를 확인한다**

Run: `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/VisitorCar/VisitorCarSettingsView.swift WooriHaru/ContentView.swift
git commit -m "feat: 방문차량 설정에서 자주 쓰는 차량과 로그아웃을 다룬다"
```

---

## Task 14: 전체 테스트와 실기기 확인

**Files:**
- Modify: `docs/superpowers/specs/2026-08-26-visitor-car-design.md` (확인한 것을 반영)

- [ ] **Step 1: 전체 테스트를 돌린다**

Run:

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -40
```

Expected: `** TEST SUCCEEDED **`. 기존 테스트가 하나라도 깨지면 **멈추고 보고한다** —
방문차량은 기존 어느 코드도 건드리지 않으므로, 깨졌다면 `Info.plist`나 라우팅 쪽을 잘못 손댄 것이다.

- [ ] **Step 2: 사용자가 실기기로 훑는다**

사용자에게 아래를 부탁하고 결과를 받는다. **시뮬레이터로 대신하지 않는다.**

1. 드로어 → 「방문차량」 → 로그인 카드에 계정을 넣는다 → 잔여시간이 뜬다.
2. 「신규 차량 등록」 → 차량번호와 오늘 날짜로 등록 → 성공하고 홈으로 물러난다.
3. 「등록 내역 조회」 → 방금 등록한 건이 보인다 → 눌러 수정 → 저장 → 목록이 바뀐다.
4. 같은 건을 삭제한다.
5. 「차량 진입 현황」 → 오늘 입출차가 보인다(없으면 빈 화면 문구).
6. 설정 → 자주 쓰는 차량을 추가하고, 등록 화면에서 골라진다.
7. 설정 → 로그아웃 → 홈이 로그인 카드로 되돌아간다.

- [ ] **Step 3: 스펙의 「확인하지 않은 것」을 줄인다**

`docs/superpowers/specs/2026-08-26-visitor-car-design.md`의 마지막 절에서 **이번에 실제로 확인한 항목을 지우고**, 관찰한 사실을 본문에 옮긴다. 특히:

- `/book-car/put`의 요청·응답 (Task 11 Step 7에서 확인)
- 입차 후 수정/삭제를 서버가 어떻게 거절하는지 (걸렸다면)
- 페이징 2쪽 이상 (내역이 11건을 넘겼다면)

확인하지 못한 것은 **그대로 남긴다.** 지우기만 하고 확인 안 한 척하지 않는다.

- [ ] **Step 4: 커밋**

```bash
git add docs/superpowers/specs/2026-08-26-visitor-car-design.md
git commit -m "docs: 방문차량 스펙에 실제 확인한 동작을 반영한다"
```
