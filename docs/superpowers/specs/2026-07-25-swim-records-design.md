# 수영 기록 목록 (읽기 전용) 설계

작성일: 2026-07-25

## 배경

애플워치 운동 앱으로 기록한 수영은 아이폰 건강(Health) 앱에 동기화된다.
HealthKit 읽기 권한만 받으면 watchOS 앱 없이 iPhone 앱에서 전체 이력을 조회할 수 있다.
HealthKit 읽기 권한에는 기간 제한이 없어, 앱 설치 이전 기록도 그대로 읽힌다.

## 범위

읽기 전용 조회 화면 하나. 서버 저장·페어 공유·DailyRecord 연동은 이번 범위에서 제외한다.

## 구조

| 구성 | 파일 | 역할 |
| --- | --- | --- |
| Model | `Models/SwimWorkout.swift` | HealthKit 타입과 분리된 순수 struct + 표시용 포맷 프로퍼티 |
| Model | `Models/SwimLap.swift` | 랩·영법 타입과 영법별 거리 집계 |
| Model | `Models/SwimSet.swift` | 휴식 기준 세트 판정 |
| Service | `Services/HealthKitService.swift` | `SwimWorkoutFetching` 프로토콜 + `HKHealthStore` 구현 |
| ViewModel | `ViewModels/SwimRecordViewModel.swift` | 로딩/에러/빈 상태, 합계 요약 |
| View | `Views/Swim/SwimRecordListView.swift` | 목록 + 빈 상태·실패 안내 |
| View | `Views/Swim/SwimWorkoutDetailView.swift` | 기록 1건 상세 — 요약·운동 강도·영법별 거리·자동 세트 |

기존 파일 수정:

- `ContentView.swift` — `AppDestination.swimRecords` 추가 및 `navigationDestination` 분기
- `Views/Components/SideDrawerView.swift` — 드로어 상단 메뉴에 "수영 기록" 항목 (통계 아래)

권한 배선:

- `WooriHaru/WooriHaru.entitlements` 신규 — `com.apple.developer.healthkit`
- `Info.plist` — `NSHealthShareUsageDescription` (읽기 전용이라 `NSHealthUpdateUsageDescription`은 두지 않는다)
- `project.pbxproj` — `CODE_SIGN_ENTITLEMENTS`를 앱 타겟 Debug/Release에 지정

## 데이터 흐름

1. 화면 진입 시 `vm.load()` → `requestAuthorization()` (읽기 타입만)
2. `HKSampleQuery`로 `.swimming` 워크아웃 조회. 시작일 내림차순, 한 번에 30건씩
3. `HKWorkout` → `SwimWorkout` 매핑. 거리·칼로리·스트로크는 `statistics(for:)`로 합계를 읽는다
   (iOS 18에서 `totalDistance`·`totalEnergyBurned`가 deprecated)
4. 수영장/개방 수역과 레인 길이는 워크아웃 metadata에서 읽는다
5. 목록에서 기록을 탭하면 `navigationDestination(for: SwimWorkout.self)`로 상세 화면을 띄운다

## 구간(split) 기록

애플워치 수영장 기록은 턴할 때마다 `HKWorkoutEvent`(type `.lap`)를 남긴다. 각 랩의 거리는
워크아웃 metadata의 레인 길이를 쓰고, 영법은 랩 이벤트 metadata의 stroke style에서 읽는다.

상세 화면은 이 랩들을 50m·100m 단위로 묶어 구간 기록(누적 거리 / 소요 시간 / 100m 환산 페이스 /
영법)을 보여준다. 규칙:

- 랩을 누적하다 단위 거리에 도달하는 순간 구간을 끊는다
- 단위에 못 미치고 남은 마지막 구간도 버리지 않고 실제 거리로 표시한다
- 구간 안에서 영법이 섞이면 혼영으로 본다
- 랩 이벤트가 길이 0인 마커로 오면 랩을 아예 만들지 않는다. 마커만으로는 헤엄친 시간과
  벽에서 쉰 시간을 나눌 수 없고, 다음 마커까지를 소요 시간으로 메우면 랩 사이 공백이 전부
  0이 되어 세트가 하나로 뭉개진다. 틀린 기록을 보여주느니 세트를 접는다

레인 길이를 모르면 거리를 나눌 수 없고 개방 수역은 랩 자체가 없다. 두 경우 모두 구간 없이
안내 문구만 띄운다.

## 자동 세트

실제 기록(2026-07-25, 50m 레인 40랩 2000m)을 진단해 보니 랩 사이 공백이 두 종류로 뚜렷하게
갈렸다. 벽 찍고 턴하는 공백은 1~7초, 세트 사이 휴식은 1분 이상이었다. 이 공백을 20초 기준으로
끊으면 피트니스 앱의 자동 세트가 그대로 재현된다 — 휴식 다섯 개가 초 단위로 일치했다.

세트 시간은 **첫 랩 시작부터 마지막 랩 종료까지**로 잰다. 벽에서 턴한 시간이 포함되므로
"실제 100m 기록"에 해당한다.

거리 단위로 자르는 구간(split) 표시도 만들어 봤으나, 세트만으로 충분하다고 판단해 걷어냈다.
랩 소요 시간의 합(턴 제외)은 순수 추진 속도를 보여주지만, 구간 경계 안쪽에 휴식이 들어가면
그 휴식이 수영 시간으로 잡혀 속도를 왜곡하는 문제가 있었다.

피트니스는 **첫 세트만 운동 시작(0:00)부터** 잰다. 실측에서 첫 랩은 +0:44에 시작했고, 그
44초(물에 들어가기까지의 시간)가 첫 세트 수영 시간에 들어가 페이스가 2:43/100m로 왜곡됐다.
우리는 첫 랩 시작부터 재므로 첫 세트만 피트니스보다 짧게 나오며, 이쪽이 정확하다.
나머지 세트는 피트니스와 사실상 동일하다.

## 상태 처리

HealthKit은 프라이버시 정책상 **읽기 권한 거부 여부를 앱에 알려주지 않는다.** 거부와 데이터 없음이
모두 "0건"으로 들어오므로 두 경우를 하나의 빈 상태로 묶고, 안내 문구에서 동기화 여부와 권한 설정을
함께 짚어 준다. 설정 앱으로 가는 버튼을 함께 둔다.

`isHealthDataAvailable`이 false인 기기(일부 iPad 등)는 별도 문구로 구분한다. 이때 서비스가
던지는 `healthDataUnavailable`은 실패로 두지 않는다. 실패로 두면 "다시 시도" 안내가 뜨는데,
재시도해도 달라지지 않는 조건이라 그 전용 문구에 영영 닿지 못한다.

## 테스트

`WooriHaruTests/SwimRecordTests.swift` — `FakeSwimFetcher`로 서비스를 대체한다.

- 모델 포맷: 거리 km/m 분기, 값 없음·0 처리, 운동 시간, 연도 표기, 장소+레인 길이 합성
- 영법별 집계: 거리순 정렬, 100m 환산 페이스
- 자동 세트: 실제 워치 기록 12랩을 그대로 넣어 피트니스 표시와 대조하는 회귀 테스트.
  세트 구분(200/100/100/100/50/50m)과 휴식 시간이 어긋나면 실패한다
- ViewModel: 로딩 성공 시 목록·합계, 빈 상태 진입 조건(로딩 전에는 뜨지 않을 것), 실패 시 에러 메시지

랩 파싱(`HKWorkoutEvent` → `SwimLap`)은 실제 워치 데이터가 있어야 검증되므로 자동화하지 않았다.
구간 묶기 로직만 페이크 랩으로 테스트한다.

HealthKit 자체 동작은 시뮬레이터에 건강 데이터가 없어 자동화하지 않는다. 실기기 수동 확인 대상.

## 알려진 제약

- 시뮬레이터에서는 목록이 비어 보인다. 실제 확인은 실기기에서만 가능
- Apple Developer 계정의 App ID에 HealthKit capability가 필요하다. 자동 서명이 처리하지만
  첫 실기기 빌드에서 프로비저닝 갱신을 요구할 수 있다
- `HKAnchoredObjectQuery` 증분 갱신은 필요해지면 추가한다 (YAGNI)

## 페이징

기간 상한이 없으므로 전체 이력이 대상이다. 한 번에 다 읽지 않고 30건씩 이어 붙인다.

커서는 **직전 페이지 마지막 기록의 시작 시각**이고, 경계를 **포함**한다
(`HKPredicateKeyPathStartDate <= 커서`). 경계를 배제하면 시작 시각이 같은 기록이 페이지
경계에 걸렸을 때 뒤쪽 기록이 통째로 빠진다.

경계를 포함하면 이미 읽은 동점 기록이 다시 딸려 오므로 UUID로 거른다. 다만 거르기만 하면
동점 기록이 한 페이지를 다 채울 때 새 기록을 하나도 못 얻어 같은 페이지를 무한히 반복할 수
있다. 그래서 **이미 읽은 동점 기록 수만큼 limit을 키운다.** 그러면 조회가 limit을 채우는 한
새 기록을 최소 pageSize개 확보하므로 반드시 앞으로 나아간다.

한 페이지가 요청한 개수를 못 채우면 끝으로 보고 더 요청하지 않는다. 조회에 실패한 경우도
같게 처리해 실패를 무한히 재시도하지 않는다.

화면 진입은 `loadIfNeeded()`로 **최초 한 번만** 읽는다. `.task`는 화면이 다시 나타날 때마다
실행되므로, 상세에서 돌아올 때 `load()`를 부르면 목록이 첫 페이지로 줄어들어 스크롤 위치가
콘텐츠 밖을 가리키고 빈 화면이 보인다. 다시 읽는 것은 당겨서 새로고침으로만 한다.

새로고침이 페이지 로딩 중에 끼어들 수 있으므로 세대(generation) 번호로 진행 중인 조회를
무효화한다. 뒤늦게 돌아온 이전 결과는 토큰이 어긋나 버려진다.

조회 실패는 `loadFailed`로 따로 들고 있는다. 에러 알림을 닫으면 `errorMessage`가 지워지는데,
이걸 빈 상태 판정에 쓰면 실패가 "기록 없음"으로 잘못 보인다.

목록 상단에 합계 요약은 두지 않는다. 페이징에서는 스크롤할수록 숫자가 커져 무엇의 합인지
알 수 없고, 각 행에 이미 거리와 시간이 있어 정보가 겹친다. 기간이 고정된 통계가 필요해지면
그때 별도로 만든다.
