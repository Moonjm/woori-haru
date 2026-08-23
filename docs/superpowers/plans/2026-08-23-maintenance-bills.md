# 관리비 미니앱 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아파트 관리비 고지서를 사진으로 올려 서버가 읽고 사람이 검수해 확정하는 미니앱을 드로어에 단다 — 목록·상세·등록(인식→검수)·통계 다섯 장.

**Architecture:** 인식→검수→확정 흐름은 배차표(`DispatchUploadView`/`DispatchService`)를 그대로 물려받고, 화면 껍데기와 차트는 차량 미니앱(`vehicleDarkTheme`·`ChartCard`·`MonthlyBarChart`·`RankBarList`·`MonthlyLineChart`)을 재사용한다. 검수와 편집은 `Mode` 하나로 갈리는 **한 화면**이다. 통계 파생 계산은 전부 순수 함수(`MaintenanceTrendMath`)로 빼서 SwiftUI 없이 테스트한다.

**Tech Stack:** SwiftUI (iOS 26), `@Observable`, Swift Testing (`import Testing`/`@Test`/`#expect`), `PhotosUI`. **Swift Charts를 들이지 않는다** — 저장소 관례대로 `Path`/`GeometryReader`/`RoundedRectangle`로 손수 그린다.

**Spec:** `docs/superpowers/specs/2026-08-23-maintenance-bills-design.md`
서버 계약: `https://daily.eunji.shop/api/v3/api-docs` 태그 「관리비」

## Global Constraints

- **서버는 손대지 않는다.** `/maintenance/*`는 이미 배포돼 있다. 계약이 모자라면 앱에서 파생시키고, 계약을 바꿔야 한다고 판단되면 멈추고 보고한다.
- **테스트는 Swift Testing이다** — `import Testing`, `@Test`, `#expect`, `try #require`. XCTest를 새로 쓰지 않는다.
- **금액은 전부 `Decimal`이다.** `Double`을 쓰지 않는다 — 항목 합계와 부과액을 견주는 화면이 있어 원 단위 오차가 그대로 보인다.
- **`nil`은 `0`이 아니다.** 사용량 5종에서 `nil` = 고지서에서 못 읽음, `0` = 안 썼다. 차트에서 `nil` 칸은 트랙 색으로 남긴다(`ChartPoint.value: Decimal?`가 이미 그 규칙이다).
- **목록·상세는 `dueAmount`(청구액), 통계는 `chargedAmount`(부과액)다.** `/maintenance/trends`에 `dueAmount`가 없다. 통계 화면에 「부과액 기준」이라고 적는다.
- **차트 탭은 콜아웃만 바꾼다.** 화면을 옮기거나 달을 바꾸지 않는다.
- **나눗셈은 뷰가 아니라 `MaintenanceTrendMath` 또는 뷰모델에서 한다.**
- **주석은 한국어로 「왜」를 적는다.** 코드가 이미 말하는 「무엇」을 반복하지 않는다.
- **시뮬레이터로 앱을 띄우지 않는다.** UI 확인은 사용자가 실기기로 한다. `xcodebuild test`만 실행한다.
- **신규 `.swift`는 프로젝트 등록이 필요 없다.** 앱 타깃·테스트 타깃 모두 폴더 동기화(`6759fbb`)다. 폴더에 파일을 만들면 그대로 빌드에 들어간다.
- 커밋은 태스크마다. 메시지는 저장소 관례(한국어 한 줄, `feat:`/`refactor:`/`docs:`)를 따른다.
- 브랜치는 `feat/maintenance-bills` (스펙 커밋 `fec29ad`이 이미 올라가 있다).

### 테스트 실행

```bash
cd /Users/youngminmoon/Documents/moonjm/woori-haru
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/<SuiteName> 2>&1 | tail -30
```

전체 실행은 `-only-testing`을 뺀다. 빌드만 확인할 때는

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

→ `** BUILD SUCCEEDED **`.

---

## 파일 구조

**신규 — 모델/서비스**
- `WooriHaru/Models/MaintenanceModels.swift` — 서버 응답·요청 전부. `MaintenanceBill`, `MaintenanceBillItem`, `MaintenanceUsage`, `MaintenanceRecognition`, `MaintenanceBillSaveRequest`, `MaintenanceTrendMonth`
- `WooriHaru/Services/MaintenanceService.swift` — `MaintenanceServing` 프로토콜 + `MaintenanceService` 구현

**신규 — 파생 계산 (순수 함수)**
- `WooriHaru/Models/MaintenanceTrendMath.swift` — 정렬·전년 동월 매칭·항목 이름 모으기·사용량 시리즈·전월 대비 증감. **뷰도 뷰모델도 여기 말고 다른 데서 계산하지 않는다.**

**신규 — 뷰모델**
- `WooriHaru/ViewModels/MaintenanceBillsViewModel.swift` — 목록·상세·삭제
- `WooriHaru/ViewModels/MaintenanceUploadViewModel.swift` — 사진·인식
- `WooriHaru/ViewModels/MaintenanceBillFormViewModel.swift` — 검수·편집 공용
- `WooriHaru/ViewModels/MaintenanceTrendsViewModel.swift` — 통계 5장

**신규 — 화면**
- `WooriHaru/Views/Maintenance/MaintenanceView.swift` — 탭 껍데기 + 내역 탭
- `WooriHaru/Views/Maintenance/MaintenanceBillCard.swift` — 목록 카드 한 장
- `WooriHaru/Views/Maintenance/MaintenanceUploadView.swift`
- `WooriHaru/Views/Maintenance/MaintenanceBillFormView.swift`
- `WooriHaru/Views/Maintenance/MaintenanceItemRow.swift` — 항목 편집 행
- `WooriHaru/Views/Maintenance/MaintenanceUsageFields.swift` — 사용량 입력 5칸
- `WooriHaru/Views/Maintenance/MaintenanceBillDetailView.swift`
- `WooriHaru/Views/Maintenance/MaintenanceStatsTab.swift` — 차트 5장
- `WooriHaru/Views/Vehicle/Charts/DivergingRankList.swift` — 신규 차트 원형(#3)

**신규 — 테스트**
- `WooriHaruTests/MaintenanceTests.swift` — 모델 디코딩·서비스
- `WooriHaruTests/MaintenanceFormTests.swift` — 폼 뷰모델
- `WooriHaruTests/MaintenanceTrendTests.swift` — 파생 계산·통계 뷰모델·`DivergingRankList` 기하

**수정**
- `WooriHaru/ContentView.swift` — `AppDestination.maintenance` 추가 + `navigationDestination` 분기
- `WooriHaru/Views/Components/SideDrawerView.swift` — 드로어 항목 「관리비」

**파일이 커지기 쉬운 자리는 처음부터 가른다.** 폼(`MaintenanceBillFormView`)에서 항목 행과 사용량 입력을 빼고, 통계 탭에서 차트 카드를 각각 `private var`로 나눈다. 한 파일이 400줄을 넘으면 그때 나누는 게 아니라 그전에 나눈다.

---

## Task 1: 모델과 디코딩

**Files:**
- Create: `WooriHaru/Models/MaintenanceModels.swift`
- Test: `WooriHaruTests/MaintenanceTests.swift`

**Interfaces:**
- Consumes: `DataResponse<T>` (`WooriHaru/Models/APIResponse.swift`)
- Produces:
  - `struct MaintenanceBillItem: Codable, Equatable, Identifiable { let name: String; let amount: Decimal; var id: String { name } }`
  - `struct MaintenanceUsage: Codable, Equatable { let electricityKwh, waterM3, hotWaterM3, heatingGcal, foodKg: Decimal? }`
  - `struct MaintenanceBill: Codable, Equatable, Identifiable { let yearMonth: String; let dong, ho: String?; let areaM2: Decimal?; let items: [MaintenanceBillItem]; let usage: MaintenanceUsage?; let chargedAmount, discountTotal, unpaidAmount, unpaidLateFee, dueAmount: Decimal; let dueDate: String?; var id: String { yearMonth } }`
  - `struct MaintenanceBillList: Codable, Equatable { let bills: [MaintenanceBill] }`
  - `struct MaintenanceRecognition: Codable, Equatable { /* MaintenanceBill의 필드 전부 + */ let yearMonth: String?; let sumMatched: Bool; let warnings: [String] }`
  - `struct MaintenanceTrendMonth: Codable, Equatable, Identifiable { let yearMonth: String; let chargedAmount: Decimal; let items: [MaintenanceBillItem]; let usage: MaintenanceUsage?; var id: String { yearMonth } }`
  - `struct MaintenanceTrend: Codable, Equatable { let months: [MaintenanceTrendMonth] }`
  - `struct MaintenanceBillSaveRequest: Encodable, Equatable { let yearMonth: String; let items: [MaintenanceBillItemRequest]; let chargedAmount, dueAmount: Decimal; let dong, ho: String?; let areaM2: Decimal?; let usage: MaintenanceUsage?; let discountTotal, unpaidAmount, unpaidLateFee: Decimal; let dueDate: String? }`
  - `struct MaintenanceBillItemRequest: Encodable, Equatable { let name: String; let amount: Decimal }`

**설계 메모(구현자가 알아야 하는 것):**

- `MaintenanceRecognition`은 `MaintenanceBill`을 품지 않고 **필드를 펼쳐 갖는다.** 서버가 중첩 없이 평평하게 주기 때문이다. 두 타입이 필드를 공유하고 싶겠지만 상속으로 묶지 않는다 — `yearMonth`가 한쪽은 `String`, 다른 쪽은 `String?`라 같은 타입이 될 수 없다.
- `usage`를 옵셔널로 둔다. 스키마상 `$ref`라 항상 올 것 같지만, **키가 통째로 빠진 응답 하나에 목록 전체 디코딩이 깨진다.** 배차표 `slotCode`에서 같은 이유로 옵셔널을 택했다.
- `MaintenanceBillItem.id`를 `name`으로 두는 것은 **한 달 안에서 이름이 유일하다는 가정**이다. 고지서 표가 그렇다. 폼에서 항목을 편집할 때는 이 `id`를 쓰지 않는다(편집 중에는 이름이 겹칠 수 있다) — Task 6이 별도 `UUID`를 가진 편집용 타입을 만든다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceTests.swift`

```swift
import Foundation
import Testing
@testable import WooriHaru

struct MaintenanceModelTests {
    /// 서버 `BillResponse`를 그대로 옮긴 응답. 필드가 하나라도 어긋나면 디코딩이 깨진다.
    static let billJSON = """
    {
      "data": {
        "yearMonth": "2026-08",
        "dong": "101",
        "ho": "1502",
        "areaM2": 84.97,
        "items": [
          { "name": "일반관리비", "amount": 121500 },
          { "name": "세대전기료", "amount": 48320 }
        ],
        "usage": {
          "electricityKwh": 312.5,
          "waterM3": 14.2,
          "hotWaterM3": null,
          "heatingGcal": null,
          "foodKg": 8.4
        },
        "chargedAmount": 169820,
        "discountTotal": 1200,
        "unpaidAmount": 0,
        "unpaidLateFee": 0,
        "dueAmount": 168620,
        "dueDate": "2026-08-31"
      }
    }
    """

    @Test func 한_달_관리비를_디코딩한다() throws {
        let data = Data(Self.billJSON.utf8)
        let response = try JSONDecoder().decode(DataResponse<MaintenanceBill>.self, from: data)
        let bill = try #require(response.data)

        #expect(bill.yearMonth == "2026-08")
        #expect(bill.items.count == 2)
        #expect(bill.items[0].amount == Decimal(121500))
        #expect(bill.dueAmount == Decimal(168620))
        #expect(bill.dueDate == "2026-08-31")
    }

    /// 못 읽은 사용량은 **0이 아니라 nil이다.** 0으로 접히면 통계에서
    /// 「안 쓴 달」과 「못 읽은 달」이 같은 막대가 된다.
    @Test func 없는_사용량은_nil로_남는다() throws {
        let data = Data(Self.billJSON.utf8)
        let bill = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceBill>.self, from: data).data
        )
        let usage = try #require(bill.usage)

        #expect(usage.electricityKwh == Decimal(string: "312.5"))
        #expect(usage.hotWaterM3 == nil)
        #expect(usage.heatingGcal == nil)
    }

    /// `usage` 키가 통째로 빠진 응답에도 나머지가 살아야 한다 — 한 달이 디코딩을
    /// 깨뜨리면 목록 화면 전체가 빈다.
    @Test func usage가_없어도_디코딩된다() throws {
        let json = """
        {
          "data": {
            "yearMonth": "2026-07",
            "dong": null, "ho": null, "areaM2": null,
            "items": [{ "name": "일반관리비", "amount": 100 }],
            "chargedAmount": 100, "discountTotal": 0,
            "unpaidAmount": 0, "unpaidLateFee": 0,
            "dueAmount": 100, "dueDate": null
          }
        }
        """
        let bill = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceBill>.self, from: Data(json.utf8)).data
        )
        #expect(bill.usage == nil)
        #expect(bill.dueDate == nil)
    }

    /// 인식 결과는 `yearMonth`가 **옵셔널**이다 — 고지서 제목이 잘리면 서버가 못 읽는다.
    @Test func 인식_결과를_디코딩한다() throws {
        let json = """
        {
          "data": {
            "yearMonth": null,
            "dong": "101", "ho": "1502", "areaM2": 84.97,
            "items": [{ "name": "일반관리비", "amount": 121500 }],
            "usage": { "electricityKwh": 312.5, "waterM3": null,
                       "hotWaterM3": null, "heatingGcal": null, "foodKg": null },
            "chargedAmount": 121500, "discountTotal": 0,
            "unpaidAmount": 0, "unpaidLateFee": 0,
            "dueAmount": 121500, "dueDate": null,
            "sumMatched": false,
            "warnings": ["항목 합계가 부과액과 맞지 않습니다"]
          }
        }
        """
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceRecognition>.self, from: Data(json.utf8)).data
        )
        #expect(recognition.yearMonth == nil)
        #expect(recognition.sumMatched == false)
        #expect(recognition.warnings == ["항목 합계가 부과액과 맞지 않습니다"])
    }

    /// 목록 응답은 `bills` 배열로 한 겹 더 싸여 온다.
    @Test func 목록을_디코딩한다() throws {
        let json = """
        { "data": { "bills": [
            { "yearMonth": "2026-08", "dong": null, "ho": null, "areaM2": null,
              "items": [], "chargedAmount": 10, "discountTotal": 0,
              "unpaidAmount": 0, "unpaidLateFee": 0, "dueAmount": 10, "dueDate": null }
        ] } }
        """
        let list = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceBillList>.self, from: Data(json.utf8)).data
        )
        #expect(list.bills.count == 1)
        #expect(list.bills[0].yearMonth == "2026-08")
    }

    /// 추이 응답. `dueAmount`가 없다 — 통계는 부과액 기준이다.
    @Test func 추이를_디코딩한다() throws {
        let json = """
        { "data": { "months": [
            { "yearMonth": "2025-08", "chargedAmount": 150000,
              "items": [{ "name": "일반관리비", "amount": 100000 }],
              "usage": { "electricityKwh": 300, "waterM3": null,
                         "hotWaterM3": null, "heatingGcal": null, "foodKg": null } }
        ] } }
        """
        let trend = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceTrend>.self, from: Data(json.utf8)).data
        )
        #expect(trend.months.count == 1)
        #expect(trend.months[0].chargedAmount == Decimal(150000))
    }

    /// 비운 사용량 칸은 **키째 빠져야 한다.** 0으로 나가면 서버에 「0을 썼다」가 저장된다.
    @Test func 저장_요청에서_빈_사용량은_키가_빠진다() throws {
        let request = MaintenanceBillSaveRequest(
            yearMonth: "2026-08",
            items: [MaintenanceBillItemRequest(name: "일반관리비", amount: 100)],
            chargedAmount: 100, dueAmount: 100,
            dong: nil, ho: nil, areaM2: nil,
            usage: MaintenanceUsage(electricityKwh: Decimal(312),
                                    waterM3: nil, hotWaterM3: nil,
                                    heatingGcal: nil, foodKg: nil),
            discountTotal: 0, unpaidAmount: 0, unpaidLateFee: 0, dueDate: nil
        )
        let data = try JSONEncoder().encode(request)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let usage = try #require(json["usage"] as? [String: Any])

        #expect(usage["electricityKwh"] != nil)
        #expect(usage["waterM3"] == nil)
        #expect(json["dong"] == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceModelTests 2>&1 | tail -30
```

기대: 컴파일 실패 — `cannot find 'MaintenanceBill' in scope`.

- [ ] **Step 3: 모델을 쓴다**

`WooriHaru/Models/MaintenanceModels.swift`

```swift
import Foundation

/// 고지서 항목 한 줄. **한 달 안에서 이름이 유일하다**는 고지서 표의 성질에 기대 `id`를 이름으로 둔다.
/// 편집 중에는 이름이 겹칠 수 있어 폼은 이 `id`를 쓰지 않는다(`MaintenanceItemDraft`).
struct MaintenanceBillItem: Codable, Equatable, Identifiable {
    let name: String
    let amount: Decimal
    var id: String { name }
}

/// 사용량 다섯 값. **전부 옵셔널이다** — 여름엔 난방 Gcal이 아예 안 찍히고, 사진이 잘리면
/// 어느 것이든 빠진다. `nil`(못 읽음)과 `0`(안 씀)은 다른 뜻이라 접지 않는다.
struct MaintenanceUsage: Codable, Equatable {
    let electricityKwh: Decimal?
    let waterM3: Decimal?
    let hotWaterM3: Decimal?
    let heatingGcal: Decimal?
    let foodKg: Decimal?
}

/// 저장된 한 달.
///
/// **금액이 `Decimal`인 이유.** 검수 화면이 항목 합계와 부과액을 견주는데, `Double`이면
/// 원 단위 합계에 없던 오차가 생겨 사람이 고칠 수 없는 「불일치」가 뜬다.
struct MaintenanceBill: Codable, Equatable, Identifiable {
    let yearMonth: String
    let dong: String?
    let ho: String?
    let areaM2: Decimal?
    let items: [MaintenanceBillItem]
    /// **옵셔널로 둔다** — 키가 통째로 빠진 한 달 때문에 목록 전체 디코딩이 깨지면 화면이 빈다.
    let usage: MaintenanceUsage?
    let chargedAmount: Decimal
    let discountTotal: Decimal
    let unpaidAmount: Decimal
    let unpaidLateFee: Decimal
    /// **실제로 내는 돈.** 목록·상세가 앞세우는 값이다(추이에는 이 값이 없다).
    let dueAmount: Decimal
    let dueDate: String?

    var id: String { yearMonth }
}

struct MaintenanceBillList: Codable, Equatable {
    let bills: [MaintenanceBill]
}

/// 사진에서 읽은 결과. **아무것도 저장되지 않았다** — 검수를 거쳐 확정한다.
///
/// `MaintenanceBill`을 품지 않고 필드를 펼쳐 갖는다. 서버가 평평하게 주기도 하고,
/// `yearMonth`가 여기서는 옵셔널이라 애초에 같은 타입이 될 수 없다.
struct MaintenanceRecognition: Codable, Equatable {
    /// 고지서 제목이 잘려 서버가 못 읽으면 nil이다. **검수 화면이 채운다.**
    let yearMonth: String?
    let dong: String?
    let ho: String?
    let areaM2: Decimal?
    let items: [MaintenanceBillItem]
    let usage: MaintenanceUsage?
    let chargedAmount: Decimal
    let discountTotal: Decimal
    let unpaidAmount: Decimal
    let unpaidLateFee: Decimal
    let dueAmount: Decimal
    let dueDate: String?
    /// 항목 합계가 부과액과 맞는가. false면 어딘가 잘못 읽혔다는 뜻이다.
    let sumMatched: Bool
    /// **이미 사용자용 한국어다** — 앱이 다시 쓰지 않고 그대로 띄운다.
    let warnings: [String]
}

/// 추이 한 달. **`dueAmount`가 없다** — 서버가 부과액만 준다. 통계 화면이 「부과액 기준」이라고 적는다.
struct MaintenanceTrendMonth: Codable, Equatable, Identifiable {
    let yearMonth: String
    let chargedAmount: Decimal
    let items: [MaintenanceBillItem]
    let usage: MaintenanceUsage?

    var id: String { yearMonth }
}

struct MaintenanceTrend: Codable, Equatable {
    let months: [MaintenanceTrendMonth]
}

struct MaintenanceBillItemRequest: Encodable, Equatable {
    /// 서버 한도 50자.
    let name: String
    let amount: Decimal
}

/// 저장·수정 요청. 둘이 같은 바디를 쓴다(`POST`는 새로, `PUT`은 그 달을 통째로 갈아 끼운다).
///
/// **`JSONEncoder`는 nil 프로퍼티의 키를 아예 뺀다.** 비운 사용량 칸을 0으로 채우지 않고
/// nil로 두는 이유가 이것이다 — 0으로 보내면 서버에 「0을 썼다」가 저장된다.
struct MaintenanceBillSaveRequest: Encodable, Equatable {
    let yearMonth: String
    /// 서버 `minItems: 1` — 빈 배열이면 400이다. 폼이 저장 버튼을 잠가 막는다.
    let items: [MaintenanceBillItemRequest]
    let chargedAmount: Decimal
    let dueAmount: Decimal
    let dong: String?
    let ho: String?
    let areaM2: Decimal?
    let usage: MaintenanceUsage?
    let discountTotal: Decimal
    let unpaidAmount: Decimal
    let unpaidLateFee: Decimal
    let dueDate: String?
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceModelTests 2>&1 | tail -30
```

기대: 7개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/MaintenanceModels.swift WooriHaruTests/MaintenanceTests.swift
git commit -m "feat: 관리비 응답·요청 모델을 만든다"
```

---

## Task 2: 서비스

**Files:**
- Create: `WooriHaru/Services/MaintenanceService.swift`
- Test: `WooriHaruTests/MaintenanceTests.swift` (수트 추가)

**Interfaces:**
- Consumes: Task 1의 모델 전부, `APIClientProtocol`(`api.get`/`postVoid`/`putVoid`/`deleteVoid`/`postMultipart`), `APIError`
- Produces:
  - `protocol MaintenanceServing: Sendable` — `fetchBills()`, `fetchBill(yearMonth:)`, `recognize(imageData:)`, `saveBill(_:)`, `updateBill(yearMonth:_:)`, `deleteBill(yearMonth:)`, `fetchTrends(months:)`
  - `struct MaintenanceService: MaintenanceServing` — `init(api: any APIClientProtocol = APIClient.shared)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceTests.swift` 아래에 덧붙인다.

```swift
@MainActor
struct MaintenanceServiceTests {
    private func makeBill(_ yearMonth: String) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil,
                        chargedAmount: 0, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: 0, dueDate: nil)
    }

    @Test func 목록을_받아_bills를_꺼낸다() async throws {
        let api = MockAPIClient()
        api.stubGet("/maintenance/bills",
                    result: DataResponse(data: MaintenanceBillList(bills: [makeBill("2026-08")])))
        let service = MaintenanceService(api: api)

        let bills = try await service.fetchBills()

        #expect(bills.map(\.yearMonth) == ["2026-08"])
        #expect(api.getCalls.map(\.path) == ["/maintenance/bills"])
    }

    @Test func 상세는_연월을_경로에_넣는다() async throws {
        let api = MockAPIClient()
        api.stubGet("/maintenance/bills/2026-08", result: DataResponse(data: makeBill("2026-08")))
        let service = MaintenanceService(api: api)

        let bill = try await service.fetchBill(yearMonth: "2026-08")

        #expect(bill.yearMonth == "2026-08")
        #expect(api.getCalls.map(\.path) == ["/maintenance/bills/2026-08"])
    }

    /// 추이는 `months`를 쿼리로 싣는다. 기본 13은 **전년 동월이 범위에 들어오라고** 고른 값이다.
    @Test func 추이는_months를_쿼리로_보낸다() async throws {
        let api = MockAPIClient()
        api.stubGet("/maintenance/trends", result: DataResponse(data: MaintenanceTrend(months: [])))
        let service = MaintenanceService(api: api)

        _ = try await service.fetchTrends(months: 13)

        #expect(api.getCalls.first?.query == ["months": "13"])
    }

    /// 인식은 multipart다. **`image/jpeg`로 보낸다** — 서버가 이 값으로 디코더를 고르는데
    /// HEIC 원본을 jpeg로 위장해 보내면 `IMAGE_UNREADABLE`이 된다.
    @Test func 인식은_jpeg_multipart로_나간다() async throws {
        let api = MockAPIClient()
        let recognition = MaintenanceRecognition(
            yearMonth: "2026-08", dong: nil, ho: nil, areaM2: nil,
            items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
            unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil,
            sumMatched: true, warnings: []
        )
        api.stubMultipartJSON("/maintenance/recognitions", result: DataResponse(data: recognition))
        let service = MaintenanceService(api: api)

        _ = try await service.recognize(imageData: Data([0xFF, 0xD8]))

        let call = try #require(api.multipartJSONCalls.first)
        #expect(call.path == "/maintenance/recognitions")
        #expect(call.mimeType == "image/jpeg")
        #expect(call.fileName.hasSuffix(".jpg"))
    }

    /// 인식 응답이 비면 200이라도 실패다 — nil을 들고 검수 화면을 열 수 없다.
    @Test func 빈_인식_응답은_에러다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/maintenance/recognitions",
                              result: DataResponse<MaintenanceRecognition>(data: nil))
        let service = MaintenanceService(api: api)

        await #expect(throws: (any Error).self) {
            _ = try await service.recognize(imageData: Data())
        }
    }

    @Test func 저장과_수정과_삭제가_각_경로로_나간다() async throws {
        let api = MockAPIClient()
        let service = MaintenanceService(api: api)
        let request = MaintenanceBillSaveRequest(
            yearMonth: "2026-08",
            items: [MaintenanceBillItemRequest(name: "일반관리비", amount: 100)],
            chargedAmount: 100, dueAmount: 100,
            dong: nil, ho: nil, areaM2: nil, usage: nil,
            discountTotal: 0, unpaidAmount: 0, unpaidLateFee: 0, dueDate: nil
        )

        try await service.saveBill(request)
        try await service.updateBill(yearMonth: "2026-08", request)
        try await service.deleteBill(yearMonth: "2026-08")

        #expect(api.postCalls.map(\.path) == ["/maintenance/bills"])
        #expect(api.putVoidCalls.map(\.path) == ["/maintenance/bills/2026-08"])
        #expect(api.deleteCalls == ["/maintenance/bills/2026-08"])
    }
}
```

> **`MockAPIClient`에 없는 접근자가 있으면 이 태스크에서 더한다.** `getCalls`·`postCalls`·`putVoidCalls`·`deleteCalls`·`multipartJSONCalls`가 이미 있는지 먼저 `grep -n "var getCalls\|var putVoidCalls\|var deleteCalls\|var multipartJSONCalls" WooriHaruTests/MockAPIClient.swift`로 확인하고, 없는 것만 기존 기록 배열을 그대로 노출하는 `var`로 추가한다. **기록 배열의 이름·타입을 바꾸지 않는다** — 다른 스위트가 이미 쓴다.

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceServiceTests 2>&1 | tail -30
```

기대: `cannot find 'MaintenanceService' in scope`.

- [ ] **Step 3: 서비스를 쓴다**

`WooriHaru/Services/MaintenanceService.swift`

```swift
import Foundation

/// 관리비 API. 테스트에서 대체할 수 있도록 프로토콜로 분리한다(`DispatchServing`과 같은 꼴).
protocol MaintenanceServing: Sendable {
    /// 저장된 달 전부. **최근 달부터 온다** — 목록 화면이 그 순서를 그대로 쓴다.
    func fetchBills() async throws -> [MaintenanceBill]

    func fetchBill(yearMonth: String) async throws -> MaintenanceBill

    /// 고지서 사진 한 장을 인식한다. **아무것도 저장되지 않는다** — 검수를 거쳐 `saveBill`로 확정한다.
    ///
    /// **연월을 보내지 않는다.** 고지서에 적힌 것을 서버가 읽는다. 앱이 보내면 사람이 손으로
    /// 넣은 오타가 그대로 엉뚱한 달에 저장된다(배차표에서 같은 판단을 했다).
    func recognize(imageData: Data) async throws -> MaintenanceRecognition

    /// 검수 확정분을 저장한다. **같은 달이 이미 있으면 409다** — 호출부가 「기존 내역 수정」으로 잇는다.
    func saveBill(_ request: MaintenanceBillSaveRequest) async throws

    /// 한 달을 통째로 갈아 끼운다. 항목은 병합이 아니라 교체다.
    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws

    func deleteBill(yearMonth: String) async throws

    /// 항목·사용량 월별 추이. **13이 기본인 이유는 전년 동월이 범위에 들어오게 하려는 것이다.**
    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth]
}

struct MaintenanceService: MaintenanceServing {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func fetchBills() async throws -> [MaintenanceBill] {
        let response: DataResponse<MaintenanceBillList> =
            try await api.get("/maintenance/bills", query: [:])
        return response.data?.bills ?? []
    }

    func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
        let response: DataResponse<MaintenanceBill> =
            try await api.get("/maintenance/bills/\(yearMonth)", query: [:])
        guard let bill = response.data else {
            throw APIError.serverError(statusCode: 200, message: "관리비 응답이 비어 있습니다")
        }
        return bill
    }

    func recognize(imageData: Data) async throws -> MaintenanceRecognition {
        let response: DataResponse<MaintenanceRecognition> = try await api.postMultipart(
            "/maintenance/recognitions",
            query: [:],
            fileData: imageData,
            fileName: "maintenance.jpg",
            mimeType: "image/jpeg"
        )
        guard let recognition = response.data else {
            throw APIError.serverError(statusCode: 200, message: "인식 응답이 비어 있습니다")
        }
        return recognition
    }

    func saveBill(_ request: MaintenanceBillSaveRequest) async throws {
        // 201 본문에 문자열이 실려 오지만 쓰지 않는다 — 저장한 연월은 호출부가 이미 안다.
        try await api.postVoid("/maintenance/bills", body: request)
    }

    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {
        try await api.putVoid("/maintenance/bills/\(yearMonth)", body: request)
    }

    func deleteBill(yearMonth: String) async throws {
        try await api.deleteVoid("/maintenance/bills/\(yearMonth)")
    }

    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] {
        let response: DataResponse<MaintenanceTrend> =
            try await api.get("/maintenance/trends", query: ["months": String(months)])
        return response.data?.months ?? []
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceServiceTests 2>&1 | tail -30
```

기대: 6개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Services/MaintenanceService.swift WooriHaruTests/MaintenanceTests.swift WooriHaruTests/MockAPIClient.swift
git commit -m "feat: 관리비 API 서비스를 붙인다"
```

---

## Task 3: 목록 뷰모델 + 전월 대비 계산

**Files:**
- Create: `WooriHaru/ViewModels/MaintenanceBillsViewModel.swift`
- Create: `WooriHaru/Models/MaintenanceTrendMath.swift`
- Test: `WooriHaruTests/MaintenanceTrendTests.swift`

**Interfaces:**
- Consumes: `MaintenanceServing`, `MaintenanceBill` (Task 1·2)
- Produces:
  - `enum MaintenanceTrendMath` — 이 태스크에서는 `static func previousMonth(of yearMonth: String) -> String?`와 `static func monthOverMonth(bills: [MaintenanceBill], at index: Int) -> MaintenanceDelta?` 둘만. Task 9가 같은 enum에 추이 함수들을 더한다.
  - `struct MaintenanceDelta: Equatable { let amount: Decimal; let ratio: Decimal? }`
  - `@MainActor @Observable final class MaintenanceBillsViewModel` — `bills: [MaintenanceBill]`, `isLoading: Bool`, `errorMessage: String?`, `load() async`, `delete(yearMonth:) async -> Bool`

**설계 메모:**

- **전월 대비는 「바로 앞 달」이 목록에 있을 때만 낸다.** 8월과 6월밖에 없는데 그 둘을 견주고 「전월 대비」라고 적으면 거짓이다. `previousMonth`가 문자열 산술로 앞 달을 만들고, 목록의 다음 원소가 그 달일 때만 델타가 나온다.
- **연 넘김을 문자열로 처리한다.** `2026-01`의 앞 달은 `2025-12`다. `Calendar`를 쓰지 않는다 — 기기 달력이 불교력이면 `2569-01`이 나온다(배차표가 `dispatchGregorian`을 따로 둔 것과 같은 함정인데, 여기서는 애초에 날짜 타입을 거치지 않는 게 더 간단하다).
- **비율은 앞 달이 0이면 nil이다.** 0으로 나누지 않는다. 화면은 그때 금액 차이만 적는다.
- `delete`가 `Bool`을 돌려주는 것은 **화면이 성공했을 때만 뒤로 물러나야** 하기 때문이다. 실패했는데 물러나면 사용자는 지워진 줄 안다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceTrendTests.swift`

```swift
import Foundation
import Testing
@testable import WooriHaru

struct MaintenanceMonthMathTests {
    @Test func 앞_달을_만든다() {
        #expect(MaintenanceTrendMath.previousMonth(of: "2026-08") == "2026-07")
    }

    /// 연 넘김. `Calendar`를 쓰지 않는 이유가 여기 있다 — 문자열 산술이라 기기 달력 설정을 타지 않는다.
    @Test func 일월의_앞_달은_작년_십이월이다() {
        #expect(MaintenanceTrendMath.previousMonth(of: "2026-01") == "2025-12")
    }

    @Test func 형식이_틀리면_nil이다() {
        #expect(MaintenanceTrendMath.previousMonth(of: "2026") == nil)
        #expect(MaintenanceTrendMath.previousMonth(of: "abcd-ef") == nil)
    }
}

struct MaintenanceDeltaTests {
    private func bill(_ yearMonth: String, due: Decimal) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil,
                        chargedAmount: due, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: due, dueDate: nil)
    }

    @Test func 바로_앞_달과_견준다() throws {
        let bills = [bill("2026-08", due: 168_620), bill("2026-07", due: 156_320)]
        let delta = try #require(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0))

        #expect(delta.amount == Decimal(12_300))
        // 12300 / 156320 ≈ 0.0787
        let ratio = try #require(delta.ratio)
        #expect(ratio > Decimal(string: "0.078")! && ratio < Decimal(string: "0.079")!)
    }

    /// **연속하지 않은 달은 견주지 않는다.** 8월과 6월을 놓고 「전월 대비」라고 적으면 거짓이다.
    @Test func 달이_건너뛰면_델타가_없다() {
        let bills = [bill("2026-08", due: 100), bill("2026-06", due: 50)]
        #expect(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0) == nil)
    }

    @Test func 마지막_달은_델타가_없다() {
        let bills = [bill("2026-08", due: 100)]
        #expect(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0) == nil)
    }

    /// 앞 달이 0이면 비율이 나오지 않는다 — 0으로 나누지 않는다. 금액 차이만 남는다.
    @Test func 앞_달이_0이면_비율은_nil이다() throws {
        let bills = [bill("2026-08", due: 100), bill("2026-07", due: 0)]
        let delta = try #require(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0))

        #expect(delta.amount == Decimal(100))
        #expect(delta.ratio == nil)
    }
}

@MainActor
struct MaintenanceBillsViewModelTests {
    private func bill(_ yearMonth: String) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil,
                        chargedAmount: 0, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: 0, dueDate: nil)
    }

    /// 목록·삭제 호출을 기록하는 대역. 서비스가 프로토콜이라 `MockAPIClient` 없이도 선다.
    final class FakeService: MaintenanceServing, @unchecked Sendable {
        var bills: [MaintenanceBill] = []
        var listError: Error?
        var deleteError: Error?
        private(set) var deletedYearMonths: [String] = []
        private(set) var listCallCount = 0

        func fetchBills() async throws -> [MaintenanceBill] {
            listCallCount += 1
            if let listError { throw listError }
            return bills
        }
        func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
            MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                            items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
                            unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil)
        }
        func recognize(imageData: Data) async throws -> MaintenanceRecognition {
            fatalError("이 스위트는 인식을 부르지 않는다")
        }
        func saveBill(_ request: MaintenanceBillSaveRequest) async throws {}
        func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {}
        func deleteBill(yearMonth: String) async throws {
            deletedYearMonths.append(yearMonth)
            if let deleteError { throw deleteError }
        }
        func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] { [] }
    }

    @Test func 목록을_받아_담는다() async {
        let service = FakeService()
        service.bills = [bill("2026-08"), bill("2026-07")]
        let vm = MaintenanceBillsViewModel(service: service)

        await vm.load()

        #expect(vm.bills.map(\.yearMonth) == ["2026-08", "2026-07"])
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func 실패하면_메시지를_남기고_목록을_비우지_않는다() async {
        let service = FakeService()
        service.bills = [bill("2026-08")]
        let vm = MaintenanceBillsViewModel(service: service)
        await vm.load()

        service.listError = APIError.serverError(statusCode: 500, message: nil)
        await vm.load()

        #expect(vm.errorMessage != nil)
        // 이미 받아 둔 목록을 지우지 않는다 — 새로고침 한 번 실패했다고 화면이 비면 안 된다.
        #expect(vm.bills.map(\.yearMonth) == ["2026-08"])
    }

    @Test func 삭제에_성공하면_목록에서_빠진다() async {
        let service = FakeService()
        service.bills = [bill("2026-08"), bill("2026-07")]
        let vm = MaintenanceBillsViewModel(service: service)
        await vm.load()

        let ok = await vm.delete(yearMonth: "2026-08")

        #expect(ok == true)
        #expect(service.deletedYearMonths == ["2026-08"])
        #expect(vm.bills.map(\.yearMonth) == ["2026-07"])
    }

    /// **실패하면 false다.** 화면이 이 값을 보고 물러날지 정한다 — 실패했는데 물러나면
    /// 사용자는 지워진 줄 안다.
    @Test func 삭제에_실패하면_false고_목록이_그대로다() async {
        let service = FakeService()
        service.bills = [bill("2026-08")]
        let vm = MaintenanceBillsViewModel(service: service)
        await vm.load()
        service.deleteError = APIError.serverError(statusCode: 500, message: nil)

        let ok = await vm.delete(yearMonth: "2026-08")

        #expect(ok == false)
        #expect(vm.bills.map(\.yearMonth) == ["2026-08"])
        #expect(vm.errorMessage != nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceMonthMathTests \
  -only-testing:WooriHaruTests/MaintenanceDeltaTests \
  -only-testing:WooriHaruTests/MaintenanceBillsViewModelTests 2>&1 | tail -30
```

기대: `cannot find 'MaintenanceTrendMath' in scope`.

- [ ] **Step 3: 계산과 뷰모델을 쓴다**

`WooriHaru/Models/MaintenanceTrendMath.swift`

```swift
import Foundation

/// 앞 달과의 차이. `ratio`는 0…1이 아니라 **비율 그대로다**(0.0787 = 7.87%).
/// 앞 달이 0이면 nil — 0으로 나누지 않는다.
struct MaintenanceDelta: Equatable {
    let amount: Decimal
    let ratio: Decimal?
}

/// 관리비 파생 계산. **뷰도 뷰모델도 여기 말고 다른 데서 계산하지 않는다** —
/// 두 군데서 계산하면 테스트하는 값과 화면 값이 다른 코드가 된다.
enum MaintenanceTrendMath {
    /// `"2026-08"` → `"2026-07"`. **`Calendar`를 쓰지 않는다** — 기기 달력을 불교력으로 둔
    /// 기기에서 `2569-07`이 나온다. 서버로 나가는 값은 늘 ISO 그레고리력 문자열이라
    /// 문자열 산술이 오히려 정확하고 짧다.
    static func previousMonth(of yearMonth: String) -> String? {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        return month == 1
            ? String(format: "%04d-12", year - 1)
            : String(format: "%04d-%02d", year, month - 1)
    }

    /// 목록에서 `index`번째 달과 **바로 다음 원소**를 견준다.
    ///
    /// **다음 원소가 바로 앞 달일 때만 낸다.** 목록은 최근 달부터라 다음 원소가 앞 달이지만,
    /// 등록을 건너뛴 달이 있으면 8월 다음이 6월이다 — 그 둘을 견주고 「전월 대비」라고
    /// 적으면 거짓이다.
    static func monthOverMonth(bills: [MaintenanceBill], at index: Int) -> MaintenanceDelta? {
        guard bills.indices.contains(index), bills.indices.contains(index + 1) else { return nil }
        let current = bills[index]
        let previous = bills[index + 1]
        guard previousMonth(of: current.yearMonth) == previous.yearMonth else { return nil }

        let amount = current.dueAmount - previous.dueAmount
        let ratio = previous.dueAmount == 0 ? nil : amount / previous.dueAmount
        return MaintenanceDelta(amount: amount, ratio: ratio)
    }
}
```

`WooriHaru/ViewModels/MaintenanceBillsViewModel.swift`

```swift
import Foundation

/// 관리비 내역 목록. 상세는 화면이 `MaintenanceBill`을 그대로 들고 가고, 필요할 때만
/// 서버에서 다시 받는다 — 목록 응답이 이미 상세와 같은 필드를 다 갖고 있다.
@MainActor
@Observable
final class MaintenanceBillsViewModel {
    private let service: any MaintenanceServing

    private(set) var bills: [MaintenanceBill] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            bills = try await service.fetchBills()
        } catch is CancellationError {
            // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return
        } catch {
            // **이미 받아 둔 목록을 지우지 않는다** — 새로고침 한 번 실패했다고 화면이 비면,
            // 사용자는 등록한 달이 사라진 줄 안다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
    }

    /// 성공하면 true. **화면은 이 값을 보고 물러난다** — 실패했는데 물러나면 지워진 줄 안다.
    func delete(yearMonth: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.deleteBill(yearMonth: yearMonth)
            bills.removeAll { $0.yearMonth == yearMonth }
            return true
        } catch {
            errorMessage = error.serverMessage ?? error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceMonthMathTests \
  -only-testing:WooriHaruTests/MaintenanceDeltaTests \
  -only-testing:WooriHaruTests/MaintenanceBillsViewModelTests 2>&1 | tail -30
```

기대: 11개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/MaintenanceTrendMath.swift \
        WooriHaru/ViewModels/MaintenanceBillsViewModel.swift \
        WooriHaruTests/MaintenanceTrendTests.swift
git commit -m "feat: 관리비 목록 뷰모델과 전월 대비 계산을 만든다"
```

---

## Task 4: 목록 화면 + 드로어 진입점

**Files:**
- Create: `WooriHaru/Views/Maintenance/MaintenanceView.swift`
- Create: `WooriHaru/Views/Maintenance/MaintenanceBillCard.swift`
- Create: `WooriHaru/Views/Maintenance/MaintenanceFormat.swift`
- Modify: `WooriHaru/ContentView.swift` (`AppDestination` enum + `navigationDestination` switch)
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift` (`drawerItem` 목록)

**Interfaces:**
- Consumes: `MaintenanceBillsViewModel`, `MaintenanceTrendMath.monthOverMonth`, `MaintenanceDelta`, `MaintenanceBill` (Task 1·3), `GlassCard`, `glassScreenBackground()`, `vehicleDarkTheme()`, `VehicleTheme`
- Produces:
  - `enum MaintenanceFormat` — `static func won(_ value: Decimal) -> String`, `static func signedWon(_ value: Decimal) -> String`, `static func percent(_ ratio: Decimal) -> String`, `static func monthTitle(_ yearMonth: String) -> String`, `static func dueDate(_ isoDate: String) -> String`
  - `struct MaintenanceView: View` — 인자 없음
  - `struct MaintenanceBillCard: View` — `let bill: MaintenanceBill`, `let delta: MaintenanceDelta?`
  - `AppDestination.maintenance`

**설계 메모:**

- **탭은 둘이 상한이다** — 내역·통계. `VehicleView`의 「세 개가 상한」 규칙과 같은 자리다.
- 통계 탭은 Task 11에서 채운다. 이 태스크에서는 **자리만 잡고 「준비 중」을 그리지 않는다** — 대신 `MaintenanceStatsTab`을 아직 만들지 않고 탭 enum에 `.stats`만 두고 `Text("통계")` 자리표시자를 둔다. Task 11이 그 한 줄을 갈아 끼운다.
- `MaintenanceFormat`을 별도 파일로 빼는 것은 **상세·폼·통계가 전부 같은 포맷을 쓰기** 때문이다. 화면마다 `NumberFormatter`를 새로 만들면 어떤 화면은 「168,620원」, 어떤 화면은 「₩168,620」이 된다.
- 카드 탭 → `NavigationLink(value:)`가 아니라 **`navigationDestination(item:)`으로 상세를 연다.** 상세는 Task 8이 만든다. 이 태스크에서는 `selectedBill` 상태만 두고 목적지에 `Text(bill.yearMonth)` 자리표시자를 둔다 — Task 8이 갈아 끼운다.

- [ ] **Step 1: 포맷 테스트를 쓴다**

`WooriHaruTests/MaintenanceTrendTests.swift` 아래에 덧붙인다.

```swift
struct MaintenanceFormatTests {
    @Test func 원화를_천단위로_끊는다() {
        #expect(MaintenanceFormat.won(Decimal(168_620)) == "168,620원")
        #expect(MaintenanceFormat.won(Decimal(0)) == "0원")
    }

    /// 증감은 **부호를 반드시 붙인다** — 「12,300원」만 적으면 오른 건지 내린 건지 모른다.
    @Test func 증감에는_부호가_붙는다() {
        #expect(MaintenanceFormat.signedWon(Decimal(12_300)) == "+12,300원")
        #expect(MaintenanceFormat.signedWon(Decimal(-4_500)) == "-4,500원")
        #expect(MaintenanceFormat.signedWon(Decimal(0)) == "+0원")
    }

    @Test func 비율은_소수_한_자리에_부호를_붙인다() {
        #expect(MaintenanceFormat.percent(Decimal(string: "0.0787")!) == "+7.9%")
        #expect(MaintenanceFormat.percent(Decimal(string: "-0.031")!) == "-3.1%")
    }

    @Test func 연월을_한국어로_적는다() {
        #expect(MaintenanceFormat.monthTitle("2026-08") == "2026년 8월")
        // 형식이 틀리면 원문 그대로 — 화면이 비는 것보다 낫다.
        #expect(MaintenanceFormat.monthTitle("bogus") == "bogus")
    }

    @Test func 납기일을_짧게_적는다() {
        #expect(MaintenanceFormat.dueDate("2026-08-31") == "8월 31일")
        #expect(MaintenanceFormat.dueDate("bogus") == "bogus")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceFormatTests 2>&1 | tail -30
```

기대: `cannot find 'MaintenanceFormat' in scope`.

- [ ] **Step 3: 포맷을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceFormat.swift`

```swift
import Foundation

/// 관리비 화면 넷이 함께 쓰는 표기. **화면마다 포매터를 새로 만들지 않는다** —
/// 그러면 어떤 화면은 「168,620원」, 어떤 화면은 「₩168,620」이 된다.
enum MaintenanceFormat {
    /// `NumberFormatter`는 만드는 값이 비싸다. 목록이 스크롤될 때마다 새로 만들지 않는다.
    private static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func won(_ value: Decimal) -> String {
        let text = decimal.string(from: value as NSDecimalNumber) ?? "\(value)"
        return "\(text)원"
    }

    /// 증감 표기. **부호를 반드시 붙인다** — 「12,300원」만 적으면 오른 건지 내린 건지 모른다.
    static func signedWon(_ value: Decimal) -> String {
        let sign = value < 0 ? "-" : "+"
        let text = decimal.string(from: abs(value) as NSDecimalNumber) ?? "\(abs(value))"
        return "\(sign)\(text)원"
    }

    /// 비율 그대로(0.0787)를 받아 `+7.9%`로 낸다.
    static func percent(_ ratio: Decimal) -> String {
        let scaled = ratio * 100
        let sign = scaled < 0 ? "-" : "+"
        let text = percentFormatter.string(from: abs(scaled) as NSDecimalNumber) ?? "\(abs(scaled))"
        return "\(sign)\(text)%"
    }

    /// `"2026-08"` → `"2026년 8월"`. **형식이 틀리면 원문 그대로 낸다** — 화면이 비는 것보다 낫다.
    static func monthTitle(_ yearMonth: String) -> String {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
            return yearMonth
        }
        return "\(year)년 \(month)월"
    }

    /// `"2026-08-31"` → `"8월 31일"`. 해는 카드 제목이 이미 말한다.
    static func dueDate(_ isoDate: String) -> String {
        let parts = isoDate.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return isoDate
        }
        return "\(month)월 \(day)일"
    }
}
```

- [ ] **Step 4: 포맷 테스트 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceFormatTests 2>&1 | tail -30
```

기대: 5개 PASS.

- [ ] **Step 5: 목록 카드를 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceBillCard.swift`

```swift
import SwiftUI

/// 목록의 한 달. 청구액을 앞세우고, **바로 앞 달이 목록에 있을 때만** 증감을 붙인다
/// (`delta`가 nil인 경우다 — 판단은 `MaintenanceTrendMath`가 이미 했다).
struct MaintenanceBillCard: View {
    let bill: MaintenanceBill
    let delta: MaintenanceDelta?

    private var hasUnpaid: Bool {
        bill.unpaidAmount > 0 || bill.unpaidLateFee > 0
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(MaintenanceFormat.monthTitle(bill.yearMonth))
                        .font(.headline)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Spacer(minLength: 8)
                    if let dueDate = bill.dueDate {
                        Text("납기 \(MaintenanceFormat.dueDate(dueDate))")
                            .font(.caption2)
                            .foregroundStyle(VehicleTheme.textTertiary)
                    }
                }

                Text(MaintenanceFormat.won(bill.dueAmount))
                    .font(.title2)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.accentBright)

                HStack(spacing: 8) {
                    if let delta {
                        // 오른 달은 경고색이다 — 「지난달보다 더 냈다」가 이 줄의 뜻이다.
                        let up = delta.amount > 0
                        Text(MaintenanceFormat.signedWon(delta.amount))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(up ? VehicleTheme.warning : VehicleTheme.accent)
                        if let ratio = delta.ratio {
                            Text(MaintenanceFormat.percent(ratio))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        Text("전월 대비")
                            .font(.caption2)
                            .foregroundStyle(VehicleTheme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if hasUnpaid {
                        Text("미납")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(VehicleTheme.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(VehicleTheme.warning.opacity(0.18),
                                        in: Capsule())
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: 화면 껍데기와 내역 탭을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceView.swift`

```swift
import SwiftUI

/// 「관리비」 미니앱 — 내역·통계 두 탭. 차량과 같은 하단 글래스 탭바 구조다.
/// **탭은 둘이 상한이다** — 더 늘리려는 순간 화면을 합칠 자리를 먼저 찾는다.
struct MaintenanceView: View {
    private enum Tab { case bills, stats }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .bills
    @State private var billsViewModel = MaintenanceBillsViewModel()
    /// 상세로 넘길 달. `navigationDestination(item:)`이 요구하는 `Hashable`을
    /// `MaintenanceBill`이 `Identifiable`로만 만족하지 못해 연월 문자열을 들고 간다.
    @State private var selectedYearMonth: String?
    @State private var showingUpload = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            tabBar
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel("뒤로")
            }
            ToolbarItem(placement: .principal) {
                Text(tab == .bills ? "관리비" : "통계")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingUpload = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("고지서 등록")
            }
        }
        .task { await billsViewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .bills: billsTab
        case .stats:
            // Task 11이 `MaintenanceStatsTab(...)`으로 갈아 끼운다.
            Text("통계")
                .foregroundStyle(VehicleTheme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var billsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if billsViewModel.bills.isEmpty, !billsViewModel.isLoading {
                    emptyState
                }
                ForEach(Array(billsViewModel.bills.enumerated()), id: \.element.yearMonth) { index, bill in
                    Button {
                        selectedYearMonth = bill.yearMonth
                    } label: {
                        MaintenanceBillCard(
                            bill: bill,
                            delta: MaintenanceTrendMath.monthOverMonth(
                                bills: billsViewModel.bills, at: index
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let message = billsViewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // 하단 탭바가 마지막 카드를 가리지 않게 띄운다.
            .padding(.bottom, 96)
        }
        .refreshable { await billsViewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(VehicleTheme.textTertiary)
            Text("등록된 관리비가 없습니다")
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textSecondary)
            Text("고지서 사진을 올려 첫 달을 등록해 보세요")
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.bills, icon: "list.bullet.rectangle", label: "내역")
            tabButton(.stats, icon: "chart.bar.fill", label: "통계")
        }
        .padding(6)
        // 다크에서는 유리를 쓰지 않는다 — 테두리가 형태를 만든다. 이 바는 목록 **위에**
        // 떠 있어서 반투명하면 지나가는 글자가 아이콘에 겹쳐 비친다.
        .background(VehicleTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(VehicleTheme.cardStroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {}
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func tabButton(_ target: Tab, icon: String, label: String) -> some View {
        let selected = tab == target
        return Button {
            withAnimation(.snappy(duration: 0.2)) { tab = target }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(VehicleTheme.accent.opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(VehicleTheme.accent.opacity(0.45), lineWidth: 1)
                        )
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
```

> **`selectedYearMonth`와 `showingUpload`는 이 태스크에서 화면을 열지 않는다.** 목적지는 Task 7·8이 붙인다. 지금은 상태만 두고 컴파일이 지나가게 한다 — 쓰이지 않는 `@State` 경고가 나면 그대로 둔다(다음 태스크가 곧 쓴다).

- [ ] **Step 7: 진입점을 붙인다**

`WooriHaru/ContentView.swift` — enum에 한 줄, switch에 한 줄.

```swift
    case dispatchUpload
    case vehicle
    case maintenance      // ← 추가
```

```swift
                    case .vehicle: VehicleView()
                    case .maintenance: MaintenanceView()      // ← 추가
```

`WooriHaru/Views/Components/SideDrawerView.swift` — 「차량」 아래 한 줄.

```swift
                drawerItem(icon: "bolt.car", label: "차량") { isOpen = false; navPath.append(AppDestination.vehicle) }
                drawerItem(icon: "wonsign.square", label: "관리비") {
                    isOpen = false
                    navPath.append(AppDestination.maintenance)
                }
```

- [ ] **Step 8: 빌드를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

기대: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: 커밋**

```bash
git add WooriHaru/Views/Maintenance WooriHaru/ContentView.swift \
        WooriHaru/Views/Components/SideDrawerView.swift \
        WooriHaruTests/MaintenanceTrendTests.swift
git commit -m "feat: 드로어에 관리비를 달고 내역 목록을 그린다"
```

---

## Task 5: 업로드 뷰모델 + 사진 화면

**Files:**
- Create: `WooriHaru/ViewModels/MaintenanceUploadViewModel.swift`
- Create: `WooriHaru/Views/Maintenance/MaintenanceUploadView.swift`
- Test: `WooriHaruTests/MaintenanceFormTests.swift`

**Interfaces:**
- Consumes: `MaintenanceServing`, `MaintenanceRecognition` (Task 1·2), `UIImage.jpegWithinByteLimit(from:)` (`WooriHaru/Extensions/UIImage+Extensions.swift`), `error.serverMessage`
- Produces:
  - `@MainActor @Observable final class MaintenanceUploadViewModel` — `enum Phase { case idle, recognizing, completed, failed }`, `imageData: Data?`, `phase: Phase`, `errorMessage: String?`, `recognition: MaintenanceRecognition?`, `canRecognize: Bool`, `setImage(_:)`, `clearImage()`, `setImageLoadFailed()`, `recognize() async`
  - `struct MaintenanceUploadView: View` — `var onSaved: () -> Void = {}` (검수 화면까지 그대로 넘긴다)

**설계 메모 — 배차표에서 값을 치르고 알아낸 것들. 하나도 빼지 않는다:**

- **사진을 축소하지 않는다.** `UIImage.jpegWithinByteLimit(from:)`를 상한 없이 불러 HEIC를 JPEG로 다시 굽되 **해상도는 원본 그대로다.** 고지서는 배차표보다 더 잘다(항목 20여 줄, 금액 6자리). 줄이면 서버가 잘라 확대해도 정보가 이미 없어 모델이 빈 칸을 숫자로 메운다.
- **앨범 원본을 그대로 보내지 않는다.** `loadTransferable(type: Data.self)`는 HEIC를 주는데 서버 `ImageIO.read`에 HEIC 리더가 없어 `IMAGE_UNREADABLE`이 되고, EXIF 방향이 안 붙어 **화면에는 똑바로 보이는 사진을 서버는 눕혀서 받는다.**
- **굽기는 `Task.detached`로 돌린다.** 뷰 액터를 물려받으면 4,800만 화소에서 화면이 몇 초 멎는다. **분리된 Task는 취소를 물려받지 않으므로** 따로 붙들어 사진 교체·화면 이탈 때 함께 접는다 — 안 그러면 겹친 디코드가 메모리를 밀어 올려 앱이 내려간다.
- **`generation` 토큰.** 인식이 도는 중에 사진을 바꾸면 이전 결과를 버린다. 안 그러면 **이전 사진의 인식 결과와 새 사진의 미리보기가 섞인** 검수 화면이 열린다.
- **늦게 돌아온 실패에서 `phase`를 건드리지 않는다.** 사진을 바꾼 뒤 새 인식이 이미 시작됐을 수 있고, 그 스피너를 꺼 버리면 유료 요청이 두 번 나간다.
- **`CancellationError`는 아무것도 띄우지 않는다.** 사용자가 화면을 떠난 것이지 실패가 아니다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceFormTests.swift`

```swift
import Foundation
import Testing
@testable import WooriHaru

/// 인식 호출을 기록하고 늦게 돌려줄 수 있는 대역.
final class RecognizeStubService: MaintenanceServing, @unchecked Sendable {
    var result: MaintenanceRecognition?
    var error: Error?
    private(set) var callCount = 0
    /// 인식이 진행 중인 순간에 끼어들 자리. **`async let`으로 두 번째 호출을 띄우지 않는다** —
    /// 자식 태스크가 언제 시작될지 보장되지 않아 교착하거나 검증 없이 통과한다(실측으로 둘 다 났다).
    /// 대역이 `recognize()` **안에서** 부르므로 재진입 상태가 결정적이다. `DispatchTests`가 쓰는 패턴이다.
    var duringRecognize: (@Sendable () async -> Void)?

    func fetchBills() async throws -> [MaintenanceBill] { [] }
    func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil)
    }
    func recognize(imageData: Data) async throws -> MaintenanceRecognition {
        callCount += 1
        await duringRecognize?()
        if let error { throw error }
        guard let result else { throw APIError.serverError(statusCode: 500, message: nil) }
        return result
    }
    func saveBill(_ request: MaintenanceBillSaveRequest) async throws {}
    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {}
    func deleteBill(yearMonth: String) async throws {}
    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] { [] }
}

func makeRecognition(
    yearMonth: String? = "2026-08",
    items: [MaintenanceBillItem] = [MaintenanceBillItem(name: "일반관리비", amount: 100)],
    chargedAmount: Decimal = 100,
    dueAmount: Decimal = 100,
    usage: MaintenanceUsage? = nil,
    sumMatched: Bool = true,
    warnings: [String] = []
) -> MaintenanceRecognition {
    MaintenanceRecognition(
        yearMonth: yearMonth, dong: "101", ho: "1502", areaM2: Decimal(string: "84.97"),
        items: items, usage: usage, chargedAmount: chargedAmount,
        discountTotal: 0, unpaidAmount: 0, unpaidLateFee: 0,
        dueAmount: dueAmount, dueDate: nil,
        sumMatched: sumMatched, warnings: warnings
    )
}

@MainActor
struct MaintenanceUploadViewModelTests {
    @Test func 사진이_없으면_인식할_수_없다() {
        let vm = MaintenanceUploadViewModel(service: RecognizeStubService())
        #expect(vm.canRecognize == false)
    }

    @Test func 인식에_성공하면_결과와_완료가_남는다() async {
        let service = RecognizeStubService()
        service.result = makeRecognition()
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))

        await vm.recognize()

        #expect(vm.phase == .completed)
        #expect(vm.recognition?.yearMonth == "2026-08")
        #expect(vm.errorMessage == nil)
    }

    /// 서버 메시지가 이미 사용자용 한국어다. 앱이 다시 쓰지 않고 봉투에서 꺼내기만 한다.
    @Test func 실패하면_서버_메시지를_그대로_띄운다() async {
        let service = RecognizeStubService()
        service.error = APIError.serverError(
            statusCode: 400,
            message: #"{"status":400,"message":"고지서를 읽지 못했습니다","code":"400"}"#
        )
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))

        await vm.recognize()

        #expect(vm.phase == .failed)
        #expect(vm.errorMessage == "고지서를 읽지 못했습니다")
    }

    /// **연타로 유료 인식이 두 번 나가지 않는다.**
    @Test func 도는_중에는_다시_부르지_않는다() async {
        let service = RecognizeStubService()
        service.result = makeRecognition()
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))
        service.duringRecognize = { [vm] in
            // 이미 인식 중이다. 두 번째 호출은 그대로 돌아가야 한다.
            await vm.recognize()
        }

        await vm.recognize()

        #expect(service.callCount == 1)
        #expect(vm.phase == .completed)
    }

    /// 사진을 바꾸면 **늦게 돌아온 이전 결과를 버린다.** 안 그러면 이전 사진의 인식 결과와
    /// 새 사진의 미리보기가 섞인 검수 화면이 열린다.
    @Test func 사진을_바꾸면_늦은_결과를_버린다() async {
        let service = RecognizeStubService()
        service.result = makeRecognition(yearMonth: "2026-07")
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))
        service.duringRecognize = { [vm] in
            // 사진을 잘못 골라 곧바로 다시 고른 상황. 이전 인식이 아직 돌아오지 않았다.
            await MainActor.run { vm.setImage(Data([0xFF, 0xD9])) }
        }

        await vm.recognize()

        #expect(vm.recognition == nil)
        #expect(vm.phase == .idle)
    }

    @Test func 사진_읽기_실패는_안내로_남는다() {
        let vm = MaintenanceUploadViewModel(service: RecognizeStubService())
        vm.setImage(Data([0xFF, 0xD8]))

        vm.setImageLoadFailed()

        #expect(vm.imageData == nil)
        #expect(vm.canRecognize == false)
        #expect(vm.errorMessage == "사진을 읽지 못했습니다. 다른 사진으로 다시 시도해 주세요.")
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceUploadViewModelTests 2>&1 | tail -30
```

기대: `cannot find 'MaintenanceUploadViewModel' in scope`.

- [ ] **Step 3: 뷰모델을 쓴다**

`WooriHaru/ViewModels/MaintenanceUploadViewModel.swift`

```swift
import Foundation

/// 고지서 사진 한 장을 골라 인식을 요청한다. 연월은 고지서에 적혀 있어 서버가 읽어 주므로
/// 여기서 묻지 않는다 — 검수 화면에서 확인·수정한다.
///
/// **사진을 축소하지 않는다.** 고지서는 항목이 스무 줄 넘고 금액이 여섯 자리라, 줄이면
/// 서버가 잘라 확대해도 정보가 이미 없어 모델이 빈 칸을 숫자로 메운다. 서버 multipart 한도는 10MB다.
@MainActor
@Observable
final class MaintenanceUploadViewModel {
    enum Phase: Equatable {
        case idle
        case recognizing
        case completed
        case failed
    }

    private let service: any MaintenanceServing

    private(set) var imageData: Data?
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var recognition: MaintenanceRecognition?

    /// 사진이 바뀔 때마다 올린다. 인식이 도는 중에 사진을 바꾸면 이전 요청이 뒤늦게 돌아와
    /// 완료를 세우는데, 그러면 **이전 사진의 인식 결과와 새 사진의 미리보기가 섞인** 검수
    /// 화면이 열리고 그대로 저장하면 다른 고지서가 들어간다.
    private var generation = 0

    init(service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
    }

    var canRecognize: Bool {
        imageData != nil && phase != .recognizing
    }

    func setImage(_ data: Data) {
        generation += 1
        imageData = data
        phase = .idle
        errorMessage = nil
        recognition = nil
    }

    /// 새 사진을 고른 순간 이전 사진은 무효다. **비워 두지 않으면** 새 사진이 아직 로딩
    /// 중인데도 「인식하기」가 살아 있어 **이전 사진이 그대로 나간다.**
    func clearImage() {
        generation += 1
        imageData = nil
        phase = .idle
        errorMessage = nil
        recognition = nil
    }

    /// 앨범에서 읽거나 JPEG로 굽는 데 실패했다. 조용히 넘기면 사진 자리가 빈 채로 남아
    /// 사용자가 「사진이 안 들어갔다」는 것조차 모른다.
    func setImageLoadFailed() {
        generation += 1
        imageData = nil
        phase = .idle
        recognition = nil
        errorMessage = "사진을 읽지 못했습니다. 다른 사진으로 다시 시도해 주세요."
    }

    func recognize() async {
        // 연타나 화면 복귀로 두 번 들어오면 유료 인식이 두 번 나간다.
        guard phase != .recognizing else { return }
        guard let imageData else { return }
        phase = .recognizing
        errorMessage = nil
        let token = generation
        do {
            let result = try await service.recognize(imageData: imageData)
            // 사진이 바뀌었다. 이 결과는 화면에 보이는 사진의 것이 아니다.
            // **여기서 phase를 건드리지 않는다** — 새 인식이 이미 시작됐을 수 있고,
            // 그 스피너를 꺼 버리면 유료 요청이 두 번 나간다. `setImage`가 이미 `.idle`로 돌려놨다.
            guard token == generation else { return }
            recognition = result
            phase = .completed
        } catch is CancellationError {
            // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return
        } catch {
            // 바뀌기 전 사진의 실패다. 새 사진으로 다시 인식하려는 참인데 오류만 떠 있으면
            // 사용자는 방금 고른 사진이 실패한 줄 안다.
            guard token == generation else { return }
            // 서버 메시지가 이미 사용자용 한국어다. 봉투 JSON째 보여주지 않으려고 `message`만 꺼낸다.
            errorMessage = error.serverMessage ?? error.localizedDescription
            phase = .failed
        }
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceUploadViewModelTests 2>&1 | tail -30
```

기대: 6개 PASS.

- [ ] **Step 5: 사진 화면을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceUploadView.swift`

```swift
import PhotosUI
import SwiftUI

/// 고지서 사진을 골라 인식을 요청한다. 연월은 검수 화면에서 확인·수정한다.
///
/// **사진을 축소하지 않는다** — `jpegWithinByteLimit`이 상한을 `min(maxDimension, originalMax)`로
/// 낮추므로 해상도는 원본 그대로고, HEIC→JPEG 재인코딩과 EXIF 회전 반영만 일어난다.
/// 이걸 건너뛰면 서버가 `IMAGE_UNREADABLE`을 내거나 눕힌 사진을 읽는다.
struct MaintenanceUploadView: View {
    /// 저장까지 끝나면 불린다 — 목록 화면이 이걸로 목록을 다시 받는다. 검수 화면까지 그대로 넘긴다.
    var onSaved: () -> Void = {}

    @State private var vm = MaintenanceUploadViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var recognizeTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    /// 굽기는 `Task.detached`로 돈다 — 취소를 물려받지 않으므로 따로 붙들어 접는다.
    @State private var normalizeTask: Task<Data?, Never>?
    /// 로딩 동안 「인식하기」가 잠긴다. 왜 잠겼는지 알리지 않으면 앨범 자산이 iCloud에서
    /// 내려오는 몇 초 동안 화면이 고장 난 것처럼 보인다.
    @State private var isLoadingPhoto = false
    /// 인식이 처음 끝났을 때 한 번만 연다. `MaintenanceRecognition`이 `Hashable`이 아니라
    /// `navigationDestination(item:)`을 쓸 수 없다.
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoSection
                guideText

                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    recognizeTask?.cancel()
                    recognizeTask = Task { await vm.recognize() }
                } label: {
                    if vm.phase == .recognizing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("인식하기").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canRecognize)
            }
            .padding()
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("관리비 등록")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            recognizeTask?.cancel()
            loadTask?.cancel()
            normalizeTask?.cancel()
            // 취소된 Task는 아래 가드에서 돌아가므로 이 값을 스스로 내리지 못한다. 그대로
            // 두면 화면으로 돌아왔을 때 스피너가 남고 「인식하기」가 잠긴 채로 있는다.
            isLoadingPhoto = false
        }
        .onChange(of: pickerItem) { _, item in
            loadTask?.cancel()
            // 굽기는 분리된 Task라 위 취소가 닿지 않는다. 따로 접지 않으면 이전 사진의
            // 굽기가 끝까지 도는 동안 새 굽기가 시작돼 메모리가 밀린다.
            normalizeTask?.cancel()
            // 진행 중이던 인식도 접는다 — 사진을 바꾼 순간 이 요청은 이미 쓸모가 없다.
            recognizeTask?.cancel()
            // 새 사진이 로딩되는 사이 「인식하기」가 눌리면 **이전 사진이 나간다.**
            previewImage = nil
            vm.clearImage()
            guard let item else { return }
            isLoadingPhoto = true
            loadTask = Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let normalize = Task.detached(priority: .userInitiated) {
                    data.flatMap { UIImage.jpegWithinByteLimit(from: $0) }
                }
                normalizeTask = normalize
                let normalized = await normalize.value

                // 앨범 읽기는 사진마다 걸리는 시간이 달라 먼저 시작한 쪽이 나중에 끝날 수 있다.
                // 그대로 두면 **화면에는 새 사진이 보이는데 인식은 이전 사진으로 돈다.**
                guard !Task.isCancelled, pickerItem == item else { return }
                isLoadingPhoto = false

                guard let normalized, let preview = UIImage(data: normalized) else {
                    previewImage = nil
                    vm.setImageLoadFailed()
                    return
                }
                vm.setImage(normalized)
                previewImage = preview
            }
        }
        .onChange(of: vm.phase) { _, newPhase in
            if newPhase == .completed, !showReview { showReview = true }
        }
        .navigationDestination(isPresented: $showReview) {
            if let recognition = vm.recognition {
                // Task 7이 이 한 줄을
                // `MaintenanceBillFormView(mode: .create(recognition), onSaved: onSaved)`로 갈아 끼운다.
                Text(recognition.yearMonth ?? "연월 없음")
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(previewImage == nil ? "사진 고르기" : "사진 바꾸기", systemImage: "photo")
            }
            if isLoadingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("사진을 불러오는 중…")
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var guideText: some View {
        Text("""
        고지서 표 전체가 한 장에 들어오게 찍어 주세요. \
        금액 열이 잘리면 항목이 어긋납니다. \
        연월이 적힌 제목 줄도 함께 담아 주세요. \
        인식에는 1~2분 걸립니다.
        """)
        .font(.footnote)
        .foregroundStyle(VehicleTheme.textTertiary)
    }
}
```

> **검수 화면(`MaintenanceBillFormView`)은 Task 7이 만든다.** 그때까지 이 태스크가 저장소를 컴파일 안 되는 상태로 남기지 않도록, 목적지를 자리표시자 `Text`로 두었다. Task 7이 그 한 줄만 갈아 끼운다.

또 `MaintenanceView`의 `showingUpload`를 여기서 잇는다 — `MaintenanceView.swift`의 `.task { ... }` 아래에 붙인다.

```swift
        .navigationDestination(isPresented: $showingUpload) {
            MaintenanceUploadView { Task { await billsViewModel.load() } }
        }
```

- [ ] **Step 6: 빌드를 확인하고 커밋한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

기대: `** BUILD SUCCEEDED **`.

```bash
git add WooriHaru/ViewModels/MaintenanceUploadViewModel.swift \
        WooriHaru/Views/Maintenance/MaintenanceUploadView.swift \
        WooriHaru/Views/Maintenance/MaintenanceView.swift \
        WooriHaruTests/MaintenanceFormTests.swift
git commit -m "feat: 고지서 사진을 골라 인식을 요청한다"
```

---

## Task 6: 검수·편집 폼 뷰모델

**Files:**
- Create: `WooriHaru/ViewModels/MaintenanceBillFormViewModel.swift`
- Test: `WooriHaruTests/MaintenanceFormTests.swift` (수트 추가)

**Interfaces:**
- Consumes: `MaintenanceServing`, `MaintenanceRecognition`, `MaintenanceBill`, `MaintenanceBillSaveRequest`, `MaintenanceBillItemRequest`, `MaintenanceUsage`, `APIError`
- Produces:
  - `struct MaintenanceItemDraft: Identifiable, Equatable { let id: UUID; var name: String; var amount: String }`
  - `@MainActor @Observable final class MaintenanceBillFormViewModel`
    - `enum Mode: Equatable { case create(MaintenanceRecognition); case edit(MaintenanceBill) }`
    - `enum SaveOutcome: Equatable { case saved, duplicated, failed }`
    - `init(mode: Mode, service: any MaintenanceServing = MaintenanceService())`
    - 편집 상태: `yearMonth: String`, `dong: String`, `ho: String`, `areaM2: String`, `items: [MaintenanceItemDraft]`, `electricityKwh/waterM3/hotWaterM3/heatingGcal/foodKg: String`, `chargedAmount/discountTotal/unpaidAmount/unpaidLateFee/dueAmount: String`, `dueDate: String`
    - 읽기 전용: `warnings: [String]`, `isYearMonthEditable: Bool`, `isSaving: Bool`, `errorMessage: String?`, `itemsTotal: Decimal`, `sumGap: Decimal`, `isSumMatched: Bool`, `canSave: Bool`
    - `addItem()`, `removeItems(at: IndexSet)`, `makeRequest() -> MaintenanceBillSaveRequest?`, `save() async -> SaveOutcome`, `switchToEdit(_ bill: MaintenanceBill)`

**설계 메모:**

- **숫자를 `String`으로 들고 있는다.** `TextField`가 값을 지우는 중간 상태(`""`, `"-"`, `"12."`)를 지나가는데, `Decimal`에 바로 바인딩하면 그 상태가 0으로 튀어 사용자가 지운 값이 되살아난다. 저장 직전에 한 번만 파싱한다.
- **`MaintenanceItemDraft.id`는 `UUID`다.** `MaintenanceBillItem.id`(이름)를 쓰면 **편집 중 이름이 겹치는 순간 `ForEach`가 행 둘을 같은 뷰로 잡아** 타이핑이 옆 행으로 튄다. 빈 행을 두 개 추가하면 바로 겹친다.
- **`sumGap`은 앱이 실시간으로 다시 계산한다.** 서버의 `sumMatched`는 인식 시점 판정이라 사람이 금액을 고치면 낡는다. 다만 **저장을 막지 않는다** — 고지서에 반올림·별도 조정이 실제로 있고, 판단은 사람이 한다.
- **`canSave`가 막는 것은 서버가 400을 낼 것들뿐이다**: 연월 형식(`YYYY-MM`), 항목 0개, 이름이 빈 항목, 금액이 숫자가 아닌 항목.
- **`switchToEdit`은 화면 값을 버리고 서버 값으로 다시 채운다.** 409에서 「기존 내역 수정하기」를 눌렀을 때 방금 인식한 값으로 기존 달을 덮는 것은 **사용자가 의도한 적 없는 파괴**다.
- **빈 사용량 칸은 nil로 나간다.** 0으로 채우면 서버에 「0을 썼다」가 저장되고 통계에서 「안 씀」이 된다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceFormTests.swift` 아래에 덧붙인다.

```swift
/// 저장·수정·조회를 기록하는 대역. 409를 흉내 낼 수 있다.
final class FormStubService: MaintenanceServing, @unchecked Sendable {
    var saveError: Error?
    var updateError: Error?
    var billToFetch: MaintenanceBill?
    private(set) var savedRequests: [MaintenanceBillSaveRequest] = []
    private(set) var updatedCalls: [(yearMonth: String, request: MaintenanceBillSaveRequest)] = []

    func fetchBills() async throws -> [MaintenanceBill] { [] }
    func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
        guard let billToFetch else {
            throw APIError.serverError(statusCode: 404, message: nil)
        }
        return billToFetch
    }
    func recognize(imageData: Data) async throws -> MaintenanceRecognition {
        fatalError("이 스위트는 인식을 부르지 않는다")
    }
    func saveBill(_ request: MaintenanceBillSaveRequest) async throws {
        savedRequests.append(request)
        if let saveError { throw saveError }
    }
    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {
        updatedCalls.append((yearMonth, request))
        if let updateError { throw updateError }
    }
    func deleteBill(yearMonth: String) async throws {}
    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] { [] }
}

@MainActor
struct MaintenanceFormViewModelTests {
    private func makeBill(
        yearMonth: String = "2026-08",
        items: [MaintenanceBillItem] = [MaintenanceBillItem(name: "일반관리비", amount: 121_500)],
        usage: MaintenanceUsage? = nil
    ) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: "101", ho: "1502",
                        areaM2: Decimal(string: "84.97"),
                        items: items, usage: usage,
                        chargedAmount: 121_500, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: 121_500, dueDate: "2026-08-31")
    }

    // MARK: - 초기화

    @Test func 인식_결과로_칸이_채워진다() {
        let recognition = makeRecognition(
            items: [MaintenanceBillItem(name: "일반관리비", amount: 121_500),
                    MaintenanceBillItem(name: "세대전기료", amount: 48_320)],
            chargedAmount: 169_820, dueAmount: 168_620,
            usage: MaintenanceUsage(electricityKwh: Decimal(string: "312.5"),
                                    waterM3: nil, hotWaterM3: nil,
                                    heatingGcal: nil, foodKg: nil),
            sumMatched: true
        )
        let vm = MaintenanceBillFormViewModel(mode: .create(recognition), service: FormStubService())

        #expect(vm.yearMonth == "2026-08")
        #expect(vm.items.map(\.name) == ["일반관리비", "세대전기료"])
        #expect(vm.items[1].amount == "48320")
        #expect(vm.electricityKwh == "312.5")
        // **못 읽은 사용량은 빈 칸이다** — 0을 적어 두면 사람이 지우지 않는 한 0이 저장된다.
        #expect(vm.waterM3 == "")
        #expect(vm.isYearMonthEditable == true)
    }

    /// 연월을 못 읽었으면 빈 칸이고, 그 상태로는 저장할 수 없다.
    @Test func 연월이_없으면_저장이_잠긴다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(yearMonth: nil)), service: FormStubService()
        )
        #expect(vm.yearMonth == "")
        #expect(vm.canSave == false)
    }

    /// **편집 모드에서 연월은 키다.** 바꾸는 것은 삭제 후 재등록이지 수정이 아니다.
    @Test func 편집_모드에서는_연월을_못_고친다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        #expect(vm.isYearMonthEditable == false)
        #expect(vm.yearMonth == "2026-08")
        #expect(vm.warnings.isEmpty)
    }

    // MARK: - 항목

    @Test func 항목을_더하고_지운다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.addItem()

        #expect(vm.items.count == 2)
        // 빈 행이 있으면 저장이 잠긴다 — 서버가 400을 낸다.
        #expect(vm.canSave == false)

        vm.removeItems(at: IndexSet(integer: 1))
        #expect(vm.items.count == 1)
        #expect(vm.canSave == true)
    }

    /// 빈 행 둘을 더해도 서로 다른 `id`를 갖는다 — 이름으로 식별하면 타이핑이 옆 행으로 튄다.
    @Test func 빈_행_둘의_id가_갈린다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.addItem()
        vm.addItem()

        #expect(Set(vm.items.map(\.id)).count == 3)
    }

    @Test func 항목이_하나도_없으면_저장이_잠긴다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.removeItems(at: IndexSet(integer: 0))
        #expect(vm.canSave == false)
    }

    // MARK: - 합계 대조

    @Test func 항목_합계와_부과액_차이를_낸다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(
                items: [MaintenanceBillItem(name: "일반관리비", amount: 100),
                        MaintenanceBillItem(name: "세대전기료", amount: 50)],
                chargedAmount: 160, dueAmount: 160
            )),
            service: FormStubService()
        )

        #expect(vm.itemsTotal == Decimal(150))
        #expect(vm.sumGap == Decimal(-10))   // 항목 합계 − 부과액
        #expect(vm.isSumMatched == false)
    }

    /// **금액을 고치면 판정이 따라온다.** 서버의 `sumMatched`는 인식 시점 값이라 낡는다.
    @Test func 금액을_고치면_합계_판정이_갱신된다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(
                items: [MaintenanceBillItem(name: "일반관리비", amount: 100)],
                chargedAmount: 150, dueAmount: 150, sumMatched: false
            )),
            service: FormStubService()
        )
        #expect(vm.isSumMatched == false)

        vm.items[0].amount = "150"

        #expect(vm.isSumMatched == true)
        #expect(vm.sumGap == 0)
    }

    /// **합계가 안 맞아도 저장은 막지 않는다** — 반올림·별도 조정이 실제로 있고 판단은 사람이 한다.
    @Test func 합계가_어긋나도_저장할_수_있다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(chargedAmount: 999, dueAmount: 999)),
            service: FormStubService()
        )
        #expect(vm.isSumMatched == false)
        #expect(vm.canSave == true)
    }

    // MARK: - 요청 조립

    @Test func 빈_사용량_칸은_nil로_나간다() throws {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.electricityKwh = "312.5"
        vm.waterM3 = ""

        let request = try #require(vm.makeRequest())

        #expect(request.usage?.electricityKwh == Decimal(string: "312.5"))
        #expect(request.usage?.waterM3 == nil)
    }

    /// 빈 문자열은 nil이지 0이 아니다 — 동·호·면적·납기일도 마찬가지다.
    @Test func 빈_세대_정보는_nil로_나간다() throws {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.dong = ""
        vm.ho = "  "
        vm.areaM2 = ""
        vm.dueDate = ""

        let request = try #require(vm.makeRequest())

        #expect(request.dong == nil)
        #expect(request.ho == nil)
        #expect(request.areaM2 == nil)
        #expect(request.dueDate == nil)
    }

    /// **`.create`와 `.edit`이 같은 값에서 같은 바디를 낸다.** 두 벌로 갈리면 한쪽만 고친 날
    /// 두 화면이 다른 값을 저장한다.
    @Test func 두_모드가_같은_바디를_낸다() throws {
        let bill = makeBill()
        let recognition = makeRecognition(
            items: bill.items, chargedAmount: bill.chargedAmount, dueAmount: bill.dueAmount
        )
        let fromCreate = MaintenanceBillFormViewModel(mode: .create(recognition), service: FormStubService())
        fromCreate.dueDate = "2026-08-31"
        let fromEdit = MaintenanceBillFormViewModel(mode: .edit(bill), service: FormStubService())

        #expect(try #require(fromCreate.makeRequest()) == (try #require(fromEdit.makeRequest())))
    }

    // MARK: - 저장

    @Test func 검수_저장은_POST로_나간다() async {
        let service = FormStubService()
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .saved)
        #expect(service.savedRequests.count == 1)
        #expect(service.updatedCalls.isEmpty)
    }

    @Test func 편집_저장은_PUT으로_나간다() async {
        let service = FormStubService()
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .saved)
        #expect(service.updatedCalls.map(\.yearMonth) == ["2026-08"])
        #expect(service.savedRequests.isEmpty)
    }

    /// **409는 실패와 다르다.** 화면이 「기존 내역 수정하기」를 띄울 수 있게 갈라 준다.
    @Test func 같은_달이_있으면_duplicated다() async {
        let service = FormStubService()
        service.saveError = APIError.serverError(statusCode: 409, message: nil)
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .duplicated)
    }

    @Test func 다른_실패는_failed고_메시지가_남는다() async {
        let service = FormStubService()
        service.saveError = APIError.serverError(
            statusCode: 400, message: #"{"status":400,"message":"항목이 비었습니다","code":"400"}"#
        )
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .failed)
        #expect(vm.errorMessage == "항목이 비었습니다")
    }

    /// **화면 값을 버리고 서버 값으로 다시 채운다** — 방금 인식한 값으로 기존 달을 덮는 것은
    /// 사용자가 의도한 적 없는 파괴다.
    @Test func 편집으로_바꾸면_서버_값으로_채워진다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(items: [MaintenanceBillItem(name: "잘못읽음", amount: 1)])),
            service: FormStubService()
        )

        vm.switchToEdit(makeBill(items: [MaintenanceBillItem(name: "일반관리비", amount: 121_500)]))

        #expect(vm.items.map(\.name) == ["일반관리비"])
        #expect(vm.isYearMonthEditable == false)
        #expect(vm.warnings.isEmpty)
    }

    /// 편집으로 바뀐 뒤 저장하면 PUT이다.
    @Test func 편집으로_바꾼_뒤_저장하면_PUT이다() async {
        let service = FormStubService()
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)
        vm.switchToEdit(makeBill())

        _ = await vm.save()

        #expect(service.updatedCalls.map(\.yearMonth) == ["2026-08"])
        #expect(service.savedRequests.isEmpty)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceFormViewModelTests 2>&1 | tail -30
```

기대: `cannot find 'MaintenanceBillFormViewModel' in scope`.

- [ ] **Step 3: 뷰모델을 쓴다**

`WooriHaru/ViewModels/MaintenanceBillFormViewModel.swift`

```swift
import Foundation

/// 편집 중인 항목 한 줄.
///
/// **`id`가 `UUID`인 이유.** `MaintenanceBillItem.id`는 이름인데, 편집 중에는 이름이 겹친다
/// (빈 행 둘만 더해도 바로 겹친다). 그러면 `ForEach`가 행 둘을 같은 뷰로 잡아 **타이핑이
/// 옆 행으로 튄다.**
///
/// **금액이 `String`인 이유.** `TextField`는 값을 지우는 중간 상태(`""`·`"12."`)를 지나간다.
/// `Decimal`에 바로 바인딩하면 그 상태가 0으로 튀어 사용자가 지운 값이 되살아난다.
struct MaintenanceItemDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var amount: String

    init(id: UUID = UUID(), name: String, amount: String) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

/// 검수(`.create`)와 편집(`.edit`)을 **한 화면으로** 다룬다.
///
/// 화면을 나누면 항목 편집·합계 검증·요청 조립이 두 벌이 되고, 한쪽만 고친 날 두 화면이
/// 다른 값을 저장한다. 갈리는 것은 저장 메서드(POST/PUT)와 연월 편집 가능 여부뿐이다.
@MainActor
@Observable
final class MaintenanceBillFormViewModel {
    enum Mode: Equatable {
        case create(MaintenanceRecognition)
        case edit(MaintenanceBill)
    }

    /// 409를 실패와 갈라 낸다 — 화면이 「기존 내역 수정하기」로 이어 붙일 수 있어야 한다.
    enum SaveOutcome: Equatable {
        case saved
        case duplicated
        case failed
    }

    private let service: any MaintenanceServing
    /// `.edit`이면 PUT, 아니면 POST. `switchToEdit`이 이 값을 바꾼다.
    private var editingYearMonth: String?

    var yearMonth: String
    var dong: String
    var ho: String
    var areaM2: String
    var items: [MaintenanceItemDraft]
    var electricityKwh: String
    var waterM3: String
    var hotWaterM3: String
    var heatingGcal: String
    var foodKg: String
    var chargedAmount: String
    var discountTotal: String
    var unpaidAmount: String
    var unpaidLateFee: String
    var dueAmount: String
    var dueDate: String

    /// 서버가 붙인 경고. **이미 사용자용 한국어다** — 앱이 다시 쓰지 않는다. 편집 모드에선 비어 있다.
    private(set) var warnings: [String]
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init(mode: Mode, service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
        switch mode {
        case .create(let recognition):
            editingYearMonth = nil
            yearMonth = recognition.yearMonth ?? ""
            dong = recognition.dong ?? ""
            ho = recognition.ho ?? ""
            areaM2 = Self.text(recognition.areaM2)
            items = recognition.items.map {
                MaintenanceItemDraft(name: $0.name, amount: Self.text($0.amount))
            }
            electricityKwh = Self.text(recognition.usage?.electricityKwh)
            waterM3 = Self.text(recognition.usage?.waterM3)
            hotWaterM3 = Self.text(recognition.usage?.hotWaterM3)
            heatingGcal = Self.text(recognition.usage?.heatingGcal)
            foodKg = Self.text(recognition.usage?.foodKg)
            chargedAmount = Self.text(recognition.chargedAmount)
            discountTotal = Self.text(recognition.discountTotal)
            unpaidAmount = Self.text(recognition.unpaidAmount)
            unpaidLateFee = Self.text(recognition.unpaidLateFee)
            dueAmount = Self.text(recognition.dueAmount)
            dueDate = recognition.dueDate ?? ""
            warnings = recognition.warnings
        case .edit(let bill):
            editingYearMonth = bill.yearMonth
            yearMonth = bill.yearMonth
            dong = bill.dong ?? ""
            ho = bill.ho ?? ""
            areaM2 = Self.text(bill.areaM2)
            items = bill.items.map {
                MaintenanceItemDraft(name: $0.name, amount: Self.text($0.amount))
            }
            electricityKwh = Self.text(bill.usage?.electricityKwh)
            waterM3 = Self.text(bill.usage?.waterM3)
            hotWaterM3 = Self.text(bill.usage?.hotWaterM3)
            heatingGcal = Self.text(bill.usage?.heatingGcal)
            foodKg = Self.text(bill.usage?.foodKg)
            chargedAmount = Self.text(bill.chargedAmount)
            discountTotal = Self.text(bill.discountTotal)
            unpaidAmount = Self.text(bill.unpaidAmount)
            unpaidLateFee = Self.text(bill.unpaidLateFee)
            dueAmount = Self.text(bill.dueAmount)
            dueDate = bill.dueDate ?? ""
            warnings = []
        }
    }

    /// **연월은 편집 모드에서 키다.** 바꾸는 것은 삭제 후 재등록이지 수정이 아니다.
    var isYearMonthEditable: Bool { editingYearMonth == nil }

    // MARK: - 항목

    func addItem() {
        items.append(MaintenanceItemDraft(name: "", amount: ""))
    }

    func removeItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    // MARK: - 합계 대조

    /// **앱이 실시간으로 다시 계산한다.** 서버의 `sumMatched`는 인식 시점 판정이라 사람이
    /// 금액을 고치면 낡는다.
    var itemsTotal: Decimal {
        items.reduce(Decimal(0)) { $0 + (Self.decimal($1.amount) ?? 0) }
    }

    /// 항목 합계 − 부과액. 음수면 항목이 모자라다는 뜻이다.
    var sumGap: Decimal {
        itemsTotal - (Self.decimal(chargedAmount) ?? 0)
    }

    var isSumMatched: Bool { sumGap == 0 }

    // MARK: - 저장

    /// **막는 것은 서버가 400을 낼 것들뿐이다.** 합계 불일치는 막지 않는다 — 고지서에
    /// 반올림·별도 조정이 실제로 있고, 판단은 사람이 한다.
    var canSave: Bool {
        guard !isSaving else { return false }
        guard MaintenanceTrendMath.isValidYearMonth(yearMonth) else { return false }
        guard !items.isEmpty else { return false }
        return items.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && Self.decimal($0.amount) != nil
        }
    }

    /// 저장할 수 없는 상태면 nil. 화면은 `canSave`로 이미 막고 있어 여기 오지 않는다.
    func makeRequest() -> MaintenanceBillSaveRequest? {
        guard canSave else { return nil }
        let drafts: [MaintenanceBillItemRequest] = items.compactMap { draft in
            guard let amount = Self.decimal(draft.amount) else { return nil }
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return MaintenanceBillItemRequest(name: name, amount: amount)
        }
        guard !drafts.isEmpty else { return nil }

        // **빈 칸은 nil이지 0이 아니다.** 0으로 보내면 서버에 「0을 썼다」가 저장돼
        // 통계에서 「못 읽은 달」이 「안 쓴 달」로 바뀐다.
        let usage = MaintenanceUsage(
            electricityKwh: Self.decimal(electricityKwh),
            waterM3: Self.decimal(waterM3),
            hotWaterM3: Self.decimal(hotWaterM3),
            heatingGcal: Self.decimal(heatingGcal),
            foodKg: Self.decimal(foodKg)
        )

        return MaintenanceBillSaveRequest(
            yearMonth: yearMonth.trimmingCharacters(in: .whitespaces),
            items: drafts,
            chargedAmount: Self.decimal(chargedAmount) ?? 0,
            dueAmount: Self.decimal(dueAmount) ?? 0,
            dong: Self.optionalText(dong),
            ho: Self.optionalText(ho),
            areaM2: Self.decimal(areaM2),
            usage: usage,
            discountTotal: Self.decimal(discountTotal) ?? 0,
            unpaidAmount: Self.decimal(unpaidAmount) ?? 0,
            unpaidLateFee: Self.decimal(unpaidLateFee) ?? 0,
            dueDate: Self.optionalText(dueDate)
        )
    }

    func save() async -> SaveOutcome {
        // **`makeRequest`가 `canSave`를 보므로 `isSaving`을 세우기 전에 부른다.**
        // 순서를 뒤집으면 `canSave`가 false가 되어 자기 저장이 자기를 막는다.
        guard let request = makeRequest() else { return .failed }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let editingYearMonth {
                try await service.updateBill(yearMonth: editingYearMonth, request)
            } else {
                try await service.saveBill(request)
            }
            return .saved
        } catch let error as APIError {
            // 409는 실패가 아니라 갈림길이다 — 화면이 「기존 내역 수정하기」를 띄운다.
            if case .serverError(409, _) = error { return .duplicated }
            errorMessage = error.serverMessage ?? error.localizedDescription
            return .failed
        } catch {
            errorMessage = error.serverMessage ?? error.localizedDescription
            return .failed
        }
    }

    /// 409에서 「기존 내역 수정하기」를 눌렀을 때. **화면 값을 버리고 서버 값으로 다시 채운다** —
    /// 방금 인식한 값으로 기존 달을 통째로 덮는 것은 사용자가 의도한 적 없는 파괴다.
    func switchToEdit(_ bill: MaintenanceBill) {
        editingYearMonth = bill.yearMonth
        yearMonth = bill.yearMonth
        dong = bill.dong ?? ""
        ho = bill.ho ?? ""
        areaM2 = Self.text(bill.areaM2)
        items = bill.items.map { MaintenanceItemDraft(name: $0.name, amount: Self.text($0.amount)) }
        electricityKwh = Self.text(bill.usage?.electricityKwh)
        waterM3 = Self.text(bill.usage?.waterM3)
        hotWaterM3 = Self.text(bill.usage?.hotWaterM3)
        heatingGcal = Self.text(bill.usage?.heatingGcal)
        foodKg = Self.text(bill.usage?.foodKg)
        chargedAmount = Self.text(bill.chargedAmount)
        discountTotal = Self.text(bill.discountTotal)
        unpaidAmount = Self.text(bill.unpaidAmount)
        unpaidLateFee = Self.text(bill.unpaidLateFee)
        dueAmount = Self.text(bill.dueAmount)
        dueDate = bill.dueDate ?? ""
        // 인식 경고는 더 이상 이 화면의 것이 아니다 — 지금 편집하는 건 저장돼 있던 달이다.
        warnings = []
        errorMessage = nil
    }

    /// 서버에서 그 달을 받아 편집 모드로 갈아 끼운다. 실패하면 false.
    func loadForEdit(yearMonth: String) async -> Bool {
        do {
            switchToEdit(try await service.fetchBill(yearMonth: yearMonth))
            return true
        } catch {
            errorMessage = error.serverMessage ?? error.localizedDescription
            return false
        }
    }

    // MARK: - 변환

    /// **못 읽은 값은 빈 칸이다** — 0을 적어 두면 사람이 지우지 않는 한 0이 저장된다.
    private static func text(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private static func decimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // `Decimal(string:)`은 로캘을 타지 않는 파서다. `NumberFormatter`를 쓰면 소수점이
        // 쉼표인 지역에서 `312.5`가 312가 된다.
        return Decimal(string: trimmed)
    }

    private static func optionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

> **연월 형식 검사기를 새로 만들지 않는다.** `previousMonth(of:)`가 이미 `YYYY-MM`을 파싱해
> 틀리면 `nil`을 낸다. 다만 그 이름이 「형식이 맞는가」를 말해 주지 않으니, `MaintenanceTrendMath`에
> 한 줄짜리 별칭을 더하고 `canSave`가 그것을 부른다 — **이 태스크에서 함께 만든다.**
>
> ```swift
> /// `previousMonth(of:)`가 이미 하는 파싱을 이름으로만 다시 세운다 —
> /// 형식 검사기를 두 개 두면 한쪽만 고친 날 폼과 차트가 다른 연월을 받아들인다.
> static func isValidYearMonth(_ yearMonth: String) -> Bool {
>     previousMonth(of: yearMonth) != nil
> }
> ```
>
> 테스트도 `MaintenanceMonthMathTests`에 한 줄 더한다:
>
> ```swift
> @Test func 연월_형식을_검사한다() {
>     #expect(MaintenanceTrendMath.isValidYearMonth("2026-08") == true)
>     #expect(MaintenanceTrendMath.isValidYearMonth("2026-13") == false)
>     #expect(MaintenanceTrendMath.isValidYearMonth("") == false)
> }
> ```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceFormViewModelTests \
  -only-testing:WooriHaruTests/MaintenanceMonthMathTests 2>&1 | tail -30
```

기대: 18개 + 4개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/MaintenanceBillFormViewModel.swift \
        WooriHaru/Models/MaintenanceTrendMath.swift \
        WooriHaruTests/MaintenanceFormTests.swift \
        WooriHaruTests/MaintenanceTrendTests.swift
git commit -m "feat: 관리비 검수·편집 폼 뷰모델을 만든다"
```

---

## Task 7: 검수·편집 폼 화면

**Files:**
- Create: `WooriHaru/Views/Maintenance/MaintenanceBillFormView.swift`
- Create: `WooriHaru/Views/Maintenance/MaintenanceItemRow.swift`
- Create: `WooriHaru/Views/Maintenance/MaintenanceUsageFields.swift`
- Modify: `WooriHaru/Views/Maintenance/MaintenanceUploadView.swift` (자리표시자 `Text`를 폼으로 교체)

**Interfaces:**
- Consumes: `MaintenanceBillFormViewModel`(Task 6), `MaintenanceFormat`(Task 4), `MaintenanceServing`, `GlassCard`, `VehicleTheme`
- Produces:
  - `struct MaintenanceBillFormView: View` — `init(mode: MaintenanceBillFormViewModel.Mode, onSaved: @escaping () -> Void)`
  - `struct MaintenanceItemRow: View` — `@Binding var item: MaintenanceItemDraft`
  - `struct MaintenanceUsageFields: View` — `@Bindable var vm: MaintenanceBillFormViewModel`

**설계 메모:**

- **`@State private var vm`을 `init`에서 세운다.** `_vm = State(initialValue: MaintenanceBillFormViewModel(mode: mode))` — 뷰가 다시 그려질 때마다 뷰모델이 새로 생기면 사용자가 친 값이 날아간다.
- **숫자 칸은 `.keyboardType(.decimalPad)`다.** `.numberPad`는 소수점이 없어 면적·사용량을 못 넣는다.
- **저장 버튼은 툴바가 아니라 화면 맨 아래에 둔다.** 항목이 스무 줄이라 스크롤이 길고, 툴바 버튼은 검수를 다 하기 전에 눌리기 쉽다.
- **409 알럿은 버튼이 둘이다** — 「기존 내역 수정하기」와 「취소」. 「수정하기」는 `loadForEdit`으로 서버 값을 받아 폼을 갈아 끼우고, **화면을 닫지 않는다.**
- `onSaved`는 저장 성공 시에만 부르고 `dismiss()`한다.

- [ ] **Step 1: 항목 행을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceItemRow.swift`

```swift
import SwiftUI

/// 항목 한 줄 — 이름과 금액. **행을 따로 뺀 이유는 폼이 커지기 때문이다**(항목 스무 줄에
/// 사용량 다섯 칸에 금액 여섯 칸). 한 파일이 400줄을 넘기기 전에 가른다.
struct MaintenanceItemRow: View {
    @Binding var item: MaintenanceItemDraft

    var body: some View {
        HStack(spacing: 10) {
            // 서버 한도 50자. 넘겨 보내면 400이라 여기서 자른다.
            TextField("항목명", text: $item.name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: item.name) { _, new in
                    if new.count > 50 { item.name = String(new.prefix(50)) }
                }
            TextField("금액", text: $item.amount)
                // **`.numberPad`가 아니다** — 소수점이 없어 소수 금액을 못 넣는다.
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 110)
        }
        .font(.subheadline)
        .foregroundStyle(VehicleTheme.textPrimary)
    }
}
```

- [ ] **Step 2: 사용량 칸을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceUsageFields.swift`

```swift
import SwiftUI

/// 사용량 다섯 칸. **비워 두면 nil로 나간다** — 뷰모델이 빈 문자열을 nil로 옮긴다.
/// 0을 미리 채워 두지 않는 이유가 그것이다: 사람이 지우지 않는 한 「0을 썼다」가 저장된다.
struct MaintenanceUsageFields: View {
    @Bindable var vm: MaintenanceBillFormViewModel

    var body: some View {
        VStack(spacing: 8) {
            field("전기", unit: "kWh", text: $vm.electricityKwh)
            field("수도", unit: "m³", text: $vm.waterM3)
            field("온수", unit: "m³", text: $vm.hotWaterM3)
            field("난방", unit: "Gcal", text: $vm.heatingGcal)
            field("음식물", unit: "kg", text: $vm.foodKg)
        }
    }

    private func field(_ label: String, unit: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textSecondary)
                .frame(width: 56, alignment: .leading)
            TextField("고지서에 없으면 비워 두세요", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
            Text(unit)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
                .frame(width: 36, alignment: .leading)
        }
    }
}
```

- [ ] **Step 3: 폼 화면을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceBillFormView.swift`

```swift
import SwiftUI

/// 검수(`.create`)와 편집(`.edit`)을 한 화면으로 다룬다. 갈리는 것은 제목·연월 편집
/// 가능 여부·저장 메서드뿐이고, 그 판단은 전부 뷰모델이 한다.
struct MaintenanceBillFormView: View {
    @State private var vm: MaintenanceBillFormViewModel
    @Environment(\.dismiss) private var dismiss
    /// 409 알럿. **버튼이 둘이다** — 「기존 내역 수정하기」와 「취소」.
    @State private var showingDuplicateAlert = false
    @State private var saveTask: Task<Void, Never>?

    var onSaved: () -> Void

    init(mode: MaintenanceBillFormViewModel.Mode, onSaved: @escaping () -> Void = {}) {
        // **`init`에서 세운다** — 뷰가 다시 그려질 때마다 뷰모델이 새로 생기면 사용자가
        // 친 값이 날아간다.
        _vm = State(initialValue: MaintenanceBillFormViewModel(mode: mode))
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                warningCard
                monthCard
                itemsCard
                sumCard
                usageCard
                amountCard
                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle(vm.isYearMonthEditable ? "고지서 검수" : "관리비 수정")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { saveTask?.cancel() }
        .alert("이미 등록된 달입니다", isPresented: $showingDuplicateAlert) {
            Button("기존 내역 수정하기") {
                saveTask?.cancel()
                saveTask = Task {
                    // **화면을 닫지 않는다.** 서버 값으로 폼을 갈아 끼우고 그 자리에 머문다 —
                    // 방금 인식한 값으로 기존 달을 덮지 않으려는 것이다.
                    _ = await vm.loadForEdit(yearMonth: vm.yearMonth)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(MaintenanceFormat.monthTitle(vm.yearMonth)) 관리비가 이미 있습니다. 기존 내역을 불러와 고칠 수 있습니다.")
        }
    }

    @ViewBuilder private var warningCard: some View {
        if !vm.warnings.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("확인이 필요합니다", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.warning)
                    // 서버 문구가 이미 사용자용 한국어다 — 앱이 다시 쓰지 않는다.
                    ForEach(vm.warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption)
                            .foregroundStyle(VehicleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var monthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("연월 · 세대")
                HStack(spacing: 10) {
                    Text("연월")
                        .font(.subheadline)
                        .foregroundStyle(VehicleTheme.textSecondary)
                        .frame(width: 56, alignment: .leading)
                    if vm.isYearMonthEditable {
                        TextField("2026-08", text: $vm.yearMonth)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .monospacedDigit()
                    } else {
                        // 편집 모드에서 연월은 키다. 바꾸는 것은 삭제 후 재등록이지 수정이 아니다.
                        Text(vm.yearMonth)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.textTertiary)
                        Spacer()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)

                HStack(spacing: 10) {
                    labeledField("동", text: $vm.dong, keyboard: .default)
                    labeledField("호", text: $vm.ho, keyboard: .default)
                    labeledField("면적", text: $vm.areaM2, keyboard: .decimalPad)
                }
            }
        }
    }

    private var itemsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("항목")
                    Spacer()
                    Button {
                        vm.addItem()
                    } label: {
                        Label("추가", systemImage: "plus")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VehicleTheme.accentBright)
                }
                ForEach($vm.items) { $item in
                    HStack(spacing: 8) {
                        MaintenanceItemRow(item: $item)
                        Button {
                            if let index = vm.items.firstIndex(where: { $0.id == item.id }) {
                                vm.removeItems(at: IndexSet(integer: index))
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("항목 삭제")
                    }
                }
                if vm.items.isEmpty {
                    Text("항목이 하나도 없으면 저장할 수 없습니다")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.warning)
                }
            }
        }
    }

    /// 항목 합계와 부과액을 나란히 놓는다. **틀려도 막지 않는다** — 반올림·별도 조정이
    /// 실제로 있고 판단은 사람이 한다. 다만 차액은 눈에 띄게 적는다.
    private var sumCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("항목 합계")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer()
                    Text(MaintenanceFormat.won(vm.itemsTotal))
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(VehicleTheme.textPrimary)
                }
                if !vm.isSumMatched {
                    HStack {
                        Text("부과액과 차이")
                            .font(.caption)
                            .foregroundStyle(VehicleTheme.warning)
                        Spacer()
                        Text(MaintenanceFormat.signedWon(vm.sumGap))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.warning)
                    }
                }
            }
        }
    }

    private var usageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("사용량")
                MaintenanceUsageFields(vm: vm)
            }
        }
    }

    private var amountCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("금액")
                amountField("부과액", text: $vm.chargedAmount)
                amountField("할인 합계", text: $vm.discountTotal)
                amountField("미납액", text: $vm.unpaidAmount)
                amountField("연체료", text: $vm.unpaidLateFee)
                amountField("청구액", text: $vm.dueAmount)
                HStack(spacing: 10) {
                    Text("납기일")
                        .font(.subheadline)
                        .foregroundStyle(VehicleTheme.textSecondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("2026-08-31", text: $vm.dueDate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .font(.subheadline)
                        .foregroundStyle(VehicleTheme.textPrimary)
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            saveTask?.cancel()
            saveTask = Task {
                switch await vm.save() {
                case .saved:
                    onSaved()
                    dismiss()
                case .duplicated:
                    showingDuplicateAlert = true
                case .failed:
                    break   // `vm.errorMessage`가 화면에 이미 뜬다
                }
            }
        } label: {
            if vm.isSaving {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("저장").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!vm.canSave)
        // 툴바가 아니라 맨 아래다 — 항목이 스무 줄이라 스크롤이 길고, 툴바 버튼은
        // 검수를 다 하기 전에 눌리기 쉽다.
        .padding(.top, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(VehicleTheme.textSecondary)
    }

    private func labeledField(_ label: String, text: Binding<String>,
                              keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            TextField("", text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
        }
    }

    private func amountField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textSecondary)
                .frame(width: 72, alignment: .leading)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
        }
    }
}
```

- [ ] **Step 4: 업로드 화면의 자리표시자를 갈아 끼운다**

`WooriHaru/Views/Maintenance/MaintenanceUploadView.swift`의 `navigationDestination(isPresented: $showReview)` 안을 이렇게 바꾼다.

```swift
        .navigationDestination(isPresented: $showReview) {
            if let recognition = vm.recognition {
                MaintenanceBillFormView(mode: .create(recognition), onSaved: onSaved)
            }
        }
```

- [ ] **Step 5: 빌드와 전체 테스트를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

기대: `** BUILD SUCCEEDED **`.

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

기대: 기존 테스트 포함 전부 PASS.

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Views/Maintenance
git commit -m "feat: 고지서 검수·편집 폼을 그린다"
```

---

## Task 8: 상세 화면 + 수정 · 삭제

**Files:**
- Create: `WooriHaru/Views/Maintenance/MaintenanceBillDetailView.swift`
- Modify: `WooriHaru/Views/Maintenance/MaintenanceView.swift` (상세 목적지 연결)

**Interfaces:**
- Consumes: `MaintenanceBill`, `MaintenanceBillsViewModel`(Task 3), `MaintenanceBillFormView`(Task 7), `MaintenanceFormat`(Task 4), `GlassCard`, `VehicleTheme`, `ChartScale.ratio`
- Produces:
  - `struct MaintenanceBillDetailView: View` — `let bill: MaintenanceBill`, `var onChanged: () -> Void`, `var onDeleted: () -> Void`

**설계 메모:**

- **목록이 이미 상세와 같은 필드를 다 갖고 있다.** `GET /bills`와 `GET /bills/{yearMonth}`가 같은 `BillResponse`다 — 상세를 열면서 다시 받지 않는다. 수정하고 돌아올 때만 목록을 다시 받는다(`onChanged`).
- **항목 표는 금액 큰 순이다.** 서버 순서는 고지서 표 순서인데, 「무엇이 컸나」가 이 표가 답하는 질문이다. 가계부가 같은 판단을 했다(`67e1bef`).
- **비율 막대는 `ChartScale.ratio`를 쓴다.** 뷰에서 나눗셈하지 않는다.
- **삭제는 확인 알럿을 거친다.** 성공했을 때만 `onDeleted()` → 목록으로 물러난다.
- 사용량은 **값이 있는 것만 적고, 하나도 없으면 카드를 그리지 않는다.** 「—」 다섯 줄은 정보가 아니다.

- [ ] **Step 1: 상세 화면을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceBillDetailView.swift`

```swift
import SwiftUI

/// 한 달 상세. **서버에서 다시 받지 않는다** — 목록 응답이 이미 같은 필드를 다 갖고 있다.
/// 수정하고 돌아올 때만 목록을 새로 받는다(`onChanged`).
struct MaintenanceBillDetailView: View {
    let bill: MaintenanceBill
    /// 수정이 저장됐다. 목록을 다시 받아야 한다.
    var onChanged: () -> Void = {}
    /// 삭제됐다. 화면이 물러난 뒤 목록에서도 빠져야 한다.
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var deleteTask: Task<Void, Never>?

    private let service: any MaintenanceServing = MaintenanceService()

    /// **금액 큰 순.** 서버 순서는 고지서 표 순서인데, 이 표가 답하는 질문은 「무엇이 컸나」다.
    private var sortedItems: [MaintenanceBillItem] {
        bill.items.sorted { $0.amount > $1.amount }
    }

    private var usageRows: [(label: String, value: Decimal, unit: String)] {
        guard let usage = bill.usage else { return [] }
        // **값이 있는 것만 담는다.** 「—」 다섯 줄은 정보가 아니다.
        return [
            ("전기", usage.electricityKwh, "kWh"),
            ("수도", usage.waterM3, "m³"),
            ("온수", usage.hotWaterM3, "m³"),
            ("난방", usage.heatingGcal, "Gcal"),
            ("음식물", usage.foodKg, "kg"),
        ].compactMap { label, value, unit in
            value.map { (label, $0, unit) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                heroCard
                amountTiles
                itemsCard
                if !usageRows.isEmpty { usageCard }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle(MaintenanceFormat.monthTitle(bill.yearMonth))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { deleteTask?.cancel() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("수정") { showingEdit = true }
                    Button("삭제", role: .destructive) { showingDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
                .accessibilityLabel("더 보기")
            }
        }
        .navigationDestination(isPresented: $showingEdit) {
            MaintenanceBillFormView(mode: .edit(bill)) {
                onChanged()
                // 이 화면이 들고 있는 `bill`은 수정 전 값이다. 그대로 남기면 방금 고친
                // 금액과 다른 숫자를 보여준다 — 목록으로 물러나 새로 받은 값을 보게 한다.
                dismiss()
            }
        }
        .alert("삭제할까요?", isPresented: $showingDeleteConfirm) {
            Button("삭제", role: .destructive) {
                deleteTask?.cancel()
                deleteTask = Task { await delete() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(MaintenanceFormat.monthTitle(bill.yearMonth)) 관리비를 지웁니다. 되돌릴 수 없습니다.")
        }
    }

    private func delete() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await service.deleteBill(yearMonth: bill.yearMonth)
            onDeleted()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            // **실패하면 물러나지 않는다** — 물러나면 사용자는 지워진 줄 안다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
    }

    private var heroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("청구액")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textSecondary)
                Text(MaintenanceFormat.won(bill.dueAmount))
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.accentBright)
                HStack(spacing: 8) {
                    if let dong = bill.dong, let ho = bill.ho {
                        Text("\(dong)동 \(ho)호")
                    }
                    if let areaM2 = bill.areaM2 {
                        Text("\(NSDecimalNumber(decimal: areaM2).stringValue)m²")
                    }
                    if let dueDate = bill.dueDate {
                        Text("납기 \(MaintenanceFormat.dueDate(dueDate))")
                    }
                }
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private var amountTiles: some View {
        GlassCard {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    tile("부과액", bill.chargedAmount, warn: false)
                    tile("할인", bill.discountTotal, warn: false)
                }
                HStack(spacing: 10) {
                    tile("미납액", bill.unpaidAmount, warn: bill.unpaidAmount > 0)
                    tile("연체료", bill.unpaidLateFee, warn: bill.unpaidLateFee > 0)
                }
            }
        }
    }

    private func tile(_ label: String, _ value: Decimal, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textTertiary)
            Text(MaintenanceFormat.won(value))
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(warn ? VehicleTheme.warning : VehicleTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private var itemsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("항목")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)
                // 비율 막대의 분모는 항목 중 최댓값이다 — 「가장 큰 항목 대비 얼마나」가
                // 눈이 읽는 질문이고, 나눗셈은 `ChartScale`이 이미 하는 일이다.
                let maxAmount = ChartScale.maxValue(
                    sortedItems.map { ChartPoint(id: $0.name, label: $0.name, value: $0.amount) }
                )
                ForEach(sortedItems) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                                .foregroundStyle(VehicleTheme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(MaintenanceFormat.won(item.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(VehicleTheme.textSecondary)
                        }
                        GeometryReader { proxy in
                            let ratio = ChartScale.ratio(item.amount, max: maxAmount)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(VehicleTheme.trackFill)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(VehicleTheme.accentMuted)
                                    .frame(width: ratio > 0 ? max(3, proxy.size.width * ratio) : 0)
                            }
                        }
                        .frame(height: 5)
                    }
                }
                if sortedItems.isEmpty {
                    Text("항목이 없습니다")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
        }
    }

    private var usageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("사용량")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)
                ForEach(usageRows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(VehicleTheme.textSecondary)
                        Spacer()
                        Text("\(NSDecimalNumber(decimal: row.value).stringValue) \(row.unit)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.textPrimary)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: 목록에서 상세를 연다**

`WooriHaru/Views/Maintenance/MaintenanceView.swift`의 `.task { ... }` 아래에 붙인다.

```swift
        .navigationDestination(item: $selectedYearMonth) { yearMonth in
            if let bill = billsViewModel.bills.first(where: { $0.yearMonth == yearMonth }) {
                MaintenanceBillDetailView(
                    bill: bill,
                    onChanged: { Task { await billsViewModel.load() } },
                    onDeleted: { Task { await billsViewModel.load() } }
                )
            }
        }
```

- [ ] **Step 3: 빌드를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

기대: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Maintenance
git commit -m "feat: 관리비 상세에서 항목을 보고 고치고 지운다"
```

---

## Task 9: 통계 파생 계산

**Files:**
- Modify: `WooriHaru/Models/MaintenanceTrendMath.swift` (Task 3·6이 만든 enum에 함수를 더한다)
- Test: `WooriHaruTests/MaintenanceTrendTests.swift` (수트 추가)

**Interfaces:**
- Consumes: `MaintenanceTrendMonth`, `MaintenanceUsage`, `ChartPoint`(`Views/Vehicle/Charts/ChartPoint.swift`)
- Produces (전부 `MaintenanceTrendMath`의 `static`):
  - `static func sorted(_ months: [MaintenanceTrendMonth]) -> [MaintenanceTrendMonth]`
  - `static func chargedPoints(_ months: [MaintenanceTrendMonth]) -> [ChartPoint]`
  - `static func itemNames(_ months: [MaintenanceTrendMonth]) -> [String]`
  - `static func itemPoints(_ months: [MaintenanceTrendMonth], name: String) -> [ChartPoint]`
  - `enum UsageKind: String, CaseIterable { case electricity, water, hotWater, heating, food }` — `var label: String`, `var unit: String`
  - `static func usagePoints(_ months: [MaintenanceTrendMonth], kind: UsageKind) -> [ChartPoint]`
  - `static func yearOverYearDeltas(_ months: [MaintenanceTrendMonth], topCount: Int = 8) -> [MaintenanceItemDelta]?`
  - `struct MaintenanceItemDelta: Identifiable, Equatable { let name: String; let delta: Decimal; var id: String { name } }`

**설계 메모:**

- **응답 순서를 믿지 않는다.** 차트 다섯 장이 전부 시간축이라 순서가 뒤집히면 전부 거짓말이 된다. `sorted`가 `yearMonth` 오름차순으로 못 박고, 나머지 함수는 전부 정렬된 배열을 받는 것을 전제한다(뷰모델이 한 번만 정렬한다).
- **`itemNames`는 13개월 전체에서 모은다.** 고지서 표기가 바뀌거나 인식이 다르게 읽으면 「전기료」와 「전기료(공동)」이 갈리는데, 최근 달에만 있는 이름을 빼면 피커에서 사라진다. **금액 합이 큰 순**으로 정렬해 자주 큰 항목이 위에 온다.
- **없는 달은 `nil`이지 `0`이 아니다.** `itemPoints`에서 그 달 항목에 그 이름이 없으면 `nil`이다 — 0으로 채우면 「그달엔 안 나왔다」가 아니라 「0원이었다」가 된다.
- **`yearOverYearDeltas`는 전년 동월이 범위에 없으면 `nil`이다.** 없는 비교를 0으로 채우면 **모든 항목이 「신설」로 보인다.** 화면은 `nil`일 때 카드 자리에 사유를 적는다.
- 전년 동월은 `yearMonth`의 연도만 1 빼서 찾는다 — 13개월 응답이면 첫 달이 그 달이지만, **응답이 짧을 수도 있으니 실제로 있는지 찾아본다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceTrendTests.swift` 아래에 덧붙인다.

```swift
struct MaintenanceTrendMathTests {
    private func month(
        _ yearMonth: String,
        charged: Decimal = 0,
        items: [MaintenanceBillItem] = [],
        usage: MaintenanceUsage? = nil
    ) -> MaintenanceTrendMonth {
        MaintenanceTrendMonth(yearMonth: yearMonth, chargedAmount: charged,
                              items: items, usage: usage)
    }

    /// **응답 순서를 믿지 않는다.** 차트 다섯 장이 전부 시간축이라 뒤집히면 전부 거짓이 된다.
    @Test func 연월_오름차순으로_정렬한다() {
        let months = [month("2026-08"), month("2025-12"), month("2026-01")]
        #expect(MaintenanceTrendMath.sorted(months).map(\.yearMonth)
                == ["2025-12", "2026-01", "2026-08"])
    }

    @Test func 부과액_점을_만든다() {
        let points = MaintenanceTrendMath.chargedPoints(
            [month("2026-07", charged: 150_000), month("2026-08", charged: 168_000)]
        )
        #expect(points.map(\.id) == ["2026-07", "2026-08"])
        #expect(points.map(\.label) == ["7", "8"])
        #expect(points.map(\.value) == [Decimal(150_000), Decimal(168_000)])
    }

    /// **13개월 전체에서 모은다.** 최근 달에만 있는 이름을 빼면 피커에서 사라진다.
    @Test func 항목_이름을_전체에서_모은다() {
        let months = [
            month("2026-07", items: [MaintenanceBillItem(name: "난방비", amount: 50_000)]),
            month("2026-08", items: [MaintenanceBillItem(name: "일반관리비", amount: 120_000),
                                     MaintenanceBillItem(name: "난방비", amount: 1_000)]),
        ]
        // 금액 합이 큰 순 — 일반관리비 120,000 > 난방비 51,000
        #expect(MaintenanceTrendMath.itemNames(months) == ["일반관리비", "난방비"])
    }

    /// **그 이름이 없는 달은 nil이다.** 0으로 채우면 「안 나왔다」가 「0원이었다」가 된다.
    @Test func 없는_달의_항목은_nil이다() {
        let months = [
            month("2026-07", items: []),
            month("2026-08", items: [MaintenanceBillItem(name: "난방비", amount: 51_000)]),
        ]
        let points = MaintenanceTrendMath.itemPoints(months, name: "난방비")

        #expect(points.map(\.value) == [nil, Decimal(51_000)])
    }

    @Test func 사용량_점을_만든다() {
        let months = [
            month("2026-07", usage: MaintenanceUsage(electricityKwh: Decimal(300), waterM3: nil,
                                                     hotWaterM3: nil, heatingGcal: nil, foodKg: nil)),
            month("2026-08", usage: nil),
        ]
        let points = MaintenanceTrendMath.usagePoints(months, kind: .electricity)

        #expect(points.map(\.value) == [Decimal(300), nil])
        #expect(MaintenanceTrendMath.UsageKind.electricity.unit == "kWh")
    }

    /// 전년 동월과 항목별로 견준다. **증감 절댓값이 큰 순 상위 N개**만 남긴다.
    @Test func 전년_동월_대비_증감을_낸다() throws {
        let months = [
            month("2025-08", items: [MaintenanceBillItem(name: "난방비", amount: 10_000),
                                     MaintenanceBillItem(name: "일반관리비", amount: 100_000)]),
            month("2026-08", items: [MaintenanceBillItem(name: "난방비", amount: 40_000),
                                     MaintenanceBillItem(name: "일반관리비", amount: 105_000)]),
        ]
        let deltas = try #require(MaintenanceTrendMath.yearOverYearDeltas(months))

        #expect(deltas.map(\.name) == ["난방비", "일반관리비"])
        #expect(deltas[0].delta == Decimal(30_000))
        #expect(deltas[1].delta == Decimal(5_000))
    }

    /// 작년에 없던 항목은 이번 달 금액 전부가 증가분이다.
    @Test func 작년에_없던_항목은_전액_증가다() throws {
        let months = [
            month("2025-08", items: []),
            month("2026-08", items: [MaintenanceBillItem(name: "승강기유지비", amount: 7_000)]),
        ]
        let deltas = try #require(MaintenanceTrendMath.yearOverYearDeltas(months))
        #expect(deltas == [MaintenanceItemDelta(name: "승강기유지비", delta: Decimal(7_000))])
    }

    /// **전년 동월이 범위에 없으면 nil이다.** 0으로 채우면 모든 항목이 「신설」로 보인다.
    @Test func 전년_동월이_없으면_nil이다() {
        let months = [
            month("2026-07", items: [MaintenanceBillItem(name: "난방비", amount: 1)]),
            month("2026-08", items: [MaintenanceBillItem(name: "난방비", amount: 2)]),
        ]
        #expect(MaintenanceTrendMath.yearOverYearDeltas(months) == nil)
    }

    @Test func 증감_상위_개수를_자른다() throws {
        let old = (1...10).map { MaintenanceBillItem(name: "항목\($0)", amount: Decimal(0)) }
        let new = (1...10).map { MaintenanceBillItem(name: "항목\($0)", amount: Decimal($0 * 1000)) }
        let months = [month("2025-08", items: old), month("2026-08", items: new)]

        let deltas = try #require(MaintenanceTrendMath.yearOverYearDeltas(months, topCount: 3))

        #expect(deltas.map(\.name) == ["항목10", "항목9", "항목8"])
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceTrendMathTests 2>&1 | tail -30
```

기대: `type 'MaintenanceTrendMath' has no member 'sorted'`.

- [ ] **Step 3: 계산을 더한다**

`WooriHaru/Models/MaintenanceTrendMath.swift`에 아래를 더한다. 파일 맨 위에 `import SwiftUI`가 필요하다(`ChartPoint`가 SwiftUI 파일에 있다).

```swift
/// 전년 동월 대비 항목 하나의 증감. 양수면 올랐다.
struct MaintenanceItemDelta: Identifiable, Equatable {
    let name: String
    let delta: Decimal
    var id: String { name }
}

extension MaintenanceTrendMath {
    /// 사용량 다섯 종. 단위가 달라 한 차트에 겹쳐 그리지 않고 토글로 하나씩 본다.
    enum UsageKind: String, CaseIterable, Identifiable {
        case electricity, water, hotWater, heating, food

        var id: String { rawValue }

        var label: String {
            switch self {
            case .electricity: "전기"
            case .water: "수도"
            case .hotWater: "온수"
            case .heating: "난방"
            case .food: "음식물"
            }
        }

        var unit: String {
            switch self {
            case .electricity: "kWh"
            case .water, .hotWater: "m³"
            case .heating: "Gcal"
            case .food: "kg"
            }
        }

        func value(in usage: MaintenanceUsage?) -> Decimal? {
            switch self {
            case .electricity: usage?.electricityKwh
            case .water: usage?.waterM3
            case .hotWater: usage?.hotWaterM3
            case .heating: usage?.heatingGcal
            case .food: usage?.foodKg
            }
        }
    }

    /// **응답 순서를 믿지 않는다.** 차트 다섯 장이 전부 시간축이라 순서가 뒤집히면
    /// 전부 거짓말이 된다. 아래 함수들은 정렬된 배열을 받는 것을 전제한다 —
    /// 뷰모델이 받자마자 한 번만 정렬한다.
    static func sorted(_ months: [MaintenanceTrendMonth]) -> [MaintenanceTrendMonth] {
        months.sorted { $0.yearMonth < $1.yearMonth }
    }

    static func chargedPoints(_ months: [MaintenanceTrendMonth]) -> [ChartPoint] {
        months.map {
            ChartPoint(id: $0.yearMonth, label: MonthLabel.axis($0.yearMonth), value: $0.chargedAmount)
        }
    }

    /// **13개월 전체에서 모은다.** 고지서 표기가 바뀌거나 인식이 다르게 읽으면 이름이
    /// 갈리는데, 최근 달에만 있는 이름을 빼면 피커에서 사라진다.
    /// 정렬은 **금액 합이 큰 순** — 자주 큰 항목이 위에 온다.
    static func itemNames(_ months: [MaintenanceTrendMonth]) -> [String] {
        var totals: [String: Decimal] = [:]
        for month in months {
            for item in month.items {
                totals[item.name, default: 0] += item.amount
            }
        }
        // 합이 같으면 이름순 — 순서가 흔들리면 피커가 열 때마다 달라 보인다.
        return totals.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// **그 이름이 없는 달은 nil이다** — 0으로 채우면 「안 나왔다」가 「0원이었다」가 된다.
    static func itemPoints(_ months: [MaintenanceTrendMonth], name: String) -> [ChartPoint] {
        months.map { month in
            ChartPoint(
                id: month.yearMonth,
                label: MonthLabel.axis(month.yearMonth),
                value: month.items.first { $0.name == name }?.amount
            )
        }
    }

    static func usagePoints(_ months: [MaintenanceTrendMonth], kind: UsageKind) -> [ChartPoint] {
        months.map {
            ChartPoint(id: $0.yearMonth, label: MonthLabel.axis($0.yearMonth),
                       value: kind.value(in: $0.usage))
        }
    }

    /// 마지막 달과 그 전년 동월을 항목별로 견준다. 증감 절댓값이 큰 순 상위 `topCount`개.
    ///
    /// **전년 동월이 범위에 없으면 nil이다.** 없는 비교를 0으로 채우면 모든 항목이
    /// 「신설」로 보인다 — 화면은 nil일 때 카드 자리에 사유를 적는다.
    static func yearOverYearDeltas(
        _ months: [MaintenanceTrendMonth],
        topCount: Int = 8
    ) -> [MaintenanceItemDelta]? {
        guard let latest = months.last else { return nil }
        let parts = latest.yearMonth.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]) else { return nil }
        let lastYearKey = String(format: "%04d-%@", year - 1, String(parts[1]))
        // **13개월이면 첫 달이 그 달이지만 응답이 짧을 수 있다** — 실제로 있는지 찾아본다.
        guard let lastYear = months.first(where: { $0.yearMonth == lastYearKey }) else { return nil }

        var previousAmounts: [String: Decimal] = [:]
        for item in lastYear.items { previousAmounts[item.name, default: 0] += item.amount }

        var deltas: [MaintenanceItemDelta] = []
        var seen: Set<String> = []
        for item in latest.items {
            seen.insert(item.name)
            deltas.append(MaintenanceItemDelta(name: item.name,
                                               delta: item.amount - (previousAmounts[item.name] ?? 0)))
        }
        // 작년에는 있었는데 올해 사라진 항목도 증감이다 — 전액 감소로 남긴다.
        for (name, amount) in previousAmounts where !seen.contains(name) {
            deltas.append(MaintenanceItemDelta(name: name, delta: -amount))
        }

        return Array(
            deltas
                .filter { $0.delta != 0 }
                .sorted { (abs($0.delta), $1.name) > (abs($1.delta), $0.name) }
                .prefix(topCount)
        )
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceTrendMathTests 2>&1 | tail -30
```

기대: 9개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Models/MaintenanceTrendMath.swift WooriHaruTests/MaintenanceTrendTests.swift
git commit -m "feat: 관리비 추이 파생 계산을 만든다"
```

---

## Task 10: 발산형 순위 리스트 차트 원형

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/DivergingRankList.swift`
- Test: `WooriHaruTests/MaintenanceTrendTests.swift` (수트 추가)

**Interfaces:**
- Consumes: `ChartScale.maxAbsValue`, `ChartScale.divergingRatio` (`Views/Vehicle/Charts/ChartPoint.swift`), `VehicleTheme`
- Produces:
  - `struct DivergingRankList: View`
    - `struct Row: Identifiable, Equatable { let id: String; let label: String; let value: Decimal; let detail: String }`
    - `let rows: [Row]`, `let selectedID: String?`, `let onSelect: (String) -> Void`
  - `enum DivergingRankGeometry` — `static func halfWidth(_ value: Decimal, maxAbs: Decimal, trackWidth: CGFloat) -> CGFloat`

**설계 메모 — 왜 원형을 새로 두는가:**

- `DivergingMonthlyBarChart`는 부호를 그리지만 **9pt 가로축 라벨**이라 「일반관리비」가 안 들어간다. 달 이름(`8`)에 맞춘 원형이다.
- `RankBarList`는 세로 리스트라 이름이 들어가지만 **막대가 늘 왼쪽에서 오른쪽으로 자라고 색이 하나다** — 부호를 표현하지 못한다.
- 그래서 둘의 가운데를 새로 둔다. **기하 계산은 이미 있는 `ChartScale.maxAbsValue`/`divergingRatio`를 그대로 쓴다** — 테스트가 이미 붙어 있는 함수를 다시 만들지 않는다.
- **원형은 `Views/Vehicle/Charts`에 둔다.** 관리비만 쓰지만, 차트 원형이 두 군데로 갈리면 다음 화면이 어디를 뒤져야 할지 모른다.
- **카드가 아니라 리스트만 그린다** — 제목·콜아웃·`GlassCard`는 부르는 쪽이 얹는다(원형 열한 개가 지키는 규칙이다).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceTrendTests.swift` 아래에 덧붙인다.

```swift
struct DivergingRankGeometryTests {
    /// 가장 크게 움직인 행이 트랙 절반을 꽉 채운다.
    @Test func 최대값이_절반을_채운다() {
        let width = DivergingRankGeometry.halfWidth(Decimal(30_000), maxAbs: Decimal(30_000),
                                                    trackWidth: 200)
        #expect(width == 100)
    }

    /// **부호는 폭에 담지 않는다** — 방향은 그리는 쪽이 정렬로 정한다. 여기선 크기만 낸다.
    @Test func 음수도_같은_크기를_낸다() {
        let up = DivergingRankGeometry.halfWidth(Decimal(15_000), maxAbs: Decimal(30_000),
                                                 trackWidth: 200)
        let down = DivergingRankGeometry.halfWidth(Decimal(-15_000), maxAbs: Decimal(30_000),
                                                   trackWidth: 200)
        #expect(up == down)
        #expect(up == 50)
    }

    /// 0으로 나누지 않는다.
    @Test func 최대가_0이면_폭이_0이다() {
        #expect(DivergingRankGeometry.halfWidth(Decimal(0), maxAbs: Decimal(0), trackWidth: 200) == 0)
    }

    /// 0이 아닌데 너무 작아 안 보이는 막대는 최소 폭을 준다 — 「0이다」와 갈려야 한다.
    @Test func 아주_작은_값도_보인다() {
        let width = DivergingRankGeometry.halfWidth(Decimal(1), maxAbs: Decimal(1_000_000),
                                                    trackWidth: 200)
        #expect(width == 2)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/DivergingRankGeometryTests 2>&1 | tail -30
```

기대: `cannot find 'DivergingRankGeometry' in scope`.

- [ ] **Step 3: 원형을 쓴다**

`WooriHaru/Views/Vehicle/Charts/DivergingRankList.swift`

```swift
import SwiftUI

/// 발산형 막대의 폭. **부호를 담지 않는다** — 방향은 그리는 쪽이 정렬로 정하고
/// 여기서는 크기만 낸다. `ChartScale.divergingRatio`에 최소 폭 규칙만 얹은 것이다.
enum DivergingRankGeometry {
    /// 0이 아닌데 안 보이는 막대를 없앤다 — 「0이다」와 갈려야 한다.
    private static let minimumWidth: CGFloat = 2

    /// `trackWidth`는 기준선 양쪽을 합친 전체 폭이다. 한쪽이 쓸 수 있는 것은 그 절반이다.
    static func halfWidth(_ value: Decimal, maxAbs: Decimal, trackWidth: CGFloat) -> CGFloat {
        let ratio = ChartScale.divergingRatio(value, max: maxAbs)
        guard ratio > 0 else { return 0 }
        return max(minimumWidth, trackWidth / 2 * ratio)
    }
}

/// 이름 있는 것들의 **증감**을 세로 리스트로 낸다. 가운데가 0이고 **오른쪽이 증가, 왼쪽이 감소**다.
///
/// **원형을 새로 둔 이유.** `DivergingMonthlyBarChart`는 부호를 그리지만 9pt 가로축 라벨이라
/// 「일반관리비」가 안 들어가고(달 이름 `8`에 맞춘 원형이다), `RankBarList`는 이름이 들어가지만
/// 막대가 늘 한 방향이라 부호를 못 그린다. 기하 계산은 이미 있는 `ChartScale`을 쓴다.
///
/// **카드가 아니라 리스트만 그린다** — 제목·콜아웃·`GlassCard`는 부르는 쪽이 얹는다.
/// **탭은 콜아웃만 바꾼다**(`onSelect`) — 다른 차트들과 같은 규칙이다.
struct DivergingRankList: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        /// 부호가 뜻을 갖는다. 양수면 올랐다.
        let value: Decimal
        /// 오른쪽에 적는 한 줄. 부호까지 포함한 표기를 부르는 쪽이 만든다.
        let detail: String
    }

    let rows: [Row]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxAbs = ChartScale.maxAbsValue(
            rows.map { ChartPoint(id: $0.id, label: $0.label, value: $0.value) }
        )
        VStack(spacing: 8) {
            ForEach(rows) { row in
                bar(row, maxAbs: maxAbs)
            }
        }
    }

    private func bar(_ row: Row, maxAbs: Decimal) -> some View {
        let isSelected = row.id == selectedID
        // 오른 항목은 경고색이다 — 「더 냈다」가 이 리스트가 답하는 질문이다.
        let up = row.value > 0
        let fill = up ? VehicleTheme.warning : VehicleTheme.accent
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.detail)
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? fill : VehicleTheme.textSecondary)
            }
            GeometryReader { proxy in
                let width = DivergingRankGeometry.halfWidth(row.value, maxAbs: maxAbs,
                                                            trackWidth: proxy.size.width)
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 3).fill(VehicleTheme.trackFill)
                    // 기준선(0)은 늘 그린다 — 「여기가 0이다」를 눈으로 준다.
                    Rectangle()
                        .fill(VehicleTheme.cardStroke)
                        .frame(width: 1)
                    HStack(spacing: 0) {
                        // 감소는 기준선 왼쪽으로, 증가는 오른쪽으로 뻗는다. 빈 쪽을 `Spacer`로
                        // 밀어 두 막대가 늘 가운데에서 시작하게 한다.
                        if up { Spacer(minLength: 0) }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? fill : fill.opacity(0.45))
                            .frame(width: width)
                        if !up { Spacer(minLength: 0) }
                    }
                    .padding(up ? .leading : .trailing, proxy.size.width / 2)
                }
            }
            .frame(height: 10)
        }
        .contentShape(.rect)
        .onTapGesture { onSelect(row.id) }
    }
}

#Preview("발산형 순위 — 전년 동월 대비") {
    let rows = [
        DivergingRankList.Row(id: "난방비", label: "난방비", value: 30_000, detail: "+30,000원"),
        DivergingRankList.Row(id: "일반관리비", label: "일반관리비", value: 5_000, detail: "+5,000원"),
        DivergingRankList.Row(id: "세대전기료", label: "세대전기료", value: -12_400, detail: "-12,400원"),
    ]
    return DivergingRankList(rows: rows, selectedID: "난방비") { _ in }
        .padding()
        .background(VehicleTheme.background)
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/DivergingRankGeometryTests 2>&1 | tail -30
```

기대: 4개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Vehicle/Charts/DivergingRankList.swift WooriHaruTests/MaintenanceTrendTests.swift
git commit -m "feat: 발산형 순위 리스트 차트 원형을 더한다"
```

---

## Task 11: 통계 탭 — 차트 다섯 장

**Files:**
- Create: `WooriHaru/ViewModels/MaintenanceTrendsViewModel.swift`
- Create: `WooriHaru/Views/Maintenance/MaintenanceStatsTab.swift`
- Modify: `WooriHaru/Views/Maintenance/MaintenanceView.swift` (통계 탭 자리표시자 교체)
- Test: `WooriHaruTests/MaintenanceTrendTests.swift` (수트 추가)

**Interfaces:**
- Consumes: `MaintenanceServing`, `MaintenanceTrendMath`(Task 9), `MaintenanceItemDelta`, `MaintenanceFormat`(Task 4), `ChartCard`, `MonthlyBarChart`, `MonthlyLineChart`, `RankBarList`, `DivergingRankList`(Task 10), `ChartPoint`
- Produces:
  - `@MainActor @Observable final class MaintenanceTrendsViewModel`
    - `months: [MaintenanceTrendMonth]`(정렬됨), `isLoading: Bool`, `errorMessage: String?`, `hasLoaded: Bool`
    - `selectedItemName: String?`, `usageKind: MaintenanceTrendMath.UsageKind`, `selectedMonthID: String?`, `selectedItemID: String?`, `selectedUsageID: String?`, `selectedDeltaID: String?`
    - `load() async`, `reload() async`
    - 파생: `chargedPoints`, `latestItemRows`, `yearOverYearRows`, `usagePoints`, `itemPoints`, `itemNames`, `latestMonthLabel`
  - `struct MaintenanceStatsTab: View` — `@Bindable var vm: MaintenanceTrendsViewModel`

**설계 메모:**

- **`load()`는 이미 받아 뒀으면 아무것도 하지 않는다**(`hasLoaded`). 탭을 오갈 때마다 13개월을 다시 받지 않는다. 저장·수정·삭제 뒤에는 `reload()`를 부른다 — 차량 통계 탭이 같은 규칙이다.
- **정렬은 받자마자 한 번만 한다.** `months`에는 이미 오름차순인 배열만 들어간다.
- **선택 상태가 차트마다 따로다.** 한 곳에 두면 #1에서 8월을 고른 순간 #5의 콜아웃까지 바뀌어, 관계없는 두 차트가 이어져 있다고 잘못 읽힌다.
- **#3은 `nil`일 때 카드를 지우지 않고 사유를 적는다.** 카드가 통째로 사라지면 「왜 없지」가 남는다.
- 화면 맨 위에 **「부과액 기준」**을 적는다 — 목록의 8월 숫자(청구액)와 통계 막대의 8월 숫자(부과액)가 달라 보이는 것을 여기서 설명한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/MaintenanceTrendTests.swift` 아래에 덧붙인다.

```swift
@MainActor
struct MaintenanceTrendsViewModelTests {
    final class TrendStubService: MaintenanceServing, @unchecked Sendable {
        var months: [MaintenanceTrendMonth] = []
        var error: Error?
        private(set) var callCount = 0
        private(set) var requestedMonths: [Int] = []

        func fetchBills() async throws -> [MaintenanceBill] { [] }
        func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
            MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                            items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
                            unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil)
        }
        func recognize(imageData: Data) async throws -> MaintenanceRecognition {
            fatalError("이 스위트는 인식을 부르지 않는다")
        }
        func saveBill(_ request: MaintenanceBillSaveRequest) async throws {}
        func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {}
        func deleteBill(yearMonth: String) async throws {}
        func fetchTrends(months monthCount: Int) async throws -> [MaintenanceTrendMonth] {
            callCount += 1
            requestedMonths.append(monthCount)
            if let error { throw error }
            return months
        }
    }

    private func month(_ yearMonth: String, charged: Decimal,
                       items: [MaintenanceBillItem] = []) -> MaintenanceTrendMonth {
        MaintenanceTrendMonth(yearMonth: yearMonth, chargedAmount: charged, items: items, usage: nil)
    }

    /// **13을 보낸다** — 전년 동월이 범위에 들어오게 하려는 것이다.
    @Test func 열세_달을_받아_오름차순으로_담는다() async {
        let service = TrendStubService()
        service.months = [month("2026-08", charged: 2), month("2025-08", charged: 1)]
        let vm = MaintenanceTrendsViewModel(service: service)

        await vm.load()

        #expect(service.requestedMonths == [13])
        #expect(vm.months.map(\.yearMonth) == ["2025-08", "2026-08"])
    }

    /// **탭을 오갈 때마다 다시 받지 않는다.**
    @Test func 이미_받았으면_다시_받지_않는다() async {
        let service = TrendStubService()
        let vm = MaintenanceTrendsViewModel(service: service)

        await vm.load()
        await vm.load()

        #expect(service.callCount == 1)
    }

    /// 저장·수정 뒤에는 낡은 값을 버리고 다시 받는다.
    @Test func reload는_다시_받는다() async {
        let service = TrendStubService()
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()

        await vm.reload()

        #expect(service.callCount == 2)
    }

    @Test func 실패하면_메시지가_남는다() async {
        let service = TrendStubService()
        service.error = APIError.serverError(statusCode: 500, message: nil)
        let vm = MaintenanceTrendsViewModel(service: service)

        await vm.load()

        #expect(vm.errorMessage != nil)
        // 실패한 로딩은 `hasLoaded`를 세우지 않는다 — 다시 열면 재시도해야 한다.
        #expect(vm.hasLoaded == false)
    }

    /// 최근 달 항목 순위. 금액 큰 순이다.
    @Test func 최근_달_항목을_금액순으로_낸다() async {
        let service = TrendStubService()
        service.months = [
            month("2026-08", charged: 170_000,
                  items: [MaintenanceBillItem(name: "세대전기료", amount: 48_000),
                          MaintenanceBillItem(name: "일반관리비", amount: 121_000)])
        ]
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()

        #expect(vm.latestItemRows.map(\.label) == ["일반관리비", "세대전기료"])
    }

    /// 전년 동월이 없으면 #3의 행이 nil이다 — 화면이 사유를 적는다.
    @Test func 전년_동월이_없으면_증감_행이_nil이다() async {
        let service = TrendStubService()
        service.months = [month("2026-07", charged: 1), month("2026-08", charged: 2)]
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()

        #expect(vm.yearOverYearRows == nil)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceTrendsViewModelTests 2>&1 | tail -30
```

기대: `cannot find 'MaintenanceTrendsViewModel' in scope`.

- [ ] **Step 3: 뷰모델을 쓴다**

`WooriHaru/ViewModels/MaintenanceTrendsViewModel.swift`

**`import SwiftUI`다.** 이 뷰모델은 `ChartPoint`·`RankBarList.Row`·`DivergingRankList.Row`를
돌려주는데 셋 다 SwiftUI 파일에 있다 — `Foundation`만으로는 컴파일되지 않는다.

```swift
import SwiftUI

/// 통계 탭 — 차트 다섯 장이 한 응답(`/maintenance/trends`) 위에 올라간다.
///
/// **13개월을 받는다.** 전년 동월이 범위에 들어오게 하려는 것이다 — 난방비처럼 계절을
/// 타는 항목은 전월이 아니라 전년 동월과 견줘야 뜻이 있다.
@MainActor
@Observable
final class MaintenanceTrendsViewModel {
    private static let monthWindow = 13

    private let service: any MaintenanceServing

    /// **늘 `yearMonth` 오름차순이다** — 받자마자 한 번만 정렬한다. 차트 다섯 장이 전부
    /// 시간축이라 순서가 뒤집히면 전부 거짓말이 된다.
    private(set) var months: [MaintenanceTrendMonth] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    /// **차트마다 선택이 따로다.** 한 곳에 두면 #1에서 8월을 고른 순간 #5의 콜아웃까지
    /// 바뀌어, 관계없는 두 차트가 이어져 있다고 잘못 읽힌다.
    var selectedMonthID: String?
    var selectedRankID: String?
    var selectedDeltaID: String?
    var selectedUsageID: String?
    var selectedItemID: String?

    var usageKind: MaintenanceTrendMath.UsageKind = .electricity
    /// nil이면 항목 목록의 첫째를 쓴다 — 화면이 열리자마자 빈 차트를 보이지 않으려는 것이다.
    var selectedItemName: String?

    init(service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
    }

    /// **이미 받아 뒀으면 아무것도 하지 않는다** — 탭을 오갈 때마다 13개월을 다시 받지 않는다.
    func load() async {
        guard !hasLoaded else { return }
        await fetch()
    }

    /// 저장·수정·삭제 뒤. 낡은 값을 버리고 다시 받는다.
    func reload() async {
        await fetch()
    }

    private func fetch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            months = MaintenanceTrendMath.sorted(
                try await service.fetchTrends(months: Self.monthWindow)
            )
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            // 실패는 `hasLoaded`를 세우지 않는다 — 다시 열면 재시도해야 한다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
    }

    // MARK: - 파생

    var latestMonthLabel: String {
        months.last.map { MaintenanceFormat.monthTitle($0.yearMonth) } ?? "—"
    }

    /// #1 월별 부과액 추이.
    var chargedPoints: [ChartPoint] { MaintenanceTrendMath.chargedPoints(months) }

    /// #2 최근 달 항목 구성 — 금액 큰 순.
    var latestItemRows: [RankBarList.Row] {
        guard let latest = months.last else { return [] }
        let total = latest.items.reduce(Decimal(0)) { $0 + $1.amount }
        return latest.items
            .sorted { $0.amount > $1.amount }
            .map { item in
                let share = total > 0 ? item.amount / total : 0
                return RankBarList.Row(
                    id: item.name,
                    label: item.name,
                    value: item.amount,
                    primary: MaintenanceFormat.won(item.amount),
                    // 비율은 부호 없이 적는다 — 구성비지 증감이 아니다.
                    secondary: MaintenanceFormat.percent(share).replacingOccurrences(of: "+", with: ""),
                    note: nil
                )
            }
    }

    /// #3 전년 동월 대비 항목별 증감. **전년 동월이 범위에 없으면 nil이다.**
    var yearOverYearRows: [DivergingRankList.Row]? {
        MaintenanceTrendMath.yearOverYearDeltas(months).map { deltas in
            deltas.map { delta in
                DivergingRankList.Row(
                    id: delta.name,
                    label: delta.name,
                    value: delta.delta,
                    detail: MaintenanceFormat.signedWon(delta.delta)
                )
            }
        }
    }

    /// #4 사용량 추이.
    var usagePoints: [ChartPoint] {
        MaintenanceTrendMath.usagePoints(months, kind: usageKind)
    }

    /// #5 항목 하나의 월별 추이.
    var itemNames: [String] { MaintenanceTrendMath.itemNames(months) }

    var effectiveItemName: String? {
        selectedItemName ?? itemNames.first
    }

    var itemPoints: [ChartPoint] {
        guard let name = effectiveItemName else { return [] }
        return MaintenanceTrendMath.itemPoints(months, name: name)
    }

    // MARK: - 콜아웃

    /// 고른 점의 값을 한 줄로. 고른 것이 없으면 마지막 점이다 — 빈 콜아웃을 두지 않는다.
    func callout(for points: [ChartPoint], selectedID: String?, suffix: String) -> String? {
        let point = points.first { $0.id == selectedID } ?? points.last
        guard let point else { return nil }
        guard let value = point.value else { return "\(point.label)월 기록 없음" }
        let text = suffix.isEmpty
            ? MaintenanceFormat.won(value)
            : "\(NSDecimalNumber(decimal: value).stringValue) \(suffix)"
        return "\(point.label)월 \(text)"
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests/MaintenanceTrendsViewModelTests 2>&1 | tail -30
```

기대: 6개 PASS.

- [ ] **Step 5: 통계 탭을 쓴다**

`WooriHaru/Views/Maintenance/MaintenanceStatsTab.swift`

```swift
import SwiftUI

/// 통계 탭 — 차트 다섯 장이 한 응답 위에 올라간다.
///
/// **「부과액 기준」을 맨 위에 적는다.** 목록의 8월 숫자는 청구액이고 여기 막대는 부과액이라
/// 서로 다른데, 안 적으면 같은 달의 숫자가 둘로 보인다(`/maintenance/trends`에 청구액이 없다).
struct MaintenanceStatsTab: View {
    @Bindable var vm: MaintenanceTrendsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                chargedCard
                latestItemsCard
                yearOverYearCard
                usageCard
                itemTrendCard
                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96)   // 하단 탭바가 마지막 카드를 가리지 않게
        }
        .task { await vm.load() }
    }

    private var header: some View {
        HStack {
            Text("최근 13개월 · 부과액 기준")
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            Spacer()
            if vm.isLoading { ProgressView().controlSize(.small) }
        }
    }

    // MARK: - #1 월별 부과액 추이

    private var chargedCard: some View {
        ChartCard(title: "월별 관리비",
                  callout: vm.callout(for: vm.chargedPoints,
                                      selectedID: vm.selectedMonthID, suffix: "")) {
            MonthlyBarChart(points: vm.chargedPoints,
                            selectedID: vm.selectedMonthID) { vm.selectedMonthID = $0 }
        }
    }

    // MARK: - #2 최근 달 항목 구성

    private var latestItemsCard: some View {
        ChartCard(title: "\(vm.latestMonthLabel) 항목 구성", callout: nil) {
            if vm.latestItemRows.isEmpty {
                emptyLine("등록된 항목이 없습니다")
            } else {
                RankBarList(rows: vm.latestItemRows,
                            selectedID: vm.selectedRankID) { vm.selectedRankID = $0 }
            }
        }
    }

    // MARK: - #3 전년 동월 대비

    private var yearOverYearCard: some View {
        ChartCard(title: "전년 동월 대비", callout: nil) {
            if let rows = vm.yearOverYearRows, !rows.isEmpty {
                DivergingRankList(rows: rows,
                                  selectedID: vm.selectedDeltaID) { vm.selectedDeltaID = $0 }
            } else if vm.yearOverYearRows != nil {
                emptyLine("작년 이맘때와 달라진 항목이 없습니다")
            } else {
                // **카드를 지우지 않는다** — 통째로 사라지면 「왜 없지」가 남는다.
                emptyLine("전년 동월 자료가 쌓이면 보여드립니다")
            }
        }
    }

    // MARK: - #4 사용량 추이

    private var usageCard: some View {
        ChartCard(title: "사용량 추이",
                  callout: vm.callout(for: vm.usagePoints,
                                      selectedID: vm.selectedUsageID,
                                      suffix: vm.usageKind.unit)) {
            VStack(spacing: 10) {
                // 단위가 달라(kWh·m³·Gcal·kg) 한 차트에 겹쳐 그리지 않고 하나씩 본다.
                Picker("사용량", selection: $vm.usageKind) {
                    ForEach(MaintenanceTrendMath.UsageKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                MonthlyLineChart(points: vm.usagePoints,
                                 selectedID: vm.selectedUsageID) { vm.selectedUsageID = $0 }
            }
        }
    }

    // MARK: - #5 항목 하나의 월별 추이

    private var itemTrendCard: some View {
        ChartCard(title: "항목별 추이",
                  callout: vm.callout(for: vm.itemPoints,
                                      selectedID: vm.selectedItemID, suffix: "")) {
            VStack(alignment: .leading, spacing: 10) {
                if vm.itemNames.isEmpty {
                    emptyLine("등록된 항목이 없습니다")
                } else {
                    Menu {
                        // **13개월에 한 번이라도 나온 이름을 전부 올린다** — 최근 달에만 있는
                        // 이름으로 좁히면 표기가 바뀐 항목이 피커에서 사라진다.
                        ForEach(vm.itemNames, id: \.self) { name in
                            Button(name) {
                                vm.selectedItemName = name
                                vm.selectedItemID = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.effectiveItemName ?? "항목 고르기")
                                .font(.caption)
                                .fontWeight(.bold)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(VehicleTheme.accentBright)
                    }

                    MonthlyBarChart(points: vm.itemPoints,
                                    selectedID: vm.selectedItemID) { vm.selectedItemID = $0 }
                }
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(VehicleTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}
```

- [ ] **Step 6: 탭 자리표시자를 갈아 끼운다**

`WooriHaru/Views/Maintenance/MaintenanceView.swift`:

```swift
    @State private var trendsViewModel = MaintenanceTrendsViewModel()   // ← @State에 추가
```

```swift
        case .stats:
            MaintenanceStatsTab(vm: trendsViewModel)
```

그리고 등록·수정·삭제 뒤에 통계도 갱신한다. **`load()`가 아니라 `reload()`다** — 전자는 「이미 받아 뒀으면 아무것도 안 한다」라 낡은 값이 그대로 남는다. `MaintenanceView`의 두 목적지 클로저를 이렇게 바꾼다.

```swift
        .navigationDestination(isPresented: $showingUpload) {
            MaintenanceUploadView {
                Task {
                    await billsViewModel.load()
                    await refreshTrendsIfLoaded()
                }
            }
        }
        .navigationDestination(item: $selectedYearMonth) { yearMonth in
            if let bill = billsViewModel.bills.first(where: { $0.yearMonth == yearMonth }) {
                MaintenanceBillDetailView(
                    bill: bill,
                    onChanged: { Task { await billsViewModel.load(); await refreshTrendsIfLoaded() } },
                    onDeleted: { Task { await billsViewModel.load(); await refreshTrendsIfLoaded() } }
                )
            }
        }
```

```swift
    /// 아직 안 열어 본 통계 탭은 그냥 둔다 — 그때는 `hasLoaded`가 false라 다음에 열 때
    /// `load()`가 처음부터 받는다. 차량 통계 탭이 같은 규칙이다.
    private func refreshTrendsIfLoaded() async {
        guard trendsViewModel.hasLoaded else { return }
        await trendsViewModel.reload()
    }
```

- [ ] **Step 7: 빌드와 전체 테스트를 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'generic/platform=iOS' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

기대: `** BUILD SUCCEEDED **`.

```bash
xcodebuild test -project WooriHaru.xcodeproj -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

기대: 저장소 전체 테스트 PASS.

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/ViewModels/MaintenanceTrendsViewModel.swift \
        WooriHaru/Views/Maintenance \
        WooriHaruTests/MaintenanceTrendTests.swift
git commit -m "feat: 관리비 통계 탭에 차트 다섯 장을 그린다"
```

---

## 끝난 뒤

사용자가 실기기로 확인할 것:

1. 드로어 → 관리비 → 빈 목록 안내가 보인다
2. 「+」 → 고지서 사진 → 인식(1~2분) → 검수 화면에 항목이 채워져 있다
3. 항목 하나를 고치면 합계 차이가 즉시 바뀐다
4. 저장 → 목록에 그 달이 뜬다
5. 같은 달을 다시 등록하면 「이미 등록된 달입니다」 → 「기존 내역 수정하기」가 서버 값으로 폼을 채운다
6. 상세 → 수정/삭제
7. 통계 탭 다섯 장 — 자료가 한 달뿐이면 #3이 「전년 동월 자료가 쌓이면」을 적는다

**PR은 사용자가 요청할 때만 올린다.** 커밋까지만 하고 멈춘다.
