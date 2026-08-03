# 끼니 항목 그램수 수정 (iOS) 설계

작성일: 2026-08-03
짝 저장소: 없음 — **서버 작업이 없다.** 아래 「API를 안 고쳐도 되는 이유」 참조.

## 배경

저장된 끼니에서 **먹은 양만 고치고 싶을 때 길이 없다.** 「250g으로 저장했는데 실제로는 300g이었다」가
가장 흔한 수정인데, 지금은 연필을 누르면 음식 교체 시트가 열려 **음식을 처음부터 다시 고르는**
흐름을 지나야 한다. 고르고 나면 수량은 그 음식의 기본값으로 돌아간다.

확인 화면(저장 전)에는 수량 조절이 이미 있다(`MealConfirmViewModel.updateQuantity`).
**저장 뒤에만 없다.**

## API를 안 고쳐도 되는 이유

`PUT /diet/meals/{id}/items`는 **항목 전체를 교체**한다. 한 항목의 수량만 바꿔 목록째 보내면
그것이 곧 「그램수만 수정」이다. 앱에 부품이 이미 다 있다:

- `MealDetailViewModel.replaceItem(_:with:)` — id로 자리를 찾아 그 항목만 갈아 끼운다
- `MealDetailViewModel.editableItem(matching:)` — 그 항목의 `MealItemRequest`를 꺼낸다
- `NutritionMath.rescaled(_:to:)` — 수량을 바꾸면 영양소 7개가 비례한다(0으로 나누는 것도 막혀 있다)

---

## ⚠️ 먼저 읽을 함정 넷

### 함정 1 — 저장 한 번에 **LLM 호출 한 번**이 나간다

`MealService.updateItems`(백엔드)가 항목이 바뀔 때마다 이렇게 한다:

```kotlin
meal.markFeedbackPending()
runAfterCommit { feedbackGenerator.generateForMeal(id) }
```

스테퍼 한 칸마다 저장하면 **250g → 300g을 맞추는 동안 유료 호출이 두 번** 나가고, 그 사이
끼니 피드백이 계속 「만드는 중」으로 깜빡인다.

**→ 「완료」에서 한 번만 보낸다.** 스테퍼를 누르는 동안은 화면에서만 바꾼다. 확인 화면이 이미
그 방식이다(저장 전까지 로컬에서만 고친다).

**→ 값이 그대로면 아예 안 보낸다.** 열었다 그냥 닫으면 호출 0이어야 한다. 이 조건이 없으면
「확인만 하려고 열어 본」 사용자가 매번 비용을 낸다.

### 함정 2 — 저장된 항목에는 **1인분 정보가 없다**

```swift
struct MealItem: Codable, Hashable, Identifiable {
    let id: Int
    let foodName: String
    let foodCode: String?
    let quantityG: Double
    // servingSizeG 도 servingSizeKnown 도 없다
}
```

그래서 **이 시트는 g 전용이다.** 「1인분」 단위를 넣으려면 `foodCode`로 식품을 다시 조회해야
하는데, 인식으로 추정된 항목은 코드 자체가 `nil`이라 절반은 조회할 수도 없다.

같은 이유로 **영양소 미리보기는 6줄이다** — 포화지방·트랜스지방·콜레스테롤은 서버가 끼니에
저장하지 않는다(`2026-08-02-diet-food-search-catchup-design.md` 참조).

### 함정 3 — 시트에서 시트로 넘어가는 자리

「다른 음식으로 교체」는 수량 시트를 닫고 교체 시트를 연다. **SwiftUI에서 닫히는 도중에 새 시트를
띄우면 조용히 삼켜진다** — 아무 일도 안 일어나고 오류도 없다. 상세 화면에는 이미 시트가 둘 있어
(`editingTarget`, `showAddItem`) 셋째가 붙는 자리다.

**→ `sheet(item:)` 하나에 목적지 enum을 물린다:**

```swift
private enum ItemEditRoute: Identifiable {
    case quantity(MealItem, MealItemRequest)
    case replace(MealItem, MealItemRequest)

    var id: String {
        switch self {
        case let .quantity(item, _): "quantity-\(item.id)"
        case let .replace(item, _): "replace-\(item.id)"
        }
    }
}
```

`id`가 바뀌면 SwiftUI가 시트를 갈아 끼운다. **실기기 확인이 필요한 자리다** — 시뮬레이터와
동작이 다른 경우가 있다.

### 함정 4 — 스테퍼 규칙이 **두 곳에 복사되면 어긋난다**

25g 단위·25g 하한·빠른 칩(50/100/200)은 지금 `FoodDetailViewModel`의 `static let`이고,
`NutrientRow`도 그 안에 중첩돼 있다. 새 시트가 그대로 쓸 수 없다.

복사해 두면 반드시 갈라진다 — 그램 스테퍼를 10g에서 25g으로 바꾼 게 얼마 전인데(`b3af044`),
그때 이 시트가 있었다면 한쪽만 바뀌었을 것이다.

**→ 둘 다 밖으로 뺀다.** 이 작업 경로 위에 있는 정리이지 별개 리팩터링이 아니다.

---

## 해야 할 일

### 1. 공용으로 빼기

`NutrientRow`를 최상위 타입으로 옮긴다. **화면에 표를 그리는 데만 쓰는 표시용 모델이라**
어느 한 뷰모델의 소유가 아니다.

```swift
/// 상세 시트의 영양소 한 줄. 검색 상세와 끼니 항목 수정이 같은 표를 그린다.
struct NutrientRow: Identifiable, Equatable {
    let name: String
    let valueText: String
    /// 탄수화물 아래 당류처럼 한 단계 들여쓰는 줄
    let isSub: Bool

    var id: String { name }
}
```

스테퍼 규칙도 함께 뺀다:

```swift
/// g 수량 조절 규칙. **한 곳에 둔다** — 두 시트가 같은 격자로 움직여야 한다.
enum GramStepper {
    /// 10g씩은 100g을 맞추는 데 열 번을 눌러야 해서 결국 타이핑하게 된다. 25g은 빠른 선택
    /// 칩과 같은 격자라 칩으로 대강 맞추고 스테퍼로 다듬는 흐름이 된다.
    static let step: Double = 25
    /// **0으로 내려가면 영양소가 전부 0으로 굳는다.** 더 잘게 넣고 싶으면 타이핑할 수 있다 —
    /// 스테퍼 하한이 입력까지 막지는 않는다.
    static let minimum: Double = 25
    static let quickGrams: [Double] = [50, 100, 200]
}
```

`FoodDetailViewModel`의 `quickGrams`·`gramStep`·`minimumGram`·`NutrientRow`를 지우고
새 타입을 쓰게 고친다. 참조하는 곳은 `FoodDetailSheet.swift:143`과
`DietPickTests.swift:209` 둘뿐이다(`NutrientRow`는 이름으로 참조하는 바깥 코드가 없다).

### 2. `MealItemQuantityViewModel`

```swift
/// 저장된 끼니 항목의 **수량만** 고친다.
///
/// **g 전용이다** — `MealItem`에 1인분 정보가 없다(함정 2). 「인분」을 쓰는 검색 상세 시트와
/// 다른 점이 그것뿐이라 헷갈리기 쉬운데, 여기서 인분을 흉내 내려면 없는 값을 지어내야 한다.
@MainActor
@Observable
final class MealItemQuantityViewModel {
    let item: MealItem
    /// 직접 입력도 되므로 문자열로 들고 있는다.
    var gramText: String

    private let original: MealItemRequest

    init(item: MealItem, original: MealItemRequest) {
        self.item = item
        self.original = original
        self.gramText = item.quantityG.trimmedText
    }

    var quantityG: Double? {
        guard let value = Double(gramText), value > 0 else { return nil }
        return value
    }

    /// 지금 수량으로 보낼 항목. **원본에서 새로 만든다** — 이미 만들어 둔 것을 고쳐 쓰면
    /// 조작할 때마다 환산 오차가 쌓인다.
    var edited: MealItemRequest? {
        quantityG.map { NutritionMath.rescaled(original, to: $0) }
    }

    /// **값이 그대로면 저장하지 않는다** — 유료 호출이 새는 자리다(함정 1).
    var hasChanges: Bool {
        guard let quantityG else { return false }
        return quantityG != original.quantityG
    }

    var canSave: Bool { hasChanges }

    func increase() { setGram((quantityG ?? 0) + GramStepper.step) }
    func decrease() { setGram((quantityG ?? GramStepper.minimum) - GramStepper.step) }
    func selectQuick(_ gram: Double) { setGram(gram) }

    private func setGram(_ value: Double) {
        gramText = max(GramStepper.minimum, value).trimmedText
    }

    var kcalText: String { "\(Int((edited?.kcal ?? 0).rounded()))kcal" }

    /// 6줄이다 — 포화지방·트랜스지방·콜레스테롤은 저장되지 않는다(함정 2).
    var nutrientRows: [NutrientRow] {
        guard let edited else { return [] }
        return [
            NutrientRow(name: "탄수화물", valueText: formattedGram(edited.carbsG), isSub: false),
            NutrientRow(name: "당류", valueText: formattedGram(edited.sugarG), isSub: true),
            NutrientRow(name: "단백질", valueText: formattedGram(edited.proteinG), isSub: false),
            NutrientRow(name: "지방", valueText: formattedGram(edited.fatG), isSub: false),
            NutrientRow(name: "나트륨", valueText: "\(Int(edited.sodiumMg.rounded()).formatted())mg", isSub: false),
            NutrientRow(name: "식이섬유", valueText: formattedGram(edited.fiberG), isSub: false)
        ]
    }

    /// 환산 결과는 `30.000000000000004`처럼 나올 수 있다 — 소수 첫째 자리에서 끊는다.
    private func formattedGram(_ value: Double) -> String {
        "\(((value * 10).rounded() / 10).trimmedText)g"
    }
}
```

줄을 만드는 코드가 `FoodDetailViewModel`과 두 곳이 된다. **합치지 않는다** — 그쪽은
`FoodPickSource`에서, 이쪽은 `MealItemRequest`에서 값을 꺼내고 줄 수도 다르다(9줄 대 6줄).
하나로 묶으면 출처를 가르는 분기가 안에 생겨 둘 다 읽기 어려워진다.

### 3. `MealItemQuantitySheet`

`FoodDetailSheet`의 g 모드와 같은 배치. 스테퍼 · 빠른 칩 · 열량 · 영양소 표 ·
「다른 음식으로 교체 ›」 · 「완료」.

- 「완료」는 `canSave`일 때만 눌린다
- 「다른 음식으로 교체」는 **바꾸던 그램수를 버리고** 교체 시트로 간다 — 음식 자체가 바뀌니
  이어받을 값이 아니다

**저장은 부모(`MealDetailView`)가 한다** — 가드(`isSaving`·`isStale`)와 하루 재조회
(`onChanged`)가 거기 있다. 시트는 결과를 받아 닫을지 말지만 정한다:

```swift
/// 저장 결과. **`Bool`로는 부족하다** — 시트가 상세 화면을 덮고 있어 상세가 띄우는 오류
/// 알럿이 화면에 나타나지 않는다. 이유를 시트까지 들고 와서 여기서 띄워야 한다.
enum QuantitySaveOutcome: Equatable {
    case saved
    case failed(String)
}

/// 성공하면 시트를 닫고, 실패하면 남아서 이유를 보여준다. **닫아 버리면 사용자는 저장된 줄
/// 알고 나간다.**
var onDone: (@MainActor (MealItemRequest) async -> QuantitySaveOutcome)?
```

**`PhotoViewerSheet.onDelete`와 같은 모양이고 같은 이유다.** 거기서도 처음에 `Bool`로 만들었다가
전체화면 뷰어가 상세를 덮어 오류가 안 보이는 것을 리뷰에서 잡았다 — 이번에는 처음부터 그 모양으로
간다. 호출부에서 `vm.errorMessage`를 꺼내 넘기고 **상세 쪽 값은 지운다**(안 지우면 시트를 닫은
뒤 같은 오류가 한 번 더 뜬다).

### 4. `MealDetailView` — 연필을 수량으로

연필이 `.quantity` 경로를 연다. 교체는 수량 시트 안으로 들어간다(사용자 확인 완료).
함정 3대로 `sheet(item:)` 하나에 enum을 물린다.

저장은 기존 경로 그대로다:

```swift
if await vm.replaceItem(target.item, with: edited) {
    onChanged()
}
```

`isSaving`·`isStale` 가드는 `replaceItems` 안에 이미 있다 — 낡은 화면에서 수량을 고쳐 보내면
앞서 성공한 변경이 사라지는데 그건 막혀 있다.

---

## 테스트

- **수량을 바꾸면 영양소 7개가 비례한다** — 250g → 500g에서 열량·탄단지·당류·나트륨·식이섬유
- **값이 그대로면 저장하지 않는다** — `canSave`가 false. 열었다 닫으면 서버 호출 0건.
  **이 확인이 없으면 매번 유료 호출을 내는 구현이 통과한다**
- **0이나 빈 값이면 저장할 수 없다** — `edited`가 nil
- **스테퍼가 25g 단위이고 25g 아래로 안 내려간다** — 25g에서 한 번 더 내려도 25g
- **타이핑은 하한 아래도 받는다** — 스테퍼 하한이 입력까지 막지 않는다(검색 상세와 같은 규칙)
- **저장에 실패하면 이유를 시트까지 들고 온다** — `.failed(메시지)`가 나오고 메시지가 비어 있지
  않은지. 시트가 상세를 덮고 있어 상세의 알럿이 안 보이는 자리다
- 기존 `FoodDetailViewModel` 테스트가 그대로 통과한다(공용 타입으로 옮긴 뒤에도)

**고의 파손 확인**을 권한다: `hasChanges`가 항상 true를 돌려주게 바꾸면 「값이 그대로면 저장하지
않는다」가, `setGram`의 `max(GramStepper.minimum,...)`을 빼면 하한 테스트가 실제로 빨개져야 한다.
**이 저장소는 「구현이 망가져도 통과하는 테스트」로 여러 번 데였다.**

## 실기기 확인

- 수량 시트 → 「다른 음식으로 교체」 → 교체 시트가 **실제로 뜨는지**(함정 3)
- 교체 시트에서 취소하고 나오면 상세 화면으로 제대로 돌아오는지
- 값을 안 바꾸고 「완료」/「닫기」 했을 때 피드백이 다시 만들어지지 않는지(깜빡이지 않는지)

## 범위 밖

- **1인분 단위** — 저장된 항목에 1인분 정보가 없다(함정 2). 넣으려면 식품 재조회가 필요하고,
  추정 항목은 그마저 불가능하다
- **여러 항목을 한 번에 조절** — 항목 하나마다 서버 왕복이라 모아 보낼 이유가 없고,
  한 번에 보내면 되돌리기가 어려워진다
- 확인 화면(저장 전)의 수량 조절 — 이미 있다
- 항목 이름·출처 수정
