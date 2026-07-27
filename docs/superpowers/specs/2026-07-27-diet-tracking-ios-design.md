# 식단 사진 기록·점수·피드백 (iOS) 설계

작성일: 2026-07-27
짝 문서: `toy-back/docs/superpowers/specs/2026-07-27-diet-tracking-backend-design.md`

## 배경

식사 사진을 올리면 서버가 음식을 인식해 탄단지를 산출하고, 개인 목표 대비 점수와 개선
피드백을 돌려준다. 앱은 **사진 업로드와 결과 표시만** 담당한다. 인식(OpenRouter)·식품DB
매칭·점수 계산·피드백 생성은 전부 백엔드 책임이다.

앱에 LLM API 키를 두지 않으므로 키 노출 위험이 없고, 프롬프트·식품DB·점수 공식을 앱 심사
없이 개선할 수 있다.

## 범위

**기존 화면과 완전히 독립적이다.** 사이드 드로어에 「식단」 메뉴를 추가하고, 그 안에서
업로드·조회·수정·피드백이 자기완결적으로 끝난다.

`CalendarView`·`DayCellView`·`DailyRecord`·`DailyOvereat`는 **건드리지 않는다.** 캘린더에 식단
점수 배지를 얹거나 과식 수준과 나란히 보여주는 연동은 이번 범위에서 제외한다. 배우자 공유도
제외한다 — 본인 기록만 본인이 본다.

## 구조

| 구성 | 파일 | 역할 |
| --- | --- | --- |
| Model | `Models/Diet.swift` | `Meal`·`MealItem`·`MealType`·`AnalysisStatus`·`NutritionSource`·`DailyDiet` + Request 타입 |
| Model | `Models/NutritionProfile.swift` | 프로필·목표치, `ActivityLevel`·`DietGoal` |
| Service | `Services/DietService.swift` | `DietServing` 프로토콜 + API 구현 (사진 업로드 포함) |
| Service | `Services/HealthKitService.swift` (수정) | `ActiveEnergyFetching` 채택 — 하루 활동 에너지 조회 |
| Service | `Services/APIClient.swift` (수정) | multipart 업로드 메서드 1개 추가 |
| Extension | `Extensions/UIImage+Extensions.swift` | 업로드 전 다운샘플 |
| ViewModel | `ViewModels/DietDayViewModel.swift` | 날짜별 하루 요약·끼니 목록·업로드·분석 폴링 |
| ViewModel | `ViewModels/NutritionProfileViewModel.swift` | 프로필 입력·저장 |
| ViewModel | `ViewModels/MealDetailViewModel.swift` | 항목 수정·삭제·재분석 |
| View | `Views/Diet/DietHomeView.swift` | 진입점 — 날짜 스트립 + 하루 요약 + 끼니 목록 |
| View | `Views/Diet/MealCaptureSheet.swift` | 사진 선택 → 끼니 종류 → 업로드 → 분석 중 |
| View | `Views/Diet/MealDetailView.swift` | 사진·항목·점수·피드백 |
| View | `Views/Diet/MealItemEditView.swift` | 식품 검색으로 항목 교체·추가 |
| View | `Views/Diet/NutritionProfileView.swift` | 키·몸무게·활동량·목표 입력 |
| View | `Views/Diet/Components/DietScoreRing.swift` | 점수 링 |
| View | `Views/Diet/Components/MacroBar.swift` | 목표 대비 탄단지 막대 |

기존 파일 수정:

- `ContentView.swift` — `AppDestination.diet` 추가 및 `navigationDestination` 분기
- `Views/Components/SideDrawerView.swift` — 드로어 메뉴에 「식단」 항목

ViewModel은 기존 관례대로 `@MainActor @Observable final class`이고, 서비스는 프로토콜로
주입한다(`SwimWorkoutFetching` 패턴). UI는 `Views/Components/Glass`의 기존 컴포넌트를 쓴다.

## 데이터 흐름

### 사진 업로드

```
1. PhotosPicker/카메라로 이미지 획득
2. UIImage.downsampled(maxDimension: 1024, quality: 0.8) → Data
3. POST /files (multipart)         → fileId
4. POST /diet/meals {date, mealType, fileId} → mealId (201 + Location)
5. GET /diet/meals/{mealId} 폴링   → status COMPLETED / FAILED
```

**다운샘플이 3번 앞에 오는 게 중요하다.** `PhotosPicker` 원본은 12MP·수 MB급이라 그대로
올리면 업로드가 느리고, 서버가 큰 이미지를 그대로 LLM에 넘겨 토큰 비용이 몇 배로 뛴다.
장변 1024px에서 음식 인식 정확도 손실은 사실상 없다.

리사이즈를 앱에서 하는 이유는 서버가 라즈베리파이라 이미지 재인코딩이 낭비이기 때문이다.

### 분석 폴링

`status == PENDING`인 동안 **2초 간격, 최대 60초** 폴링한다.

타임아웃하면 실패로 단정하지 않는다 — 서버는 계속 처리 중일 수 있으므로 "분석이 지연되고
있어요, 잠시 후 새로고침해 주세요"로 안내한다. `status == FAILED`로 확인된 경우에만 재시도
버튼(`POST /diet/meals/{id}/retry`)을 보여준다.

`SwimRecordViewModel`의 `generation` 카운터 패턴을 가져와, 사용자가 날짜를 바꾸거나 화면을
벗어난 뒤 늦게 도착한 응답을 버린다. `APIClient`가 `URLError.cancelled`를 `CancellationError`로
변환해 주므로 Task 취소는 그대로 전파된다.

### 활동 에너지

`DietHomeView` 진입 시 HealthKit에서 그날의 `activeEnergyBurned` 합계를 읽어
`PUT /diet/activity {date, activeEnergyKcal}`로 올린다. 서버는 이 값을 피드백 프롬프트의
맥락으로 쓴다 — "오늘 수영으로 900kcal 쓰셨으니 저녁에 단백질을 더 채우세요" 같은 조언이
가능해진다.

**`activeEnergyBurned` 읽기 권한은 이미 `HealthKitService.readTypes`에 있다**(수영 소모 칼로리용).
추가 권한 요청이 필요 없다. `HKStatisticsQuery`로 하루 합계를 구한다.

**목표 칼로리에는 반영하지 않는다.** 활동량에 따라 목표를 매일 변동시키면 점수 기준선이
흔들려서 "어제보다 잘 먹었는데 점수가 낮은" 설명 불가능한 상황이 생긴다. 활동 에너지는
하루 요약의 보조 표시("섭취 1,850 / 소모 2,400")와 피드백 맥락으로만 쓴다.

**HealthKit 쓰기는 하지 않는다.** `Info.plist`에 `NSHealthUpdateUsageDescription`이 있지만
(커밋 `29855fe`, 심사 이슈 대응) `toShare: []`를 유지한다. 분석 결과를 건강 앱 영양 데이터로
저장하면 항목 수정 시 이미 저장한 샘플을 찾아 갱신해야 해서 동기화 상태가 하나 늘어난다.
앱 안에서만 볼 데이터라면 그 비용을 낼 이유가 없다.

## `APIClient` 확장

`APIClientProtocol`에 메서드 하나를 추가한다:

```swift
func postMultipartCreated(_ path: String, fileData: Data, fileName: String, mimeType: String) async throws -> Int
```

`/files`가 `@ResponseCreated`로 Location 헤더를 돌려주므로 기존 `postCreated`의 Location 파싱
로직을 재사용한다. **multipart를 쓰는 곳은 이 한 군데뿐이고 나머지 식단 API는 전부 JSON**이다.
`MockAPIClient`에도 같은 메서드를 추가한다.

## 화면

### `DietHomeView` — 진입점

주간 날짜 스트립(선택 날짜 변경) → 하루 요약 카드(`DietScoreRing` + `MacroBar` 3개 + 섭취/소모
칼로리 + 하루 피드백) → 끼니 카드 목록 → 사진 추가 버튼.

**프로필이 없으면 `NutritionProfileView`를 먼저 띄운다.** 목표가 없으면 점수를 낼 수 없으므로
업로드를 허용해도 결과가 비어 있게 된다.

### `MealCaptureSheet`

카메라/앨범 선택 → 끼니 종류(아침·점심·저녁·간식) 선택 → 업로드 → 분석 진행 표시.
분석 완료 시 시트를 닫고 `DietHomeView`를 갱신한다.

### `MealDetailView`

사진(presigned URL을 `AsyncImage`로), 항목 목록, 끼니 점수, 피드백.
`source == .llmEstimated` 항목에는 **「추정」 배지**를 붙여 식품DB 매칭이 안 됐음을 알린다.
항목 편집·삭제로 진입하면 `PUT /diet/meals/{id}/items` 후 재계산 결과를 다시 받는다.

presigned URL은 10분 만료이므로 URL을 오래 캐시하지 않는다. 화면을 다시 열 때 조회한다.

### `NutritionProfileView`

키·몸무게·활동량(5단계)·목표(감량/유지/증량) 입력. 성별·생년월일은 기존 `User` 값을 쓰므로
입력하지 않되, 둘 중 하나가 비어 있으면 서버가 저장을 거절하므로 **프로필 화면으로 안내**한다.
저장하면 서버가 계산한 목표 칼로리·탄단지 g을 받아 화면에 보여준다.

체중은 수동 입력이다 — HealthKit에서 자동으로 가져오지 않는다.

## 테스트 (`WooriHaruTests/DietTests.swift`)

점수 계산은 서버 책임이므로 앱은 상태 전이와 표시 로직만 검증한다. `MockAPIClient` 재사용.

- 업로드 → 폴링 → `COMPLETED` 전이
- 폴링 중 `FAILED` → 재시도 버튼 노출 상태
- 60초 타임아웃 → 실패가 아닌 "지연" 상태 (실패로 단정하지 않는지)
- 날짜를 바꿨을 때 늦게 온 이전 응답 폐기 (`generation`)
- `MacroBar`용 목표 대비 비율 계산 (목표 0일 때 0으로 나누지 않는지)
- 프로필 미설정 시 프로필 화면 우선 표시 분기

## 리스크

1. **분석 대기 경험** — 사진을 올리고 결과가 나오기까지 수 초가 걸린다. 즉시 결과가 나오는
   기록 화면들과 체감이 다르므로, 분석 중에도 사진과 끼니 종류는 바로 보여주고 점수·피드백
   영역만 로딩 상태로 둔다.
2. **인식 오류 수정 부담** — 상차림에서 반찬을 잘못 인식하면 사용자가 항목을 손으로 고쳐야
   한다. `MealItemEditView`의 검색·수정이 번거로우면 기록 자체를 포기하게 되므로, 편집 동선을
   짧게 유지하는 게 중요하다.
3. **개인정보 처리방침** — 식사 사진이 서버를 거쳐 외부 AI 서비스(OpenRouter 및 하위
   프로바이더)로 전송된다. **출시 전 처리방침에 명시가 필요하다.**

## 범위 외

배우자 공유 · 주간 리포트 · 캘린더 연동 · 과식 수준(`DailyOvereat`)과의 통합 표시 ·
HealthKit 영양 데이터 쓰기 · 체중 자동 동기화 · 바코드·영수증 인식 · 물 섭취 기록.
