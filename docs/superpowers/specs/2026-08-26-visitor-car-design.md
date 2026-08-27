# 방문차량 미니앱 설계

**한 줄 요약.** 아파트 주차관제 웹(`nxpmsc`)에 **앱에서 바로** 방문차량을 등록하고, 등록 내역과 입출차 현황을 보는 미니앱을 드로어에 새로 단다. 서버는 우리 것이 아니다 — **남의 세션 기반 웹사이트를 앱이 대신 두드린다.**

**대상 사이트:** `http://dasanesesang.iptime.org/nxpmsc`. 계정은 세대 단위이고, **아이디 자체가 동·호를 담고 있다**(`{동4자리}{호4자리}`).

**이 문서에 실린 아이디·동·호·차량번호는 전부 자리를 채우려고 지어낸 값이다.** 실제 값은 문서에 남기지 않는다 — 계정은 Keychain에, 동·호는 사이트가 응답으로 준다.

**따라가는 선례:** 미니앱 껍데기·다크 테마·글래스 탭바는 `docs/superpowers/specs/2026-08-23-maintenance-bills-design.md`(관리비)와 `2026-08-13-vehicle-mini-app-design.md`(차량)를 그대로 물려받는다.

## 배경

방문차량을 등록하려면 지금은 브라우저를 열어 `nxpmsc`에 로그인하고, 사이드 메뉴에서 「차량 방문예약」으로 들어가, 모달을 띄워 폼을 채운다. 데스크톱용 부트스트랩 화면이라 폰에서는 글자가 깨알같고 달력 위젯이 손가락에 맞지 않는다. **한 달에 몇 번씩 하는 일인데 매번 로그인부터 시작한다.**

그런데 사이트를 뜯어 보면 앱이 쓸 만한 것이 이미 다 있다. 목록 조회 둘은 **DataTables 서버사이드 페이징용 JSON 엔드포인트**를 그대로 노출하고, 등록·수정·삭제는 `{"result":"success"}` 꼴의 JSON을 돌려준다. 화면만 낡았지 속은 API다.

우리 하루에는 이미 「차량」·「관리비」 미니앱이 있고, 아파트에 관한 것은 관리비가 이미 들어와 있다. 방문차량은 **같은 서랍에 들어갈 물건**이다.

## 목표

- 드로어에서 두 번 눌러 **차량번호와 기간만 채우면** 방문차량이 등록된다.
- 자주 오는 차(부모님 차 등)를 기기에 저장해 두고 **골라서** 등록한다.
- 등록 내역을 기간으로 조회하고, 입차 전이면 고치거나 지운다.
- 우리 세대 차량이 **지금 들어와 있는지, 몇 시간째인지** 본다.
- 로그인은 처음 한 번뿐이다. 세션이 끊기면 앱이 조용히 다시 붙는다.

## 비목표

- **주차 초과 요금 계산기를 만들지 않는다.** 참고 화면에는 있지만 요금표를 사이트에서 가져올 길이 없다. 상수를 손으로 박아 넣으면 요금 개정 때 조용히 틀린 값을 보여준다 — 틀린 금액은 없는 것보다 나쁘다.
- **비밀번호 변경을 넣지 않는다.** 사이트에 `/nxpmsc/user/password/next`가 있지만 일 년에 한 번 쓸까 말까다. 브라우저로 한다.
- **여러 세대·여러 계정을 다루지 않는다.** 자격증명은 한 벌만 저장한다.
- **엑셀 내려받기를 옮기지 않는다.**
- **웹 화면을 `WKWebView`로 감싸지 않는다.** 그건 지금 브라우저로 하는 일과 같고, 로그인 자동화도 폼 주입이라 더 부서지기 쉽다. 네이티브로 그린다.
- **알림을 넣지 않는다.** 잔여시간이 바닥나는 시점을 앱이 알 방법이 폴링뿐이다.

---

## 외부 API 규격

**아래는 전부 실제로 호출해 확인한 것이다.** 문서가 없는 사이트라 관찰이 유일한 근거다. 확인하지 않은 것은 그렇다고 적었다.

공통: `Base = http://dasanesesang.iptime.org`, 컨텍스트 `/nxpmsc`. 인증은 `JSESSIONID` 쿠키 하나.

경로가 두 갈래인 점을 먼저 알아 두어야 한다. 화면을 그리는 낡은 경로(`/nxpmsc/book-car/*`)와, DataTables가 쓰는 새 경로(`/nxpmsc/web/*`)가 공존한다. **목록 조회는 `/web` 쪽을 쓴다** — 페이징·정렬이 규격화되어 있고 응답이 일관된다. 등록·수정·삭제는 `/web`에 짝이 없어 낡은 경로를 쓴다.

### 1. 로그인 — `POST /nxpmsc/do-login`

`application/x-www-form-urlencoded`, 필드 `id`·`password`·`loginUserLogout=N`.

**성공과 실패가 둘 다 302다.** 상태코드로는 가를 수 없고 `Location`으로 갈라야 한다.

| | Location |
|---|---|
| 성공 | `http://.../nxpmsc/book-car` + `Set-Cookie: JSESSIONID=…` |
| 실패 | `http://.../nxpmsc/login;jsessionid=…?result=아이디+또는+비밀번호가+잘못되었습니다.` |

실패 쪽 `result` 쿼리는 **이미 사용자용 한국어다** — 앱이 문구를 새로 짓지 않고 퍼센트 디코딩해 그대로 띄운다(배차표 `errorMessage`와 같은 규칙).

판정 규칙은 하나로 족하다: **`Location`의 경로가 `/nxpmsc/login`으로 시작하면 실패다.**

### 2. 잔여시간 — `GET /nxpmsc/book-car` (HTML)

JSON API가 없다. 페이지에 박힌 히든 필드를 긁는다.

```html
<input type="hidden" id="reservedVehiclePointValue" value="6000"/>
```

**단위는 분이다.** 6000분 = 100시간 0분이고, 같은 페이지 내비게이션에 `100시 0분 남음`으로 찍힌다. **그 텍스트가 아니라 이 숫자를 읽는다** — 문구는 현장마다 갈리지만 이 필드는 값 하나다.

음수가 올 수 있다. 웹은 음수면 「N분 초과 사용하였습니다」 모달을 띄운다(`book-car-original.js`의 `openModal`). 앱도 초과분을 그렇게 표시한다.

### 3. 세대 정보(동·호) — `POST /nxpmsc/book-car/getOriginal` (HTML)

`id=`(빈 값)으로 부르면 **신규 등록 모달의 HTML**이 온다. 등록에 되돌려 보내야 하는 값들이 여기 들어 있다.

```html
<input name="compName" value="1001" readonly/>   <!-- 동 -->
<input name="deptName" value="0101" readonly/>   <!-- 호 -->
<select name="parkingLot">  <option value="1" selected>○○아파트</option>
<select name="parkingZone"> <option value="1" selected>기본 구역</option>
```

`id`에 값을 주면 **그 예약의 수정 모달**이 온다. 수정 화면은 목록이 이미 들고 있는 값으로 채우므로 앱은 이 경로를 신규(동·호 조회) 용도로만 쓴다.

### 4. 등록 내역 — `POST /nxpmsc/web/book-car/pageList` (JSON)

```json
{ "page": 0, "size": 10, "sort": "desc", "sortName": "startDate",
  "userId": "10010101",
  "startDate": "2026-07-01", "endDate": "2026-09-30",
  "carNo1": "", "insertType": "", "visitReason": "", "otherInfo": "" }
```

응답 — `data`가 스프링 `Page`다.

```json
{"data":{"content":[{"id":25752,"compName":"1001","deptName":"0101","name":"",
  "carNo":"12가3456","tel":"","startDate":1784300400,"endDate":1784386799,
  "updateDate":1784356046,"userName":"10010101","insertType":"W","address":""}],
  "totalElements":1,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
```

- **날짜는 전부 유닉스 초다.** 밀리초가 아니다.
- `startDate`는 그날 `00:00:00`, `endDate`는 `23:59:59`로 온다. 웹은 그 시각일 때 시간을 감추고 날짜만 그린다 — 앱도 같게 한다.
- `address`가 **방문사유**다. 이름이 어긋나 있으니 모델에서 `visitReason`으로 바꿔 받는다.
- `insertType`: `K` 키오스크 · `W` 사전방문 · `L` 방문 · `B` 예약차량 · `N` 방문차량(승인). 앱이 등록하면 `W`가 된다.

### 5. 진입 현황 — `POST /nxpmsc/web/car/reserved-vehicle-entry-status-by-generation-page` (JSON)

```json
{ "page": 0, "size": 10, "sort": "desc", "sortName": "updateDate",
  "userId": "10010101", "parkingZoneIdCode": "", "carNo": "",
  "startDate": "2026-07-01 00:00:00", "endDate": "2026-08-26 23:59:59" }
```

**날짜 형식이 4번과 다르다.** 여기는 `yyyy-MM-dd HH:mm:ss`여야 하고, 날짜만 보내면 **500**이 떨어진다(메시지 없는 스프링 기본 오류 본문). 두 화면이 같은 포맷터를 쓰면 한쪽이 죽는다 — 포맷터를 엔드포인트별로 나눠 둔다.

```json
{"message":"200","data":{"content":[{"id":354751,"inDate":1784357197,
  "outDate":1784374505,"outChk":2,"carNo":"12가3456","name":"",
  "startDate":1784300400,"endDate":1784386799,"updateDate":1784356046}], "…": "…"}}
```

- `outDate`는 **아직 안 나갔으면 `null`이다.** 주차시간은 `outDate ?? 지금 - inDate`로 센다.
- `outChk`: `0` 입차 · `1` 출차대기 · `2` 출차 · `3` 강제출차 · `4` 미확인출차 · `5` 장애출차. 그 밖의 값은 빈 문자열로 둔다(웹의 `default` 분기와 같게).
- 응답에 `message: "200"`이 붙는데 4번에는 없다. **읽지 않는다** — 두 엔드포인트를 같은 디코더로 다루기 위해서다.

### 6. 등록 — `POST /nxpmsc/book-car/post` (form-urlencoded)

| 필드 | 값 | 비고 |
|---|---|---|
| `id` | 빈 값 | 신규 |
| `siteName` | `none` | 페이지 히든값 그대로 |
| `selectParkingZone` | `true` | 〃 |
| `parkingLot` / `parkingZone` | `1` / `1` | 3번에서 읽어 둔 값 |
| `carNo` | 차량번호 | **필수** |
| `bookStartDate` / `bookEndDate` | `yyyy-MM-dd` | **필수** |
| `compName` / `deptName` | `1001` / `0101` | 3번에서 읽어 둔 값 |
| `name`, `tel`, `address` | 빈 값 허용 | |

응답: `{"result":"success","message":"성공적으로 등록되었습니다."}` — `result`가 `success`가 아니면 `message`를 그대로 띄운다.

**`tel`은 빈 값으로 통과한다 — 실제로 등록해 확인했다(만든 예약은 곧바로 삭제했다).** 웹 폼의 JS는 휴대폰을 필수로 막지만 서버는 아니다. 폼 HTML에 `필수입력항목에서 휴대폰 제거 - bae (20201223)`라는 주석이 남아 있는 것이 방증이다. **화면에서 휴대폰 칸을 뺀다.**

차량번호 검증은 웹 JS(`book-car2.js`)를 그대로 옮긴다 — 공백 불가, `` `~!@#$%^&*|\'";:/?`` 불가, 9자 이하. 서버가 뭘 막는지는 확인하지 않았으므로 **앱이 먼저 막는다.**

### 7. 수정 — `POST /nxpmsc/book-car/put`, 삭제 — `POST /nxpmsc/book-car/delete`

수정은 6번과 같은 바디에 `id`를 채운다. 삭제는 `id` 하나. 삭제 응답은 `{"result":"success","message":"삭제 되었습니다."}` — 확인했다. **수정은 호출해 보지 않았다**(실제 데이터를 건드리게 된다). 구현 때 한 건으로 확인하고, 어긋나면 이 문서를 고친다.

웹 화면에 `※ 입차 후 수정/삭제 불가능 합니다`라고 적혀 있다. **앱이 그 조건을 판정하지 않는다** — 입차 여부는 다른 엔드포인트의 일이고, 앱이 흉내 내면 서버 규칙과 갈라진다. 그냥 보내고 거절당하면 `message`를 띄운다.

### 8. 세션 만료

쿠키 없이 어느 경로를 두드려도 **302 → `/nxpmsc/login`**이다. JSON 엔드포인트도 마찬가지다 — 401이 아니다.

**이것이 이 설계에서 가장 조용히 틀릴 수 있는 자리다.** `URLSession`은 기본으로 리다이렉트를 따라가므로, 그대로 두면 로그인 **HTML 페이지가 200으로** 돌아온다. JSON 디코딩이 실패하면서 「데이터 파싱 오류」로 보이고, 진짜 원인(세션 만료)은 어디에도 안 남는다.

그래서 **리다이렉트를 따라가지 않는다.**

---

## 아키텍처

기존 `APIClient`(우리 서버, HTTPS, JSON REST, 액세스 토큰)와 **한 줄도 섞지 않는다.** 성질이 다르다 — 여기는 HTTP, 세션 쿠키, form 인코딩, HTML 응답이다. `APIClientProtocol`을 넓혀 이걸 태우려는 시도는 두 쪽 모두를 망친다.

```
VisitorCarView (화면)
   └ VisitorCar*ViewModel
        └ VisitorCarServing          ← 프로토콜. 테스트가 여기를 가짜로 바꾼다
             └ VisitorCarService
                  ├ VisitorCarClient      HTTP·쿠키·302·재로그인
                  ├ VisitorCarHTMLParser  잔여시간·동/호 추출
                  └ VisitorCarCredentialStore  Keychain
```

### `VisitorCarClient` — 저수준

전용 `URLSession`을 하나 만든다. **쿠키 저장소를 앱 공용(`HTTPCookieStorage.shared`)과 나눈다** — `SessionManager`가 공용 저장소를 쓰고 있어서, 남의 사이트 `JSESSIONID`를 거기 섞으면 두 세션의 수명이 서로 얽힌다.

리다이렉트를 막는다. `URLSessionTaskDelegate`의 `willPerformHTTPRedirection`에서 `nil`을 돌려주면 302가 응답 그대로 손에 들어온다.

요청은 세 가지 모양뿐이다.

- `form(path:fields:)` → `(status, Data, Location?)`
- `json(path:body:)` → `Data`
- `html(path:fields:)` → `String`

셋 모두 **응답이 302이고 `Location`이 `/nxpmsc/login`이면** `VisitorCarError.sessionExpired`를 던진다. 그 위에서 서비스가 **딱 한 번** 재로그인하고 원 요청을 다시 태운다. 두 번은 하지 않는다 — 자격증명이 틀렸는데 무한히 되풀이하면 계정이 잠길 수 있다.

재로그인은 **직렬화한다.** 화면 넷이 동시에 뜨면 만료를 동시에 만나 로그인을 넷 던진다. `actor`로 감싸 진행 중인 로그인 `Task`를 공유한다 — `SessionManager.refreshToken`이 이미 같은 방식이다.

### `VisitorCarHTMLParser` — 파싱

**여기가 이 기능에서 가장 부서지기 쉬운 자리다.** 사이트가 마크업을 바꾸면 죽는다. 그래서 서비스에서 떼어내 순수 함수로 두고, 저장해 둔 실제 HTML 조각으로 테스트를 건다.

- `remainingMinutes(html:) -> Int?` — `id="reservedVehiclePointValue"`의 `value`
- `household(html:) -> VisitorCarHousehold?` — `compName`·`deptName`·`parkingLot`·`parkingZone`

`NSRegularExpression`으로 충분하다. HTML 파서를 의존성으로 들이지 않는다 — 찾는 게 히든 인풋 넷뿐이다.

**둘 다 옵셔널을 돌려준다.** 못 찾으면 크래시가 아니라 「잔여시간을 불러오지 못했습니다」다. 다만 **동·호를 못 읽으면 등록을 막는다** — 빈 동·호로 등록하면 다른 세대 이름으로 예약이 들어갈 수 있다.

### `VisitorCarCredentialStore` — Keychain

`kSecClassGenericPassword`, 서비스 `com.woori.haru.visitorcar`, 계정은 로그인 아이디. 저장·읽기·삭제 셋이면 된다. 저장소에 Keychain을 쓰는 코드가 아직 없으므로 **이 타입이 첫 사례다** — 좁게 만든다.

**비밀번호는 로그에 절대 남기지 않는다.** `Logger`에 요청 바디를 통째로 찍는 코드를 두지 않는다.

### 세대 정보 캐시

동·호는 계정이 바뀌지 않는 한 그대로다. **첫 등록 때 한 번 읽고 `UserDefaults`에 담아 둔다.** 매번 `getOriginal`을 부르면 등록 한 번에 왕복이 둘이 된다. 로그아웃하면 지운다.

### `FrequentCarStore` — 자주 쓰는 차량

`{ id, nickname, carNo }`의 배열을 `UserDefaults`에 JSON으로. **서버로 보내지 않는다** — 참고 앱의 안내 문구와 같다: 이 기기에만 저장되고, 앱을 지우면 사라진다. 화면에도 그 문구를 띄운다.

---

## 데이터

### `VisitorCarBooking` — 등록 내역 한 건

| 필드 | 타입 | 원본 |
|---|---|---|
| `id` | `Int` | `id` |
| `carNo` | `String` | `carNo` |
| `name`, `tel` | `String` | 빈 문자열로 옴 |
| `dong`, `ho` | `String` | `compName`, `deptName` |
| `startDate`, `endDate` | `Date` | 유닉스 초 |
| `updateDate` | `Date?` | 유닉스 초. `null` 가능 |
| `registrant` | `String` | `userName` |
| `insertType` | `VisitorCarInsertType` | `K/W/L/B/N` |
| `visitReason` | `String` | **`address`** |

### `VisitorCarEntry` — 진입 현황 한 건

| 필드 | 타입 | 비고 |
|---|---|---|
| `id` | `Int` | |
| `inDate` | `Date` | 입차 |
| `outDate` | `Date?` | **`null`이면 아직 안 나갔다** |
| `status` | `VisitorCarEntryStatus` | `outChk` 0~5 |
| `carNo`, `name` | `String` | |
| `startDate`, `endDate`, `updateDate` | `Date` | |

주차시간은 저장하지 않고 그릴 때 센다. `parkingTime` 필드가 응답에 있지만 웹도 쓰지 않는다(`orderable: false`에 렌더러가 직접 계산한다).

### `VisitorCarPage<T>`

`{ content: [T], totalElements: Int, totalPages: Int, number: Int, last: Bool }`. 두 목록이 같은 껍데기를 쓴다.

---

## 화면

전부 `VehicleTheme` 다크 + 글래스 카드. 관리비 미니앱과 같은 껍데기다.

### 홈 — `VisitorCarView`

드로어에서 `방문차량`으로 들어오는 자리. 카드를 세로로 쌓는다.

1. **충전 잔여 시간** — `100시간 0분 남음`, 오른쪽에 새로고침. 음수면 `N분 초과 사용`으로 붉게.
2. **신규 차량 등록** →
3. **등록 내역 조회** →
4. **차량 진입 현황** →

툴바 오른쪽 톱니 → 설정.

자격증명이 없으면 카드 대신 **로그인 카드**를 띄운다. 아이디·비밀번호를 받아 4번 규칙으로 판정하고, 성공하면 Keychain에 넣고 홈을 다시 그린다.

### 신규 차량 등록 — `VisitorCarRegisterView`

- **차량 정보**: 차량번호 한 칸 + `자주 쓰는 차량 선택`(저장된 게 없으면 감춘다).
- **방문 기간**: 시작일·종료일. 기본값은 둘 다 오늘. **종료일이 시작일보다 앞서면 등록 버튼을 잠근다.**
- 방문사유는 넣는다(20자). 웹 폼에 있고 관리사무소가 보는 값이다. 비워도 된다.
- 휴대폰은 **넣지 않는다**(위 6번 참고).

등록에 성공하면 뒤로 물러나며 홈의 잔여시간을 다시 읽는다.

### 등록 내역 조회 — `VisitorCarBookingsView`

조회 조건(시작일·종료일) 카드 + 결과 목록. 기본 범위는 **오늘부터 한 달 뒤까지** — 참고 앱과 같다. 결과가 없으면 「등록 내역이 없습니다」.

행을 누르면 상세 시트: 차량번호·기간·등록구분·방문사유·등록자. 여기서 **수정**과 **삭제**. 삭제는 확인 알림을 한 번 받는다.

페이징은 `size: 10`으로 두고 **더 보기** 버튼으로 잇는다. 무한 스크롤은 만들지 않는다 — 세대 하나가 쌓는 건수가 그만큼 되지 않는다.

### 차량 진입 현황 — `VisitorCarEntriesView`

같은 조건 카드(기본 오늘 00:00:00 ~ 23:59:59) + 목록. 한 줄에 차량번호·상태 배지·입차시각·주차시간. **아직 안 나간 차는 주차시간이 계속 흐른다** — 화면이 떠 있는 동안 1분마다 다시 그린다.

### 설정 — `VisitorCarSettingsView`

- **자주 쓰는 차량 관리** → 별칭·차량번호로 추가, 목록에서 삭제. 「이 기기에만 저장됩니다」 안내.
- **로그아웃** — Keychain·쿠키·세대 캐시를 모두 지운다.

---

## 오류 처리

`VisitorCarError`로 모은다.

| 경우 | 화면에 뜨는 것 |
|---|---|
| `Location`이 `/nxpmsc/login` (로그인 시도 중) | `result` 쿼리의 서버 메시지 그대로 |
| 세션 만료 후 재로그인도 실패 | 「다시 로그인해 주세요」 + 로그인 카드로 되돌림 |
| `result != "success"` | `message` 그대로 |
| HTML 파싱 실패 | 「잔여시간을 불러오지 못했습니다」 / 등록은 막고 「세대 정보를 불러오지 못했습니다」 |
| 5xx·네트워크 | 「서버에 연결하지 못했습니다」 + 다시 시도 |

**서버가 준 한국어는 다시 쓰지 않는다.** 이 저장소가 배차표·관리비에서 이미 지키는 규칙이다.

---

## 앱 설정 변경

`Info.plist`에 ATS 예외를 넣는다. **사이트가 `http`라 예외 없이는 연결 자체가 안 된다.**

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>dasanesesang.iptime.org</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
      <key>NSIncludesSubdomains</key><true/>
    </dict>
  </dict>
</dict>
```

**`NSAllowsArbitraryLoads`는 쓰지 않는다.** 우리 서버는 HTTPS이고, 전역으로 열면 그쪽 보호까지 같이 내려간다. 심사에서도 도메인 한정이 설명하기 쉽다.

비밀번호가 평문으로 나가는 것은 사이트가 HTTP인 이상 피할 수 없다. **다만 노출 빈도는 브라우저보다 늘어난다.** 쿠키 저장소를 `.ephemeral`로 고른 것(남의 사이트 세션과 우리 앱 세션을 섞지 않으려는 옳은 결정이다)과 자동 재로그인이 합쳐지면, 앱을 껐다 켤 때마다 쿠키가 사라져 평문 HTTP로 비밀번호가 한 번씩 더 나간다. 브라우저는 세션 쿠키를 재시작 너머로 유지해 로그인이 훨씬 드물다. 설계를 바꾸지는 않는다 — 쿠키 격리가 노출 빈도보다 중요하다 — 다만 거래 조건은 정직하게 적어 둔다. 저장은 Keychain의 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`라 기기 안에서는 오히려 낫고, 암호화 백업을 타고 새 기기로 옮겨 가지도 않는다.

## 연결 지점

- `AppDestination`에 `case visitorCar` 하나. `ContentView`의 `switch`에 한 줄.
- `SideDrawerView`의 `drawerItem` 목록에 「방문차량」을 **「관리비」 아래**에 둔다 — 둘 다 아파트 일이다. 아이콘은 `parkingsign`.

## 테스트

`WooriHaruTests`에 저장소 관례대로.

- **`VisitorCarHTMLParserTests`** — 실제 응답에서 잘라 온 HTML 조각으로 잔여시간·동/호 추출. 필드가 없는 조각에서 `nil`이 나오는 것까지.
- **`VisitorCarDecodingTests`** — 위에 적어 둔 실제 JSON 두 벌을 그대로 디코딩. `outDate: null`, `updateDate: null`, 유닉스 초 → `Date` 변환.
- **`VisitorCarRequestTests`** — 등록 폼 바디에 필드 열셋이 다 실리는가, 날짜 포맷이 엔드포인트별로 갈리는가(`yyyy-MM-dd` vs `yyyy-MM-dd HH:mm:ss`).
- **`VisitorCarSessionTests`** — 가짜 클라이언트로 302→로그인→재시도가 **한 번만** 일어나는지, 재로그인 실패가 `sessionExpired`로 올라오는지, 동시 요청 넷이 로그인을 하나만 던지는지.
- **`VisitorCarValidationTests`** — 차량번호 규칙(공백·특수문자·9자), 기간 역전.
- **`VisitorCarEntryTests`** — 주차시간 계산(`outDate` 있음/없음), `outChk` 0~5와 범위 밖 값.

**네트워크를 타는 테스트는 만들지 않는다.** 남의 서버에 붙는 테스트는 CI에서 죽고, 죽으면 지워진다.

## 확인하지 않은 것

구현 때 실제로 확인하고, 어긋나면 이 문서를 고친다.

- **수정(`/book-car/put`)의 요청·응답.** 등록과 같은 바디일 것으로 보지만 호출해 보지 않았다.
- **입차 후 수정/삭제를 서버가 어떻게 거절하는지.** `result != success`일 것으로 보지만 확인하지 않았다.
- **잔여시간이 언제 깎이는지.** 등록 시점인지 출차 정산 시점인지. 화면 표시에는 영향이 없다.
- **페이징 2쪽 이상.** 현재 계정에 내역이 한 건뿐이라 `page: 1`을 확인할 데이터가 없다.
