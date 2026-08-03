# 추정 영양소 표시 + 끼니 항목 그램수 수정 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상세 시트에서 서버가 계산해 채운 영양소를 「추정」으로 구분해 보여 주고, 저장된 끼니 항목의 그램수만 고칠 길을 연다.

**Architecture:** 두 설계가 **`NutrientRow` 한 타입에서 만난다** — 한쪽은 그것을 최상위로 빼서 새 시트와 나눠 쓰자고 하고, 다른 쪽은 거기에 `isEstimated`를 더하자고 한다. 그래서 **먼저 빼고, 그 위에 얹고, 마지막에 새 시트를 만든다.** 순서를 바꾸면 같은 파일을 두 번 헤집게 된다.

**Tech Stack:** Swift / SwiftUI, Swift Testing, `@MainActor @Observable` 뷰모델

**설계 문서 둘:**
- `docs/superpowers/specs/2026-08-03-food-estimated-fields-design.md` (추정 표시)
- `docs/superpowers/specs/2026-08-03-meal-item-quantity-edit-design.md` (그램수 수정)

## Global Constraints

- **서버 작업 없음.** 그램수 수정은 기존 `PUT /diet/meals/{id}/items`로 되고, 추정 필드는 서버가 이미 준비돼 있다(`toy-back` `develop` `159c97a`).
- **`estimatedFields`는 옵셔널로 받는다.** non-optional로 받으면 서버 배포 전에 앱이 나가는 순간 `[Food]` 디코딩이 통째로 실패한다.
- **저장된 항목에는 출처가 없다.** `.frequent`와 끼니 항목(`MealItem`)은 `isEstimated`가 항상 `false`인데, 이는 **「원본 값」이 아니라 「모른다」는 뜻이다.**
- **저장 한 번에 LLM 호출 한 번이 나간다**(`MealService.updateItems`). 그램수는 「완료」에서 한 번만 보내고, 값이 그대로면 아예 안 보낸다.
- 각 태스크는 **고의 파손 확인**으로 끝낸다 — 구현을 망가뜨려 새 테스트가 실제로 빨개지는지 보고 되돌린다.
- 테스트 실행: `perl -e 'alarm 500; exec @ARGV' xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests > /tmp/t.log 2>&1`
  - **백그라운드로 돌리지 말고 출력은 파일로 리다이렉트한다**(`| tail` 금지 — 파이프가 멈춘다). 이 맥에는 `timeout`/`gtimeout`이 없다.
  - **프로덕션 타입에 멤버를 추가한 태스크는 `clean test`로 돌린다.** 이 저장소에서 증분 빌드가 옛 모듈로 테스트를 컴파일해 「없는 멤버」 에러를 내거나, 더 나쁘게는 **새 테스트가 안 돈 채 통과로 보고**된 적이 있다. 통과만 보지 말고 **개수가 예상만큼 늘었는지** 확인한다(시작점: **285개 / 34 스위트**).
  - **`#expect` 뒤에서 배열을 인덱스로 읽지 않는다.** 실패해도 멈추지 않으므로 범위를 벗어나면 테스트가 프로세스째 죽어 남은 테스트가 판정도 못 받는다(이 세션에서 실제로 겪었다). `.first`/`.last`나 이름 기준 딕셔너리를 쓴다.
- 커밋 메시지 마지막 줄: `Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC`

## 시작 전 확인 (서버)

추정 배지는 **DB 재적재를 해야 뜬다.** 안 하면 `estimatedFields`가 전부 빈 배열로 와서 배지가 한 번도 안 보이고, **앱이 잘못된 것처럼 보인다.**

- [ ] `toy-back` `develop` `159c97a`가 배포된 서버에 올라가 있다
- [ ] 재적재가 끝났다 — `GET /diet/foods?q=파파존스`가 500건 근처를 주고 `estimatedFields`에 `["carbs","fat"]`이 있다 (지금까지는 **0건**이었다)

확인이 안 되면 Task 2의 실기기 확인만 미루고 코드는 진행해도 된다 — 옵셔널이라 앱이 죽지 않는다.

## File Structure

| 파일 | 하는 일 | 태스크 |
| --- | --- | --- |
| `WooriHaru/Models/NutrientRow.swift` | **새 파일** — 상세 표 한 줄(최상위 타입) | 1 |
| `WooriHaru/Models/GramStepper.swift` | **새 파일** — g 조절 규칙(25g 단위·하한·빠른 칩) | 1 |
| `WooriHaru/ViewModels/FoodDetailViewModel.swift` | 중첩 타입·상수 제거, `isEstimated` 반영 | 1·2 |
| `WooriHaru/Views/Diet/FoodDetailSheet.swift` | 상수 참조 갱신, 「추정」 배지와 설명 한 줄 | 1·2 |
| `WooriHaru/Models/Food.swift` | `estimatedFields` | 2 |
| `WooriHaru/Models/FoodPickSource.swift` | `isEstimated(_:)` | 2 |
| `WooriHaru/ViewModels/MealItemQuantityViewModel.swift` | **새 파일** — 수량만 고치는 뷰모델 | 3 |
| `WooriHaru/Views/Diet/MealItemQuantitySheet.swift` | **새 파일** — 수량 시트 | 4 |
| `WooriHaru/Views/Diet/MealDetailView.swift` | 연필 → 수량 시트, 시트 경로 enum | 4 |

**새 파일은 Xcode 프로젝트에 등록해야 한다** — `project.pbxproj`에 앱 타깃 기준 4곳(`PBXBuildFile`, `PBXFileReference`, 그룹의 `children`, `PBXSourcesBuildPhase`). 등록을 빠뜨리면 「없는 타입」 에러가 난다.

**의존 순서:** 1 → 2 → 3 → 4. 1이 2와 3의 토대다.

---

### Task 1: `NutrientRow`·`GramStepper`를 공용으로 뺀다

**동작이 하나도 안 바뀌는 태스크다.** 기존 테스트가 그대로 통과하는 것이 유일한 판정 기준이다.

**Files:**
- Create: `WooriHaru/Models/NutrientRow.swift`, `WooriHaru/Models/GramStepper.swift`
- Modify: `WooriHaru/ViewModels/FoodDetailViewModel.swift:24-31`(중첩 타입), `:33-46`(상수), `:126-134`(스테퍼)
- Modify: `WooriHaru/Views/Diet/FoodDetailSheet.swift:143`
- Modify: `WooriHaruTests/DietPickTests.swift:209`

**Interfaces:**
- Produces: 최상위 `NutrientRow`(`name`·`valueText`·`isSub`), `enum GramStepper`(`step`·`minimum`·`quickGrams`)

- [ ] **Step 1: `NutrientRow.swift`를 만든다**

```swift
import Foundation

/// 상세 표의 영양소 한 줄. **두 시트가 같은 표를 그린다** — 검색 상세(`FoodDetailSheet`)와
/// 끼니 항목 수량 수정(`MealItemQuantitySheet`). 어느 한 뷰모델의 소유가 아니라 표시용
/// 모델이라 밖에 둔다.
struct NutrientRow: Identifiable, Equatable {
    let name: String
    let valueText: String
    /// 탄수화물 아래 당류처럼 한 단계 들여쓰는 줄
    let isSub: Bool

    var id: String { name }
}
```

- [ ] **Step 2: `GramStepper.swift`를 만든다**

```swift
import Foundation

/// g 수량 조절 규칙. **한 곳에 둔다** — 검색 상세와 끼니 항목 수정이 같은 격자로 움직여야
/// 한다. 두 곳에 복사하면 반드시 어긋난다(그램 스테퍼를 10g에서 25g으로 바꾼 적이 있는데,
/// 그때 두 번째 시트가 있었다면 한쪽만 바뀌었을 것이다).
enum GramStepper {
    /// 10g씩은 100g을 맞추는 데 열 번을 눌러야 해서 결국 타이핑하게 된다. 25g은 빠른 선택
    /// 칩과 같은 격자라 칩으로 대강 맞추고 스테퍼로 다듬는 흐름이 된다.
    static let step: Double = 25
    /// **0으로 내려가면 영양소가 전부 0으로 굳는다.** 더 잘게 넣고 싶으면 직접 타이핑할 수
    /// 있다 — 스테퍼 하한이 입력까지 막지는 않는다.
    static let minimum: Double = 25
    /// g 모드 빠른 선택. 1인분을 모르는 항목은 지금 반드시 타이핑해야 하는데 검색 결과의
    /// 상당수가 여기 해당한다(원재료 전부·가공식품 31%·음식 21%).
    static let quickGrams: [Double] = [50, 100, 200]
}
```

- [ ] **Step 3: 두 파일을 Xcode 프로젝트에 등록한다**

`project.pbxproj`에 앱 타깃 기준 4곳씩. 기존 `Models/` 그룹의 다른 파일(`Food.swift` 등) 항목을 그대로 본떠 넣는다.

- [ ] **Step 4: `FoodDetailViewModel`에서 옛 자리를 지운다**

- 중첩 `struct NutrientRow`(`:24-31`) 삭제
- `static let quickGrams`·`gramStep`·`minimumGram`(`:35`, `:45-46`) 삭제
- `increaseGram`/`decreaseGram`/`setGram`이 `GramStepper.step`·`GramStepper.minimum`을 쓰게 고친다
- `servingStep`·`minimumServings`는 **그대로 둔다** — 인분은 이 시트에만 있다

- [ ] **Step 5: 참조 두 곳을 고친다**

- `FoodDetailSheet.swift:143` — `FoodDetailViewModel.quickGrams` → `GramStepper.quickGrams`
- `DietPickTests.swift:209` — 같은 치환

`NutrientRow`는 이름으로 참조하는 바깥 코드가 없다(시트는 `vm.nutrientRows`만 쓴다).

- [ ] **Step 6: `clean test`**

기대: **285개 그대로**, 전부 통과. 새 테스트가 없는 태스크다.

- [ ] **Step 7: 고의 파손 확인 — 이 태스크는 건너뛴다**

동작이 안 바뀌었으므로 파손할 새 계약이 없다. **기존 285개가 그대로 통과하는 것이 이 태스크의 판정**이고, 개수가 하나라도 줄었으면 옮기다 뭔가 잃은 것이다.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
refactor: 영양소 줄과 g 조절 규칙을 공용 타입으로 뺀다

끼니 항목 수량 수정 시트가 같은 표와 같은 스테퍼를 쓴다. 뷰모델 안에 두면
복사하게 되고, 복사하면 어긋난다 — 그램 단위를 10g에서 25g으로 바꾼 적이 있다.

동작은 바뀌지 않는다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
```

---

### Task 2: 추정으로 채운 영양소를 「추정」으로 보여준다

**Files:**
- Modify: `WooriHaru/Models/Food.swift`, `WooriHaru/Models/NutrientRow.swift`, `WooriHaru/Models/FoodPickSource.swift`
- Modify: `WooriHaru/ViewModels/FoodDetailViewModel.swift`(`nutrientRows`·`fatDetailRows`)
- Modify: `WooriHaru/Views/Diet/FoodDetailSheet.swift`
- Test: `WooriHaruTests/DietTests.swift`(디코딩), `WooriHaruTests/DietPickTests.swift`(줄 표시)

**Interfaces:**
- Consumes: 최상위 `NutrientRow`(Task 1)
- Produces: `Food.estimatedFields: [String]?`, `FoodPickSource.isEstimated(_:)`, `NutrientRow.isEstimated`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`DietTests.swift`의 `FoodDecodingTests`에 더한다:

```swift
    /// **옵셔널이어야 한다.** non-optional로 받으면 서버가 이 키를 안 주는 순간 `[Food]`
    /// 배열 전체가 디코딩에 실패해 검색 화면이 빈 목록이 된다 — 배포 순서가 묶인다.
    @Test func 추정_필드_키가_없어도_디코딩된다() throws {
        let foods = try JSONDecoder().decode([Food].self, from: Data(json.utf8))

        // 위 픽스처에는 estimatedFields가 아예 없다.
        #expect(foods.count == 2)
        #expect(foods[0].estimatedFields == nil)
    }

    @Test func 추정_필드를_읽는다() throws {
        let json = """
        [{"code":"D1","name":"리아 두툼새우","dataset":"DISH",
          "servingSizeG":100,"servingSizeKnown":true,
          "kcalPer100g":200,"carbsPer100g":18.31,"proteinPer100g":10,"fatPer100g":7,
          "sugarPer100g":3,"sodiumMgPer100g":400,"fiberPer100g":1.5,
          "saturatedFatPer100g":2,"transFatPer100g":0,"cholesterolMgPer100g":30,
          "estimatedFields":["carbs","fat"]}]
        """
        let foods = try JSONDecoder().decode([Food].self, from: Data(json.utf8))

        #expect(foods.first?.estimatedFields == ["carbs", "fat"])
    }
```

`DietPickTests.swift`의 `FoodPickSourceTests`에 더한다:

```swift
    /// **한 행 안에서 공식값과 추정값이 섞인다.** `["fat"]`인 행이 647건, 그 반대가 105건
    /// 있다 — 시트 전체에 「추정」을 한 번 달면 공식값인 탄수화물까지 의심받는다.
    @Test func 추정_표시는_해당_영양소에만_붙는다() {
        let source = FoodPickSource.food(makePickFood(estimatedFields: ["fat"]))

        #expect(!source.isEstimated("carbs"))
        #expect(source.isEstimated("fat"))
    }

    /// 서버가 값을 늘려도 앱이 죽지 않는다 — 모르는 값은 그냥 안 맞을 뿐이다.
    @Test func 모르는_추정_값이_섞여도_아는_것만_붙는다() {
        let source = FoodPickSource.food(makePickFood(estimatedFields: ["carbs", "calcium"]))

        #expect(source.isEstimated("carbs"))
        #expect(!source.isEstimated("calcium2"))
    }

    /// **`false`가 「원본 값」이라는 뜻이 아니라 「모른다」는 뜻이다.** 저장된 항목의 출처를
    /// 되짚을 방법이 서버에도 없다.
    @Test func 자주_드셨어요는_출처를_모른다() {
        let source = FoodPickSource.frequent(makeFrequent())

        #expect(!source.isEstimated("carbs"))
        #expect(!source.isEstimated("fat"))
    }
```

`FoodDetailViewModelTests`에 더한다:

```swift
    /// 탄수화물·지방 두 줄만 참일 수 있다. **나머지는 서버가 출처를 기록하지 않으므로 항상
    /// 거짓이다** — 당류·나트륨에 붙으면 없는 정보를 지어낸 것이다.
    @Test func 추정_배지는_탄수화물과_지방_줄에만_붙는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(
            known: true, serving: 100, estimatedFields: ["fat"]
        )))

        let estimated = Set(vm.nutrientRows.filter(\.isEstimated).map(\.name))
        #expect(estimated == ["지방"])
    }

    @Test func 추정이_없으면_아무_줄에도_안_붙는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 100)))

        #expect(vm.nutrientRows.allSatisfy { !$0.isEstimated })
    }
```

- [ ] **Step 2: 실패를 확인한다** — `has no member 'estimatedFields'`, `has no member 'isEstimated'`

- [ ] **Step 3: `Food`에 필드를 더한다**

`cholesterolMgPer100g` 아래:

```swift
    /// 서버가 잔여 열량에서 계산해 채운 필드(`["carbs","fat"]`). 비었으면 전부 원본 값이다.
    ///
    /// 프랜차이즈 영양성분표는 어린이 기호식품 의무표시 항목(열량·단백질·나트륨·당류·
    /// 포화지방)만 싣는다. 탄수화물·총지방이 아예 없어서 서버가 같은 분류의 음식에서
    /// 탄:지 비율을 빌려 채운다.
    ///
    /// **옵셔널이다** — non-optional로 받으면 서버 배포 전에 앱이 나가는 순간 검색 결과
    /// 배열 전체가 디코딩에 실패한다. 빈 배열과 nil을 화면에서 구분하지 않는다(둘 다
    /// 「추정 없음」이다).
    let estimatedFields: [String]?
```

픽스처 둘에 인자를 더한다(`makeFood`·`makePickFood`, 기본값 `nil`).

- [ ] **Step 4: `NutrientRow`에 `isEstimated`를 더한다**

```swift
struct NutrientRow: Identifiable, Equatable {
    let name: String
    let valueText: String
    /// 탄수화물 아래 당류처럼 한 단계 들여쓰는 줄
    let isSub: Bool
    /// 서버가 잔여 열량에서 계산해 채운 값. **틀렸다는 뜻이 아니라 출처가 다르다는 뜻이다.**
    ///
    /// **기본값이 `false`인 것은 「원본 값」이 아니라 「모른다」는 뜻이다** — 서버가 출처를
    /// 기록하는 것은 탄수화물·지방 둘뿐이고, 저장된 항목에는 그마저 없다.
    let isEstimated: Bool

    var id: String { name }

    init(name: String, valueText: String, isSub: Bool, isEstimated: Bool = false) {
        self.name = name
        self.valueText = valueText
        self.isSub = isSub
        self.isEstimated = isEstimated
    }
}
```

**기본값을 두는 이유:** 줄이 15개 가까이 되는데 대부분 `false`다. 전부 명시하면 진짜 의미 있는 두 줄이 묻힌다. 기본값이 있으면 `isEstimated:`가 적힌 줄이 곧 「출처를 아는 줄」이 된다.

- [ ] **Step 5: `FoodPickSource.isEstimated(_:)`**

`brandText` 아래:

```swift
    /// 이 영양소가 추정으로 채워진 값인가. **검색 결과에만 있다** — 자주 드셨어요는 저장된
    /// 항목이라 출처를 모른다(`badge`·`brandText`와 같은 이유).
    ///
    /// `.frequent`의 `false`는 **「원본 값」이 아니라 「모른다」**는 뜻이다.
    func isEstimated(_ field: String) -> Bool {
        switch self {
        case let .food(food): food.estimatedFields?.contains(field) == true
        case .frequent: false
        }
    }
```

- [ ] **Step 6: `nutrientRows` 두 줄에만 넣는다**

```swift
            NutrientRow(name: "탄수화물", valueText: formattedGram(item.carbsG), isSub: false,
                        isEstimated: source.isEstimated("carbs")),
            NutrientRow(name: "당류", valueText: formattedGram(item.sugarG), isSub: true),
            NutrientRow(name: "단백질", valueText: formattedGram(item.proteinG), isSub: false),
            NutrientRow(name: "지방", valueText: formattedGram(item.fatG), isSub: false,
                        isEstimated: source.isEstimated("fat"))
```

**단백질에는 안 넣는다.** 서버가 `"protein"`을 열어 뒀지만 실제로 안 온다(원본에 단백질이 없는 행은 서버가 버린다). 안 오는 값을 화면에 연결해 두면 그 줄이 검증된 적 없는 채로 남는다.

`fatDetailRows`(포화지방·트랜스지방·콜레스테롤)는 손대지 않는다 — 서버가 출처를 기록하지 않는다.

- [ ] **Step 7: 시트에 배지와 설명을 단다**

`FoodDetailSheet.swift:188` 근처, `Text(row.valueText)` 옆:

```swift
                        Text(row.valueText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.slate700)
                        if row.isEstimated {
                            Text("추정")
                                .font(.caption2)
                                .foregroundStyle(Color.slate400)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.slate100, in: Capsule())
                        }
```

표 아래에 설명 한 줄. **배지만으로는 무슨 뜻인지 알 수 없다:**

```swift
                if vm.nutrientRows.contains(where: \.isEstimated) {
                    Text("「추정」은 브랜드가 공개하지 않아 열량에서 계산한 값이에요.")
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                        .padding(.top, 4)
                }
```

**문구는 「추정」이다.** 「부정확」·「주의」처럼 값을 깎아내리는 말을 쓰지 않는다 — 사용자가 알아야 할 것은 값이 틀렸다는 게 아니라 **출처가 다르다**는 것이다.

- [ ] **Step 8: `clean test`** — 기대 **292개**(285 + 7)

- [ ] **Step 9: 고의 파손 확인**

1. `estimatedFields`를 non-optional(`[String]`)로 바꾼다 → `추정_필드_키가_없어도_디코딩된다`가 빨개진다
2. 탄수화물 줄에도 `isEstimated: source.isEstimated("fat")`을 넣는다(시트 전체 플래그를 흉내) → `추정_배지는_탄수화물과_지방_줄에만_붙는다`가 빨개진다

둘 다 되돌리고 `git diff`로 확인한다.

- [ ] **Step 10: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 서버가 계산해 채운 영양소를 추정으로 구분해 보여준다

프랜차이즈 영양성분표는 의무표시 항목만 실어서 탄수화물·총지방이 없다. 서버가
잔여 열량에서 채우는데, 한 행 안에서 공식값과 섞이므로 줄마다 표시한다 — 시트
전체에 한 번 달면 공식값까지 의심받는다.

estimatedFields는 옵셔널로 받는다. non-optional이면 서버가 이 키를 안 주는 순간
검색 결과 배열 전체가 디코딩에 실패한다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
```

---

### Task 3: `MealItemQuantityViewModel`

**Files:**
- Create: `WooriHaru/ViewModels/MealItemQuantityViewModel.swift` (+ pbxproj 등록)
- Test: `WooriHaruTests/DietPickTests.swift` 끝에 새 스위트

**Interfaces:**
- Consumes: `NutrientRow`·`GramStepper`(Task 1)
- Produces: `MealItemQuantityViewModel(item:original:)`, `edited`, `canSave`, `nutrientRows`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
@MainActor
struct MealItemQuantityViewModelTests {
    private func makeVM(quantityG: Double = 250) -> MealItemQuantityViewModel {
        let item = makeMealItem(quantityG: quantityG)
        let original = MealItemRequest(
            foodName: item.foodName, foodCode: item.foodCode, quantityG: item.quantityG,
            kcal: item.kcal, carbsG: item.carbsG, proteinG: item.proteinG, fatG: item.fatG,
            sugarG: item.sugarG, sodiumMg: item.sodiumMg, fiberG: item.fiberG, source: item.source
        )
        return MealItemQuantityViewModel(item: item, original: original)
    }

    @Test func 수량을_두_배로_하면_영양소가_두_배가_된다() throws {
        let vm = makeVM(quantityG: 250)
        vm.gramText = "500"

        let edited = try #require(vm.edited)
        #expect(edited.quantityG == 500)
        #expect(edited.kcal == 750)
        #expect(edited.carbsG == 60)
        #expect(edited.proteinG == 50)
        #expect(edited.fatG == 34)
        #expect(edited.sugarG == 14)
        #expect(edited.sodiumMg == 2000)
        #expect(edited.fiberG == 6)
    }

    /// **값이 그대로면 저장하지 않는다.** 저장 한 번에 LLM 호출 한 번이 나가므로, 열었다
    /// 그냥 닫는 사용자가 매번 비용을 내면 안 된다.
    @Test func 값이_그대로면_저장할_수_없다() {
        let vm = makeVM(quantityG: 250)

        #expect(!vm.canSave)

        vm.gramText = "275"
        #expect(vm.canSave)

        // 되돌리면 다시 잠긴다.
        vm.gramText = "250"
        #expect(!vm.canSave)
    }

    @Test func 비었거나_0이면_저장할_수_없다() {
        let vm = makeVM()

        vm.gramText = ""
        #expect(vm.edited == nil)
        #expect(!vm.canSave)

        vm.gramText = "0"
        #expect(vm.edited == nil)
        #expect(!vm.canSave)
    }

    /// 검색 상세 시트와 같은 격자다 — 두 시트가 다르게 움직이면 안 된다.
    @Test func 스테퍼는_25g_단위이고_25g_아래로_안_내려간다() {
        let vm = makeVM(quantityG: 250)

        vm.increase()
        #expect(vm.gramText == "275")

        vm.gramText = "25"
        vm.decrease()
        #expect(vm.gramText == "25")
    }

    /// **하한이 입력까지 막지는 않는다** — 스테퍼로 못 내려갈 뿐이다(검색 상세와 같은 규칙).
    @Test func 하한_아래도_타이핑할_수_있다() throws {
        let vm = makeVM()
        vm.gramText = "10"

        #expect(try #require(vm.edited).quantityG == 10)
    }

    /// 저장된 항목에는 출처가 없다 — 「원본 값」이 아니라 **「모른다」**는 뜻이다.
    @Test func 저장된_항목에는_추정_표시가_없다() {
        let vm = makeVM()
        vm.gramText = "300"

        #expect(vm.nutrientRows.map(\.name) == ["탄수화물", "당류", "단백질", "지방", "나트륨", "식이섬유"])
        #expect(vm.nutrientRows.allSatisfy { !$0.isEstimated })
    }
}
```

**`makeMealItem`에 `quantityG` 인자가 이미 있는지 확인한다** — 없으면 더한다(기본값 250).
기본 픽스처의 100g당이 아니라 **절대값**이라 위 기대값은 `makeMealItem`의 기본값 기준으로 다시 계산해야 한다. 픽스처를 먼저 읽고 숫자를 맞춘다.

- [ ] **Step 2: 실패를 확인한다**

- [ ] **Step 3: 뷰모델을 만든다**

```swift
import Foundation

/// 저장된 끼니 항목의 **수량만** 고친다.
///
/// **g 전용이다** — `MealItem`에 1인분 정보(`servingSizeG`·`servingSizeKnown`)가 없다.
/// 「인분」을 쓰는 검색 상세 시트와 다른 점이 그것뿐이라 헷갈리기 쉬운데, 여기서 인분을
/// 흉내 내려면 없는 값을 지어내야 한다.
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

    /// **값이 그대로면 저장하지 않는다** — 저장 한 번에 LLM 호출 한 번이 나가므로, 열었다
    /// 그냥 닫는 사용자가 매번 비용을 내면 안 된다.
    var canSave: Bool {
        guard let quantityG else { return false }
        return quantityG != original.quantityG
    }

    func increase() { setGram((quantityG ?? 0) + GramStepper.step) }
    func decrease() { setGram((quantityG ?? GramStepper.minimum) - GramStepper.step) }
    func selectQuick(_ gram: Double) { setGram(gram) }

    private func setGram(_ value: Double) {
        gramText = max(GramStepper.minimum, value).trimmedText
    }

    var kcalText: String { "\(Int((edited?.kcal ?? 0).rounded()))kcal" }

    /// 6줄이다 — 포화지방·트랜스지방·콜레스테롤은 서버가 끼니에 저장하지 않는다.
    ///
    /// **`isEstimated`는 전부 기본값(false)이다** — 저장된 항목의 출처를 되짚을 방법이
    /// 서버에도 없다. 「원본 값」이 아니라 「모른다」는 뜻이다.
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

- [ ] **Step 4: pbxproj 등록 + `clean test`** — 기대 **298개**(292 + 6)

- [ ] **Step 5: 고의 파손 확인**

1. `canSave`를 `edited != nil`로 바꾼다(값 비교 제거) → `값이_그대로면_저장할_수_없다`가 빨개진다
2. `setGram`의 `max(GramStepper.minimum, ...)`을 지운다 → 하한 테스트가 빨개진다

- [ ] **Step 6: 커밋**

---

### Task 4: 수량 시트와 상세 화면 연결

**Files:**
- Create: `WooriHaru/Views/Diet/MealItemQuantitySheet.swift` (+ pbxproj 등록)
- Modify: `WooriHaru/Views/Diet/MealDetailView.swift`

**Interfaces:**
- Consumes: `MealItemQuantityViewModel`(Task 3)

- [ ] **Step 1: 시트를 만든다**

`FoodDetailSheet`의 g 모드와 같은 배치 — 스테퍼 · 빠른 칩(`GramStepper.quickGrams`) · 열량 · 영양소 표 · 「다른 음식으로 교체 ›」 · 「완료」.

저장 결과를 받아 닫을지 정한다:

```swift
/// 저장 결과. **`Bool`로는 부족하다** — 시트가 상세 화면을 덮고 있어 상세가 띄우는 오류
/// 알럿이 화면에 나타나지 않는다. 이유를 시트까지 들고 와서 여기서 띄워야 한다.
enum QuantitySaveOutcome: Equatable {
    case saved
    case failed(String)
}
```

**`PhotoViewerSheet.onDelete`와 같은 모양이고 같은 이유다** — 거기서도 `Bool`로 만들었다가 전체화면 뷰어가 상세를 덮어 오류가 안 보이는 것을 리뷰에서 잡혔다.

`QuantitySaveOutcome`은 **`MealItemQuantitySheet.swift` 최상위에 둔다** — 뷰모델(Step 3)과 시트가 함께 쓴다.

- [ ] **Step 2: 상세 화면의 시트를 경로 enum으로 합친다**

**함정:** 「다른 음식으로 교체」는 수량 시트를 닫고 교체 시트를 연다. **SwiftUI에서 닫히는 도중에 새 시트를 띄우면 조용히 삼켜진다** — 아무 일도 안 일어나고 오류도 없다.

`editingTarget`(교체)과 새 수량 경로를 **`sheet(item:)` 하나**로 합친다:

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

연필은 `.quantity`를 연다. 시트 안의 「교체」는 같은 `@State`를 `.replace`로 바꾼다 — `id`가 달라지므로 SwiftUI가 갈아 끼운다.

교체로 넘어가면 **바꾸던 그램수는 버린다** — 음식 자체가 바뀌니 이어받을 값이 아니다.

- [ ] **Step 3: 저장을 뷰모델에 둔다 (테스트가 닿게)**

결과를 만드는 자리를 뷰에 두면 **실패 경로가 테스트에 안 닿는다.** `MealDetailViewModel`에
얇은 메서드를 하나 더한다 — 기존 `replaceItem`은 교체 시트가 쓰고 있으므로 그대로 둔다:

```swift
    /// 수량 시트용 저장. **결과에 이유를 담아 돌려준다** — 시트가 상세 화면을 덮고 있어
    /// 상세가 띄우는 오류 알럿이 화면에 나타나지 않는다(사진 뷰어에서 같은 것을 겪었다).
    func saveQuantity(_ item: MealItem, with replacement: MealItemRequest) async -> QuantitySaveOutcome {
        guard await replaceItem(item, with: replacement) else {
            // **상세 쪽 값을 지운다** — 안 지우면 시트를 닫은 뒤 같은 오류가 한 번 더 뜬다.
            let message = errorMessage ?? "저장하지 못했어요."
            errorMessage = nil
            return .failed(message)
        }
        return .saved
    }
```

화면은 `.saved`일 때만 `onChanged()`를 부르고 시트를 닫는다.

테스트를 더한다:

```swift
    /// **실패 이유가 시트까지 와야 한다.** 시트가 상세를 덮고 있어 상세의 알럿은 안 보인다 —
    /// 그냥 닫아 버리면 사용자는 저장된 줄 알고 나간다.
    @Test func 수량_저장에_실패하면_이유를_담아_돌려준다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = makeVM(service)
        await vm.load()
        let item = try? #require(vm.meal?.items.first)
        guard let item, let edited = vm.editableItem(matching: item) else {
            Issue.record("항목을 찾지 못했다")
            return
        }

        service.errors["updateMealItems"] = dietServerError("INTERNAL_ERROR", status: 500)
        let outcome = await vm.saveQuantity(item, with: edited)

        guard case let .failed(message) = outcome else {
            Issue.record("실패를 담아 돌려줘야 한다: \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        // 시트가 띄웠으므로 상세에 남겨 두면 닫은 뒤 한 번 더 뜬다.
        #expect(vm.errorMessage == nil)
    }
```

- [ ] **Step 4: `clean test`** — 기대 **299개**(298 + 1)

- [ ] **Step 5: 고의 파손 확인**

`saveQuantity`의 `errorMessage = nil`을 지운다 → 위 테스트의 마지막 `#expect`가 빨개진다.

- [ ] **Step 6: 커밋**

---

## 실기기 확인 (사용자 몫)

시뮬레이터를 띄우지 않는다.

**추정 표시**
- 「파파존스」·「도미노」·「스타벅스」로 검색해 결과가 나오는지 (**0건이면 서버 재적재가 안 된 것이다**)
- 상세 시트에서 탄수화물·지방 옆에만 「추정」이 붙고, 당류·나트륨에는 안 붙는지
- 한쪽만 추정인 행에서 한 줄에만 붙는지
- 「피자」로 검색했을 때 상위 50건이 쓸 만한지 (되살린 4,227행이 쏟아진다)
- 롯데리아에서 같은 버거가 두 번 보이면 **서버 쪽 문제**이니 알려 주기

**그램수 수정**
- 연필 → 수량 시트 → 「다른 음식으로 교체」 → 교체 시트가 **실제로 뜨는지**(위 함정)
- 교체 시트에서 취소하고 나오면 상세 화면으로 제대로 돌아오는지
- 값을 안 바꾸고 「완료」/「닫기」 했을 때 **피드백이 다시 만들어지지 않는지**(깜빡이지 않는지)
- 값을 바꿔 저장하면 하루 화면의 합계·점수가 따라 바뀌는지
