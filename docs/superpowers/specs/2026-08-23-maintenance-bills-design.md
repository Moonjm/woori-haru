# 관리비 미니앱 설계

**한 줄 요약.** 아파트 관리비 고지서를 **사진으로 찍어 올리면 서버가 읽고, 사람이 검수해 확정**하는 미니앱을 드로어에 새로 단다. 화면은 목록·상세·등록(인식→검수)·통계 넷이고, 통계는 13개월 추이로 차트 다섯 장을 그린다. 서버는 이미 다 있고 앱만 붙인다.

**서버 API:** `https://daily.eunji.shop/api/swagger-ui/index.html` — 태그 「관리비」 (`/maintenance/*`)

**따라가는 선례:** 인식→검수→확정 흐름은 `docs/superpowers/specs/2026-08-12-schedule-calendar-design.md`(배차표 업로드), 차트 원형·다크 테마는 `docs/superpowers/specs/2026-08-20-vehicle-insights-tabs-design.md`(차량 통계 탭)를 그대로 물려받는다.

## 배경

관리비 고지서는 매달 종이로 온다. 지금은 아무 데도 안 남는다 — 가계부에 총액 한 줄을 적어도 **「전기가 오른 건지 난방이 오른 건지」에 답하지 못한다.** 항목이 스무 개 넘게 찍혀 나오는데 그 표를 손으로 앱에 옮겨 적을 사람은 없다.

서버에 이미 답이 있다. `POST /maintenance/recognitions`가 고지서 사진 한 장을 받아 **항목·금액·사용량을 통째로 읽어 준다.** 저장은 하지 않고 결과만 주므로, 배차표와 똑같이 **사람이 눈으로 검수한 뒤 확정**하는 구조를 그대로 쓸 수 있다. `GET /maintenance/trends`는 기본 13개월을 주는데, 13이라는 숫자는 **전년 동월이 범위에 들어오라고** 고른 값이다 — 난방비처럼 계절을 타는 항목은 전월이 아니라 전년 동월과 견줘야 뜻이 있다.

## 목표

- 고지서 사진 한 장에서 **손으로 적는 일 없이** 한 달치가 저장된다.
- 인식이 틀린 자리를 **저장 전에** 고칠 수 있다. 저장 뒤에도 고칠 수 있다.
- 「이번 달 왜 많이 나왔나」에 항목 단위로 답한다.
- 차트를 새로 그리지 않는다 — 차량 통계 탭의 원형을 그대로 쓴다.

## 비목표

- **가계부와 잇지 않는다.** 관리비를 가계부 내역으로 자동 등록하는 길은 이번에 만들지 않는다. 서버에도 그 연결이 없다.
- **고지서 사진을 보관하지 않는다.** 서버가 사진을 저장하지 않고 `BillResponse`에 이미지 필드가 없다. 앱도 저장한 뒤 사진을 버린다.
- **여러 세대를 다루지 않는다.** `dong`·`ho`는 인식 결과를 그대로 싣고 보여줄 뿐, 세대별로 나누어 조회하지 않는다.
- **알림을 넣지 않는다.** 납기일이 서버에서 빠지면서 알릴 시점 자체가 없어졌다.
- **Swift Charts를 들이지 않는다.** 저장소 관례대로 `Views/Vehicle/Charts`의 원형을 쓴다.

---

## 데이터

서버 스키마를 그대로 옮긴다. 이름만 앱 관례(`Maintenance*`)로 맞춘다.

### 한 달치 — `MaintenanceBill`

| 필드 | 타입 | 비고 |
|---|---|---|
| `yearMonth` | `String` | `2026-08` |
| `dong`, `ho` | `String?` | 인식 결과. 없을 수 있다 |
| `areaM2` | `Decimal?` | 전용면적 |
| `items` | `[MaintenanceBillItem]` | `name`(≤50자) · `amount` |
| `usage` | `MaintenanceUsage` | 전기kWh · 수도m³ · 온수m³ · 난방Gcal · 음식물kg, **전부 옵셔널** |
| `chargedAmount` | `Decimal` | **당월 부과액 — 이 기능이 다루는 숫자** |
| `discountTotal` | `Decimal` | 할인 합계 |

**금액은 `Decimal`로 받는다.** `Double`로 받으면 원 단위 합계가 어긋나고, 항목 합계와 부과액을 견주는 검수 화면이 있을 자리도 없는 오차를 띄운다. 저장소의 `LedgerModels`가 이미 `Decimal`을 쓴다.

**`usage`의 다섯 값은 전부 nil일 수 있다.** 여름에는 난방 Gcal이 아예 안 찍히고, 사진이 잘리면 어느 것이든 빠진다. 「0」과 「모름」은 다르다 — 0으로 접으면 통계에서 **안 쓴 달과 못 읽은 달이 같은 막대**가 된다. 차트 원형(`ChartPoint.value: Decimal?`)이 이미 그 구분을 그리게 되어 있다.

### 인식 결과 — `MaintenanceRecognition`

`MaintenanceBill`의 모든 필드에 둘이 더 붙는다.

- `sumMatched: Bool` — **항목 합계가 부과액과 맞는가.** false면 어딘가 잘못 읽혔다는 뜻이라 검수 화면이 크게 알린다.
- `warnings: [String]` — 서버가 붙이는 경고. **이미 사용자용 한국어다** — 앱이 다시 쓰지 않고 그대로 띄운다(배차표 `errorMessage` 처리와 같은 규칙).

`yearMonth`는 **옵셔널이다.** 고지서 제목이 잘리면 서버가 못 읽는다 — 검수 화면이 채운다.

### 추이 — `MaintenanceTrendMonth`

`yearMonth` · `chargedAmount` · `items` · `usage`. `GET /maintenance/trends?months=13`이 오래된 달부터인지 최근 달부터인지는 **응답을 믿지 않고 앱에서 `yearMonth` 오름차순으로 정렬한다** — 차트 다섯 장이 전부 시간축이라 순서가 뒤집히면 전부 거짓말이 된다.

**금액은 `chargedAmount` 하나다.** 초기 설계는 목록·상세가 `dueAmount`(청구액)를, 통계가 `chargedAmount`(부과액)를 쓰는 구조였고, 같은 달의 숫자가 화면마다 달라 보이는 것을 「부과액 기준」이라 적어 막을 작정이었다. **서버가 `dueAmount`·`unpaidAmount`·`unpaidLateFee`·`dueDate` 네 컬럼을 지우면서 그 갈림이 사라졌다** — 미납을 다루지 않기로 하면 납기내 금액이 늘 당월부과액과 같아지기 때문이다. 이제 목록·상세·통계가 전부 같은 숫자를 그리므로 화면에 기준을 적을 자리가 없다.

---

## 서비스

```swift
protocol MaintenanceServing: Sendable {
    func fetchBills() async throws -> [MaintenanceBill]
    func fetchBill(yearMonth: String) async throws -> MaintenanceBill
    func recognize(imageData: Data) async throws -> MaintenanceRecognition
    func saveBill(_ request: MaintenanceBillSaveRequest) async throws
    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws
    func deleteBill(yearMonth: String) async throws
    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth]
}
```

`DispatchServing`과 같은 꼴이다 — 프로토콜로 갈라 두어야 `MockAPIClient` 없이도 뷰모델 테스트가 선다. 구현은 `APIClient`의 `get`/`postVoid`/`putVoid`/`deleteVoid`/`postMultipart`를 그대로 쓴다.

**`POST /maintenance/bills`는 201에 문자열 본문을 준다.** `postVoid`로 받고 본문을 버린다 — 저장한 연월은 호출자가 이미 알고 있다.

---

## 화면

진입점은 드로어 상단 메뉴의 「관리비」(`wonsign.square`), 「차량」 바로 아래. `AppDestination.maintenance`를 더한다.

전 화면이 `.glassScreenBackground().vehicleDarkTheme()`을 쓴다. 차량 미니앱과 같은 껍데기다.

### 1. `MaintenanceView` — 목록 + 통계 두 탭

차량과 같은 하단 글래스 탭바. **탭은 둘이 상한이다.**

**내역 탭.** `GET /maintenance/bills`를 최근 달부터 카드로 세운다. 카드 한 장에:

- `2026년 8월` — 큰 글씨
- 부과액(`chargedAmount`) — 강조색, `monospacedDigit`
- 전월 대비 증감 — `+12,300 (+4.1%)`. **바로 앞 달이 목록에 없으면 그리지 않는다** — 두 달 건너뛴 비교를 「전월 대비」라고 적으면 거짓이다
- 할인이 있으면 그 액수를 한 줄로

빈 목록이면 「고지서 사진을 올려 첫 달을 등록해 보세요」 + 등록 버튼.

툴바 오른쪽 「+」 → 등록 화면.

**통계 탭.** 아래 [통계](#통계) 절.

### 2. `MaintenanceUploadView` — 사진 고르기·인식

`DispatchUploadView`를 본으로 삼는다. 그 화면이 값을 치르고 알아낸 것들을 그대로 물려받는다.

- **사진을 축소하지 않는다.** `UIImage.jpegWithinByteLimit`로 HEIC를 JPEG로 다시 굽되 해상도는 원본 그대로다. 고지서는 배차표보다 더 잘아서(항목 20여 줄에 금액이 6자리) 줄이면 숫자가 뭉개진다. 서버 multipart 한도 10MB.
- 굽기는 `Task.detached` — 메인에서 돌리면 4,800만 화소에서 화면이 몇 초 멎는다. 사진을 바꾸면 **이전 굽기도 함께 취소한다.**
- 뷰모델에 `generation` 토큰 — 인식 도는 중에 사진을 바꾸면 이전 결과를 버린다. 안 그러면 **이전 사진의 인식 결과와 새 사진의 미리보기가 섞인** 검수 화면이 열린다.
- 연월을 앱이 보내지 않는다. 사진에 적힌 것을 서버가 읽는다.
- 안내 문구: 고지서 표 전체가 한 장에 들어오게, 금액 열이 잘리지 않게, 인식에 1~2분.

인식이 끝나면 검수 화면으로 넘어간다(`navigationDestination(isPresented:)` + `onChange(of: phase)`).

### 3. `MaintenanceBillFormView` — 검수 = 편집 (한 화면 공용)

```swift
enum Mode: Equatable {
    case create(MaintenanceRecognition)   // 인식 결과 검수
    case edit(MaintenanceBill)            // 저장된 달 수정
}
```

**두 경우를 한 화면으로 둔다.** 화면을 나누면 항목 편집·합계 검증·저장 요청 조립이 두 벌이 되고, 한쪽만 고친 날 두 화면이 다른 값을 저장한다.

구성(위에서부터):

1. **경고 배너** — `.create`에서만. `sumMatched == false`면 「항목 합계와 부과액이 맞지 않습니다」를 경고색으로, `warnings`가 있으면 줄줄이. 서버 문구를 그대로 쓴다.
2. **연월** — `.create`에서 nil이면 비어 있고, **비어 있으면 저장 버튼이 잠긴다.** `.edit`에서는 읽기 전용(연월이 곧 키다 — 바꾸는 것은 삭제 후 재등록이지 수정이 아니다).
3. **세대** — 동·호·면적. 셋 다 옵셔널.
4. **항목** — 이름·금액 편집 행. 행 추가/삭제(스와이프). **최소 한 줄**(서버 `minItems: 1`). 이름 50자 제한.
5. **항목 합계 / 부과액 대조** — 항목 금액을 더한 값과 입력된 `chargedAmount`를 나란히 놓고, 다르면 차액을 경고색으로 띄운다. **앱이 실시간으로 다시 계산한다** — 서버의 `sumMatched`는 인식 시점 판정이라 사람이 금액을 고치면 낡는다. **막지는 않는다** — 고지서에 반올림·별도 조정이 실제로 있을 수 있어, 판단은 사람이 한다.
6. **사용량** — 전기·수도·온수·난방·음식물 다섯 칸. 비우면 nil로 나간다(0으로 채우지 않는다).
7. **금액** — 부과액과 할인 합계 둘뿐이다.

저장: `.create` → `POST`, `.edit` → `PUT`. 성공하면 목록으로 돌아가며 목록을 다시 받는다.

**409 처리.** `POST`가 409면 그 달이 이미 있다는 뜻이다. 에러 문구만 띄우면 사용자가 막힌다 — 「이미 등록된 달입니다」와 함께 **「기존 내역 수정하기」 버튼**을 띄우고, 누르면 그 달을 받아 `.edit` 모드로 갈아 끼운다. 사용자가 지금 화면에서 손본 값은 그대로 두고 저장 방식만 바뀌는 게 아니라, **서버 값을 받아 다시 채운다** — 방금 인식한 값으로 기존 달을 통째로 덮는 것은 사용자가 의도한 적 없는 파괴다.

### 4. `MaintenanceBillDetailView` — 한 달 상세

`GET /maintenance/bills/{yearMonth}`.

- 부과액 히어로 + 연월 + 세대(동/호/면적)
- 할인 합계 — 0이 아닐 때만 한 줄
- **항목 표** — 금액 큰 순. 각 행에 부과액 대비 비율 막대를 옅게 깐다
- **사용량 타일** — 값이 있는 것만. nil은 「—」로 자리만 지킨다

툴바: 「수정」 → `.edit` 폼, 「삭제」 → 확인 알럿 후 `DELETE`, 목록으로 복귀.

---

## 통계

`GET /maintenance/trends?months=13`. 목록·상세와 같은 `chargedAmount`를 그리므로 기준을 따로 적지 않는다.

전부 `ChartCard`로 감싸고, 차량 통계 탭의 규칙을 지킨다 — **탭은 콜아웃만 바꾼다.** 화면을 옮기거나 달을 바꾸지 않는다.

| # | 카드 | 원형 | 답하는 질문 |
|---|---|---|---|
| 1 | 월별 관리비 추이 | `MonthlyBarChart` | 언제 많이 나왔나 |
| 2 | 최근 달 항목 구성 | `RankBarList` | 이번 달 무엇이 컸나 |
| 3 | 전년 동월 대비 항목별 증감 | `DivergingRankList` (신규 원형) | 작년 이맘때보다 무엇이 올랐나 |
| 4 | 사용량 추이 | `MonthlyLineChart` + 5종 토글 | 실제로 더 썼나, 단가가 오른 건가 |
| 5 | 항목 하나의 월별 추이 | `MonthlyBarChart` + 항목 피커 | 이 항목만 따라가 보기 |

**#3의 축은 달이 아니라 항목이라, 원형 하나를 새로 둔다.** 기존 `DivergingMonthlyBarChart`는 `[ChartPoint]`를 받아 부호까지 그리지만 **가로축에 9pt 라벨을 놓는다** — 달 이름(`8`)은 들어가도 「일반관리비」·「세대전기료」는 슬롯 폭에 못 들어간다. `RankBarList`는 세로 리스트라 이름이 들어가지만 **부호를 표현하지 못한다**(막대가 늘 왼쪽에서 오른쪽으로 자라고 색이 하나다).

그래서 `DivergingRankList`를 새로 만든다 — 세로 리스트, 가운데 기준선, **오른쪽으로 자라면 증가(경고색), 왼쪽으로 자라면 감소(강조색)**. 기하 계산은 이미 있는 `ChartScale.maxAbsValue`·`divergingRatio`를 그대로 쓴다(테스트가 이미 붙어 있다). 값은 `이번 달 금액 − 전년 동월 금액`, **증감 절댓값 큰 순 상위 8개**만 그린다 — 항목이 스무 개 넘어 전부 그리면 0에 가까운 행이 화면을 먹는다.

새 원형은 관리비만 쓰지만 `Views/Vehicle/Charts`에 둔다 — 차트 원형이 두 군데로 갈리면 다음 화면이 어디를 뒤져야 할지 모른다.

**전년 동월이 범위에 없으면 #3을 그리지 않는다.** 13개월이 다 차지 않은 초기(등록한 달이 두세 달뿐)에는 카드 자리에 「전년 동월 자료가 쌓이면 보여드립니다」를 놓는다. 없는 비교를 0으로 채우면 **모든 항목이 「신설」로 보인다.**

**#4의 다섯 값은 단위가 다르다**(kWh · m³ · Gcal · kg). 한 차트에 겹쳐 그리지 않고 **토글로 하나씩** 본다. 값이 없는 달은 `ChartPoint.value = nil`로 넘겨 트랙 색 자리만 남긴다.

**#5의 항목 이름은 달마다 다를 수 있다.** 고지서 표기가 바뀌거나 인식이 조금 다르게 읽으면 「전기료」와 「전기료(공동)」이 갈린다. 피커에는 **13개월에 한 번이라도 나온 이름을 전부** 올리고, 그 이름이 없는 달은 nil이다(0이 아니다).

---

## 오류와 빈 상태

| 상황 | 화면 |
|---|---|
| 목록 비었음 | 안내 + 등록 버튼 |
| 인식 실패 | 서버 메시지(`error.serverMessage`)를 그대로. 사진 다시 고르기 유도 |
| 사진 읽기/굽기 실패 | 「사진을 읽지 못했습니다. 다른 사진으로 다시 시도해 주세요」 |
| 저장 409 | 「이미 등록된 달입니다」 + 기존 내역 수정하기 |
| 통계 자료 부족 | 카드별로 자리를 지키고 사유를 적는다. 화면 전체를 비우지 않는다 |
| 취소(`CancellationError`) | 아무것도 띄우지 않는다 — 사용자가 화면을 떠난 것이지 실패가 아니다 |

---

## 테스트

`WooriHaruTests/MaintenanceTests.swift`. TDD로 붙인다.

**서비스** — `MockAPIClient`로 경로·쿼리·바디를 검증한다. 특히 `trends`의 `months` 쿼리, `bills/{yearMonth}`의 경로 조립, 저장 요청에서 **비운 사용량 칸이 키째 빠지는지**(0으로 나가면 안 된다).

**폼 뷰모델** — 항목 추가/삭제 후 합계 재계산, 합계 불일치 판정, 연월이 비면 저장 잠금, 항목이 0개면 저장 잠금, `.create`/`.edit`가 만드는 저장 요청이 같은 항목 리스트에서 같은 바디를 내는지.

**통계 파생** — 순수 함수로 뽑아 검증한다.
- `yearMonth` 오름차순 정렬
- 전년 동월 매칭(있음/없음)과 항목별 증감 계산
- 13개월 전체에서 항목 이름 모으기, 없는 달이 nil로 남는지
- 사용량 시리즈에서 nil이 0으로 접히지 않는지
- 목록의 전월 대비 증감이 **연속하지 않은 달에서는 나오지 않는지**

**업로드 뷰모델** — `generation` 토큰이 늦게 돌아온 인식 결과를 버리는지(배차표 테스트와 같은 모양).

---

## 파일

```
Views/Vehicle/Charts/DivergingRankList.swift      신규 차트 원형 (#3)
Models/MaintenanceModels.swift
Services/MaintenanceService.swift
ViewModels/MaintenanceBillsViewModel.swift        목록·상세·삭제
ViewModels/MaintenanceUploadViewModel.swift       사진·인식
ViewModels/MaintenanceBillFormViewModel.swift     검수·편집 공용
ViewModels/MaintenanceTrendsViewModel.swift       통계
Views/Maintenance/MaintenanceView.swift           탭 껍데기 + 내역 탭
Views/Maintenance/MaintenanceBillCard.swift       목록 카드
Views/Maintenance/MaintenanceUploadView.swift
Views/Maintenance/MaintenanceBillFormView.swift
Views/Maintenance/MaintenanceItemRow.swift        항목 편집 행
Views/Maintenance/MaintenanceUsageFields.swift    사용량 입력 5칸
Views/Maintenance/MaintenanceBillDetailView.swift
Views/Maintenance/MaintenanceStatsTab.swift       차트 5장
WooriHaruTests/MaintenanceTests.swift
```

고치는 파일: `ContentView.swift`(`AppDestination.maintenance`), `Views/Components/SideDrawerView.swift`(드로어 항목).

**폼과 통계 탭이 커지기 쉽다.** 항목 행·사용량 입력·차트 카드를 처음부터 갈라 둔다 — 한 파일이 400줄을 넘으면 그때 나누는 게 아니라 그전에 나눈다.

---

## 작업 순서

1. 모델 + 서비스 + 서비스 테스트
2. 목록 탭 + 드로어 진입점 (빈 상태까지)
3. 업로드 → 인식 → 검수 폼 → 저장 (409 포함)
4. 상세 + 수정 + 삭제
5. 통계 탭 다섯 장

각 단계가 끝나면 화면이 돌아간다. 3단계까지만 있어도 쓸모가 있다.
