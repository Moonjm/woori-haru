# 식단 사진 기록·점수·피드백 (iOS) 설계

작성일: 2026-07-27
짝 문서: `toy-back/docs/superpowers/specs/2026-07-27-diet-tracking-backend-design.md`

> **2026-07-28 개정** — 끼니당 사진 여러 장(최대 5장)을 허용하고, 인식 결과를 **사용자가
> 확인·수정한 뒤 저장**하는 흐름으로 바꿨다. 점수는 근거(권장 범위 대비 실제 비율)를 함께
> 받아 화면에 표시한다. 백엔드 스펙의 같은 날짜 개정과 짝을 이룬다.
>
> **2026-07-29 개정** — 백엔드 1차 구현이 끝나면서 스펙이 여러 곳 바뀌었고, 여기에 기능 4개가
> 더해진다. 아래 두 절(「백엔드 변경 반영」·「보강 기능 4가지」)이 이번 개정 내용이고, 그
> 아래 본문은 2026-07-28 기준이라 두 절과 충돌하는 서술은 두 절이 이긴다.
>
> 짝 문서가 둘로 늘었다 — 1차 설계는
> `toy-back/docs/superpowers/specs/2026-07-27-diet-tracking-backend-design.md`,
> 보강 4가지는 `toy-back/docs/superpowers/specs/2026-07-29-diet-tracking-additions-design.md`.

## 백엔드 변경 반영 (2026-07-29)

1차 구현 과정에서 백엔드 스펙이 바뀐 것들이다. **앱이 안 고치면 깨지거나 어긋나는 것부터** 적는다.

### 하루 피드백도 폴링 대상이 됐다 — 폴링이 셋이다

`GET /diet/days/{date}`가 마감 피드백을 **동기로 만들지 않는다.** 조회는 즉시 돌아오고
`feedback`이 `null`이면 서버가 뒤에서 만들고 있다는 뜻이다. 끼니 피드백과 같은 성격이라
같은 방식으로 다룬다 — 화면을 붙잡지 말고 피드백 영역만 로딩으로 두었다가 채운다.

원래는 서버가 조회 중에 LLM을 불렀는데, 그러면 하루 화면이 최대 60초 멈추고 OpenRouter가
죽어 있으면 열 때마다 호출이 나갔다. 그래서 비동기로 뺐다.

**재시도 버튼을 두지 않는다.** 생성이 실패하면 서버가 끼니가 바뀔 때까지 다시 부르지 않는다
(비용 방어). 사용자가 끼니를 추가·수정하면 자연히 다시 만들어지므로, 앱은 "잠시 후 다시
확인해 주세요" 수준의 안내만 한다.

> `POST /diet/meals/{id}/retry`(피드백 재생성)가 서버에 있지만 **앱은 부르지 않는다.**
> 누락이 아니라 위 결정의 결과다. 사진 인식 재시도(`/analyses/{id}/retry`)와 헷갈리지 말 것 —
> 그쪽은 재시도 없이는 진행이 막히므로 버튼을 둔다.

### 몸무게 전용 엔드포인트가 생겼다

```
PUT /diet/profile/weight {weightKg}   → 204
```

몸무게는 매일 재는 값이라 프로필 전체를 다시 보내게 하면 안 된다. `NutritionProfileView`에
들어가지 않고 **하루 화면에서 바로 고칠 수 있는 동선**을 준다 — 예를 들어 하루 요약 카드의
몸무게 표시를 탭하면 숫자만 고치는 시트가 뜨는 식이다.

목표는 서버가 다시 계산한다. 갱신 후 하루 요약을 다시 읽으면 새 목표가 반영된다.

**과거 점수는 바뀌지 않는다.** 서버가 끼니 확정 시점의 몸무게·목표를 그 끼니에 스냅샷으로
남기고, 하루 점수는 그날 첫 끼니의 스냅샷을 기준으로 계산한다. 앱이 "몸무게를 고치면 지난
기록이 바뀌나요?"를 걱정할 필요가 없고, 그렇게 안내해도 된다.

체중 자동 동기화(HealthKit)는 여전히 범위 외다.

### 서버에 LLM 키가 없으면 인식이 503으로 막힌다

`POST /diet/analyses`와 `/analyses/{id}/retry`가 `LLM_UNAVAILABLE`(503)을 돌려줄 수 있다.
개발·장애 상황에서 나온다.

이때 **나머지 기능은 전부 정상이다** — 프로필, 확정, 점수, 하루 집계, 식품 검색이 다 된다.
그러니 "서버 오류"로 뭉뚱그리지 말고 **사진 인식만 지금 못 쓴다**고 안내하고,
아래 「사진 없는 기록」 동선으로 유도한다.

### 식품 검색 결과에 `dataset`이 붙는다

`GET /diet/foods` 응답에 `dataset`(`DISH`/`RAW`/`PROCESSED`)이 생겼다. 가공식품 약 30만 건과
원재료 523건이 추가돼서, 검색하면 조리 음식·원재료·포장 제품이 섞여 나온다.
**목록에서 구분해 보여준다** — 「가공식품」 배지 정도면 충분하다.

사진 인식 경로에서는 서버가 알아서 우선순위를 정하므로 앱이 신경 쓸 게 없다.

### `servingSizeKnown`이 false면 `servingSizeG`를 기본 수량으로 쓰지 않는다

```json
{"name":"달걀","dataset":"RAW","servingSizeG":200.0,"servingSizeKnown":false, ...}
```

**false는 「원본에 1인분 정보가 없어 서버가 200g으로 채웠다」는 뜻이다.** 그대로 기본 수량에
넣으면 달걀 한 개가 200g·312kcal(4배)로 담긴다. 검색 결과의 상당수가 여기 걸린다 —
**원재료 523건 전부, 가공식품 31%, 음식 21%.**

false일 때는 수량 칸을 비우고 **사용자가 직접 넣게 한다.** 「1인분 정보 없음」 같은 힌트를
붙이면 왜 비었는지 읽힌다. true면 지금처럼 `servingSizeG`를 기본값으로 채운다.

> 이 값이 없던 동안 1kg짜리 새우칩이 200g으로 바뀌어 400g·1320kcal로 기록됐다(실제 8조각 ≈ 40g).
> 상한을 걸기 전에는 1800g처럼 눈에 띄게 이상해서 사용자가 고쳤지만, **200g은 그럴듯해 보여서
> 오히려 안 고친다.** 인식 경로는 이 값을 보고 모델이 준 1인분 중량으로 갈아타는데, 검색 경로는
> 앱이 판단해야 한다.

### 끼니 피드백에 하루 맥락이 담기지 않는다

끼니 피드백 프롬프트에서 "그날 누적 섭취량"을 뺐다. 앞선 끼니를 고치면 나중 끼니의 조언이
낡아버리는 문제가 있었고, 애초에 점수가 「끼니는 균형, 하루는 총량」으로 나눠 놓은 경계를
프롬프트만 넘고 있었다.

**화면 기대치가 바뀐다** — "저녁에 단백질을 몰아 드세요" 같은 하루 맥락 조언은 이제 하루
요약 카드의 마감 피드백에서만 나온다. 끼니 상세의 피드백은 그 끼니의 균형에 대해서만 말한다.

### 하루 응답의 끼니가 `mealType` 순으로 온다

아침→점심→저녁→간식 순으로 정렬돼서 온다. **앱이 다시 정렬할 필요가 없다.** 저녁을 먼저
확정하고 아침을 나중에 확정해도 화면 순서는 자연스럽다.

## 보강 기능 4가지 (2026-07-29)

필라이즈와 대조해 빠진 것을 채운다. **①②가 「기록을 계속하게 만드는」 축이고 ③④는 기록이
쌓인 뒤에 값이 생긴다.** 이 순서로 만든다.

### ① 사진 없는 기록

지금은 사진을 찍지 않으면 끼니를 만들 수 없다. 과자 하나, 사과 한 개를 기록하려고 사진을
찍게 만들면 기록을 안 하게 된다.

```
POST /diet/meals {date, mealType, analysisId: null, items}
```

`analysisId`가 선택으로 바뀌었다. 없으면 사진 없이 끼니가 만들어지고 응답의 `photos`가
**빈 배열**이다 — `PhotoStrip`과 `MealDetailView`가 이 경우를 처리해야 한다.

**항목을 만드는 방법은 둘이다.**

- **식품DB 검색** — `GET /diet/foods?q=`로 찾아 고르고 수량을 정한다. `MealItemEditView`가
  이미 하는 일이라 그대로 쓴다.
- **직접 입력** — 이름과 탄단지·칼로리를 손으로 채운다. 식품DB에도 없고 포장지 영양성분표를
  보고 넣어야 하는 경우의 최후 수단이다.

  **`foodCode`는 빈 문자열이 아니라 `nil`로 보낸다.** 직접 입력에는 코드가 없으니 `""`를
  채우기 쉬운데, 서버 검증(`@Size(max = 30)`)이 `""`를 막지 않는다. 서버가 저장할 때 `nil`로
  정규화하긴 하지만, 자주 먹는 음식 집계가 코드로 묶으므로 애초에 안 보내는 편이 안전하다.
  `source`도 `.llmEstimated`로 둔다 — 식품DB에서 온 값이 아니다.

**영양소 환산이 앱 책임이 된다.** `GET /diet/foods`는 100g당 값만 주므로,
`quantityG / 100 × per100g`을 앱이 계산해 보낸다. 서버의 환산식과 같아야 하며 다르면 저장된
수치가 틀린다. 확인 화면에서 수량을 고칠 때도 같은 계산이 필요하므로 **한 곳에 모아 두고
테스트로 고정한다.**

**환산 대상은 7개 전부다** — 열량·탄수·단백·지방에 더해 **당류·나트륨·식이섬유**(③)까지.
직접 입력 화면도 이 셋의 입력란을 가져야 한다(포장지 영양성분표에 있는 값들이다). 넷만 채워
보내면 서버가 나머지를 `0.0`으로 받아 **말없이 저장한다** — 서버는 이것을 잡지 못한다.

화면은 `MealConfirmView`를 재사용한다 — 항목 목록·합계·저장 버튼이 그대로 필요하고
`PhotoStrip`만 숨기면 된다. 진입은 `DietHomeView`의 추가 버튼에서 「사진으로 추가」와
「직접 추가」로 갈린다.

### ② 자주 먹는 음식

```
GET /diet/items/frequent?days=30&size=20
```

내가 **실제로 저장했던 항목**을 빈도순(동률이면 최근순)으로 준다. 응답 한 건이 그대로
`MealItemRequest` 모양이라 **탭 한 번으로 담긴다** — 수량과 영양소가 딸려 오므로 앱이 계산할
것도 없다. 직접 입력했던 항목도 그대로 다시 나온다.

`count`(기간 내 먹은 횟수)와 `lastEatenOn`을 함께 주므로 "이번 주 7회" 같은 표시가 가능하다.

**놓을 자리가 중요하다.** ①의 직접 추가 화면에 들어갔을 때 **검색창보다 먼저** 이 목록이
보여야 한다. 매일 먹는 것을 매번 검색하게 만들면 ①을 만든 이유가 사라진다.
`MealItemEditView`의 검색 결과 위에도 같은 목록을 얹는다.

### ③ 주의 영양소

당류·나트륨·식이섬유가 저장·표시된다. `GET /diet/days/{date}` 응답에 `nutrientLimits`가 붙는다.

**먼저, 세 값이 앱을 통과하는 경로 전체에 필드를 더해야 한다.** 백엔드에서 이 목록을 빠뜨려
「사진으로 기록한 모든 끼니가 나트륨 0」이 된 적이 있다. 값이 *표시되는* 자리만 세고 *흘러가는*
자리를 안 세면 같은 일이 앱에서 반복된다:

| 타입 | 파일 | 왜 필요한가 |
| --- | --- | --- |
| `MealItem` | `Models/Diet.swift` | 상세 화면 표시 + 수정 시 되돌려 보냄 |
| `MealItemRequest` | `Models/Diet.swift` | **여기가 빠지면 서버가 0으로 받는다** |
| `DailyDiet` | `Models/Diet.swift` | 하루 합계 3개 + `nutrientLimits` + `estimatedItemCount` |
| `AnalyzedItem` | `Models/MealAnalysis.swift` | 인식 결과 → 확정 요청으로 옮겨 담는 자리 |
| `FrequentItem` | `Models/FrequentItem.swift` | 탭 한 번으로 담기므로 여기서 끊기면 0이 된다 |
| `NutritionMath` | `Models/NutritionMath.swift` | 환산 대상 7개 (①) |
| `NutritionProfile` | `Models/NutritionProfile.swift` | 목표 3개 |

**서버는 이 누락을 잡아 주지 못한다.** `MealItemRequest`의 세 필드가 `0.0` 기본값이라, 앱이
안 보내면 검증 오류 없이 0으로 저장된다. 증상은 「나트륨이 매일 기준 이하」로만 나타난다.

```json
"nutrientLimits": [
  {"name":"나트륨","intake":2850,"unit":"mg","standardText":"2,300mg 이하","status":"WARN"}
]
```

**`ScoreBasisCard`와 같은 원칙으로 다룬다 — 앱은 판정하지 않는다.** `status`가 `WARN`이면
강조하고 `OK`면 평범하게 둔다. `standardText`는 서버 문구를 그대로 쓴다(기준이 개정되면
앱 배포 없이 따라간다).

**점수와는 무관하다는 게 화면에서 드러나야 한다.** 점수는 여전히 탄단지 비율만 보고
매겨지므로, 주의 영양소를 점수 링 옆에 붙여 감점 요인처럼 보이게 하면 안 된다. 하루 요약
카드의 별도 줄로 둔다.

끼니 상세에는 넣지 않는다 — 나트륨 기준 자체가 하루 단위다.

**`estimatedItemCount`를 같은 줄에 붙인다.** 응답에 그날 LLM 추정 항목 수가 함께 온다.

```json
"estimatedItemCount": 2
```

0보다 크면 `nutrientLimits` 아래에 「추정 2건 포함」을 작게 단다. 식품DB에 매칭되지 않은 음식도
2026-07-29부터 나트륨 등을 LLM 추정값으로 받지만 **그 오차까지 사라지는 것은 아니다** — 「기준
이하」가 오차 범위 안의 이야기일 수 있다는 것을 사용자가 알아야 한다. 값이 0이면 아무것도 그리지
않는다(항목 단위 「추정」 배지와 달리 여기서는 없음이 기본이다).

세 영양소가 모두 같은 항목 집합에서 오므로 서버가 하루에 한 번만 내려준다 — `NutrientLimitRow`
각각이 아니라 그 목록 전체에 붙는 주석이다.

### ④ 기간 통계

```
GET /diet/stats?from=&to=
```

새 화면 `DietStatsView` + `DietStatsViewModel`. 주·월 토글로 `from`~`to`만 바꿔 같은
엔드포인트를 부른다.

담는 것 — 기록한 날 수, 평균 하루 점수, **일별 점수 추이**, 평균 섭취량과 목표 대비,
자주 먹은 음식 Top N.

```json
{"from":"2026-07-22","to":"2026-07-28","recordedDays":6,
 "averageDayScore":74,
 "dailyScores":[{"date":"2026-07-22","dayScore":81}],
 "averageIntake":{"kcal":1980.0,"carbsG":250.1,"proteinG":78.4,"fatG":62.0,
                  "sugarG":44.2,"sodiumMg":2610.0,"fiberG":14.8},
 "averageTargets":{"kcal":2509,"carbsG":345,"proteinG":94,"fatG":84,
                   "sugarG":125,"sodiumMg":2300,"fiberG":30},
 "topFoods":[]}
```

**기록이 0건이면 `averageDayScore`·`averageIntake`·`averageTargets`가 `null`이고
`dailyScores`는 빈 배열이다.** `recordedDays`만 0으로 온다 — 옵셔널로 받아 빈 상태를 그린다.

`dailyScores`에는 **기록한 날만** 들어간다. 안 적은 날은 빠지므로, 추이 차트를 그릴 때
x축을 배열 인덱스로 잡으면 날짜 간격이 뭉개진다. `date`로 배치해야 한다.

`topFoods`는 `GET /diet/items/frequent`와 **같은 모양**(`FrequentItem`)이라 ②의 목록
컴포넌트를 그대로 쓴다. 상한은 20으로 서버가 자른다.

기간은 **최대 366일**(양 끝 포함)이고 넘기면 `INVALID_REQUEST`다. 주·월 토글만 쓰면 걸릴 일이
없지만, 사용자 지정 범위를 열어 준다면 앱에서 먼저 막는 편이 낫다.

**평균은 기록한 날로만 낸 값이다.** 안 적은 날을 0으로 세지 않는다 — 화면에도 "6일 기록"을
함께 보여줘야 평균이 무슨 뜻인지 읽힌다.

LLM 조언이 없어서 폴링도 로딩 상태도 필요 없다. 한 번 부르면 끝이다.

## 배경

식사 사진을 올리면 서버가 음식을 인식해 탄단지를 산출하고, 개인 목표 대비 점수와 개선
피드백을 돌려준다. 앱은 **사진 업로드, 인식 결과 확인·수정, 결과 표시**를 담당한다.
인식(OpenRouter)·식품DB 매칭·점수 계산·피드백 생성은 전부 백엔드 책임이다.

**인식 결과를 바로 저장하지 않고 사용자가 확인한다.** 사진을 여러 장 올리면 같은 음식이
중복으로 잡히거나 반찬이 잘못 인식될 수 있는데, 이걸 서버가 음식명만으로 판단할 수는 없다.
확인 화면이 이 설계에서 앱이 맡는 가장 중요한 역할이다.

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
| Model | `Models/Diet.swift` | `Meal`·`MealPhoto`·`MealItem`·`MealType`·`AnalysisStatus`·`NutritionSource`·`DailyDiet`·`ScoreBasis` + Request 타입 |
| Model | `Models/MealAnalysis.swift` | `MealAnalysis`·`AnalyzedPhoto`·`AnalyzedItem` — 확인 전 인식 결과 |
| Model | `Models/NutritionProfile.swift` | 프로필·목표치, `ActivityLevel`·`DietGoal` |
| Service | `Services/DietService.swift` | `DietServing` 프로토콜 + API 구현 (사진 업로드 포함) |
| Service | `Services/HealthKitService.swift` (수정) | `ActiveEnergyFetching` 채택 — 하루 활동 에너지 조회 |
| Service | `Services/APIClient.swift` (수정) | multipart 업로드 메서드 1개 추가 |
| Extension | `Extensions/UIImage+Extensions.swift` | 업로드 전 다운샘플 |
| ViewModel | `ViewModels/DietDayViewModel.swift` | 날짜별 하루 요약·끼니 목록·피드백 폴링 |
| ViewModel | `ViewModels/MealCaptureViewModel.swift` | 다중 사진 업로드 → 인식 요청 → 인식 폴링 |
| ViewModel | `ViewModels/MealConfirmViewModel.swift` | 인식 결과 확인·항목 편집·확정 |
| ViewModel | `ViewModels/NutritionProfileViewModel.swift` | 프로필 입력·저장 |
| ViewModel | `ViewModels/MealDetailViewModel.swift` | 항목 수정·항목 삭제·**끼니 삭제** |
| View | `Views/Diet/DietHomeView.swift` | 진입점 — 날짜 스트립 + 하루 요약 + 끼니 목록 |
| View | `Views/Diet/MealCaptureSheet.swift` | 사진 여러 장 선택 → 끼니 종류 → 업로드 → 인식 중 |
| View | `Views/Diet/MealConfirmView.swift` | **인식 결과 확인·수정 후 저장** |
| View | `Views/Diet/MealDetailView.swift` | 사진(여러 장)·항목·점수·근거·피드백 |
| View | `Views/Diet/MealItemEditView.swift` | 식품 검색으로 항목 교체·추가 |
| View | `Views/Diet/NutritionProfileView.swift` | 키·몸무게·활동량·목표 입력 |
| View | `Views/Diet/Components/DietScoreRing.swift` | 점수 링 |
| View | `Views/Diet/Components/MacroBar.swift` | 목표 대비 탄단지 막대 |
| View | `Views/Diet/Components/ScoreBasisCard.swift` | **점수 근거 — 권장 범위 대비 실제 비율** |
| View | `Views/Diet/Components/PhotoStrip.swift` | 사진 여러 장 가로 스트립 (확인·상세 공용) |

기존 파일 수정:

- `ContentView.swift` — `AppDestination.diet` 추가 및 `navigationDestination` 분기
- `Views/Components/SideDrawerView.swift` — 드로어 메뉴에 「식단」 항목

2026-07-29 개정으로 더해지는 것:

| 구성 | 파일 | 역할 |
| --- | --- | --- |
| Model | `Models/NutritionMath.swift` | **100g당 값 → 수량 기준 환산 한 곳.** 서버 공식과 같아야 한다 |
| Model | `Models/FrequentItem.swift` | 자주 먹는 음식 응답 (`count`·`lastEatenOn` 포함) |
| Model | `Models/DietStats.swift` | 기간 통계 응답 |
| ViewModel | `ViewModels/DietStatsViewModel.swift` | 기간 통계 — 주/월 토글 |
| View | `Views/Diet/DietStatsView.swift` | 일별 점수 추이·평균·자주 먹은 음식 |
| View | `Views/Diet/Components/FrequentItemList.swift` | 자주 먹는 음식 — 탭하면 바로 담김 |
| View | `Views/Diet/Components/NutrientLimitRow.swift` | 주의 영양소 한 줄 (`WARN` 강조) |

수정되는 것 — `Models/Diet.swift`·`Models/MealAnalysis.swift`·`Models/NutritionProfile.swift`
(**주의 영양소 3필드 — ③의 표 참고**), `MealConfirmViewModel`·`MealConfirmView`(사진 없는 모드),
`MealItemEditView`(자주 먹는 음식 목록을 검색창 위에, 직접 입력에 3필드 입력란),
`NutritionProfileViewModel`(몸무게 전용 갱신), `DietDayViewModel`(하루 피드백 폴링,
주의 영양소·`estimatedItemCount`), `DietService`(새 엔드포인트 4개).

ViewModel은 기존 관례대로 `@MainActor @Observable final class`이고, 서비스는 프로토콜로
주입한다(`SwimWorkoutFetching` 패턴). UI는 `Views/Components/Glass`의 기존 컴포넌트를 쓴다.

## 데이터 흐름

### 업로드 → 인식 → 확인 → 저장

```
1. PhotosPicker/카메라로 이미지 1~5장 획득
2. 각 장에 UIImage.downsampled(maxDimension: 1024, quality: 0.8) → Data
3. POST /files (multipart) × N              → fileId들
4. POST /diet/analyses {fileIds}            → analysisId (201 + Location)
5. GET /diet/analyses/{analysisId} 폴링     → status COMPLETED / FAILED
6. MealConfirmView에서 사용자가 확인·수정
7. POST /diet/meals {date, mealType, analysisId, items} → mealId (201 + Location)
8. GET /diet/meals/{mealId} 폴링            → 피드백 도착 (status COMPLETED / FAILED)
```

**다운샘플이 3번 앞에 오는 게 중요하다.** `PhotosPicker` 원본은 12MP·수 MB급이라 그대로
올리면 업로드가 느리고, 서버가 큰 이미지를 그대로 LLM에 넘겨 토큰 비용이 몇 배로 뛴다.
장변 1024px에서 음식 인식 정확도 손실은 사실상 없다.

리사이즈를 앱에서 하는 이유는 서버가 라즈베리파이라 이미지 재인코딩이 낭비이기 때문이다.

**3번의 업로드는 순차로 한다.** 병렬로 5장을 밀어넣으면 라즈베리파이에서 멀티파트 5개가
동시에 처리되고, 어느 하나가 실패했을 때 어디까지 올라갔는지 추적이 지저분해진다. 장당 수백
KB라 순차로도 충분히 빠르다. 중간에 실패하면 **이미 올린 파일은 그대로 두고 중단한다** —
확정되지 않은 파일은 서버가 24시간 뒤 자동 수거하므로 앱이 되돌릴 게 없다.

**사진은 최대 5장이다.** 서버가 사진마다 LLM을 호출하므로 장수가 곧 비용·대기시간이다.
`PhotosPicker`의 `maxSelectionCount`를 5로 두어 애초에 더 못 고르게 한다.

### 폴링이 두 번 있다

> **2026-07-29 — 이제 셋이다.** 하루 마감 피드백(`GET /diet/days/{date}`의 `feedback`)이
> 비동기로 바뀌어 폴링 대상이 하나 늘었다. 성격은 아래 8번(피드백 폴링)과 같다 — 화면을
> 붙잡지 않고 그 영역만 채운다. 차이는 **실패해도 재시도 버튼을 두지 않는다**는 것이다
> (서버가 끼니가 바뀔 때까지 다시 부르지 않는다). 위 「백엔드 변경 반영」 절 참조.

흐름에 폴링 구간이 둘이고 **성격이 다르다.** 하나로 뭉뚱그리면 UI 상태가 꼬인다.

| | 5번 인식 폴링 | 8번 피드백 폴링 |
| --- | --- | --- |
| 대상 | `GET /diet/analyses/{id}` | `GET /diet/meals/{id}` |
| 기다리는 것 | 음식 인식 결과 | 피드백 문장 |
| 사용자 대기 | **기다려야 확인 화면으로 갈 수 있다** | 기다릴 필요 없다 |
| 실패 시 | 재시도(`/analyses/{id}/retry`) 없이는 진행 불가 | 점수는 이미 있고 피드백만 비어 있다 |

**8번은 화면을 붙잡지 않는다.** 확정 응답 시점에 점수·항목은 이미 확정돼 있으므로 저장 즉시
`MealDetailView`(또는 홈)로 넘어가고, 피드백 영역만 로딩으로 두었다가 채운다.

둘 다 `status == PENDING`인 동안 **2초 간격, 최대 60초** 폴링한다. 타임아웃해도 실패로 단정하지
않는다 — 서버는 계속 처리 중일 수 있으므로 "지연되고 있어요, 잠시 후 새로고침해 주세요"로
안내한다. `status == FAILED`로 확인된 경우에만 재시도 버튼을 보여준다.

**재시도 버튼은 누르는 즉시 잠근다.** 서버가 `PENDING`인 동안 들어온 재시도를
`ANALYSIS_IN_PROGRESS`(400)로 거절하므로 중복 유료 호출은 나가지 않지만, 잠그지 않으면 사용자가
연타할 때마다 오류 알럿이 뜬다. 이 코드를 받으면 알럿 대신 폴링을 다시 시작한다 — 이미 서버가
처리 중이라는 뜻이지 실패가 아니다. `ANALYSIS_NOT_RETRYABLE`과 구분해야 하는 이유다(그쪽은
재시도할 것이 없다는 뜻이라 버튼을 감춰야 한다).

`SwimRecordViewModel`의 `generation` 카운터 패턴을 가져와, 사용자가 날짜를 바꾸거나 화면을
벗어난 뒤 늦게 도착한 응답을 버린다. `APIClient`가 `URLError.cancelled`를 `CancellationError`로
변환해 주므로 Task 취소는 그대로 전파된다.

### 사진 일부만 인식에 실패했을 때

서버는 사진별 부분 실패를 허용한다. 5장 중 1장이 실패해도 나머지 결과로 확인 화면을 띄우고
그 사진만 `failed: true`로 온다. **앱은 실패한 사진을 확인 화면에 그대로 보여주되 "인식 실패"
배지를 달고, 그 사진만 다시 시도하는 버튼**(`POST /diet/analyses/{id}/retry`)을 준다.

실패한 사진을 화면에서 감추면 안 된다. 사용자는 자기가 5장을 올린 걸 알고 있어서, 4장 분량의
항목만 보이면 나머지가 어디 갔는지 알 수 없다.

전부 실패했을 때만(`status == FAILED`) 확인 화면 대신 실패 상태를 보여준다.

### 활동 에너지

`DietHomeView` 진입 시 HealthKit에서 그날의 `activeEnergyBurned` 합계를 읽어
`PUT /diet/activity {date, activeEnergyKcal}`로 올린다. 서버는 이 값을 **하루 마감 피드백**
프롬프트의 맥락으로 쓴다 — "오늘 수영으로 900kcal 쓰셨으니 저녁에 단백질을 더 채우세요"
같은 조언이 가능해진다.

> **2026-07-29** — 끼니 피드백에는 활동 에너지가 들어가지 않는다(하루 맥락을 걷어냈다).
> 하루 마감 피드백에만 들어간다.
>
> **이 값을 올려도 마감 피드백은 다시 만들어지지 않는다.** 활동 에너지는 하루 종일 늘어나는
> 값이라, 갱신할 때마다 피드백을 재생성하면 화면을 열 때마다 LLM 호출이 나간다. 서버가
> 의도적으로 무효화하지 않으므로 **앱은 진입할 때마다 편하게 올려도 된다** — 비용이 늘지 않는다.
> 대신 피드백 문장이 조금 낡은 활동량을 말할 수 있는데, 끼니를 추가·수정하면 어차피 재생성되므로
> 하루가 끝날 무렵에는 최근 값을 담는다.

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

메서드는 **한 장 단위 그대로 둔다.** 사진 여러 장은 `DietService`가 이 메서드를 순차로 여러 번
부르는 것으로 처리한다 — 다중 업로드용 API를 따로 만들면 서버에 없는 엔드포인트를 가정하게
되고(서버 `/files`는 단건 업로드다), 실패 지점도 흐려진다.

### 식단 도메인 에러 코드

**분기 기준은 응답 바디의 `error` 필드다.** `code`는 HTTP 상태를 문자열로 담을 뿐이라
(`"400"`) 종류를 가르지 못한다 — 이름이 헷갈리니 주의한다.

```json
{"status":400,"message":"인식이 진행 중입니다...","code":"400","error":"ANALYSIS_IN_PROGRESS"}
```

**대부분은 앱이 UI로 미리 막는 상태**라, 뜬다면 앱 쪽 분기가 빠진 것으로 보면 된다.
예외는 `LLM_UNAVAILABLE`·`ANALYSIS_IN_PROGRESS` 둘이다.

| `error` | HTTP | 언제 | 앱이 할 일 |
| --- | --- | --- | --- |
| `PROFILE_NOT_FOUND` | 404 | 프로필 없이 확정 | `NutritionProfileView`로 보낸다 |
| `PHOTO_LIMIT_EXCEEDED` | 400 | 사진 6장 이상 | 선택 단계에서 5장으로 막는다 |
| `LLM_UNAVAILABLE` | 503 | 서버에 키가 없음 | "사진 인식만 지금 안 된다" + 직접 추가 유도. **재시도 버튼에서도 온다** — 눌러도 안 되니 버튼을 감추고 같은 안내로 바꾼다 |
| `ANALYSIS_NOT_CONFIRMABLE` | 400 | 인식 중인 분석을 확정 | 폴링이 `COMPLETED`가 되기 전엔 저장 버튼을 잠근다 |
| `ANALYSIS_NOT_RETRYABLE` | 400 | 실패한 사진이 없음 | 재시도 버튼을 감춘다 |
| `ANALYSIS_IN_PROGRESS` | 400 | 재인식이 이미 진행 중 | 알럿 대신 폴링 재개 (실패가 아니다) |
| `FEEDBACK_NOT_RETRYABLE` | 400 | — | 앱이 이 엔드포인트를 안 부르므로 발생하지 않는다 |

타인 소유 리소스는 전부 **404**다(`RESOURCE_NOT_FOUND`) — 저장소 관례상 403이 아니라 존재
자체를 숨긴다. 앱에서는 "찾을 수 없습니다"로 같게 다루면 된다.

## 화면

### `DietHomeView` — 진입점

주간 날짜 스트립(선택 날짜 변경) → 하루 요약 카드(`DietScoreRing` + `MacroBar` 3개 + 섭취/소모
칼로리 + 하루 피드백) → 끼니 카드 목록 → 사진 추가 버튼.

**프로필이 없으면 `NutritionProfileView`를 먼저 띄운다.** 목표가 없으면 점수를 낼 수 없으므로
업로드를 허용해도 결과가 비어 있게 된다.

### `MealCaptureSheet`

카메라/앨범에서 **1~5장 선택** → 끼니 종류(아침·점심·저녁·간식) 선택 → 업로드 → 인식 진행 표시.
인식이 끝나면 시트를 닫지 않고 **`MealConfirmView`로 이어진다.**

업로드·인식 진행률은 "3장 중 2장 올리는 중" 수준으로 보여준다. 사진 수만큼 시간이 늘어나므로
진행 상황이 안 보이면 멈춘 것처럼 느껴진다.

### `MealConfirmView` — 이번 개정의 핵심 화면

인식 결과를 사용자가 확인·수정하고 저장한다. 저장하기 전에는 `Meal`이 만들어지지 않는다.

구성 — 상단에 `PhotoStrip`(올린 사진들), 그 아래 **사진별로 묶인 인식 항목 목록**, 하단에
합계(칼로리·탄단지)와 저장 버튼.

**항목을 사진별로 묶어 보여주는 게 중요하다.** 서버가 사진마다 따로 인식하므로 같은 음식이
여러 사진에서 중복으로 잡힐 수 있는데, "2번 사진의 제육볶음"과 "3번 사진의 제육볶음"이
따로 보여야 사용자가 같은 접시인지 판단할 수 있다. 항목을 뭉쳐서 보여주면 중복인지
진짜 2인분인지 구분할 근거가 화면에서 사라진다.

각 항목에서 할 수 있는 것 — 삭제(중복 제거), 수량 조정, 식품 검색으로 교체(`MealItemEditView`
재사용), 그리고 인식이 놓친 음식 추가.

`source == .llmEstimated` 항목에는 「추정」 배지를 붙인다. 확인 화면에서 특히 중요하다 —
사용자가 어느 값을 우선 검토해야 하는지 알려준다.

**저장하지 않고 나가면 아무것도 남지 않는다.** 서버의 인식 결과와 업로드된 사진은 24시간 뒤
자동 정리되므로 앱이 정리 요청을 보낼 필요는 없다. 다만 사용자가 실수로 이탈하지 않도록
뒤로가기 시 확인 알럿을 띄운다 — 여기까지 오는 데 LLM 비용과 대기시간이 이미 들었다.

### `MealDetailView`

사진 여러 장(`PhotoStrip`, presigned URL을 `AsyncImage`로), 항목 목록, 끼니 점수,
**점수 근거(`ScoreBasisCard`)**, 피드백.

`source == .llmEstimated` 항목에는 **「추정」 배지**를 붙여 식품DB 매칭이 안 됐음을 알린다.
항목 편집·삭제로 진입하면 `PUT /diet/meals/{id}/items` 후 재계산 결과를 다시 받는다.

**끼니 통째로 지우기가 여기 있어야 한다.**

```
DELETE /diet/meals/{id}   → 204
```

`PUT /items`가 **빈 배열을 거절**하므로, 이 동선이 없으면 잘못 찍은 끼니를 지울 방법이 아예
없다 — 항목을 하나씩 지워도 마지막 하나가 남는다. 삭제는 되돌릴 수 없으니 확인 알럿을 둔다.

서버에서 이 경로는 단순 삭제가 아니다. 사진을 `TEMP`로 되돌리고(정리 배치가 나중에 수거)
그날 하루 피드백 캐시를 지운다. 그래서 **삭제 뒤에는 하루 요약을 다시 조회해야 한다** —
점수·합계·`nutrientLimits`가 전부 달라지고, 피드백은 `null`로 돌아와 다시 생성이 걸린다.

presigned URL은 10분 만료이므로 URL을 오래 캐시하지 않는다. 화면을 다시 열 때 조회한다.
사진이 여러 장이므로 URL도 여러 개이고, **만료 시각이 같으니 한 번에 다시 받는다.**

### `ScoreBasisCard` — 점수의 근거를 보여준다

서버가 `scoreBasis`를 함께 내려준다. 앱은 계산하지 않고 그대로 표시한다.

```
끼니 점수 76점
2025 한국인 영양소 섭취기준(KDRIs) 에너지적정비율

탄수화물  75%  ▓▓▓▓▓▓▓▓░░   권장 50~65%   +10%p 초과
단백질     8%  ▓░░░░░░░░░   권장 10~20%    -2%p 부족
지방      17%  ▓▓▓░░░░░░░   권장 15~30%    범위 안
```

**판정(`status`)과 감점(`penalty`)은 서버가 계산해 내려준 값을 쓴다.** 앱이 비율과 범위만 받아
직접 판정하면 감점 규칙이 앱과 서버 두 곳에 생기고, 서버가 기울기를 바꿨을 때 화면의 설명과
실제 점수가 어긋난다.

`standard` 문자열도 서버 값을 그대로 쓴다. 기준이 개정되면 앱 배포 없이 문구가 따라간다.

하루 점수에도 같은 카드를 쓰되 칼로리 항목(섭취/목표/비율)이 하나 더 붙는다.

### `NutritionProfileView`

키·몸무게·활동량(5단계)·목표(감량/유지/증량) 입력. 성별·생년월일은 기존 `User` 값을 쓰므로
입력하지 않되, 둘 중 하나가 비어 있으면 서버가 저장을 거절하므로 **프로필 화면으로 안내**한다.
저장하면 서버가 계산한 목표 칼로리·탄단지 g을 받아 화면에 보여준다.

체중은 수동 입력이다 — HealthKit에서 자동으로 가져오지 않는다.

## 테스트 (`WooriHaruTests/DietTests.swift`)

점수 계산은 서버 책임이므로 앱은 상태 전이와 표시 로직만 검증한다. `MockAPIClient` 재사용.

- 사진 N장 업로드 → 인식 요청 → 폴링 → `COMPLETED` 전이
- 업로드 중 2번째 장이 실패 → 중단하고 오류 표시, 이미 올린 fileId를 되돌리려 하지 않는지
- 사진 일부 `failed` → 실패 사진이 확인 화면에서 감춰지지 않고 배지와 함께 남는지
- 전부 실패(`status == FAILED`) → 확인 화면 대신 실패 상태
- 폴링 중 `FAILED` → 재시도 버튼 노출 상태
- 재시도 연타 → 버튼이 잠기는지, `ANALYSIS_IN_PROGRESS`가 오면 오류 알럿 대신 폴링 재개인지
- 60초 타임아웃 → 실패가 아닌 "지연" 상태 (실패로 단정하지 않는지)
- 확인 화면에서 항목 삭제·수량 변경 후 **저장한 items가 전송되는지** (인식 원본이 아니라)
- 저장 없이 이탈 → 확인 알럿, `Meal` 생성 요청이 나가지 않는지
- 확정 직후 피드백 폴링이 화면을 붙잡지 않는지 (점수는 이미 표시)
- 날짜를 바꿨을 때 늦게 온 이전 응답 폐기 (`generation`)
- `MacroBar`용 목표 대비 비율 계산 (목표 0일 때 0으로 나누지 않는지)
- `ScoreBasisCard` 표시 — 서버가 준 `status`·`penalty`를 그대로 쓰는지(앱이 재판정하지 않는지)
- 프로필 미설정 시 프로필 화면 우선 표시 분기

2026-07-29 개정으로 더해지는 것:

- **`NutritionMath` 환산** — 100g당 값과 수량으로 계산한 결과가 서버 값과 맞는지. 1인분 300g·
  100g당 150kcal을 150g 먹으면 225kcal. **이 테스트가 이번 개정에서 가장 중요하다** — 환산식이
  서버와 앱 두 곳에 살게 되므로 어긋나면 저장된 수치가 틀린다
- 사진 없는 확정 — `analysisId`가 빠진 요청이 나가는지, 응답의 `photos`가 비었을 때 `PhotoStrip`이
  깨지지 않는지
- 자주 먹는 음식 탭 → 수량·영양소가 딸려와 그대로 담기는지(앱이 다시 계산하지 않는지)
- **주의 영양소 3필드가 경로 끝까지 살아 있는지** — 검색·직접 입력·자주 먹는 음식·인식 결과
  네 경로로 각각 담아 저장한 뒤, `GET /diet/days/{date}`의 나트륨이 0이 아닌지 확인한다.
  서버가 0을 조용히 받으므로 **이 확인을 빼면 증상이 「매일 기준 이하」로만 나타난다**
- `nutrientLimits` 표시 — `WARN`/`OK` 강조 분기, 앱이 판정을 다시 하지 않는지
- `servingSizeKnown == false`인 검색 결과 — 수량 칸이 비어 있는지(200g이 기본으로 안 들어가는지)
- `estimatedItemCount` — 0이면 아무것도 안 그리고, 0보다 크면 「추정 N건 포함」이 뜨는지
- 하루 피드백 폴링 — `feedback`이 null인 동안 화면을 붙잡지 않는지, 실패 시 재시도 버튼을
  띄우지 않는지(서버가 자동 재시도를 안 하는 것과 짝이다)
- 인식 요청이 503(`LLM_UNAVAILABLE`) → "사진 인식만 지금 안 된다"는 안내와 직접 추가 유도
- 기간 통계 — 기록한 날 수와 평균이 함께 표시되는지, 0건일 때 빈 상태
  (`averageDayScore`·`averageIntake`·`averageTargets`가 `null`로 와도 안 깨지는지)
- **끼니 삭제** — 확인 알럿 뒤 `DELETE /diet/meals/{id}`, 그 다음 하루 요약을 다시 조회해
  점수·합계·`nutrientLimits`가 갱신되고 피드백이 다시 생성에 걸리는지
- 에러 분기는 `code`가 아니라 **`error` 필드**를 보는지 (`code`는 `"400"` 같은 상태 문자열이다)

## 리스크

1. **인식 대기 경험** — 사진을 올리고 결과가 나오기까지 수 초가 걸리고, **사진 수만큼 늘어난다.**
   즉시 결과가 나오는 기록 화면들과 체감이 다르므로, 대기 중에도 올린 사진과 끼니 종류는 바로
   보여주고 진행률("3장 중 2장")을 표시한다.
2. **확인 단계가 이탈 지점이 된다** — 이번 개정에서 가장 큰 리스크다. 확인 화면이 번거로우면
   사용자가 저장하지 않고 나가고, 그러면 **LLM 비용은 나갔는데 기록은 남지 않는다.** 기본값을
   그대로 저장하는 게 가장 쉬운 동선이어야 하고(저장 버튼이 1탭), 수정은 하고 싶은 사람만
   하도록 둔다. 확인 화면을 "검수 과업"이 아니라 "저장 전 미리보기"로 느껴지게 만드는 게 관건이다.
3. **인식 오류 수정 부담** — 상차림에서 반찬을 잘못 인식하면 사용자가 항목을 손으로 고쳐야
   한다. `MealItemEditView`의 검색·수정이 번거로우면 기록 자체를 포기하게 되므로, 편집 동선을
   짧게 유지하는 게 중요하다.
4. **사진을 몇 장이나 올릴지 모른다** — 상한 5장은 서버와 맞춘 초기값이다. 실제로 대부분 1~2장만
   올린다면 다중 선택 UI의 복잡도가 값을 못 하고, 반대로 습관적으로 5장을 올린다면 비용과 대기
   시간이 예상보다 커진다. **출시 후 평균 장수를 보고 상한과 UI를 조정한다.**
3. **개인정보 처리방침** — 식사 사진이 서버를 거쳐 외부 AI 서비스(OpenRouter 및 하위
   프로바이더)로 전송된다. **출시 전 처리방침에 명시가 필요하다.**

## 범위 외

배우자 공유 · 캘린더 연동 · 과식 수준(`DailyOvereat`)과의 통합 표시 ·
HealthKit 영양 데이터 쓰기 · 체중 자동 동기화 · 바코드·영수증 인식 · 물 섭취 기록 ·
텍스트로 적으면 LLM이 정리하는 입력 · 식단 추천 · 기간 조언(LLM).

> **2026-07-29** — 「주간 리포트」를 범위 외에서 뺐다. 보강 기능 ④가 그것이다.
> **「체중 자동 동기화」는 범위 외로 유지한다** — 몸무게 전용 갱신 엔드포인트가 생겼지만
> 입력은 여전히 수동이다. HealthKit 체중을 끌어오면 어느 시각 값을 쓸지, 앱이 안 켜진 날은
> 어떻게 할지를 정해야 하는데 그만한 값이 없다.
