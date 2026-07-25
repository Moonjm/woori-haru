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
| Service | `Services/HealthKitService.swift` | `SwimWorkoutFetching` 프로토콜 + `HKHealthStore` 구현 |
| ViewModel | `ViewModels/SwimRecordViewModel.swift` | 로딩/에러/빈 상태, 합계 요약 |
| View | `Views/Swim/SwimRecordListView.swift` | 요약 카드 + 목록 + 빈 상태 안내 |

기존 파일 수정:

- `ContentView.swift` — `AppDestination.swimRecords` 추가 및 `navigationDestination` 분기
- `Views/Components/SideDrawerView.swift` — 드로어 상단 메뉴에 "수영 기록" 항목 (통계 아래)

권한 배선:

- `WooriHaru/WooriHaru.entitlements` 신규 — `com.apple.developer.healthkit`
- `Info.plist` — `NSHealthShareUsageDescription` (읽기 전용이라 `NSHealthUpdateUsageDescription`은 두지 않는다)
- `project.pbxproj` — `CODE_SIGN_ENTITLEMENTS`를 앱 타겟 Debug/Release에 지정

## 데이터 흐름

1. 화면 진입 시 `vm.load()` → `requestAuthorization()` (읽기 타입만)
2. `HKSampleQuery`로 `.swimming` 워크아웃 조회. predicate에 기간을 두지 않아 전 기간 대상, 시작일 내림차순, 최대 100건
3. `HKWorkout` → `SwimWorkout` 매핑. 거리·칼로리·스트로크는 `statistics(for:)`로 합계를 읽는다
   (iOS 18에서 `totalDistance`·`totalEnergyBurned`가 deprecated)
4. 수영장/개방 수역과 레인 길이는 워크아웃 metadata에서 읽는다

## 상태 처리

HealthKit은 프라이버시 정책상 **읽기 권한 거부 여부를 앱에 알려주지 않는다.** 거부와 데이터 없음이
모두 "0건"으로 들어오므로 두 경우를 하나의 빈 상태로 묶고, 안내 문구에서 동기화 여부와 권한 설정을
함께 짚어 준다. 설정 앱으로 가는 버튼을 함께 둔다.

`isHealthDataAvailable`이 false인 기기(일부 iPad 등)는 별도 문구로 구분한다.

## 테스트

`WooriHaruTests/SwimRecordTests.swift` — `FakeSwimFetcher`로 서비스를 대체한다.

- 모델 포맷: 거리 km/m 분기, 값 없음·0 처리, 운동 시간, 장소+레인 길이 합성
- ViewModel: 로딩 성공 시 목록·합계, 빈 상태 진입 조건(로딩 전에는 뜨지 않을 것), 실패 시 에러 메시지

HealthKit 자체 동작은 시뮬레이터에 건강 데이터가 없어 자동화하지 않는다. 실기기 수동 확인 대상.

## 알려진 제약

- 시뮬레이터에서는 목록이 비어 보인다. 실제 확인은 실기기에서만 가능
- Apple Developer 계정의 App ID에 HealthKit capability가 필요하다. 자동 서명이 처리하지만
  첫 실기기 빌드에서 프로비저닝 갱신을 요구할 수 있다
- 100건 상한. 페이징과 `HKAnchoredObjectQuery` 증분 갱신은 필요해지면 추가한다 (YAGNI)
