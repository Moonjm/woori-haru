# 카드 전체를 탭 영역으로, 끼니 타입은 골라야 저장 설계

작성일: 2026-08-11
짝 저장소: 없음 — **서버 작업이 없다.** 앱의 탭 영역과 기본값 문제다.

## 배경

관련 없어 보이는 두 가지가 하나의 증상으로 묶인다 — **눌러야 할 것이 안 눌리고, 안 눌러도
되는 것이 이미 눌려 있다.**

1. 수영 기록 목록에서 카드의 **글씨 없는 자리를 누르면 아무 일도 안 일어난다.** 카드처럼
   생긴 것은 어디를 눌러도 열려야 한다.
2. 식단을 등록할 때 끼니 타입이 **이미 골라져 있어서** 그대로 저장된다. 잘못 등록하고
   나중에 고치는 일이 반복된다.

---

## 카드 전체가 탭 영역이어야 한다

### 왜 안 눌리나

`GlassCard`는 `glassEffect`로 배경을 그릴 뿐 **히트 테스트 영역을 정의하지 않는다.** 그래서
`NavigationLink` 안에 넣으면 탭이 닿는 곳은 글씨·아이콘 픽셀뿐이고, 그 사이 여백은 통과한다.

```swift
content()
    .padding(padding)
    .frame(maxWidth: .infinity, alignment: alignment)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
```

### 공용 컴포넌트를 고친다

호출지 두 곳(`SwimRecordListView`, `DietHomeView`)에 각각 붙이지 않고 `GlassCard` 자체에
넣는다. **같은 한 줄이 카드를 쓸 때마다 반복될 문제**이고, 다음에 카드를 링크로 감싸는
사람이 같은 함정을 다시 밟는다.

```swift
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
```

모서리 곡률을 유리 모양과 맞춘다. `.rect`로 두면 **보이지 않는 귀퉁이가 눌린다.**

**다른 사용처에 영향이 없다.** 카드 안에 자체 버튼이 있으면 자식이 탭을 먼저 가져가고,
탭 제스처가 걸려 있지 않은 카드에서는 `contentShape`이 아무 일도 하지 않는다. 실질 변화는
`NavigationLink`로 감싼 두 곳뿐이다.

### 검증

**유닛 테스트가 닿지 않는다.** SwiftUI 히트 테스트라 실기기에서 카드 여백을 눌러 보는 것이
유일한 확인이다.

---

## 끼니 타입은 골라야 저장된다

### 기본값이 두 곳에 박혀 있다

| 경로 | 지금 |
| --- | --- |
| 사진으로 추가 | `MealCaptureViewModel.mealType = .lunch` |
| 직접 추가 | `MealConfirmView(date:mealType: .snack, analysis: nil)` |

확인 화면에도 같은 Picker가 있어 고칠 수는 있다. **하지만 이미 채워져 있으니 그냥 저장한다.**

### 값 자체를 옵셔널로 만든다

「골랐는지」를 따로 든 플래그로 표시하지 않고, `MealType?`로 바꿔 **「안 골랐다」를 진짜
상태로 둔다.** 플래그를 얹으면 값은 여전히 `.lunch`라, 어딘가 한 군데서 플래그 검사를
빠뜨리는 순간 **고르지도 않은 끼니가 서버로 나간다.** 옵셔널이면 그 실수가 컴파일되지 않는다.

- `MealCaptureViewModel.mealType: MealType?` = `nil`
- `MealConfirmViewModel.mealType: MealType?`, `init(mealType: MealType?)`
- 직접 추가 경로가 넘기는 `.snack` → `nil`

파급되는 곳은 넷이다:

| 자리 | 미선택일 때 |
| --- | --- |
| `mergesIntoExisting` | `false` — 합쳐질 대상이 정해지지 않았다 |
| `mergeNoticeText` | `nil` — 병합 안내가 뜰 수 없다 |
| `canSave` | `false` |
| `save()` | `guard let`으로 빠져나간다 |

`save()`는 `canSave` 가드 뒤라 미선택으로 도달할 수 없다. **그래도 강제 언래핑하지 않는다** —
`canSave`의 조건이 나중에 하나 바뀌면 그 크래시는 사용자 기기에서 처음 발견된다.

### 미선택을 어떻게 보여주나

두 화면의 세그먼티드 Picker에서 태그를 `Optional($0)`로 바꾼다. **일치하는 태그가 없으면
어느 칸도 선택되지 않은 채로 그려진다** — 그 자체가 미선택 표시다. 「선택 안 함」 칸을
따로 만들지 않는다. 고를 수 있는 값처럼 보이면 그것을 고르고 저장하려 든다.

### 저장을 막는 자리는 한 곳이다

**확인 화면의 저장 버튼 하나.** 사진 경로와 직접 추가 경로가 **둘 다 이 화면을 거치므로**
게이트가 하나로 끝난다. 사진 시트의 「인식 시작」은 막지 않는다 — 끼니 타입은 인식과
아무 상관이 없는 값이라, 사진만 넣어 보려는 사용자를 무관한 이유로 세우게 된다.

버튼은 `canSave`로 이미 비활성화된다. 다만 **빈 세그먼티드만으로는 「왜 저장이 안 되지」가
된다** — 미선택일 때만 Picker 바로 아래에 한 줄을 띄운다.

```
⚠️ 끼니를 골라 주세요
```

병합 안내(`mergeNoticeText`)가 앉는 자리와 같다. 미선택일 때는 병합 안내가 나올 수 없으므로
둘이 겹치지 않는다.

### 「1탭」 원칙과 상충한다 — 알고 받아들인다

`MealConfirmView`의 파일 주석이 못 박고 있다:

> **저장 버튼이 1탭이어야 한다.** 확인 화면이 번거로우면 저장하지 않고 나가고, 그러면
> LLM 비용은 나갔는데 기록은 남지 않는다.

이번 변경은 사진 경로에서 탭을 하나 늘린다. **그럼에도 이쪽을 고른다** — 잘못 등록한 끼니를
고치는 비용이 더 크게 나타났다. 끼니 타입 수정은 화면을 다시 열고 메뉴를 찾아야 하고,
같은 날 같은 끼니로 바꾸면 **되돌릴 수 없는 병합**까지 걸린다. 저장 전 한 번 고르는 쪽이
싸다.

---

## 무엇을 테스트하나

뷰모델만 유닛 테스트가 닿는다.

- 미선택이면 `canSave == false` — 항목이 담겨 있어도 그렇다
- 미선택으로 `save()`를 불러도 **서버 호출이 나가지 않는다** (가짜 서비스의 호출 기록으로 확인)
- 끼니를 고르면 `canSave == true`가 되고, 저장 요청에 **그 값이 실린다**
- 미선택이면 `mergesIntoExisting == false`, `mergeNoticeText == nil`
- `MealCaptureViewModel`과 `MealConfirmViewModel` 둘 다 **미선택으로 시작한다**

탭 영역은 실기기 확인이다(위에 적었다).

## 손대는 파일

| 파일 | 하는 일 |
| --- | --- |
| `WooriHaru/Views/Components/Glass/GlassCard.swift` | `contentShape` |
| `WooriHaru/ViewModels/MealCaptureViewModel.swift` | `mealType`을 옵셔널·기본 nil로 |
| `WooriHaru/ViewModels/MealConfirmViewModel.swift` | 옵셔널화와 그 파급 넷 |
| `WooriHaru/Views/Diet/MealCaptureSheet.swift` | Picker 태그 |
| `WooriHaru/Views/Diet/MealConfirmView.swift` | Picker 태그, 미선택 안내 |
| `WooriHaru/Views/Diet/DietHomeView.swift` | 직접 추가가 넘기는 `.snack` → `nil` |
| `WooriHaruTests/DietConfirmTests.swift` | 확인 화면 뷰모델 케이스 |
| `WooriHaruTests/DietCaptureTests.swift` | 캡처 뷰모델이 미선택으로 시작하는지 |

새 파일이 없다 — `project.pbxproj`를 안 건드린다.
