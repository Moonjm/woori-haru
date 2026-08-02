import Foundation
import Testing
import UIKit
@testable import WooriHaru

/// 지정한 크기의 단색 JPEG을 만든다. 다운샘플이 실제로 픽셀을 줄이는지 보려면 원본이 커야 한다.
private func makeJPEG(width: Int, height: Int) -> Data {
    let size = CGSize(width: width, height: height)
    // scale = 1을 강제한다 — 그렇지 않으면 시뮬레이터 화면 배율(예: 3x)이 반영되어
    // 실제 JPEG 픽셀 크기가 width/height의 몇 배로 인코딩되고, 아래 테스트들이
    // 기대하는 원본 픽셀 크기와 어긋난다.
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    return image.jpegData(compressionQuality: 1.0)!
}

struct ImageDownsampleTests {
    @Test func 장변이_상한_이하로_줄어든다() throws {
        let original = makeJPEG(width: 2400, height: 1200)
        let data = try #require(UIImage.downsampledJPEG(from: original, maxDimension: 1024, quality: 0.8))
        let image = try #require(UIImage(data: data))

        #expect(max(image.size.width, image.size.height) <= 1024)
        #expect(data.count < original.count)
    }

    @Test func 상한보다_작은_이미지는_키우지_않는다() throws {
        let original = makeJPEG(width: 400, height: 300)
        let data = try #require(UIImage.downsampledJPEG(from: original, maxDimension: 1024, quality: 0.8))
        let image = try #require(UIImage(data: data))

        #expect(max(image.size.width, image.size.height) <= 400)
    }

    @Test func 이미지가_아닌_데이터는_nil() {
        #expect(UIImage.downsampledJPEG(from: Data("not an image".utf8), maxDimension: 1024, quality: 0.8) == nil)
    }
}

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

struct FoodDecodingTests {
    /// 서버 응답 두 건 — 하나는 아는 데이터셋, 하나는 **아직 모르는 값**.
    /// `maker` 키는 둘째에서 아예 빠져 있다.
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

struct NutritionMathTests {
    /// 서버 `Food.nutritionFor`와 같은 식이어야 한다 — `per100g × (quantityG / 100)`, 반올림 없음.
    @Test func 백그램당_값을_수량으로_환산한다() {
        #expect(NutritionMath.scale(per100g: 150, quantityG: 150) == 225)
        #expect(NutritionMath.scale(per100g: 150, quantityG: 100) == 150)
        #expect(NutritionMath.scale(per100g: 0, quantityG: 300) == 0)
        #expect(NutritionMath.scale(per100g: 150, quantityG: 0) == 0)
    }

    @Test func 검색_결과를_항목으로_옮기면_일곱_값이_모두_환산된다() {
        let item = NutritionMath.item(from: makeFood(), quantityG: 150)

        #expect(item.foodName == "제육볶음")
        #expect(item.foodCode == "D000001")
        #expect(item.quantityG == 150)
        #expect(item.kcal == 225)
        #expect(item.carbsG == 18)
        #expect(item.proteinG == 15)
        #expect(item.fatG == 10.5)
        #expect(item.sugarG == 4.5)
        #expect(item.sodiumMg == 600)
        #expect(item.fiberG == 2.25)
        #expect(item.source == .dbMatched)
    }

    /// 「1인분 300g·100g당 150kcal을 150g 먹으면 225kcal」 — 스펙의 기준 예시.
    @Test func 스펙의_기준_예시가_맞는다() {
        let item = NutritionMath.item(from: makeFood(servingSizeG: 300), quantityG: 150)
        #expect(item.kcal == 225)
    }

    @Test func 수량을_바꾸면_일곱_값이_비례해서_따라온다() {
        let original = NutritionMath.item(from: makeFood(), quantityG: 100)
        let doubled = NutritionMath.rescaled(original, to: 200)

        #expect(doubled.quantityG == 200)
        #expect(doubled.kcal == 300)
        #expect(doubled.carbsG == 24)
        #expect(doubled.proteinG == 20)
        #expect(doubled.fatG == 14)
        #expect(doubled.sugarG == 6)
        #expect(doubled.sodiumMg == 800)
        #expect(doubled.fiberG == 3)
        #expect(doubled.id == original.id)
    }

    /// 수량 0인 항목(직접 입력 도중)에서 0으로 나누지 않는다.
    @Test func 원래_수량이_0이면_수량만_바꾸고_영양소는_그대로_둔다() {
        var item = NutritionMath.item(from: makeFood(), quantityG: 100)
        item.quantityG = 0
        let changed = NutritionMath.rescaled(item, to: 50)

        #expect(changed.quantityG == 50)
        #expect(changed.kcal == item.kcal)
    }

    /// `servingSizeKnown == false`면 서버가 채운 200g 자리채움값이라 기본 수량으로 쓰면 안 된다.
    @Test func 일인분_미상이면_기본_수량이_없다() {
        #expect(NutritionMath.defaultQuantity(for: makeFood(servingSizeG: 250, servingSizeKnown: true)) == 250)
        #expect(NutritionMath.defaultQuantity(for: makeFood(servingSizeG: 200, servingSizeKnown: false)) == nil)
    }

    /// 인식 결과와 자주 먹는 음식은 **다시 계산하지 않고** 값을 그대로 옮긴다.
    @Test func 인식_결과와_자주_먹는_음식은_값을_그대로_옮긴다() {
        let analyzed = AnalyzedItem(
            foodName: "김치찌개", foodCode: nil, quantityG: 400,
            kcal: 320, carbsG: 20, proteinG: 18, fatG: 19,
            sugarG: 5, sodiumMg: 1800, fiberG: 3, source: .llmEstimated
        )
        let fromAnalyzed = NutritionMath.request(from: analyzed)
        #expect(fromAnalyzed.sodiumMg == 1800)
        #expect(fromAnalyzed.source == .llmEstimated)
        #expect(fromAnalyzed.foodCode == nil)

        let frequent = FrequentItem(
            foodName: "사과", foodCode: "R000012", quantityG: 200,
            kcal: 104, carbsG: 28, proteinG: 0.6, fatG: 0.4,
            sugarG: 21, sodiumMg: 2, fiberG: 4.8, source: .dbMatched,
            count: 7, lastEatenOn: "2026-07-29"
        )
        let fromFrequent = NutritionMath.request(from: frequent)
        #expect(fromFrequent.quantityG == 200)
        #expect(fromFrequent.kcal == 104)
        #expect(fromFrequent.fiberG == 4.8)
    }
}

struct DietDecodingTests {
    /// 서버가 실제로 내려주는 모양 그대로 디코드된다.
    @Test func 하루_응답을_디코드한다() throws {
        let json = """
        {"data":{"date":"2026-07-29","dayScore":74,"scoreBasis":null,"feedback":null,
        "totalKcal":1980.0,"carbsG":250.1,"proteinG":78.4,"fatG":62.0,"activeEnergyKcal":2400,
        "meals":[],"nutrientLimits":[{"name":"나트륨","intake":2850.0,"unit":"mg",
        "standardText":"2,300mg 이하","status":"WARN"}],"estimatedItemCount":2}}
        """
        let response = try JSONDecoder().decode(DataResponse<DailyDiet>.self, from: Data(json.utf8))
        let day = try #require(response.data)

        #expect(day.feedback == nil)
        #expect(day.estimatedItemCount == 2)
        #expect(day.nutrientLimits.first?.status == .warn)
        #expect(day.nutrientLimits.first?.standardText == "2,300mg 이하")
    }

    /// 기록 0건인 기간 — 세 값이 null로 와도 깨지지 않는다.
    @Test func 기록이_없는_기간_통계를_디코드한다() throws {
        let json = """
        {"data":{"from":"2026-07-22","to":"2026-07-28","recordedDays":0,"averageDayScore":null,
        "dailyScores":[],"averageIntake":null,"averageTargets":null,"topFoods":[]}}
        """
        let stats = try #require(try JSONDecoder().decode(DataResponse<DietStats>.self, from: Data(json.utf8)).data)

        #expect(stats.recordedDays == 0)
        #expect(stats.averageDayScore == nil)
        #expect(stats.averageIntake == nil)
        #expect(stats.dailyScores.isEmpty)
    }

    /// 사진 없이 기록한 끼니는 `photos`가 빈 배열이다.
    @Test func 사진_없는_끼니를_디코드한다() throws {
        let json = """
        {"data":{"id":7,"date":"2026-07-29","mealType":"SNACK","status":"COMPLETED","score":62,
        "scoreBasis":null,"totalKcal":180.0,"carbsG":24.0,"proteinG":2.0,"fatG":8.0,
        "sugarG":12.0,"sodiumMg":150.0,"fiberG":1.0,"feedback":null,"weightKg":70.0,
        "targetKcal":2509,"photos":[],"items":[]}}
        """
        let meal = try #require(try JSONDecoder().decode(DataResponse<Meal>.self, from: Data(json.utf8)).data)

        #expect(meal.photos.isEmpty)
        #expect(meal.mealType == .snack)
    }

    /// `analysisId`가 nil이면 키 자체가 빠진다 — 서버가 「사진 없는 기록」으로 받는다.
    @Test func 사진_없는_확정_요청에는_analysisId가_없다() throws {
        let request = MealConfirmRequest(date: "2026-07-29", mealType: .snack, analysisId: nil, items: [])
        let json = try #require(String(data: try JSONEncoder().encode(request), encoding: .utf8))

        #expect(!json.contains("analysisId"))
    }

    /// 로컬 식별자는 전송하지 않는다.
    @Test func 항목_요청에_로컬_id가_실리지_않는다() throws {
        let item = NutritionMath.manualItem(
            name: "새우깡", quantityG: 40, kcal: 220, carbsG: 27,
            proteinG: 3, fatG: 11, sugarG: 2, sodiumMg: 280, fiberG: 1
        )
        let json = try #require(String(data: try JSONEncoder().encode(item), encoding: .utf8))

        #expect(!json.contains("\"id\""))
        #expect(!json.contains("foodCode"))
        #expect(json.contains("\"sodiumMg\":280"))
    }
}

struct DietErrorCodeTests {
    private func serverError(_ code: String, status: Int = 400) -> Error {
        APIError.serverError(
            statusCode: status,
            message: #"{"status":\#(status),"message":"...","code":"\#(status)","error":"\#(code)"}"#
        )
    }

    /// **`code`가 아니라 `error` 필드를 본다** — `code`는 `"400"` 같은 상태 문자열이다.
    @Test func error_필드로_분기한다() {
        #expect(serverError("ANALYSIS_IN_PROGRESS").dietErrorCode == .analysisInProgress)
        #expect(serverError("ANALYSIS_NOT_RETRYABLE").dietErrorCode == .analysisNotRetryable)
        #expect(serverError("LLM_UNAVAILABLE", status: 503).dietErrorCode == .llmUnavailable)
        #expect(serverError("PROFILE_NOT_FOUND", status: 404).dietErrorCode == .profileNotFound)
    }

    @Test func 모르는_코드나_JSON이_아니면_nil() {
        #expect(serverError("SOMETHING_ELSE").dietErrorCode == nil)
        #expect(APIError.serverError(statusCode: 500, message: "Internal Server Error").dietErrorCode == nil)
        #expect(APIError.unauthorized.dietErrorCode == nil)
    }
}

struct DietServiceTests {
    @Test func 프로필이_없으면_nil을_돌려준다() async throws {
        let api = MockAPIClient()
        api.setError(
            APIError.serverError(statusCode: 404, message: #"{"status":404,"code":"404","error":"PROFILE_NOT_FOUND"}"#),
            for: "GET /diet/profile"
        )

        #expect(try await DietService(api: api).fetchProfile() == nil)
    }

    @Test func 식품_검색은_q와_size를_붙인다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/foods", result: DataResponse<[Food]>(data: []))

        _ = try await DietService(api: api).searchFoods(query: "제육")

        #expect(api.getCalls.first?.path == "/diet/foods")
        #expect(api.getCalls.first?.query["q"] == "제육")
        // **서버 상한인 50이다.** 필터 칩이 받아 온 페이지를 앱에서 거르기 때문에 페이지가
        // 작으면 상위 결과가 전부 가공식품일 때 「음식」 칩이 빈 목록을 보여준다.
        #expect(api.getCalls.first?.query["size"] == "50")
    }

    @Test func 자주_먹는_음식은_days와_size를_붙인다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/items/frequent", result: DataResponse<[FrequentItem]>(data: []))

        _ = try await DietService(api: api).fetchFrequentItems()

        #expect(api.getCalls.first?.query == ["days": "30", "size": "20"])
    }

    @Test func 기간_통계는_from과_to를_붙인다() async throws {
        let api = MockAPIClient()
        api.stubGet("/diet/stats", result: DataResponse<DietStats>(data: DietStats(
            from: "2026-07-22", to: "2026-07-28", recordedDays: 0, averageDayScore: nil,
            dailyScores: [], averageIntake: nil, averageTargets: nil, topFoods: []
        )))

        _ = try await DietService(api: api).fetchStats(from: "2026-07-22", to: "2026-07-28")

        #expect(api.getCalls.first?.query == ["from": "2026-07-22", "to": "2026-07-28"])
    }

    @Test func 사진_업로드는_files로_간다() async throws {
        let api = MockAPIClient()
        api.stubMultipart(fileIds: [11])

        let fileId = try await DietService(api: api).uploadPhoto(Data(repeating: 0xFF, count: 128))

        #expect(fileId == 11)
        #expect(api.multipartCalls.map(\.path) == ["/files"])
        #expect(api.multipartCalls.first?.byteCount == 128)
    }

    /// **필드 이름이 서버 `@RequestParam("file")`과 정확히 맞아야 한다** — 어긋나면 사진
    /// 업로드가 매번 400으로 죽는데, 로컬에서는 아무 신호도 없다. `MockAPIClient`가 아니라
    /// `APIClient`가 실제로 만드는 본문을 바이트 단위로 확인한다.
    @Test func 멀티파트_본문의_필드_이름은_file이다() throws {
        let body = APIClient.multipartBody(
            boundary: "Boundary-TEST",
            fileData: Data([0x01, 0x02, 0x03]),
            fileName: "photo.jpg",
            mimeType: "image/jpeg"
        )
        let text = try #require(String(data: body, encoding: .isoLatin1))

        #expect(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\""))
        #expect(text.contains("Content-Type: image/jpeg"))
        #expect(text.hasPrefix("--Boundary-TEST\r\n"))
        #expect(text.hasSuffix("--Boundary-TEST--\r\n"))
    }

    @Test func 끼니_삭제는_DELETE로_간다() async throws {
        let api = MockAPIClient()

        try await DietService(api: api).deleteMeal(id: 42)

        #expect(api.deleteCalls == ["/diet/meals/42"])
    }
}

struct MacroBarTests {
    /// 목표가 0이면 0으로 나누지 않는다 — 프로필 저장 전에도 화면이 그려져야 한다.
    @Test func 목표가_0이면_비율이_0이다() {
        #expect(MacroBar.ratio(intakeG: 50, targetG: 0) == 0)
        #expect(MacroBar.ratio(intakeG: 0, targetG: 0) == 0)
    }

    @Test func 비율은_목표_대비값이고_초과해도_잘리지_않는다() {
        #expect(MacroBar.ratio(intakeG: 50, targetG: 100) == 0.5)
        #expect(MacroBar.ratio(intakeG: 120, targetG: 100) == 1.2)
    }

    /// 막대 길이는 넘쳐도 화면 밖으로 나가지 않게 1로 자른다(비율 표시는 자르지 않는다).
    @Test func 막대_길이는_1을_넘지_않는다() {
        #expect(MacroBar.fill(intakeG: 120, targetG: 100) == 1.0)
        #expect(MacroBar.fill(intakeG: 50, targetG: 100) == 0.5)
    }

    /// **나트륨만 mg다.** 고정으로 "g"를 붙이면 `2000g / 2300g`처럼 천 배 틀린 값이 된다 —
    /// 영양 수치를 틀린 단위로 보여 주는 것이라 그냥 오타보다 나쁘다.
    @Test func 값에_주어진_단위를_붙인다() {
        #expect(MacroBar.valueText(intakeG: 2000, targetG: 2300, unit: "mg") == "2000mg / 2300mg")
        #expect(MacroBar.valueText(intakeG: 120.4, targetG: 300, unit: "g") == "120g / 300g")
    }
}

@MainActor
struct DietDisplayTests {
    /// **0이면 아무것도 그리지 않는다** — 항목 단위 「추정」 배지와 달리 여기서는 없음이 기본이다.
    @Test func 추정_건수는_0이면_표시하지_않는다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(estimatedItemCount: 0)]
        let vm = DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher())
        await vm.load()

        #expect(vm.estimatedNoticeText == nil)
    }

    @Test func 추정_건수가_있으면_몇_건인지_보여준다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(estimatedItemCount: 2)]
        let vm = DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher())
        await vm.load()

        #expect(vm.estimatedNoticeText == "추정 2건 포함")
    }

    /// **앱이 판정을 다시 하지 않는다** — 섭취량이 기준을 넘어도 서버가 `OK`라고 하면 `OK`다.
    /// 기준 문구도 서버 값을 그대로 쓴다.
    @Test func 주의_영양소는_서버_판정을_그대로_쓴다() async {
        let service = FakeDietService()
        service.profile = makeProfile()
        service.days = [makeDay(nutrientLimits: [
            NutrientLimit(name: "나트륨", intake: 9999, unit: "mg", standardText: "2,300mg 이하", status: .ok)
        ])]
        let vm = DietDayViewModel(service: service, energyFetcher: FakeActiveEnergyFetcher())
        await vm.load()

        let limit = try! #require(vm.day?.nutrientLimits.first)
        #expect(limit.status == .ok)
        #expect(limit.standardText == "2,300mg 이하")
    }

    /// 점수 근거도 마찬가지다 — 앱이 `percent`와 범위로 재판정하지 않는다.
    @Test func 점수_근거는_서버_status와_penalty를_그대로_쓴다() async {
        let service = FakeDietService()
        service.meals = [makeMeal()]
        let vm = MealDetailViewModel(mealId: 1, service: service)
        await vm.load()

        let macros = try! #require(vm.meal?.scoreBasis?.macros)
        #expect(macros[0].status == .over)
        #expect(macros[0].penalty == 20)
        #expect(macros[2].status == .inRange)
        #expect(macros[2].penalty == 0)
        #expect(vm.meal?.scoreBasis?.standard == "2025 한국인 영양소 섭취기준(KDRIs) 에너지적정비율")
    }
}

/// **주의 영양소 3필드가 경로 끝까지 살아 있는지.** 값이 *표시되는* 자리만 세고 *흘러가는*
/// 자리를 안 세면 「사진으로 기록한 모든 끼니가 나트륨 0」이 재현된다.
@MainActor
struct NutrientPassthroughTests {
    private func assertNutrientsSurvive(
        _ item: MealItemRequest,
        sugar: Double,
        sodium: Double,
        fiber: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let service = FakeDietService()
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .lunch, analysis: nil, service: service
        )
        vm.addItem(item, to: vm.groups[0].id)

        await vm.save()

        let sent = service.confirmRequests.first?.items.first
        #expect(sent?.sugarG == sugar, sourceLocation: sourceLocation)
        #expect(sent?.sodiumMg == sodium, sourceLocation: sourceLocation)
        #expect(sent?.fiberG == fiber, sourceLocation: sourceLocation)
    }

    /// ① 식품DB 검색 경로 — 100g당 값을 앱이 환산한다.
    @Test func 검색_경로() async {
        let food = Food(
            code: "D1", name: "제육볶음", maker: nil, dataset: .dish,
            servingSizeG: 250, servingSizeKnown: true,
            kcalPer100g: 150, carbsPer100g: 12, proteinPer100g: 10, fatPer100g: 7,
            sugarPer100g: 3, sodiumMgPer100g: 400, fiberPer100g: 1.5,
            saturatedFatPer100g: 2, transFatPer100g: 0.1, cholesterolMgPer100g: 30
        )
        await assertNutrientsSurvive(
            NutritionMath.item(from: food, quantityG: 250),
            sugar: 7.5, sodium: 1000, fiber: 3.75
        )
    }

    /// ② 직접 입력 경로 — 포장지 영양성분표 값을 그대로 담는다.
    @Test func 직접_입력_경로() async {
        await assertNutrientsSurvive(
            NutritionMath.manualItem(
                name: "포장 김밥", quantityG: 230, kcal: 430, carbsG: 60,
                proteinG: 12, fatG: 15, sugarG: 4, sodiumMg: 980, fiberG: 3
            ),
            sugar: 4, sodium: 980, fiber: 3
        )
    }

    /// ③ 자주 먹는 음식 경로 — 서버가 준 값을 다시 계산하지 않는다.
    @Test func 자주_먹는_음식_경로() async {
        let frequent = FrequentItem(
            foodName: "사과", foodCode: "R1", quantityG: 200, kcal: 104,
            carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
            source: .dbMatched, count: 7, lastEatenOn: "2026-07-29"
        )
        await assertNutrientsSurvive(
            NutritionMath.request(from: frequent),
            sugar: 21, sodium: 2, fiber: 4.8
        )
    }

    /// ④ 인식 결과 경로 — 미매칭 항목도 LLM 추정값이 들어온다. 0으로 덮으면 안 된다.
    @Test func 인식_결과_경로() async {
        let analyzed = AnalyzedItem(
            foodName: "김치찌개", foodCode: nil, quantityG: 400, kcal: 320,
            carbsG: 20, proteinG: 18, fatG: 19, sugarG: 5, sodiumMg: 1800, fiberG: 3,
            source: .llmEstimated
        )
        await assertNutrientsSurvive(
            NutritionMath.request(from: analyzed),
            sugar: 5, sodium: 1800, fiber: 3
        )
    }

    /// 수량을 고쳐도 세 필드가 함께 따라온다.
    @Test func 수량_변경_뒤에도_살아_있다() async {
        let analyzed = AnalyzedItem(
            foodName: "김치찌개", foodCode: nil, quantityG: 400, kcal: 320,
            carbsG: 20, proteinG: 18, fatG: 19, sugarG: 5, sodiumMg: 1800, fiberG: 3,
            source: .llmEstimated
        )
        let service = FakeDietService()
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .lunch, analysis: nil, service: service
        )
        vm.addItem(NutritionMath.request(from: analyzed), to: vm.groups[0].id)
        let item = vm.groups[0].items[0]
        vm.updateQuantity(200, of: item, in: vm.groups[0].id)

        await vm.save()

        let sent = try! #require(service.confirmRequests.first?.items.first)
        #expect(sent.sodiumMg == 900)
        #expect(sent.sugarG == 2.5)
        #expect(sent.fiberG == 1.5)
    }

    /// ⑤ 저장된 끼니 편집 경로 — `MealDetailViewModel.editableItems`가 살아남은 항목들을
    /// 다시 실어 보낸다. 항목 하나를 지우거나 고칠 때마다 **나머지 항목 전부**가 이 매핑을
    /// 거쳐 다시 전송되므로, 값이 표시되는 자리만 세면 이 경로가 `sugarG`를 몰래 지워도
    /// 걸리지 않는다("사진으로 기록한 모든 끼니가 나트륨 0"과 같은 종류의 사고).
    @Test func 저장된_끼니_편집_경로() async {
        let service = FakeDietService()
        let survivor = makeMealItem(id: 1, sugar: 12, sodium: 555, fiber: 6)
        let target = makeMealItem(id: 2, sugar: 20, sodium: 800, fiber: 9)
        service.meals = [makeMeal(items: [survivor, target]), makeMeal(score: 88, items: [survivor])]
        let vm = MealDetailViewModel(mealId: 1, service: service)
        await vm.load()

        // target을 지우면 남은 survivor가 editableItems를 거쳐 다시 전송된다.
        await vm.deleteItem(target)

        let sent = try! #require(service.updatedItems.first?.items.first)
        #expect(sent.sugarG == 12)
        #expect(sent.sodiumMg == 555)
        #expect(sent.fiberG == 6)
    }

    /// ⑥ ⊕ 즉시 담기 경로 — 목록에서 한 번에 담는다. 상세 시트를 거치지 않으므로
    /// 환산이 `FoodPickSource.quickAddItem` 한 곳에서만 일어난다.
    @Test func 즉시_담기_경로() async throws {
        let food = Food(
            code: "D1", name: "제육볶음", maker: nil, dataset: .dish,
            servingSizeG: 250, servingSizeKnown: true,
            kcalPer100g: 150, carbsPer100g: 12, proteinPer100g: 10, fatPer100g: 7,
            sugarPer100g: 3, sodiumMgPer100g: 400, fiberPer100g: 1.5,
            saturatedFatPer100g: 2, transFatPer100g: 0.1, cholesterolMgPer100g: 30
        )
        let item = try #require(FoodPickSource.food(food).quickAddItem)

        await assertNutrientsSurvive(item, sugar: 7.5, sodium: 1000, fiber: 3.75)
    }

    /// ⑦ 상세 시트 경로 — 수량·단위를 조정한 뒤 담는다. 자주 드셨어요 출처는 100g당 값이
    /// 없어 **비례 환산**을 타므로 검색 출처와 다른 코드 경로다.
    @Test func 상세_시트_경로() async throws {
        let frequent = FrequentItem(
            foodName: "사과", foodCode: "R1", quantityG: 200, kcal: 104,
            carbsG: 28, proteinG: 0.6, fatG: 0.4, sugarG: 21, sodiumMg: 2, fiberG: 4.8,
            source: .dbMatched, count: 7, lastEatenOn: "2026-07-29"
        )
        let vm = FoodDetailViewModel(source: .frequent(frequent))
        vm.selectQuickGram(100)
        let item = try #require(vm.item)

        await assertNutrientsSurvive(item, sugar: 10.5, sodium: 1, fiber: 2.4)
    }

    /// `MealItemRequest`가 7개 필드를 전부 직렬화하는지 — 하나라도 빠지면 서버가 0으로 받는다.
    @Test func 요청_본문에_일곱_필드가_모두_실린다() throws {
        let item = NutritionMath.manualItem(
            name: "테스트", quantityG: 100, kcal: 200, carbsG: 20,
            proteinG: 10, fatG: 5, sugarG: 3, sodiumMg: 400, fiberG: 2
        )
        let json = try #require(String(data: try JSONEncoder().encode(item), encoding: .utf8))

        for key in ["kcal", "carbsG", "proteinG", "fatG", "sugarG", "sodiumMg", "fiberG"] {
            #expect(json.contains("\"\(key)\""), "\(key)가 빠졌다")
        }
    }
}
