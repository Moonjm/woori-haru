# 식품 검색 — 밀린 백엔드 변경 따라잡기 (iOS) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서버가 이미 주고 있는 `dataset` 필터·브랜드(`maker`)·영양소 3종을 앱이 쓰게 하고, 서버가 데이터셋을 늘리는 날 검색이 죽지 않게 막는다.

**Architecture:** 필터 칩을 「받아 온 결과를 앱에서 거르기」에서 **「칩이 곧 쿼리」**로 바꾼다. 그러면 `dataset`이 서버 SQL의 `where`로 들어가 페이징 **전에** 걸러지므로, 상위 50건이 전부 가공식품일 때 「음식」 칩이 빈 목록이 되던 문제가 사라진다. `Food` 모델에는 필드 넷을 더하고, `FoodDataset`은 모르는 값을 `.unknown`으로 삼켜 배열 전체가 날아가지 않게 한다.

**Tech Stack:** Swift / SwiftUI, Swift Testing, `@MainActor @Observable` 뷰모델, 프로토콜 주입 서비스

**설계 문서:** `docs/superpowers/specs/2026-08-02-diet-food-search-catchup-design.md`

## Global Constraints

- **서버는 이미 배포돼 있다**(`toy-back` `d1e3fd2`, DB 재적재 완료). 그래서 영양소 3종을 non-optional `Double`로 받는다. **`maker`만 옵셔널이다.**
- **`.unknown`은 절대 쿼리로 보내지 않는다** — 서버가 enum 변환에 실패해 400을 준다.
- **앱은 `dataset`으로 거르지 않는다.** 서버가 거른 결과를 그대로 믿는다.
- 새 UI 문구는 기존 화면 말투를 따른다(존댓말, 「」로 감싼 칩 이름).
- 각 태스크는 **고의 파손 확인**으로 끝낸다 — 구현을 망가뜨려 새 테스트가 실제로 빨개지는지 보고 되돌린다. 이 저장소는 「구현이 망가져도 통과하는 테스트」로 여러 번 데였다.
- 테스트 실행: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests`
  - **백그라운드로 돌리지 말 것.** 타임아웃은 `perl -e 'alarm 560; exec @ARGV' xcodebuild …`로 감싸고 출력은 파일로 리다이렉트한다(`| tail` 금지 — 파이프가 멈춘다). 이 맥에는 `timeout`/`gtimeout`이 없다.
  - **프로덕션 타입에 멤버를 추가한 태스크(1·2·4·5)는 `clean test`로 돌린다.** 이 저장소에서 증분 빌드가 옛 모듈로 테스트를 컴파일해 「없는 멤버」 에러를 내거나, 더 나쁘게는 **새 테스트가 아예 안 돈 채 통과로 보고**된 적이 있다. 통과만 보지 말고 **테스트 개수가 예상만큼 늘었는지** 확인한다(시작점: 272개 / 33 스위트).
- 커밋 메시지 마지막 줄: `Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC`

## File Structure

| 파일 | 하는 일 | 태스크 |
| --- | --- | --- |
| `WooriHaru/Models/Food.swift` | `Food`에 필드 넷, `FoodDataset`에 `.unknown`과 관대한 디코딩 | 1 |
| `WooriHaruTests/DietTests.swift` | `makeFood` 픽스처, `Food` 디코딩 테스트, `searchFoods` 쿼리 테스트 | 1·2 |
| `WooriHaruTests/DietPickTests.swift` | `makePickFood` 픽스처, 고르기 화면 테스트 | 1·3·4·5 |
| `WooriHaru/Services/DietService.swift` | `searchFoods(query:dataset:)` | 2 |
| `WooriHaruTests/DietFakes.swift` | 대역이 `dataset`을 기록한다 | 2 |
| `WooriHaru/ViewModels/MealItemPickViewModel.swift` | 앱 필터 제거, 칩 전환 시 재검색, 빈 상태 문구 | 3 |
| `WooriHaru/Views/Diet/MealItemEditView.swift` | 칩이 재검색을 부른다, 이름 바뀐 프로퍼티 | 3 |
| `WooriHaru/Models/FoodPickSource.swift` | `brandText` | 4 |
| `WooriHaru/Views/Diet/Components/FoodPickRow.swift` | 브랜드를 배지 줄에 그린다 | 4 |
| `WooriHaru/ViewModels/FoodDetailViewModel.swift` | 포화지방·트랜스지방·콜레스테롤 줄 | 5 |

**의존 순서:** 1 → 2 → 3. 4와 5는 1에만 의존하므로 2·3과 순서가 자유롭다. 위 순서대로 진행한다.

---

### Task 1: `Food` 모델 확장과 미지 데이터셋 흡수

**Files:**
- Modify: `WooriHaru/Models/Food.swift:3-37`
- Modify: `WooriHaruTests/DietTests.swift:44-64` (`makeFood` 픽스처)
- Modify: `WooriHaruTests/DietPickTests.swift:7-20` (`makePickFood` 픽스처)
- Test: `WooriHaruTests/DietTests.swift`

**Interfaces:**
- Produces: `FoodDataset.unknown`, `Food.maker: String?`, `Food.saturatedFatPer100g / transFatPer100g / cholesterolMgPer100g: Double`
- Produces: `makeFood(…, maker:saturatedFat:transFat:cholesterol:)`와 `makePickFood(…, maker:saturatedFat:transFat:cholesterol:)` — 뒤 태스크들이 이 인자로 값을 넣는다

**이 태스크가 한 덩어리인 이유:** `Food`에 non-optional 필드를 더하는 순간 두 픽스처가 동시에 컴파일 실패한다. 나눌 수 없다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietTests.swift`의 `makeFood` 바로 아래에 새 스위트를 만든다:

```swift
struct FoodDecodingTests {
    /// 서버 응답 두 건 — 하나는 아는 데이터셋, 하나는 **아직 모르는 값**.
    /// `maker` 키는 둘째에서 아예 빠져 있다(서버가 null을 생략하지 않더라도 안전해야 한다).
    private let json = """
    [
      {"code":"D1","name":"제육볶음","maker":"백종원","dataset":"DISH",
       "servingSizeG":250,"servingSizeKnown":true,
       "kcalPer100g":150,"carbsPer100g":12,"proteinPer100g":10,"fatPer100g":7,
       "sugarPer100g":3,"sodiumMgPer100g":400,"fiberPer100g":1.5,
       "saturatedFatPer100g":2.5,"transFatPer100g":0.1,"cholesterolMgPer100g":30},
      {"code":"U1","name":"내가 등록한 음식","dataset":"USER",
       "servingSizeG":100,"servingSizeKnown":false,
       "kcalPer100g":100,"carbsPer100g":1,"proteinPer100g":1,"fatPer100g":1,
       "sugarPer100g":1,"sodiumMgPer100g":1,"fiberPer100g":1,
       "saturatedFatPer100g":0,"transFatPer100g":0,"cholesterolMgPer100g":0}
    ]
    """

    /// **한 건이라도 모르는 `dataset`이면 `[Food]` 전체가 실패한다.** 서버에 「사용자 등록
    /// 식품(USER)」 계획이 있고, 그날 이 흡수가 없으면 검색 화면이 통째로 빈 목록이 된다.
    /// 화면이 죽는 방식이 「그 한 건이 안 보인다」가 아니라 「전부 안 보인다」라 위험하다.
    @Test func 모르는_데이터셋이_섞여도_목록_전체가_살아난다() throws {
        let foods = try JSONDecoder().decode([Food].self, from: Data(json.utf8))

        #expect(foods.count == 2)
        #expect(foods[0].dataset == .dish)
        #expect(foods[1].dataset == .unknown)
        // 이름을 모르니 지어내지 않는다.
        #expect(foods[1].dataset.badge == nil)
    }

    /// `maker`는 없는 행이 더 많다(음식 68%, 원재료 100%). **키 자체가 빠져도 디코딩된다.**
    @Test func 브랜드는_없어도_디코딩된다() throws {
        let foods = try JSONDecoder().decode([Food].self, from: Data(json.utf8))

        #expect(foods[0].maker == "백종원")
        #expect(foods[1].maker == nil)
    }

    /// 서버가 값 없는 칸을 0.0으로 채워 보내므로 non-optional로 받는다.
    @Test func 새_영양소_셋을_읽는다() throws {
        let foods = try JSONDecoder().decode([Food].self, from: Data(json.utf8))

        #expect(foods[0].saturatedFatPer100g == 2.5)
        #expect(foods[0].transFatPer100g == 0.1)
        #expect(foods[0].cholesterolMgPer100g == 30)
    }
}
```

**`JSONDecoder()`를 그대로 쓰는 것이 맞다** — `APIClient.swift:168`이 아무 전략도 세우지 않은 기본 디코더를 쓴다.

- [ ] **Step 2: 실패를 확인한다**

```bash
perl -e 'alarm 560; exec @ARGV' xcodebuild test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; grep -E "error:" /tmp/t.log | head
```

기대: 컴파일 에러 — `'Food' has no member 'maker'`, `type 'FoodDataset' has no member 'unknown'`.

- [ ] **Step 3: `FoodDataset`을 고친다**

`WooriHaru/Models/Food.swift:3-16`을 통째로 바꾼다:

```swift
enum FoodDataset: String, Codable, Hashable {
    case dish = "DISH"
    case raw = "RAW"
    case processed = "PROCESSED"
    /// 서버가 새 데이터셋을 늘렸을 때 **검색 결과 전체가 날아가지 않게** 흡수하는 값.
    /// 배지는 달지 않는다 — 이름을 모르니 지어내지 않는다.
    ///
    /// **쿼리로 보내면 안 된다**(`DietService.searchFoods`) — 서버가 enum 변환에 실패해 400을 준다.
    case unknown

    /// **모르는 값을 던지지 않고 삼킨다.** `[Food]` 배열은 한 건만 실패해도 전체가 실패하므로,
    /// 서버가 `USER` 같은 값을 늘리는 날 검색 화면이 통째로 빈 목록이 된다.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodDataset(rawValue: raw) ?? .unknown
    }

    /// 목록에서 구분해 보여줄 배지 문구. 조리 음식은 기본값이라 배지를 달지 않는다.
    var badge: String? {
        switch self {
        case .dish: nil
        case .raw: "원재료"
        case .processed: "가공식품"
        case .unknown: nil
        }
    }
}
```

- [ ] **Step 4: `Food`에 필드 넷을 더한다**

`code`와 `name` 사이에 `maker`를, `fiberPer100g` 아래에 영양소 셋을 넣는다:

```swift
struct Food: Codable, Hashable, Identifiable {
    let code: String
    let name: String
    /// 프랜차이즈·제조사. 없는 행이 더 많다(음식 68%, 원재료 100%).
    ///
    /// **식품명에 브랜드가 없다** — 도미노피자 318건이 전부
    /// `피자_뉴욕 오리진 피자 오리지널 (L)` 같은 이름이다. 이 값이 없으면 「도미노」로
    /// 검색해 나온 결과를 보고도 왜 나왔는지 알 수 없다.
    let maker: String?
    let dataset: FoodDataset
    let servingSizeG: Double
    /// **false면 `servingSizeG`(200g)는 서버가 채운 자리채움값이다** — 기본 수량으로 쓰면
    /// 달걀 한 개가 4배로 담긴다. 검색 결과 중 원재료 전부·가공식품 31%·음식 21%가 여기 걸린다.
    let servingSizeKnown: Bool
    let kcalPer100g: Double
    let carbsPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let sugarPer100g: Double
    let sodiumMgPer100g: Double
    let fiberPer100g: Double
    /// **상세 시트 표시 전용이다.** 서버가 끼니에 저장하지 않으므로 담은 뒤에는 사라진다 —
    /// 자주 드셨어요·사진 인식 항목에는 이 값이 없다. 값이 없는 칸은 서버가 0.0으로 채운다.
    let saturatedFatPer100g: Double
    let transFatPer100g: Double
    let cholesterolMgPer100g: Double

    /// 코드는 데이터셋 안에서만 유일하다.
    ///
    /// **알려진 한계:** `.unknown`끼리는 `"unknown-"`을 공유한다. 서버가 데이터셋을 둘 이상
    /// 늘리고 그 둘에 같은 `code`가 있어야 겹치므로, 그때 가서 원본 문자열을 들고 있으면 된다.
    var id: String { "\(dataset.rawValue)-\(code)" }
}
```

- [ ] **Step 5: 픽스처 둘을 고친다**

`WooriHaruTests/DietTests.swift:44-64`:

```swift
private func makeFood(
    code: String = "D000001",
    name: String = "제육볶음",
    maker: String? = nil,
    dataset: FoodDataset = .dish,
    servingSizeG: Double = 250,
    servingSizeKnown: Bool = true,
    kcal: Double = 150,
    carbs: Double = 12,
    protein: Double = 10,
    fat: Double = 7,
    sugar: Double = 3,
    sodium: Double = 400,
    fiber: Double = 1.5,
    saturatedFat: Double = 2,
    transFat: Double = 0.1,
    cholesterol: Double = 30
) -> Food {
    Food(
        code: code, name: name, maker: maker, dataset: dataset,
        servingSizeG: servingSizeG, servingSizeKnown: servingSizeKnown,
        kcalPer100g: kcal, carbsPer100g: carbs, proteinPer100g: protein, fatPer100g: fat,
        sugarPer100g: sugar, sodiumMgPer100g: sodium, fiberPer100g: fiber,
        saturatedFatPer100g: saturatedFat, transFatPer100g: transFat,
        cholesterolMgPer100g: cholesterol
    )
}
```

`WooriHaruTests/DietPickTests.swift:7-20`:

```swift
func makePickFood(
    _ name: String = "제육볶음",
    code: String = "D9",
    maker: String? = nil,
    dataset: FoodDataset = .dish,
    known: Bool = true,
    serving: Double = 250,
    saturatedFat: Double = 2,
    transFat: Double = 0.1,
    cholesterol: Double = 30
) -> Food {
    Food(
        code: code, name: name, maker: maker, dataset: dataset,
        servingSizeG: serving, servingSizeKnown: known,
        kcalPer100g: 150, carbsPer100g: 12, proteinPer100g: 10, fatPer100g: 7,
        sugarPer100g: 3, sodiumMgPer100g: 400, fiberPer100g: 1.5,
        saturatedFatPer100g: saturatedFat, transFatPer100g: transFat,
        cholesterolMgPer100g: cholesterol
    )
}
```

**기존 호출부는 안 고쳐도 된다** — 새 인자에 전부 기본값이 있다.

- [ ] **Step 6: `clean test`로 통과를 확인한다**

```bash
perl -e 'alarm 560; exec @ARGV' xcodebuild clean test -scheme WooriHaru \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WooriHaruTests > /tmp/t.log 2>&1; grep -E "Test run with|error:" /tmp/t.log
```

기대: **275개** (272 + 3), 전부 통과.

- [ ] **Step 7: 고의 파손 확인**

`FoodDataset`의 `init(from:)`을 통째로 지운다 → `모르는_데이터셋이_섞여도_목록_전체가_살아난다`가 디코딩 실패로 빨개져야 한다. 되돌리고 `git diff`로 원상복구를 확인한다.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 식품 모델에 브랜드·영양소 3종을 싣고 모르는 데이터셋을 흡수한다

FoodDataset이 옵셔널도 기본값도 아니라, 서버가 값을 하나 늘리면 [Food] 배열
디코딩이 통째로 실패해 검색 화면이 빈 목록이 된다. 서버에 사용자 등록 식품
계획이 있어 실제로 닿는 자리다. 모르는 값은 .unknown으로 삼킨다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
```

---

### Task 2: `searchFoods`가 `dataset`을 서버로 보낸다

**Files:**
- Modify: `WooriHaru/Services/DietService.swift:29` (프로토콜), `:136-139` (구현)
- Modify: `WooriHaruTests/DietFakes.swift:250-260` (대역)
- Test: `WooriHaruTests/DietTests.swift:254` 근처

**Interfaces:**
- Consumes: `FoodDataset.unknown` (Task 1)
- Produces: `DietServing.searchFoods(query:dataset:)` — `dataset` 기본값 `nil`
- Produces: `FakeDietService.searchCalls: [(query: String, dataset: FoodDataset?)]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/DietTests.swift`의 `식품_검색은_q와_size를_붙인다`를 **아래 셋으로 교체한다.** 기존 테스트의 주석이 「앱에서 거르기 때문에 size가 50」이라고 설명하는데 그 전제가 이번에 사라진다:

```swift
@Test func 식품_검색은_q와_size를_붙인다() async throws {
    let api = MockAPIClient()
    api.stubGet("/diet/foods", result: DataResponse<[Food]>(data: []))

    _ = try await DietService(api: api).searchFoods(query: "제육")

    #expect(api.getCalls.first?.path == "/diet/foods")
    #expect(api.getCalls.first?.query["q"] == "제육")
    // 서버 상한이 50이다.
    #expect(api.getCalls.first?.query["size"] == "50")
    // **칩이 「전체」면 파라미터를 아예 안 보낸다** — 빈 문자열을 보내면 서버가 400을 준다.
    #expect(api.getCalls.first?.query["dataset"] == nil)
}

/// **거르기는 페이징 전에 일어나야 한다.** 앱에서 거르면 상위 50건이 전부 가공식품일 때
/// 「음식」 칩이 빈 목록이 된다 — 실제로 매칭되는 조리 음식이 뒤에 있는데도 그렇다.
@Test func 데이터셋_칩은_쿼리로_나간다() async throws {
    let api = MockAPIClient()
    api.stubGet("/diet/foods", result: DataResponse<[Food]>(data: []))

    _ = try await DietService(api: api).searchFoods(query: "제육", dataset: .dish)

    #expect(api.getCalls.first?.query["dataset"] == "DISH")
}

/// `.unknown`은 서버에 없는 값이라 보내면 enum 변환에 실패해 400이 온다.
/// **검색이 되기는 해야 하므로 파라미터만 빼고 보낸다.**
@Test func 모르는_데이터셋은_쿼리로_보내지_않는다() async throws {
    let api = MockAPIClient()
    api.stubGet("/diet/foods", result: DataResponse<[Food]>(data: []))

    _ = try await DietService(api: api).searchFoods(query: "제육", dataset: .unknown)

    #expect(api.getCalls.first?.query["dataset"] == nil)
    #expect(api.getCalls.first?.query["q"] == "제육")
}
```

- [ ] **Step 2: 실패를 확인한다**

Task 1 Step 2와 같은 명령. 기대: `extra argument 'dataset' in call`.

- [ ] **Step 3: 프로토콜과 구현을 고친다**

`WooriHaru/Services/DietService.swift:29`:

```swift
    /// **`dataset`을 서버로 넘긴다.** 앱에서 거르면 상위 50건이 전부 가공식품일 때 「음식」
    /// 칩이 빈 목록이 된다 — 거르기는 페이징 **전에** 일어나야 한다.
    func searchFoods(query: String, dataset: FoodDataset?) async throws -> [Food]
```

`:136-139`:

```swift
    func searchFoods(query: String, dataset: FoodDataset? = nil) async throws -> [Food] {
        var parameters = ["q": query, "size": "50"]
        // `.unknown`은 서버에 없는 값이다 — 보내면 enum 변환에 실패해 400이 온다.
        if let dataset, dataset != .unknown {
            parameters["dataset"] = dataset.rawValue
        }
        let response: DataResponse<[Food]> = try await api.get("/diet/foods", query: parameters)
        return response.data ?? []
    }
```

**프로토콜 선언에는 기본값을 두지 않는다.** 설계 문서의 경고대로, 기본값을 두면 기존 호출부가 **그대로 컴파일되어** 「고쳤는데 안 부르는」 상태가 조용히 남는다. 기본값이 없으면 컴파일러가 호출부를 짚어 준다.

- [ ] **Step 4: 컴파일러가 짚어 주는 호출부를 고친다**

프로토콜에 기본값이 없으므로 `MealItemPickViewModel.swift:200`이 그 자리에서 깨진다. **이 태스크에서 함께 고친다** — 안 고치면 이 태스크가 혼자 빌드되지 않는다:

```swift
            let results = try await service.searchFoods(query: keyword, dataset: filter.dataset)
```

이 시점에는 앱 필터(`filteredSearchSources`)가 아직 남아 있어 **서버와 앱이 같은 기준으로 두 번 거른다.** 결과는 같으므로 해롭지 않고, Task 3에서 앱 쪽을 걷어낸다.

`DietTests.swift:259`는 구상 타입(`DietService`)을 직접 부르므로 구현 쪽 기본값이 받아 준다 — 안 고쳐도 된다.

- [ ] **Step 5: 대역을 고친다**

`WooriHaruTests/DietFakes.swift`의 기록 프로퍼티 옆(`:106` 근처)에 더한다:

```swift
    /// 검색 호출 전체 — 어떤 칩으로 나갔는지까지 본다. `searchQueries`는 검색어만 본다.
    private(set) var searchCalls: [(query: String, dataset: FoodDataset?)] = []
```

`:250-260`을 바꾼다:

```swift
    /// **대역은 `dataset`으로 거르지 않는다.** 거르면 「앱이 안 거른다」를 확인하는 테스트가
    /// 대역의 거르기에 가려 통과해 버린다 — 서버 몫은 서버 테스트에 있다.
    func searchFoods(query: String, dataset: FoodDataset?) async throws -> [Food] {
        lock.lock()
        searchQueries.append(query)
        searchCalls.append((query, dataset))
        let gate = searchGates[query]
        let override = foodsByQuery[query]
        lock.unlock()

        if let gate { await gate.hold() }
        try check("searchFoods")
        return override ?? foods
    }
```

- [ ] **Step 6: `clean test`로 통과를 확인한다**

기대: **277개** (275 + 2, 기존 하나는 교체라 순증 2).

- [ ] **Step 7: 고의 파손 확인**

`if let dataset, dataset != .unknown` 에서 `, dataset != .unknown`을 지운다 → `모르는_데이터셋은_쿼리로_보내지_않는다`가 빨개져야 한다. 다음으로 `parameters["dataset"] = …` 줄을 지운다 → `데이터셋_칩은_쿼리로_나간다`가 빨개져야 한다. 둘 다 되돌린다.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 식품 검색이 데이터셋 필터를 서버로 넘긴다

앱에서 거르면 상위 50건이 전부 가공식품일 때 음식 칩이 빈 목록이 된다.
거르기가 페이징 전에 일어나야 한다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
```

---

### Task 3: 고르기 화면을 서버 필터로 옮긴다

**Files:**
- Modify: `WooriHaru/ViewModels/MealItemPickViewModel.swift:128-150`(목록·빈 상태), `:176` 위(`selectFilter`)
- Modify: `WooriHaru/Views/Diet/MealItemEditView.swift:117-121`, `:144`
- Test: `WooriHaruTests/DietPickTests.swift:471-497` (교체), 그 아래 빈 상태 테스트

**Interfaces:**
- Consumes: `DietServing.searchFoods(query:dataset:)`와 **Task 2가 이미 칩을 실어 보내게 고쳐 둔 `search()`**
- Produces: `MealItemPickViewModel.searchSources`(이름 변경), `selectFilter(_:) async`

**이 태스크의 핵심 함정:** 칩이 곧 쿼리이므로 **칩을 바꾸면 재검색해야 한다.** 안 하면 칩을 눌러도 목록이 그대로다 — 앱 필터만 지우고 재검색을 안 붙이는 것이 가장 흔한 미완성이다.

- [ ] **Step 1: 낡은 테스트를 지우고 새 테스트를 쓴다**

`WooriHaruTests/DietPickTests.swift:471-497`의 `필터_칩이_데이터셋으로_거른다`를 **지운다.** 앱이 거르지 않게 되므로 그 테스트는 요구사항 자체가 사라진다. 자리에 아래를 넣는다:

```swift
/// **칩이 곧 쿼리다.** 앱 필터를 지우기만 하고 재검색을 안 붙이면 칩을 눌러도 목록이
/// 그대로다 — 이 테스트가 그 미완성을 잡는다.
@Test func 칩을_바꾸면_그_데이터셋으로_다시_검색한다() async {
    let (vm, service) = makeVM()
    service.foods = [makePickFood("제육볶음", code: "D1")]
    vm.query = "제육"
    await vm.search()

    #expect(service.searchCalls.count == 1)
    #expect(service.searchCalls[0].dataset == nil)

    await vm.selectFilter(.processed)

    #expect(vm.filter == .processed)
    #expect(service.searchCalls.count == 2)
    #expect(service.searchCalls[1].dataset == .processed)
    #expect(service.searchCalls[1].query == "제육")
}

/// **서버가 거른 결과를 그대로 믿는다.** 대역이 칩과 안 맞는 한 건을 줘도 앱이 지우면 안 된다 —
/// 앱이 또 거르면 서버가 페이징 전에 거른 의미가 없어지고, 두 곳의 기준이 어긋나면
/// 「검색은 됐는데 목록이 빈」 상태가 다시 생긴다.
@Test func 앱은_데이터셋으로_더_거르지_않는다() async {
    let (vm, service) = makeVM()
    service.foods = [makePickFood("삼각김밥", code: "P1", dataset: .processed)]
    vm.query = "김"
    await vm.search()

    await vm.selectFilter(.dish)

    #expect(vm.searchSources.map(\.name) == ["삼각김밥"])
}

/// 칩이 걸린 채 0건이면 **원인이 칩일 수 있다**고 알려 준다 — 「전체」에는 결과가 있을 수 있다.
@Test func 칩이_걸린_채_결과가_없으면_전체로_보라고_안내한다() async {
    let (vm, service) = makeVM()
    service.foods = []
    vm.query = "없는음식"

    await vm.selectFilter(.dish)
    #expect(vm.searchEmptyText == "「음식」에는 검색 결과가 없어요. 「전체」로 보거나 검색어를 바꿔 보세요.")

    // 칩이 「전체」면 칩 탓이 아니다 — 원인을 잘못 짚으면 안 된다.
    await vm.selectFilter(.all)
    #expect(vm.searchEmptyText == "검색 결과가 없어요. 다른 이름으로 찾아 보세요.")
}
```

**`makeVM()`이 이미 파일에 있다**(`DietPickTests.swift`의 `MealItemPickViewModelTests`). 그대로 쓴다.

- [ ] **Step 2: 실패를 확인한다**

기대: `has no member 'selectFilter'`, `has no member 'searchSources'`.

- [ ] **Step 3: 앱 필터를 지우고 이름을 바꾼다**

`MealItemPickViewModel.swift:128-136`을 바꾼다:

```swift
    /// 검색결과 탭 목록. **서버가 이미 `dataset`으로 거른 결과다** — 여기서 또 거르지 않는다.
    /// 두 곳에서 거르면 기준이 어긋나는 날 「검색은 됐는데 목록이 빈」 상태가 다시 생긴다.
    var searchSources: [FoodPickSource] { searchResults.map(FoodPickSource.food) }
```

- [ ] **Step 4: 빈 상태 문구의 판정 기준을 옮긴다**

`:142-150`을 바꾼다:

```swift
    /// 검색결과 탭이 비었을 때 무엇을 보여줄지. **셋을 가른다** — 아직 검색 전인지, 정말
    /// 없는지, 칩 때문인지가 사용자에게 다른 다음 행동을 뜻한다.
    ///
    /// **기준이 「칩이 걸려 있나」다.** 예전에는 「받아 온 것과 거른 것이 다른가」로 갈랐는데,
    /// 서버가 거르는 지금은 그 둘이 항상 같아 세 번째 가지가 영영 안 밟힌다.
    var searchEmptyText: String? {
        guard searchSources.isEmpty else { return nil }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "찾을 음식을 검색해 주세요."
        }
        guard filter == .all else {
            return "「\(filter.label)」에는 검색 결과가 없어요. 「전체」로 보거나 검색어를 바꿔 보세요."
        }
        return "검색 결과가 없어요. 다른 이름으로 찾아 보세요."
    }
```

- [ ] **Step 5: 칩 전환이 재검색을 부르게 한다**

`:176`의 `func search()` 바로 위에 넣는다:

```swift
    /// 칩을 고른다. **칩이 곧 쿼리라 다시 검색해야 한다** — 서버가 `dataset`으로 거르므로
    /// 이미 받아 둔 결과를 다시 쓸 수 없다.
    ///
    /// `search()`가 `searchGeneration`을 올리므로 **먼저 나간 칩의 응답이 늦게 돌아와
    /// 덮어쓰는 일은 그쪽에서 막힌다** — 칩을 빠르게 두 번 누르는 경로가 이번에 새로 생긴다.
    func selectFilter(_ newFilter: DatasetFilter) async {
        guard newFilter != filter else { return }
        filter = newFilter
        await search()
    }
```

`search()`의 서비스 호출은 **Task 2에서 이미 `dataset: filter.dataset`을 싣도록 고쳤다** — 여기서 다시 손대지 않는다.

- [ ] **Step 6: 화면을 맞춘다**

`MealItemEditView.swift:120`:

```swift
                        vm.filter = option
```
→
```swift
                        Task { await vm.selectFilter(option) }
```

`:144`:

```swift
            pickList(vm.filteredSearchSources, emptyText: vm.searchEmptyText ?? "")
```
→
```swift
            pickList(vm.searchSources, emptyText: vm.searchEmptyText ?? "")
```

`DietPickTests.swift`에 남아 있는 `filteredSearchSources` 참조(`:391`, `:411`, `:433`, `:440`, `:460`, `:467`)도 전부 `searchSources`로 바꾼다.

- [ ] **Step 7: 통과를 확인한다**

기대: **279개** — 277에서 `필터_칩이_데이터셋으로_거른다` 하나를 지우고 셋을 더했으니 순증 2다.

- [ ] **Step 8: 고의 파손 확인**

세 가지를 각각 확인한다:
1. `selectFilter`에서 `await search()`를 지운다 → `칩을_바꾸면…`이 빨개진다
2. `searchSources`에 `.filter { filter.dataset == nil || $0.dataset == filter.dataset }`를 도로 넣는다 → `앱은_데이터셋으로_더_거르지_않는다`가 빨개진다
3. `searchEmptyText`의 `guard filter == .all` 가지를 지운다 → `칩이_걸린_채…`가 빨개진다

셋 다 되돌리고 `git diff`로 확인한다.

- [ ] **Step 9: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 데이터셋 칩이 서버 검색을 다시 부른다

칩이 곧 쿼리가 되므로 앱에서 거르던 것을 지우고, 칩을 바꿀 때 다시 검색한다.

빈 상태 문구의 판정 기준도 옮긴다. 받아 온 것과 거른 것을 비교하던 조건은
서버가 거르는 지금 항상 같아져 세 번째 가지가 죽는다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
```

---

### Task 4: 검색 결과에 브랜드를 보여준다

**Files:**
- Modify: `WooriHaru/Models/FoodPickSource.swift:33` 아래
- Modify: `WooriHaru/Views/Diet/Components/FoodPickRow.swift:25-32` 근처
- Test: `WooriHaruTests/DietPickTests.swift`

**Interfaces:**
- Consumes: `Food.maker` (Task 1)
- Produces: `FoodPickSource.brandText: String?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`DietPickTests.swift`의 `FoodPickSource` 관련 스위트에 더한다(없으면 `struct FoodPickSourceTests`를 새로 만든다):

```swift
/// **브랜드는 검색 결과에만 있다.** `FrequentItem`은 저장된 `MealItem`에서 만들어지는데
/// 서버가 브랜드를 끼니에 저장하지 않는다 — `dataset`이 없는 것과 같은 이유다.
@Test func 브랜드는_검색_결과에만_붙는다() {
    let branded = FoodPickSource.food(makePickFood("피자_뉴욕 오리진", maker: "도미노피자"))
    let plain = FoodPickSource.food(makePickFood("제육볶음"))
    let frequent = FoodPickSource.frequent(makeFrequent())

    #expect(branded.brandText == "도미노피자")
    #expect(plain.brandText == nil)
    #expect(frequent.brandText == nil)
}
```

- [ ] **Step 2: 실패를 확인한다** — `has no member 'brandText'`

- [ ] **Step 3: `brandText`를 더한다**

`FoodPickSource.swift`의 `badge` 바로 아래:

```swift
    /// 「도미노피자」. **검색 결과에만 있다** — 자주 드셨어요는 저장된 항목이라 브랜드가 없다.
    ///
    /// 식품명에 브랜드가 안 들어 있어서(`피자_뉴욕 오리진 피자 오리지널 (L)`) 이 값이 없으면
    /// 「도미노」로 검색해 나온 결과를 보고도 왜 나왔는지 알 수 없다.
    var brandText: String? {
        switch self {
        case let .food(food): food.maker
        case .frequent: nil
        }
    }
```

- [ ] **Step 4: 행에 그린다**

`FoodPickRow.swift`의 배지 줄(`if let badge = source.badge { … }`) **바로 아래**, 같은 `HStack(spacing: 5)` 안에 넣는다:

```swift
                        if let brand = source.brandText {
                            Text(brand)
                                .font(.caption2)
                                .foregroundStyle(Color.blue500)
                                .lineLimit(1)
                        }
```

**이름 줄이 아니라 배지 줄이다** — 이름이 `피자_뉴욕 오리진 피자 오리지널 (L)`처럼 길어서 한 줄에 브랜드까지 넣으면 둘 다 잘린다. 배지와 달리 캡슐 배경을 두르지 않는다(브랜드는 분류가 아니라 정보다).

- [ ] **Step 5: `clean test`** — 기대 **280개**

- [ ] **Step 6: 고의 파손 확인**

`brandText`의 `.frequent`를 `nil` 대신 `"브랜드"`로 바꾼다 → 테스트가 빨개진다. 되돌린다.

- [ ] **Step 7: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 검색 결과에 브랜드를 보여준다

식품명에 브랜드가 없어서, 이 값이 없으면 도미노로 검색해 나온 결과를 보고도
왜 나왔는지 알 수 없다. 이름 줄이 아니라 배지 줄에 둔다 — 이름이 길어서 한 줄에
합치면 둘 다 잘린다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
```

---

### Task 5: 상세 시트에 포화지방·트랜스지방·콜레스테롤

**Files:**
- Modify: `WooriHaru/ViewModels/FoodDetailViewModel.swift:173-184`
- Test: `WooriHaruTests/DietPickTests.swift`

**Interfaces:**
- Consumes: `Food.saturatedFatPer100g / transFatPer100g / cholesterolMgPer100g` (Task 1)

**함정:** 이 셋은 `MealItemRequest`에 없고 **`Food`에만 100g당으로** 있다. `nutrientRows`가 지금은 `item`(=`MealItemRequest`)에서만 값을 꺼내므로, 새 줄은 `source`와 `quantityG`에서 직접 환산해야 한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
/// **셋은 `Food`에만 100g당으로 있다** — `MealItemRequest`에 없으므로 `item`이 아니라
/// 출처에서 직접 환산해야 한다. 지방 아래에 들여쓰고 콜레스테롤은 mg다.
@Test func 검색_결과는_포화지방_트랜스지방_콜레스테롤을_보여준다() {
    let vm = FoodDetailViewModel(source: .food(makePickFood(
        known: true, serving: 200, saturatedFat: 3, transFat: 0.4, cholesterol: 50
    )))

    let names = vm.nutrientRows.map(\.name)
    #expect(names == ["탄수화물", "당류", "단백질", "지방", "포화지방", "트랜스지방", "콜레스테롤", "나트륨", "식이섬유"])

    // 1인분 200g = 100g당 값의 2배.
    let rows = Dictionary(uniqueKeysWithValues: vm.nutrientRows.map { ($0.name, $0.valueText) })
    #expect(rows["포화지방"] == "6g")
    #expect(rows["트랜스지방"] == "0.8g")
    #expect(rows["콜레스테롤"] == "100mg")
}

/// **자주 드셨어요에는 이 값이 없다.** 서버가 끼니에 저장하지 않는다 — 0으로 그리면
/// 「없음」이 아니라 「진짜 0」으로 읽혀서, 포화지방 0인 음식으로 오해한다.
@Test func 자주_드셨어요에는_세_줄이_없다() {
    let vm = FoodDetailViewModel(source: .frequent(makeFrequent()))

    let names = vm.nutrientRows.map(\.name)
    #expect(!names.contains("포화지방"))
    #expect(!names.contains("트랜스지방"))
    #expect(!names.contains("콜레스테롤"))
    #expect(names == ["탄수화물", "당류", "단백질", "지방", "나트륨", "식이섬유"])
}
```

- [ ] **Step 2: 실패를 확인한다** — 줄 이름 목록이 안 맞아 빨개진다.

- [ ] **Step 3: `nutrientRows`를 고친다**

`FoodDetailViewModel.swift:173-184`를 바꾼다:

```swift
    /// 참고 화면에 없는 **식이섬유**가 우리에게는 있어 한 줄이 더 붙는다.
    ///
    /// 포화지방·트랜스지방·콜레스테롤은 **검색 결과에만 있다** — `MealItemRequest`에 없고
    /// `Food`에 100g당으로만 있어서 `item`이 아니라 출처에서 직접 환산한다. 자주 드셨어요는
    /// 저장된 항목이라 값이 없고, **0으로 그리면 「없음」이 아니라 「진짜 0」으로 읽히므로**
    /// 줄 자체를 감춘다.
    var nutrientRows: [NutrientRow] {
        guard let item else { return [] }
        return [
            NutrientRow(name: "탄수화물", valueText: formattedGram(item.carbsG), isSub: false),
            NutrientRow(name: "당류", valueText: formattedGram(item.sugarG), isSub: true),
            NutrientRow(name: "단백질", valueText: formattedGram(item.proteinG), isSub: false),
            NutrientRow(name: "지방", valueText: formattedGram(item.fatG), isSub: false)
        ] + fatDetailRows + [
            NutrientRow(name: "나트륨", valueText: "\(Int(item.sodiumMg.rounded()).formatted())mg", isSub: false),
            NutrientRow(name: "식이섬유", valueText: formattedGram(item.fiberG), isSub: false)
        ]
    }

    /// 지방 아래 들여쓰는 두 줄과 콜레스테롤. 검색 결과에서만 나온다.
    ///
    /// **서버가 값 없는 칸을 0.0으로 채워 보내므로 「진짜 0」과 구분되지 않는다.** 검색
    /// 결과에서는 그대로 0으로 보여 준다 — 원본이 그렇게 왔다는 뜻이고, 그 이상은 알 수 없다.
    private var fatDetailRows: [NutrientRow] {
        guard case let .food(food) = source, let quantityG else { return [] }
        let cholesterol = NutritionMath.scale(per100g: food.cholesterolMgPer100g, quantityG: quantityG)
        return [
            NutrientRow(
                name: "포화지방",
                valueText: formattedGram(NutritionMath.scale(per100g: food.saturatedFatPer100g, quantityG: quantityG)),
                isSub: true
            ),
            NutrientRow(
                name: "트랜스지방",
                valueText: formattedGram(NutritionMath.scale(per100g: food.transFatPer100g, quantityG: quantityG)),
                isSub: true
            ),
            NutrientRow(
                name: "콜레스테롤",
                valueText: "\(Int(cholesterol.rounded()).formatted())mg",
                isSub: false
            )
        ]
    }
```

**화면은 안 고쳐도 된다** — `FoodDetailSheet`가 `nutrientRows`를 `ForEach`로 그리고 `isSub`로 들여쓴다.

- [ ] **Step 4: `clean test`** — 기대 **282개**

- [ ] **Step 5: 고의 파손 확인**

`fatDetailRows`의 `guard case let .food(food)`를 지우고 `.frequent`에서도 0으로 그리게 만든다 → `자주_드셨어요에는_세_줄이_없다`가 빨개진다. 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -F - <<'EOF'
feat: 상세 시트에 포화지방·트랜스지방·콜레스테롤을 보여준다

셋은 Food에만 100g당으로 있어서 MealItemRequest가 아니라 출처에서 직접 환산한다.
자주 드셨어요에는 값이 없으므로 줄을 감춘다 — 0으로 그리면 없음이 아니라
진짜 0으로 읽힌다.

Claude-Session: https://claude.ai/code/session_01X36YxRCjxps5N8d784HibC
EOF
```

---

## 실기기 확인 (사용자 몫)

시뮬레이터를 띄우지 않는다. 아래를 실기기로 확인한다.

- 「도미노」로 검색해 브랜드가 보이는지 — **안 보이면 DB 재적재가 안 된 것이다**(디코딩은 통과하므로 앱은 멀쩡히 돈다)
- 칩을 「가공식품」으로 바꾸면 목록이 실제로 바뀌는지, 「음식」 칩이 예전처럼 빈 목록이 되지 않는지
- 칩을 빠르게 여러 번 눌러도 마지막 칩의 결과가 남는지
- 결과가 0건일 때 칩이 걸려 있으면 「전체로 보라」고 하고, 「전체」면 그 말을 안 하는지
- 상세 시트에서 검색 결과에는 세 줄이 보이고 자주 드셨어요에는 안 보이는지

## 범위 밖

사용자 직접 등록 화면 · 브랜드로만 좁혀 보는 필터 · 브랜드별 목록 화면 ·
「자주 드셨어요」에 브랜드 싣기(서버가 `MealItem`에 저장하지 않는다).
