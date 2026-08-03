# 식품 검색 — 밀린 백엔드 변경 따라잡기 (iOS) 설계

작성일: 2026-08-02
짝 저장소: `toy-back` — 서버 작업은 **전부 끝나 있다.** 이 문서는 앱만 다룬다.

## 배경

백엔드가 7/30·8/2에 `GET /diet/foods`를 세 번 넓혔는데 앱이 따라가지 않았다.

| 서버가 주는 것 | 앱 | 넣은 날 |
| --- | --- | --- |
| `dataset` **쿼리 파라미터** | 안 보냄 — 받아 온 페이지를 앱에서 거른다 | 7/30 |
| `maker` (브랜드) | 모델에 없음 | 8/2 |
| `saturatedFatPer100g`·`transFatPer100g`·`cholesterolMgPer100g` | 모델에 없음 | 7/30 |

**지금 깨지는 건 없다.** Swift `Codable`은 모르는 키를 무시하므로 응답이 넓어져도 디코딩은
그대로 통과한다. 다만 서버가 이미 주는 값을 안 쓰고 있고, 그 탓에 화면에 남아 있는 문제가 있다.

---

## ⚠️ 먼저 읽을 함정 셋

### 함정 1 — `FoodDataset`가 옵셔널이 아니다. 서버가 값을 늘리면 **검색 결과가 통째로 날아간다**

```swift
enum FoodDataset: String, Codable, Hashable {
    case dish = "DISH"
    case raw = "RAW"
    case processed = "PROCESSED"
}

struct Food: Codable {
    let dataset: FoodDataset   // ← 옵셔널도 기본값도 없다
}
```

`Food`가 배열로 디코딩되므로 **한 건이라도 모르는 `dataset`이면 `[Food]` 전체가 실패**하고
검색 화면이 빈 목록이 된다. 서버에는 이미 「사용자 등록 식품(`USER`)」 계획이 있다
(`toy-back` 2026-08-02 대화). **그날 앱이 배포돼 있지 않으면 검색이 죽는다.**

**→ 모르는 값을 흡수한다.** `init(from:)`은 **`FoodDataset`에** 둔다 — `Food`에 두면 필드
14개를 손으로 풀어야 해서 새 필드를 넣을 때마다 빠뜨릴 자리가 생긴다.

```swift
enum FoodDataset: String, Codable, Hashable {
    case dish = "DISH"
    case raw = "RAW"
    case processed = "PROCESSED"
    /// 서버가 새 데이터셋을 늘렸을 때 **검색 결과 전체가 날아가지 않게** 흡수하는 값.
    /// 배지는 달지 않는다 — 이름을 모르니 지어내지 않는다.
    case unknown

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodDataset(rawValue: raw) ?? .unknown
    }
}
```

`badge`의 `switch`에 `.unknown: nil`을 더한다.

**알려진 한계:** `Food.id`가 `"\(dataset.rawValue)-\(code)"`라 `.unknown`끼리는 `"unknown-"`을
공유한다. 서버가 데이터셋을 **둘 이상** 늘리고 그 둘에 같은 `code`가 있으면 `id`가 겹쳐
목록에서 한 행이 사라진다. 그때 가서 `.unknown(String)`으로 원본을 들고 있으면 되고, 그 전에
미리 복잡하게 만들지 않는다 — 데이터셋 하나가 늘어나는 동안은 겹치지 않는다.

### 함정 2 — 서버 필터로 바꾸면 「빈 목록」 안내 문구의 전제가 바뀐다

지금 `searchEmptyText`는 세 경우를 가른다:

```
검색어 없음        → "찾을 음식을 검색해 주세요."
결과 없음          → "검색 결과가 없어요. ..."
필터가 다 걸러냄    → "이 검색 결과에는 「음식」이 없어요. 「전체」로 보거나 ..."
```

세 번째는 **앱이 거르기 때문에** 생기던 상태다. 서버가 걸러 주면 「받아 온 결과는 있는데
필터가 다 걸러낸」 경우가 **없어진다** — 서버가 그 데이터셋에서 0건을 준 것이라
「그 데이터셋에 없다」가 맞는 말이 된다.

**→ 문구와 함께 판정 조건도 바꾼다.** 지금은 `searchResults`(받아 온 것)와
`filteredSearchSources`(거른 것)를 비교해 셋을 가르는데, 서버가 거르면 **그 둘이 항상 같아져**
세 번째 가지가 영영 안 밟히는 죽은 코드가 된다. 문구만 고치고 조건을 그대로 두면 그렇게 된다.

가르는 기준을 「거르고 남았나」에서 **「칩이 걸려 있나」**로 옮긴다:

```
검색어 없음                   → "찾을 음식을 검색해 주세요."
결과 0건 + 칩이 「전체」        → "검색 결과가 없어요. 다른 이름으로 찾아 보세요."
결과 0건 + 칩이 걸려 있음      → "「음식」에는 검색 결과가 없어요. 「전체」로 보거나 검색어를 바꿔 보세요."
```

「전체로 보라」는 여전히 유효한 안내다 — 다른 데이터셋에는 결과가 있을 수 있다.

**칩을 바꾸면 재검색해야 한다.** 지금은 한 번 받아 온 결과를 앱에서 거르므로 칩 전환이
즉시 반영되지만, 서버 필터는 **칩이 곧 쿼리**다. `filter`가 바뀔 때 `search()`를 다시 부른다
— 안 하면 칩을 눌러도 목록이 그대로다.

### 함정 3 — 브랜드는 검색에만 있고 「자주 드셨어요」에는 없다

`maker`는 `Food`(검색 결과)에만 온다. `FrequentItem`은 저장된 `MealItem`에서 만들어지므로
브랜드가 없다 — `dataset`이 없는 것과 같은 이유다.

**→ `FoodPickSource.brandText`는 `.frequent`에서 nil이다.** `badge`가 이미 같은 모양이라
그 옆에 붙이면 된다. 두 출처가 다르다는 것을 화면이 이미 알고 있다.

---

## 해야 할 일

### 1. `Food` 모델 — 필드 넷 추가

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
    let servingSizeKnown: Bool
    let kcalPer100g: Double
    let carbsPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let sugarPer100g: Double
    let sodiumMgPer100g: Double
    let fiberPer100g: Double
    /// **상세 시트 표시 전용이다.** 서버가 끼니에 저장하지 않으므로 담은 뒤에는 사라진다 —
    /// 자주 드셨어요·사진 인식 항목에는 이 값이 없다(`toy-back` 설계의 A1 범위).
    let saturatedFatPer100g: Double
    let transFatPer100g: Double
    let cholesterolMgPer100g: Double

    var id: String { "\(dataset.rawValue)-\(code)" }
}
```

`maker`만 옵셔널이다. 나머지 셋은 서버가 값이 없을 때 `0.0`으로 채워 보낸다
(`FoodCsvParser`가 `?: 0.0`).

### 2. `FoodDataset` — 미지값 흡수

함정 1 참조.

### 3. `DietService.searchFoods` — `dataset` 파라미터를 보낸다

```swift
/// `size`는 서버 상한인 50이다.
///
/// **`dataset`을 서버로 넘긴다.** 앱에서 거르면 상위 50건이 전부 가공식품일 때
/// 「음식」 칩이 빈 목록이 된다 — 실제로 매칭되는 조리 음식이 뒤에 있는데도 그렇다.
/// 거르기는 페이징 **전에** 일어나야 한다.
func searchFoods(query: String, dataset: FoodDataset? = nil) async throws -> [Food] {
    var q = ["q": query, "size": "50"]
    if let dataset, dataset != .unknown { q["dataset"] = dataset.rawValue }
    let response: DataResponse<[Food]> = try await api.get("/diet/foods", query: q)
    return response.data ?? []
}
```

`.unknown`은 보내지 않는다 — 서버가 400을 준다(enum 변환 실패 → `BAD_REQUEST`).

`DietServing` 프로토콜도 함께 고친다. **기본값 `nil`을 두면 기존 호출부가 그대로 컴파일되므로
「고쳤는데 안 부르는」 상태가 조용히 남는다** — 호출부를 반드시 함께 확인한다.

### 4. `MealItemPickViewModel` — 앱 필터 제거, 칩 전환 시 재검색

- `filteredSearchSources`에서 `filter.dataset`으로 거르는 부분을 없앤다.
  서버가 이미 거른 결과다
- `filter`가 바뀌면 `search()`를 다시 부른다(함정 2)
- 진행 중인 이전 요청의 응답이 늦게 도착해 덮어쓰지 않도록 막는다 —
  **이 화면에 이미 같은 가드가 있다**(`7a1d035 fix: … 지난 검색 응답을 막는다`).
  칩 전환이 검색을 유발하게 되면 그 경로가 하나 늘어난다
- `searchEmptyText`의 **문구와 판정 조건**을 함께 갱신한다(함정 2) — 조건을 그대로 두면
  세 번째 가지가 죽은 코드가 된다

### 5. `FoodPickSource` — 브랜드 노출

```swift
/// 「도미노피자」. 검색 결과에만 있다(함정 3).
var brandText: String? {
    switch self {
    case let .food(food): food.maker
    case .frequent: nil
    }
}
```

`FoodPickRow`에서 `badge` 옆에 그린다. 이름이 `피자_뉴욕 오리진 피자 오리지널 (L)`처럼
길어서 **한 줄에 브랜드까지 넣으면 잘린다** — 배지 줄에 두거나 `detailText`에 합친다.

### 6. `FoodDetailViewModel` — 포화지방·트랜스지방·콜레스테롤

상세 시트에 세 줄을 더한다. **`.food`에서만 값이 있다** — `.frequent`는 저장된 항목이라
이 값이 없다. 없는 쪽은 줄을 감춘다(빈 값을 0으로 그리면 「없음」이 아니라 「0」으로 읽힌다).

수량 환산은 기존과 같다(`NutritionMath.scale(per100g:quantityG:)`).

---

## 테스트

- **`dataset`을 쿼리에 담아 보낸다** — 칩이 「음식」이면 `dataset=DISH`가 실린다.
  `.all`이면 파라미터가 아예 없다
- **칩을 바꾸면 재검색한다** — `api.getCalls`가 두 번 쌓이는지. 이 확인이 없으면
  「앱 필터만 지우고 재검색을 안 붙인」 구현이 통과한다
- **앱에서 더 거르지 않는다** — 서버가 `PROCESSED` 한 건을 줬는데 칩이 「음식」이어도
  그 한 건이 그대로 보이는지(서버를 믿는다)
- **모르는 `dataset`이 와도 목록이 살아난다** — `"USER"` 한 건이 섞인 응답을 디코딩해
  전체가 살아 있고 그 항목의 배지가 nil인지. **함정 1이 재현되는 자리다**
- **`maker`가 없는 행도 디코딩된다** — 키 자체가 빠진 JSON으로 고정
- **브랜드가 검색 결과에만 붙는다** — `.frequent`의 `brandText`가 nil
- **칩이 걸린 채 0건이면 「전체로 보라」고 안내한다** — 칩이 「전체」일 때와 문구가 다른지.
  이 확인이 없으면 판정 조건을 안 고쳐 죽은 가지를 남겨도 통과한다
- 기존 검색 테스트(`식품_검색은_q와_size를_붙인다`, `DietTests.swift:254`)가 그대로 통과하는지 —
  그 테스트의 주석이 「앱에서 거르기 때문에 size가 50」이라고 설명하므로 함께 고친다

**고의 파손 확인**을 권한다: `dataset`을 쿼리에서 빼면 첫 테스트가, 칩 전환 시 재검색을
없애면 두 번째가, `FoodDataset`의 `init(from:)`을 지우면 네 번째가 실제로 빨개져야 한다.
**두 저장소 모두 「구현이 망가져도 통과하는 테스트」로 여러 번 데였다.**

---

## 백엔드 배포와의 순서

**서버를 먼저 배포하고 나서 앱을 작업한다.** 이 저장소들의 규칙이다.

그래서 영양소 3종을 non-optional `Double`로 받는다(§1). 서버가 이미 주고 있는 값이므로
옵셔널로 감싸 봐야 화면에서 풀 일만 늘어난다.

**대신 순서를 어기면 검색이 통째로 죽는다.** 서버가 그 키들을 안 주면 `[Food]` 디코딩이
실패하고 — 함정 1과 **정확히 같은 사고**다. 앱 작업 전에 아래 둘을 눈으로 확인한다:

- [ ] 백엔드 `d1e3fd2`(`origin/develop`)가 **배포된 서버에 올라가 있다**
- [ ] **DB 재적재까지 끝났다**(`delete from food;` → 재기동). 안 하면 브랜드가 전부 null이다 —
      디코딩은 통과하지만(`maker`는 옵셔널) 이번 작업의 절반이 화면에 안 나온다

확인이 안 되면 앱 작업을 시작하지 않는다. 「일단 짜 두고 배포를 기다린다」가 이 사고의
가장 흔한 경로다 — 짜 두면 내보내게 된다.

## 범위 밖

사용자 직접 등록 화면 · 브랜드로만 좁혀 보는 필터 · 브랜드별 목록 화면 ·
「자주 드셨어요」에 브랜드 싣기(서버가 `MealItem`에 저장하지 않는다).
