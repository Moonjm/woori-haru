import Testing
import Foundation
@testable import WooriHaru

// MARK: - 픽스처

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

func makeFrequent(
    _ name: String = "사과",
    code: String? = "R1",
    quantityG: Double = 200,
    count: Int = 7
) -> FrequentItem {
    FrequentItem(
        foodName: name, foodCode: code, quantityG: quantityG, kcal: 104,
        carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
        source: .dbMatched, count: count, lastEatenOn: "2026-07-29"
    )
}

// MARK: - 출처

struct FoodPickSourceTests {
    /// 「1인분 (250g)」과 **1인분 기준 열량**. 150kcal/100g × 250g = 375kcal.
    @Test func 일인분을_아는_음식은_일인분_기준으로_보여준다() {
        let source = FoodPickSource.food(makePickFood(known: true, serving: 250))

        #expect(source.name == "제육볶음")
        #expect(source.detailText == "1인분 (250g)")
        #expect(source.kcalText == "375kcal")
    }

    /// **모르는 항목은 100g 기준이다.** 서버가 채운 200g으로 계산한 열량을 먼저 보여주면
    /// 그럴듯하게 틀린 수치를 각인시킨다 — 150kcal/100g × 200g = 300kcal가 아니라 150kcal다.
    @Test func 일인분을_모르는_음식은_100g_기준으로_보여준다() {
        let source = FoodPickSource.food(makePickFood("달걀", known: false, serving: 200))

        #expect(source.detailText == "100g 기준")
        #expect(source.kcalText == "150kcal")
    }

    /// 자주 드셨어요는 지난번 수량과 빈도를 쓴다.
    @Test func 자주_드셨어요는_지난번_수량과_빈도를_보여준다() {
        let source = FoodPickSource.frequent(makeFrequent(quantityG: 200, count: 7))

        #expect(source.detailText == "200g · 7회")
        #expect(source.kcalText == "104kcal")
    }

    /// 조리 음식은 기본값이라 배지를 달지 않고, 원재료·가공식품만 단다.
    @Test func 배지는_데이터셋이_있을_때만_붙는다() {
        #expect(FoodPickSource.food(makePickFood(dataset: .dish)).badge == nil)
        #expect(FoodPickSource.food(makePickFood(dataset: .raw)).badge == "원재료")
        #expect(FoodPickSource.food(makePickFood(dataset: .processed)).badge == "가공식품")
        #expect(FoodPickSource.frequent(makeFrequent()).badge == nil)
    }

    /// **⊕가 갈리는 자리다.** 1인분을 알면 그대로 담기고, 모르면 담을 기본 수량이 없다.
    @Test func 일인분을_모르는_음식은_즉시_담을_수_없다() {
        #expect(FoodPickSource.food(makePickFood(known: true)).canQuickAdd)
        #expect(FoodPickSource.food(makePickFood(known: false)).quickAddItem == nil)
        // 자주 드셨어요는 지난번 수량이 딸려 오므로 항상 담긴다.
        #expect(FoodPickSource.frequent(makeFrequent()).canQuickAdd)
    }

    /// **주의 영양소 3필드가 ⊕ 즉시 담기에서도 살아 있어야 한다** — 서버는 빠진 값을
    /// 검증 오류 없이 0으로 저장한다.
    @Test func 즉시_담기는_주의_영양소까지_환산한다() throws {
        let item = try #require(FoodPickSource.food(makePickFood(known: true, serving: 250)).quickAddItem)

        #expect(item.quantityG == 250)
        #expect(item.kcal == 375)
        #expect(item.sugarG == 7.5)
        #expect(item.sodiumMg == 1000)
        #expect(item.fiberG == 3.75)
        #expect(item.foodCode == "D9")
        #expect(item.source == .dbMatched)
    }

    /// 자주 드셨어요는 **다시 계산하지 않는다** — 저장된 값이 그대로 온다.
    @Test func 자주_드셨어요_즉시_담기는_저장된_값을_그대로_쓴다() throws {
        let item = try #require(FoodPickSource.frequent(makeFrequent(quantityG: 200)).quickAddItem)

        #expect(item.quantityG == 200)
        #expect(item.kcal == 104)
        #expect(item.sugarG == 21)
        #expect(item.sodiumMg == 2)
        #expect(item.fiberG == 4.8)
    }

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

    /// 목록에서 서로 다른 행으로 구분돼야 한다 — 코드는 데이터셋 안에서만 유일하다.
    @Test func 출처가_다르면_아이디가_다르다() {
        let food = FoodPickSource.food(makePickFood(code: "X1", dataset: .dish))
        let sameCodeOtherDataset = FoodPickSource.food(makePickFood(code: "X1", dataset: .raw))
        let frequent = FoodPickSource.frequent(makeFrequent(code: "X1"))

        #expect(food.id != sameCodeOtherDataset.id)
        #expect(food.id != frequent.id)
    }
}

// MARK: - 상세 시트

@MainActor
struct FoodDetailViewModelTests {
    /// 1인분을 아는 항목은 1인분 모드로 뜨고 수량이 1인분이다.
    @Test func 일인분을_알면_인분_모드로_열린다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        #expect(vm.unit == .serving)
        #expect(vm.servings == 1)
        #expect(vm.servingsText == "1인분")
        #expect(vm.servingSizeText == "1인분 = 250g")
        #expect(vm.showsUnitPicker)
        #expect(vm.quantityG == 250)
        #expect(try #require(vm.item).kcal == 375)
    }

    /// **수량이 인분 수에 비례한다** — `quantityG = servingSizeG × 인분수`이고 영양소 7개가 따라온다.
    @Test func 인분_수를_올리면_수량과_영양소가_함께_커진다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        vm.increaseServings()   // 1.5인분

        #expect(vm.servings == 1.5)
        #expect(vm.servingsText == "1.5인분")
        #expect(vm.quantityG == 375)

        let item = try #require(vm.item)
        #expect(item.quantityG == 375)
        #expect(item.kcal == 562.5)
        #expect(item.carbsG == 45)
        #expect(item.proteinG == 37.5)
        #expect(item.fatG == 26.25)
        #expect(item.sugarG == 11.25)
        #expect(item.sodiumMg == 1500)
        #expect(item.fiberG == 5.625)
    }

    /// **「반 그릇」이 가장 흔한 조정이다.** 한 번 내리면 0.5인분 = 125g, 열량도 절반.
    @Test func 인분은_0점5씩_움직이고_0점5_아래로_내려가지_않는다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        vm.decreaseServings()

        #expect(vm.servings == 0.5)
        #expect(vm.servingsText == "0.5인분")
        #expect(vm.quantityG == 125)
        #expect(try #require(vm.item).kcal == 187.5)

        // 하한을 넘어 내려가면 안 된다 — 0이 되면 영양소가 전부 0으로 굳는다.
        vm.decreaseServings()
        vm.decreaseServings()
        #expect(vm.servings == 0.5)
        #expect(try #require(vm.item).kcal == 187.5)
    }

    /// **1인분을 모르면 g 모드로 고정하고 수량을 비운다.** 단위 선택도 감춘다.
    @Test func 일인분을_모르면_g_모드로_고정되고_수량이_비어_있다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false, serving: 200)))

        #expect(vm.unit == .gram)
        #expect(vm.gramText.isEmpty)
        #expect(!vm.showsUnitPicker)
        #expect(vm.servingSizeText == nil)
        #expect(vm.servingSizeUnknownHint != nil)
        #expect(vm.quantityG == nil)
        #expect(vm.item == nil)
        #expect(!vm.canAdd)
    }

    /// **빠른 선택 칩** — 1인분을 모르는 항목의 타이핑을 대부분 없앤다.
    @Test func 빠른_선택_칩을_누르면_수량과_영양소가_따라온다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false, serving: 200)))

        #expect(vm.showsQuickGramChips)
        #expect(GramStepper.quickGrams == [50, 100, 200])

        vm.selectQuickGram(100)

        #expect(vm.gramText == "100")
        #expect(vm.quantityG == 100)
        let item = try #require(vm.item)
        #expect(item.kcal == 150)
        #expect(item.sodiumMg == 400)
        #expect(item.fiberG == 1.5)
    }

    /// **`> 0`만으로는 부족하다.** `inf`도 `1e300`도 통과하고, 그 값으로 만든 열량이
    /// `kcalText`의 `Int(...)`에서 트랩을 걸어 **앱이 그 자리에서 죽는다.**
    /// `isFinite`만 넣으면 `1e300`이 그대로 남는다.
    @Test func 터무니없는_그램수는_담기지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false)))

        for bad in ["inf", "1e300", "1e309"] {
            vm.gramText = bad
            #expect(vm.quantityG == nil, "\(bad)이 통과했다")
            #expect(vm.item == nil)
            #expect(!vm.canAdd)
            // 죽지 않고 그려져야 한다.
            #expect(vm.kcalText == "0kcal")
        }

        vm.gramText = "100"
        #expect(vm.canAdd)
    }

    /// **읽는 쪽만 막으면 부족하다.** 스테퍼는 `currentGram`을 쓰는데, 거기가 검증을 안 하면
    /// 붙여넣은 값이 그대로 들어와 `trimmedText`의 `Int(...)`에서 트랩을 건다.
    @Test func 터무니없는_값을_붙여넣고_스테퍼를_눌러도_죽지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false)))

        for bad in ["inf", "1e300"] {
            vm.gramText = bad
            vm.increaseGram()
            // 범위 밖이었으므로 25g부터 다시 센다.
            #expect(vm.gramText == "25")

            vm.gramText = bad
            vm.decreaseGram()
            #expect(vm.gramText == "25")
        }
    }

    /// 단위 전환도 같은 값을 쓴다 — **인분으로 바꾸는 것만으로 g 모드 검증을 우회하면 안 된다.**
    @Test func 터무니없는_값에서_인분으로_바꿔도_죽지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        vm.setUnit(.gram)
        vm.gramText = "1e300"

        vm.setUnit(.serving)

        #expect(vm.unit == .serving)
        #expect(vm.servings == 1)
        #expect(vm.servingsText == "1인분")
        #expect(vm.quantityG == 250)
    }

    /// **1인분 모드에서는 칩이 안 보인다** — 1인분을 아는 항목의 화면을 어지럽히지 않는다.
    @Test func 인분_모드에서는_빠른_선택_칩이_보이지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        #expect(vm.unit == .serving)
        #expect(!vm.showsQuickGramChips)

        vm.setUnit(.gram)
        #expect(vm.showsQuickGramChips)
    }

    /// g 스테퍼는 ±25이고 25 아래로 내려가지 않는다. 빠른 선택 칩(50·100·200)과 같은 격자라
    /// 칩으로 대강 맞추고 스테퍼로 다듬는 흐름이 된다.
    @Test func g_스테퍼는_25씩_움직이고_25_아래로_내려가지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false)))
        vm.selectQuickGram(50)

        vm.increaseGram()
        #expect(vm.gramText == "75")

        vm.decreaseGram()
        vm.decreaseGram()
        #expect(vm.gramText == "25")

        // 하한 아래로는 안 내려간다 — 0이 되면 영양소가 전부 0으로 굳는다.
        vm.selectQuickGram(100)
        for _ in 0..<10 { vm.decreaseGram() }
        #expect(vm.gramText == "25")
        #expect(try! #require(vm.item).kcal > 0)
    }

    /// **스테퍼 하한이 직접 입력까지 막지는 않는다.** 25g보다 잘게 넣고 싶으면 타이핑한다 —
    /// 사용자가 의도해 친 값을 25로 덮어쓰는 편이 더 나쁘다.
    @Test func 직접_입력은_스테퍼_하한에_묶이지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood("달걀", known: false)))

        vm.gramText = "5"

        #expect(vm.quantityG == 5)
        #expect(vm.canAdd)
    }

    /// 단위를 바꿔도 숫자가 튀지 않는다 — 지금 수량을 옮겨 담는다.
    @Test func 단위를_바꾸면_지금_수량이_옮겨진다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        vm.increaseServings()       // 1.5인분 = 375g

        vm.setUnit(.gram)
        #expect(vm.gramText == "375")

        vm.selectQuickGram(200)     // 200g = 0.8인분 → 가장 가까운 0.5 배수는 1.0
        vm.setUnit(.serving)
        #expect(vm.servings == 1)
        #expect(vm.quantityG == 250)
    }

    /// **0.5 배수로 반올림한다** — 정수 반올림이면 1.0이 되어 갈리는 값을 쓴다.
    /// 175g / 250g = 0.7 → 0.5 배수 반올림은 0.5, 정수 반올림은 1.0.
    @Test func g에서_인분으로_바꾸면_0점5_배수로_맞춘다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        vm.setUnit(.gram)
        vm.gramText = "175"

        vm.setUnit(.serving)

        #expect(vm.servings == 0.5)
        #expect(vm.quantityG == 125)
    }

    /// **하한이 없으면 0인분이 되어 영양소가 전부 0으로 굳는다.** 10g / 250g = 0.04 →
    /// 0.5 배수 반올림만 하면 0이다.
    @Test func g에서_인분으로_바꿔도_0인분이_되지_않는다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        vm.setUnit(.gram)
        vm.gramText = "10"

        vm.setUnit(.serving)

        #expect(vm.servings == 0.5)
        #expect(try! #require(vm.item).kcal > 0)
    }

    /// **자주 드셨어요는 저장된 절대값뿐이라 1인분 개념이 없다** — 지난번 수량이 채워진
    /// g 모드로 뜨고, 수량을 바꾸면 비례 환산한다(100g당 값이 남아 있지 않다).
    @Test func 자주_드셨어요는_지난번_수량의_g_모드로_열리고_비례_환산한다() throws {
        let vm = FoodDetailViewModel(source: .frequent(makeFrequent(quantityG: 200)))

        #expect(vm.unit == .gram)
        #expect(vm.gramText == "200")
        #expect(!vm.showsUnitPicker)
        #expect(try #require(vm.item).kcal == 104)

        vm.selectQuickGram(100)

        let halved = try #require(vm.item)
        #expect(halved.quantityG == 100)
        #expect(halved.kcal == 52)
        #expect(halved.sugarG == 10.5)
        #expect(halved.sodiumMg == 1)
        #expect(halved.fiberG == 2.4)
    }

    /// **프로필이 없으면 감춘다** — 목표가 없으면 비율에 의미가 없다.
    @Test func 일일목표_배지는_목표가_있을_때만_보인다() {
        let withTarget = FoodDetailViewModel(
            source: .food(makePickFood(known: true, serving: 250)), targetKcal: 2509
        )
        // 375 / 2509 = 14.9% → 15%
        #expect(withTarget.dailyGoalPercentText == "일일목표 15%")

        let withoutTarget = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        #expect(withoutTarget.dailyGoalPercentText == nil)
    }

    /// 참고 화면에 없는 **식이섬유**가 우리에게는 있다. 당류는 탄수화물 아래, 포화·트랜스지방은
    /// 지방 아래로 들여쓴다.
    ///
    /// **인덱스로 읽지 않는다** — 줄이 하나 늘 때마다 뒤 인덱스가 전부 밀려, 실패해도 멈추지
    /// 않는 `#expect` 뒤에서 범위를 벗어나면 테스트가 프로세스째 죽는다.
    @Test func 영양소_표는_하위_영양소를_들여쓴다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))

        let rows = vm.nutrientRows
        #expect(rows.map(\.name) == [
            "탄수화물", "당류", "단백질", "지방", "포화지방", "트랜스지방", "콜레스테롤", "나트륨", "식이섬유"
        ])

        let indented = Set(rows.filter(\.isSub).map(\.name))
        #expect(indented == ["당류", "포화지방", "트랜스지방"])

        let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.valueText) })
        #expect(values["탄수화물"] == "30g")
        #expect(values["당류"] == "7.5g")
        #expect(values["나트륨"] == "1,000mg")
        #expect(values["식이섬유"] == "3.8g")
        #expect(vm.kcalText == "375kcal")
    }

    /// **셋은 `Food`에만 100g당으로 있다** — `MealItemRequest`에 없으므로 `item`이 아니라
    /// 출처에서 직접 환산해야 한다. 콜레스테롤은 mg다.
    @Test func 검색_결과는_포화지방_트랜스지방_콜레스테롤을_보여준다() {
        let vm = FoodDetailViewModel(source: .food(makePickFood(
            known: true, serving: 200, saturatedFat: 3, transFat: 0.4, cholesterol: 50
        )))

        // 1인분 200g = 100g당 값의 2배.
        let values = Dictionary(uniqueKeysWithValues: vm.nutrientRows.map { ($0.name, $0.valueText) })
        #expect(values["포화지방"] == "6g")
        #expect(values["트랜스지방"] == "0.8g")
        #expect(values["콜레스테롤"] == "100mg")
    }

    /// **자주 드셨어요에는 이 값이 없다.** 서버가 끼니에 저장하지 않는다 — 0으로 그리면
    /// 「없음」이 아니라 「진짜 0」으로 읽혀서, 포화지방 0인 음식으로 오해한다.
    @Test func 자주_드셨어요에는_세_줄이_없다() {
        let vm = FoodDetailViewModel(source: .frequent(makeFrequent()))

        #expect(vm.nutrientRows.map(\.name) == ["탄수화물", "당류", "단백질", "지방", "나트륨", "식이섬유"])
    }

    /// **주의 영양소 3필드가 상세 시트 경로에서도 살아 있어야 한다.**
    @Test func 상세_시트에서_담아도_주의_영양소가_남는다() throws {
        let vm = FoodDetailViewModel(source: .food(makePickFood(known: true, serving: 250)))
        vm.setUnit(.gram)
        vm.selectQuickGram(100)

        let item = try #require(vm.item)
        #expect(item.sugarG == 3)
        #expect(item.sodiumMg == 400)
        #expect(item.fiberG == 1.5)
    }
}

// MARK: - 고르기 ViewModel

@MainActor
struct MealItemPickViewModelTests {
    private func makeVM(_ mode: MealItemPickMode = .addMany) -> (MealItemPickViewModel, FakeDietService) {
        let service = FakeDietService()
        service.profile = makeProfile()
        return (MealItemPickViewModel(mode: mode, service: service), service)
    }

    /// 진입하면 자주 드셨어요와 프로필을 함께 읽는다. **프로필은 상세 시트의 일일목표 %에만
    /// 쓰이므로 없어도 화면을 막지 않는다.**
    @Test func 진입하면_자주_드셨어요와_프로필을_읽는다() async {
        let (vm, service) = makeVM()
        service.frequentItems = [makeFrequent()]

        await vm.load()

        #expect(vm.frequentSources.count == 1)
        #expect(vm.targetKcal == 2509)
        #expect(service.frequentCallCount == 1)
        #expect(service.searchQueries.isEmpty)
    }

    @Test func 프로필_조회가_실패해도_고르기는_열린다() async {
        let (vm, service) = makeVM()
        service.frequentItems = [makeFrequent()]
        service.errors["fetchProfile"] = dietServerError("INTERNAL_ERROR", status: 500)

        await vm.load()

        #expect(vm.frequentSources.count == 1)
        #expect(vm.targetKcal == nil)
    }

    /// **검색어를 확정하면 검색결과 탭으로 자동 전환한다** — 결과가 다른 탭 뒤에 숨으면 안 된다.
    @Test func 검색하면_검색결과_탭으로_넘어간다() async {
        let (vm, service) = makeVM()
        service.foods = [makePickFood()]
        vm.query = "제육"

        #expect(vm.tab == .frequent)
        await vm.search()

        #expect(vm.tab == .search)
        #expect(service.searchQueries == ["제육"])
        #expect(vm.searchSources.count == 1)
    }

    /// 실패한 뒤 다시 검색해 성공하면 **지난 오류가 남아 있으면 안 된다** — 정상 결과 위에
    /// 낡은 오류 알림이 떠 있게 된다.
    @Test func 검색이_실패한_뒤_성공하면_지난_오류가_지워진다() async {
        let (vm, service) = makeVM()
        service.errors["searchFoods"] = dietServerError("INTERNAL_ERROR", status: 500)
        vm.query = "제육"

        await vm.search()

        #expect(vm.errorMessage != nil)

        service.errors["searchFoods"] = nil
        service.foods = [makePickFood()]

        await vm.search()

        #expect(vm.errorMessage == nil)
        #expect(vm.searchSources.count == 1)
    }

    /// **늦게 돌아온 옛 검색이 최신 결과를 덮으면 안 된다.** 먼저 나간 「제」를 게이트로
    /// 붙잡아 둔 채 「제육」을 끝내고, 그다음 「제」를 풀어 준다 — 토큰이 없으면 나중에 끝난
    /// 「제」가 이겨서 지금 검색어와 다른 결과가 화면에 남는다.
    @Test func 늦게_돌아온_옛_검색은_최신_결과를_덮지_않는다() async {
        let (vm, service) = makeVM()
        let gate = AsyncGate()
        service.searchGates = ["제": gate]
        service.foodsByQuery = [
            "제": [makePickFood("제자리걸음", code: "OLD")],
            "제육": [makePickFood("제육볶음", code: "NEW")]
        ]

        vm.query = "제"
        let stale = Task { await vm.search() }
        await gate.waitUntilBlocked()

        vm.query = "제육"
        await vm.search()

        #expect(vm.searchSources.map(\.name) == ["제육볶음"])
        #expect(!vm.isSearching)

        await gate.open()
        await stale.value

        // 옛 응답이 돌아온 뒤에도 최신 결과가 그대로여야 한다.
        #expect(vm.searchSources.map(\.name) == ["제육볶음"])
        #expect(!vm.isSearching)
        #expect(service.searchQueries == ["제", "제육"])
    }

    /// 검색 도중에 검색어를 지우고 확정하면, **진행 중이던 검색도 무효로 만들어야 한다.**
    /// 안 그러면 옛 요청이 아직 유효한 토큰을 들고 돌아와 빈 검색어 아래에 지운 결과를 도로 채운다.
    @Test func 검색어를_지우면_진행_중이던_검색도_버린다() async {
        let (vm, service) = makeVM()
        let gate = AsyncGate()
        service.searchGates = ["제": gate]
        service.foodsByQuery = ["제": [makePickFood("제자리걸음", code: "OLD")]]

        vm.query = "제"
        let stale = Task { await vm.search() }
        await gate.waitUntilBlocked()

        vm.query = ""
        await vm.search()

        #expect(vm.searchSources.isEmpty)
        #expect(!vm.isSearching)

        await gate.open()
        await stale.value

        // 옛 응답이 돌아와도 비어 있어야 한다.
        #expect(vm.searchSources.isEmpty)
        #expect(!vm.isSearching)
    }

    /// **칩이 곧 쿼리다.** 앱 필터를 지우기만 하고 재검색을 안 붙이면 칩을 눌러도 목록이
    /// 그대로다 — 이 테스트가 그 미완성을 잡는다.
    @Test func 칩을_바꾸면_그_데이터셋으로_다시_검색한다() async {
        let (vm, service) = makeVM()
        service.foods = [makePickFood("제육볶음", code: "D1")]
        vm.query = "제육"
        await vm.search()

        #expect(service.searchCalls.count == 1)
        #expect(service.searchCalls.first?.dataset == nil)

        await vm.selectFilter(.processed)

        #expect(vm.filter == .processed)
        #expect(service.searchCalls.count == 2)
        // **인덱스로 읽지 않는다.** `#expect`는 실패해도 멈추지 않으므로, 재검색이 없어
        // 호출이 1건일 때 `searchCalls[1]`을 읽으면 테스트가 실패가 아니라 **프로세스째
        // 죽어** 남은 테스트가 판정도 못 받는다(고의 파손 확인에서 실제로 겪었다).
        #expect(service.searchCalls.last?.dataset == .processed)
        #expect(service.searchCalls.last?.query == "제육")
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

    /// **새 검색이 시작되면 예전 결과를 버린다.** 안 버리면 요청이 도는 동안, 그리고 실패하면
    /// 영영, 새 칩 라벨 아래에 이전 결과가 남는다 — 「원재료」를 눌렀는데 가공식품이 목록에
    /// 있고 그걸 담을 수 있다.
    @Test func 검색이_실패하면_예전_결과를_남기지_않는다() async {
        let (vm, service) = makeVM()
        service.foods = [makePickFood("삼각김밥", code: "P1", dataset: .processed)]
        vm.query = "김"
        await vm.search()
        #expect(vm.searchSources.count == 1)

        service.errors["searchFoods"] = dietServerError("INTERNAL_ERROR", status: 500)
        await vm.selectFilter(.raw)

        #expect(vm.searchSources.isEmpty)
        #expect(vm.errorMessage != nil)
        // **「없다」가 아니라 「못 받았다」라고 해야 한다** — 알럿은 닫으면 사라지는데 목록은
        // 남아서, 「검색 결과가 없어요」를 띄우면 그 음식이 식품DB에 없다고 믿게 된다.
        #expect(vm.searchEmptyText == "검색에 실패했어요. 잠시 후 다시 시도해 주세요.")
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

    /// **검색결과 탭의 빈 상태는 셋을 가른다** — 아직 검색 전, 검색했지만 결과가 없음,
    /// 결과는 있지만 필터가 다 걸러냄. 셋을 뭉뚱그리면 필터가 원인인데 「검색해 주세요」가
    /// 떠서 사용자가 원인을 알 길이 없다.
    @Test func 검색_전에는_검색해_달라는_문구를_보여준다() {
        let (vm, _) = makeVM()

        #expect(vm.searchEmptyText == "찾을 음식을 검색해 주세요.")
    }

    @Test func 검색했는데_결과가_없으면_다른_이름을_권한다() async {
        let (vm, service) = makeVM()
        service.foods = []
        vm.query = "존재하지않는음식"

        await vm.search()

        #expect(vm.searchEmptyText == "검색 결과가 없어요. 다른 이름으로 찾아 보세요.")
    }

    // 「받아 온 결과는 있는데 앱 필터가 다 걸러낸」 상태는 **더 이상 생기지 않는다** — 서버가
    // 그 데이터셋에서 0건을 준 것이라 「그 데이터셋에 없다」가 맞는 말이다. 그 자리를
    // `칩이_걸린_채_결과가_없으면_전체로_보라고_안내한다`가 대신한다.

    @Test func 결과가_있으면_빈_문구가_없다() async {
        let (vm, service) = makeVM()
        service.foods = [makePickFood()]
        vm.query = "제육"
        await vm.search()

        #expect(vm.searchEmptyText == nil)
    }

    /// **⊕가 갈린다** — 1인분을 알면 바로 담기고, 모르면 상세 시트를 열라고 알린다.
    @Test func 일인분을_모르는_항목의_담기_버튼은_상세_시트를_연다() {
        let (vm, _) = makeVM()

        let known = FoodPickSource.food(makePickFood(known: true, serving: 250))
        let unknown = FoodPickSource.food(makePickFood("달걀", known: false, serving: 200))

        #expect(vm.quickAdd(unknown) == .needsDetail)
        #expect(vm.commitPicked().isEmpty)

        #expect(vm.quickAdd(known) == .collected)
        #expect(vm.commitPicked().count == 1)
    }

    /// 여러 개 모드 — 세 개를 담으면 원소 3개 배열이 나온다.
    @Test func 여러_개_모드는_모아_두었다가_한꺼번에_넘긴다() {
        let (vm, _) = makeVM(.addMany)
        let a = FoodPickSource.food(makePickFood("제육볶음", code: "D1"))
        let b = FoodPickSource.food(makePickFood("김치찌개", code: "D2"))

        #expect(vm.showsBottomBar)
        #expect(!vm.canCommitPicked)

        #expect(vm.quickAdd(a) == .collected)
        #expect(vm.quickAdd(b) == .collected)
        #expect(vm.quickAdd(a) == .collected)   // 같은 음식 2인분

        #expect(vm.canCommitPicked)
        #expect(vm.bottomBarText == "3개 담기")
        #expect(vm.pickedCount(for: a) == 2)
        #expect(vm.pickedCount(for: b) == 1)

        let committed = vm.commitPicked()
        #expect(committed.count == 3)
        #expect(committed.map(\.foodName) == ["제육볶음", "김치찌개", "제육볶음"])
    }

    /// **한 개 모드는 고르는 즉시 닫힌다** — 하단 바도 담김 배지도 없다.
    @Test func 한_개_모드는_바로_넘기고_바구니를_쓰지_않는다() {
        for mode in [MealItemPickMode.addOne, .replace(makeManualRequest())] {
            let service = FakeDietService()
            let vm = MealItemPickViewModel(mode: mode, service: service)
            let source = FoodPickSource.food(makePickFood(known: true, serving: 250))

            #expect(!vm.showsBottomBar)

            guard case let .commit(items) = vm.quickAdd(source) else {
                Issue.record("한 개 모드는 .commit이어야 한다: \(mode)")
                return
            }
            #expect(items.count == 1)
            #expect(items[0].quantityG == 250)
            #expect(vm.pickedCount(for: source) == 0)
            #expect(vm.commitPicked().isEmpty)
        }
    }

    /// **주의 영양소 3필드가 바구니를 거쳐도 살아 있어야 한다.**
    @Test func 바구니를_거쳐도_주의_영양소가_남는다() throws {
        let (vm, _) = makeVM(.addMany)
        vm.quickAdd(.food(makePickFood(known: true, serving: 250)))
        vm.quickAdd(.frequent(makeFrequent(quantityG: 200)))

        let items = vm.commitPicked()
        #expect(items.count == 2)
        #expect(items[0].sugarG == 7.5)
        #expect(items[0].sodiumMg == 1000)
        #expect(items[0].fiberG == 3.75)
        #expect(items[1].sugarG == 21)
        #expect(items[1].sodiumMg == 2)
        #expect(items[1].fiberG == 4.8)
    }

    /// 직접 등록 — `foodCode`는 `""`가 아니라 `nil`이고 `source`는 `.llmEstimated`다.
    @Test func 직접_등록은_코드를_보내지_않는다() throws {
        let (vm, _) = makeVM(.addOne)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"
        vm.manualKcal = "430"
        vm.manualCarbs = "60"
        vm.manualProtein = "12"
        vm.manualFat = "15"
        vm.manualSugar = "4"
        vm.manualSodium = "980"
        vm.manualFiber = "3"

        guard case let .commit(items) = try #require(vm.acceptManual()) else {
            Issue.record("한 개 모드의 직접 등록은 .commit이어야 한다")
            return
        }
        #expect(items[0].foodCode == nil)
        #expect(items[0].source == .llmEstimated)
        #expect(items[0].sugarG == 4)
        #expect(items[0].sodiumMg == 980)
        #expect(items[0].fiberG == 3)
    }

    @Test func 직접_등록에_이름이나_수량이_없으면_담을_수_없다() {
        let (vm, _) = makeVM(.addOne)

        #expect(vm.acceptManual() == nil)

        vm.manualName = "포장 김밥"
        #expect(vm.acceptManual() == nil)

        vm.manualQuantity = "0"
        #expect(vm.acceptManual() == nil)

        vm.manualQuantity = "230"
        #expect(vm.acceptManual() != nil)
    }

    /// **잘못 적힌 칸을 0으로 갈아 끼우면 안 된다.** 화면에는 적은 대로 남아 있어서 사용자는
    /// 자기 값이 들어간 줄 아는데, 저장된 것은 「나트륨 0mg」이다.
    @Test func 잘못_적힌_영양소는_0으로_바꾸지_않는다() {
        let (vm, _) = makeVM(.addOne)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"
        vm.manualKcal = "430"

        vm.manualSodium = "98O"   // 0이 아니라 알파벳 O
        #expect(vm.buildManualItem() == nil)
        #expect(vm.manualHint == "영양소는 0 이상 숫자로 넣어 주세요.")

        vm.manualSodium = "980"
        #expect(vm.buildManualItem() != nil)
        #expect(vm.manualHint == nil)
    }

    /// **음수는 서버가 거절하는데, 그러면 그 항목이 아니라 끼니 전체가 저장되지 않는다.**
    @Test func 음수_영양소는_담을_수_없다() {
        let (vm, _) = makeVM(.addOne)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"

        vm.manualCarbs = "-5"
        #expect(vm.buildManualItem() == nil)

        vm.manualCarbs = "5"
        #expect(vm.buildManualItem() != nil)
    }

    /// **빈 칸은 0이다** — 안 적은 것이지 잘못 적은 것이 아니다. 이 구분이 없으면 식이섬유를
    /// 비워 둔 사용자가 아무것도 담을 수 없게 된다.
    @Test func 비워_둔_영양소_칸은_0으로_본다() throws {
        let (vm, _) = makeVM(.addOne)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"
        vm.manualKcal = "430"
        // 나머지 칸은 그대로 비워 둔다.

        let item = try #require(vm.buildManualItem())
        #expect(item.kcal == 430)
        #expect(item.fiberG == 0)
        #expect(item.sodiumMg == 0)
    }

    /// `Double("inf")`는 `> 0`을 통과한다. 그 값은 JSON 인코딩에서 터져 **저장 자체가 실패한다.**
    ///
    /// **`1e300`도 막아야 한다** — 유한하지만 화면이 합계를 `Int(...)`로 그릴 때 트랩이 걸려
    /// 앱이 죽는다. `isFinite`만 넣으면 이 값이 그대로 통과한다.
    @Test func 터무니없는_수량은_담을_수_없다() {
        let (vm, _) = makeVM(.addOne)
        vm.manualName = "포장 김밥"

        for bad in ["inf", "1e300", "1e309"] {
            vm.manualQuantity = bad
            #expect(vm.buildManualItem() == nil, "\(bad)이 통과했다")
            #expect(vm.manualHint == "수량을 0보다 큰 숫자로 넣어 주세요.")
        }

        vm.manualQuantity = "230"
        #expect(vm.buildManualItem() != nil)
    }

    /// 영양소 칸도 같다 — 100,000kcal짜리 항목이 확인 화면 합계를 `Int(...)`로 그리다 죽인다.
    @Test func 터무니없는_영양소는_담을_수_없다() {
        let (vm, _) = makeVM(.addOne)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"

        vm.manualKcal = "1e300"
        #expect(vm.buildManualItem() == nil)

        vm.manualKcal = "430"
        #expect(vm.buildManualItem() != nil)
    }

    /// **여러 개 모드에서 직접 등록을 담으면 칸을 비운다** — 다음 항목이 앞 항목의
    /// 영양소를 물려받으면 이름만 다른 값이 조용히 담긴다.
    @Test func 직접_등록을_담으면_다음_입력을_위해_칸을_비운다() {
        let (vm, _) = makeVM(.addMany)
        vm.manualName = "포장 김밥"
        vm.manualQuantity = "230"
        vm.manualSodium = "980"
        vm.manualFiber = "3"

        #expect(vm.acceptManual() == .collected)

        #expect(vm.manualName.isEmpty)
        #expect(vm.manualQuantity.isEmpty)
        #expect(vm.manualSodium.isEmpty)
        #expect(vm.manualFiber.isEmpty)
        #expect(vm.buildManualItem() == nil)

        vm.manualName = "우유"
        vm.manualQuantity = "200"
        let second = vm.commitPicked()
        #expect(second.count == 1)   // 아직 두 번째는 안 담았다
        _ = vm.acceptManual()
        let both = vm.commitPicked()
        #expect(both.count == 2)
        #expect(both[1].foodName == "우유")
        #expect(both[1].sodiumMg == 0)   // 앞 항목의 980이 새 나가면 안 된다
        #expect(both[1].fiberG == 0)
    }

    /// 상세 시트에서 「추가하기」로 온 항목도 같은 길을 탄다.
    @Test func 상세_시트에서_온_항목도_모드를_따른다() {
        let source = FoodPickSource.food(makePickFood(known: false))
        let edited = NutritionMath.item(from: makePickFood(known: false), quantityG: 100)

        let (many, _) = makeVM(.addMany)
        #expect(many.accept(edited, from: source) == .collected)
        #expect(many.pickedCount(for: source) == 1)

        let (one, _) = makeVM(.addOne)
        #expect(one.accept(edited, from: source) == .commit([edited]))
        #expect(one.commitPicked().isEmpty)
    }

    /// 교체 모드는 무엇을 바꾸는지 화면에 적어 준다.
    @Test func 교체_모드는_대상을_제목_아래_적는다() {
        let target = makeManualRequest(name: "제육볶음")

        #expect(MealItemPickMode.replace(target).title == "음식 교체")
        #expect(MealItemPickMode.replace(target).replacingText == "「제육볶음」을 교체합니다")
        #expect(MealItemPickMode.addOne.title == "음식 추가")
        #expect(MealItemPickMode.addOne.replacingText == nil)
        #expect(MealItemPickMode.addMany.replacingText == nil)
    }

    private func makeManualRequest(name: String = "제육볶음") -> MealItemRequest {
        NutritionMath.manualItem(
            name: name, quantityG: 250, kcal: 375, carbsG: 30, proteinG: 25,
            fatG: 17, sugarG: 7, sodiumMg: 1000, fiberG: 3
        )
    }
}

@MainActor
struct MealDetailEditTargetTests {
    /// 교체 시트는 **무엇을 바꾸는지** 알아야 한다 — 옛 화면은 `current: nil`을 넘겨
    /// 대상을 안 보여줬다.
    @Test func 교체_대상을_편집용_요청으로_바꾼다() async throws {
        let service = FakeDietService()
        let target = makeMealItem(id: 7, name: "제육볶음", quantityG: 250, sodium: 1000)
        service.meals = [makeMeal(items: [makeMealItem(id: 6, name: "밥"), target])]
        let vm = MealDetailViewModel(mealId: 1, service: service)
        await vm.load()

        let request = try #require(vm.editableItem(matching: target))

        #expect(request.foodName == "제육볶음")
        #expect(request.quantityG == 250)
        #expect(request.sodiumMg == 1000)

        // 목록에 없는 항목이면 nil이다.
        #expect(vm.editableItem(matching: makeMealItem(id: 999)) == nil)
    }
}

/// 스펙의 「여는 곳 × 모드」 표 중 `MealConfirmView`의 두 행 — 새 항목이면 여러 개,
/// 기존 항목이면 한 개(교체)다. 이 매핑이 화면 밖에 있어야 단위 테스트가 닿는다.
struct MealConfirmEditTargetTests {
    @Test func 새_항목이면_여러_개_모드다() {
        let target = MealConfirmView.EditTarget(groupId: 0, item: nil)

        #expect(target.pickMode == .addMany)
    }

    @Test func 기존_항목이면_교체_모드다() {
        let item = NutritionMath.manualItem(
            name: "제육볶음", quantityG: 250, kcal: 375, carbsG: 30, proteinG: 25,
            fatG: 17, sugarG: 7, sodiumMg: 1000, fiberG: 3
        )
        let target = MealConfirmView.EditTarget(groupId: 0, item: item)

        #expect(target.pickMode == .replace(item))
    }
}
