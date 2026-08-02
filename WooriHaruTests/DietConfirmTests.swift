import Testing
import Foundation
@testable import WooriHaru

@MainActor
struct MealConfirmViewModelTests {
    private func analyzedItem(_ name: String, kcal: Double = 300, sodium: Double = 900) -> AnalyzedItem {
        AnalyzedItem(
            foodName: name, foodCode: "D1", quantityG: 200, kcal: kcal,
            carbsG: 30, proteinG: 20, fatG: 10, sugarG: 5, sodiumMg: sodium, fiberG: 2,
            source: .dbMatched
        )
    }

    /// 서버가 같은 날 같은 끼니를 하나로 묶으므로, 저장 전에 그 사실을 알려 준다.
    @Test func 그날_같은_끼니가_이미_있으면_합쳐진다고_알린다() async {
        let service = FakeDietService()
        service.days = [makeDay(date: "2026-07-29", meals: [makeMeal(mealType: .breakfast)])]
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .breakfast, analysis: nil, service: service
        )

        await vm.loadExistingMeals()

        #expect(vm.mergeNoticeText == "이미 기록한 아침에 합쳐져요.")

        // 없는 끼니로 바꾸면 사라진다 — 새 카드가 생기는 것이 맞다.
        vm.mealType = .dinner
        #expect(vm.mergeNoticeText == nil)
    }

    /// 안내만으로는 놓친다 — **저장을 누른 순간에 한 번 더 묻는다.** 합쳐진 뒤에는 어느
    /// 항목이 이번 것이었는지 구분되지 않아 되돌릴 수 없다.
    @Test func 합쳐지는_저장은_확인을_한_번_받는다() async {
        let service = FakeDietService()
        service.days = [makeDay(date: "2026-07-29", meals: [makeMeal(mealType: .breakfast)])]
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .breakfast, analysis: nil, service: service
        )

        await vm.loadExistingMeals()

        #expect(vm.mergesIntoExisting)
        #expect(vm.mergeConfirmMessage?.contains("아침") == true)

        // **합쳐지지 않는 저장은 묻지 않는다** — 1탭이어야 한다. 확인이 번거로우면 저장
        // 없이 나가고, 그러면 LLM 비용은 나갔는데 기록이 남지 않는다.
        vm.mealType = .dinner
        #expect(!vm.mergesIntoExisting)
        #expect(vm.mergeConfirmMessage == nil)
    }

    /// 간식은 합쳐지지 않으므로 **묻지도 않는다.** 이 확인이 없으면 「전부 묻는다」로 잘못
    /// 짜도 위 테스트가 통과한다.
    @Test func 간식은_이미_있어도_확인을_받지_않는다() async {
        let service = FakeDietService()
        service.days = [makeDay(date: "2026-07-29", meals: [makeMeal(mealType: .snack)])]
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .snack, analysis: nil, service: service
        )

        await vm.loadExistingMeals()

        #expect(vm.existingMealTypes.contains(.snack))
        #expect(!vm.mergesIntoExisting)
        #expect(vm.mergeConfirmMessage == nil)
    }

    /// **간식은 묶지 않는다** — 본래 여러 번이라 합치면 점수가 뒤섞인다.
    /// 이 테스트가 없으면 「전부 묶인다」로 잘못 안내해도 통과한다.
    @Test func 간식은_이미_있어도_합쳐진다고_알리지_않는다() async {
        let service = FakeDietService()
        service.days = [makeDay(date: "2026-07-29", meals: [makeMeal(mealType: .snack)])]
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .snack, analysis: nil, service: service
        )

        await vm.loadExistingMeals()

        #expect(vm.existingMealTypes.contains(.snack))
        #expect(vm.mergeNoticeText == nil)
    }

    /// 조회가 실패해도 확인 화면은 그대로 쓸 수 있어야 한다 — 여기까지 오는 데 이미
    /// LLM 비용과 대기시간이 들었다.
    @Test func 하루_조회가_실패해도_확인_화면은_막히지_않는다() async {
        let service = FakeDietService()
        service.errors["fetchDay"] = dietServerError("INTERNAL_ERROR", status: 500)
        let vm = MealConfirmViewModel(
            date: Date.from("2026-07-29")!, mealType: .breakfast, analysis: nil, service: service
        )

        await vm.loadExistingMeals()

        #expect(vm.mergeNoticeText == nil)
        #expect(vm.errorMessage == nil)
    }

    private func twoPhotoAnalysis() -> MealAnalysis {
        makeAnalysis(photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [analyzedItem("제육볶음")]),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: false, items: [analyzedItem("제육볶음"), analyzedItem("공기밥")])
        ])
    }

    /// 사진 2가 실패한 채로 온 두 장짜리 분석 — 재시도 병합 테스트의 출발점.
    private func partialFailureAnalysis() -> MealAnalysis {
        makeAnalysis(photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [
                analyzedItem("제육볶음"), analyzedItem("공기밥", kcal: 200, sodium: 5)
            ]),
            AnalyzedPhoto(fileId: 12, url: nil, failed: true, items: [])
        ])
    }

    private func makeVM(_ analysis: MealAnalysis?, service: FakeDietService = .init()) -> MealConfirmViewModel {
        MealConfirmViewModel(date: Date.from("2026-07-29")!, mealType: .lunch, analysis: analysis, service: service)
    }

    /// **항목을 사진별로 묶어 보여준다** — "2번 사진의 제육볶음"과 "3번 사진의 제육볶음"이 따로
    /// 보여야 사용자가 같은 접시인지 판단할 수 있다.
    @Test func 항목이_사진별로_묶인다() {
        let vm = makeVM(twoPhotoAnalysis())

        #expect(vm.groups.count == 2)
        #expect(vm.groups[0].items.count == 1)
        #expect(vm.groups[1].items.count == 2)
        #expect(vm.allItems.count == 3)
    }

    @Test func 합계가_항목에서_계산된다() {
        let vm = makeVM(twoPhotoAnalysis())

        #expect(vm.totalKcal == 900)
        #expect(vm.totalCarbsG == 90)
    }

    /// **저장한 items가 전송된다 — 인식 원본이 아니다.**
    @Test func 삭제하고_수량을_바꾼_결과가_전송된다() async {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), service: service)
        let duplicated = vm.groups[1].items[0]
        vm.removeItem(duplicated, in: vm.groups[1].id)
        let remaining = vm.groups[0].items[0]
        vm.updateQuantity(400, of: remaining, in: vm.groups[0].id)

        await vm.save()

        let request = try! #require(service.confirmRequests.first)
        #expect(request.items.count == 2)
        #expect(request.analysisId == 100)
        #expect(request.date == "2026-07-29")
        #expect(request.mealType == .lunch)
        let changed = try! #require(request.items.first { $0.foodName == "제육볶음" })
        #expect(changed.quantityG == 400)
        #expect(changed.kcal == 600)
        #expect(changed.sodiumMg == 1800)
        #expect(vm.savedMealID == 200)
    }

    /// **주의 영양소 3필드가 인식 경로 끝까지 살아 있어야 한다.** 서버가 0을 조용히 받는다.
    @Test func 인식_경로의_주의_영양소가_요청까지_살아_있다() async {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), service: service)

        await vm.save()

        let items = try! #require(service.confirmRequests.first?.items)
        #expect(items.allSatisfy { $0.sodiumMg > 0 })
        #expect(items.allSatisfy { $0.sugarG > 0 })
        #expect(items.allSatisfy { $0.fiberG > 0 })
    }

    /// 사진 없는 기록 — `analysisId`가 빠지고 그룹이 하나뿐이며 `PhotoStrip`이 그릴 게 없다.
    @Test func 사진_없는_기록은_analysisId를_보내지_않는다() async {
        let service = FakeDietService()
        let vm = makeVM(nil, service: service)
        vm.addItem(NutritionMath.manualItem(
            name: "새우깡", quantityG: 40, kcal: 220, carbsG: 27,
            proteinG: 3, fatG: 11, sugarG: 2, sodiumMg: 280, fiberG: 1
        ), to: vm.groups[0].id)

        await vm.save()

        let request = try! #require(service.confirmRequests.first)
        #expect(request.analysisId == nil)
        #expect(request.items.count == 1)
        #expect(vm.photoURLs.isEmpty)
        #expect(!vm.hasPhotos)
    }

    /// 항목이 하나도 없으면 저장할 수 없다 — 서버가 빈 배열을 거절한다.
    @Test func 항목이_없으면_저장할_수_없다() {
        let vm = makeVM(nil)
        #expect(!vm.canSave)

        vm.addItem(NutritionMath.manualItem(
            name: "사과", quantityG: 200, kcal: 104, carbsG: 28,
            proteinG: 1, fatG: 0, sugarG: 21, sodiumMg: 2, fiberG: 5
        ), to: vm.groups[0].id)
        #expect(vm.canSave)
    }

    /// 저장 없이 이탈하면 `Meal` 생성 요청이 나가지 않는다. 확인 알럿을 띄울지는 화면이 정한다.
    @Test func 저장하지_않으면_생성_요청이_나가지_않는다() {
        let service = FakeDietService()
        let vm = makeVM(twoPhotoAnalysis(), service: service)
        vm.removeItem(vm.groups[0].items[0], in: vm.groups[0].id)

        #expect(service.confirmRequests.isEmpty)
        #expect(vm.hasChanges)
    }

    /// 프로필이 없으면 서버가 확정을 거절한다 — 프로필 화면으로 보낸다.
    @Test func 프로필이_없으면_프로필_화면으로_보낸다() async {
        let service = FakeDietService()
        service.errors["confirmMeal"] = dietServerError("PROFILE_NOT_FOUND", status: 404)
        let vm = makeVM(twoPhotoAnalysis(), service: service)

        await vm.save()

        #expect(vm.needsProfile)
        #expect(vm.savedMealID == nil)
    }

    /// 인식이 끝나기 전에는 저장 버튼을 잠근다 — 뜨면 앱 분기가 빠진 것이다.
    @Test func 확정_불가_응답은_안내로_바꾼다() async {
        let service = FakeDietService()
        service.errors["confirmMeal"] = dietServerError("ANALYSIS_NOT_CONFIRMABLE")
        let vm = makeVM(twoPhotoAnalysis(), service: service)

        await vm.save()

        #expect(vm.errorMessage != nil)
        #expect(vm.savedMealID == nil)
    }

    /// 실패한 사진도 그룹으로 남는다 — 감추면 사용자가 나머지가 어디 갔는지 알 수 없다.
    @Test func 실패한_사진도_그룹으로_남는다() {
        let vm = makeVM(makeAnalysis(photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [analyzedItem("제육볶음")]),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: true, items: [])
        ]))

        #expect(vm.groups.count == 2)
        #expect(vm.groups[1].failed)
        #expect(vm.groups[1].items.isEmpty)
    }

    /// **0으로 내리는 요청은 무시한다.** `rescaled`는 현재 수량이 0일 때 영양소를 그대로 두고
    /// 수량만 바꾸므로, 0을 한 번이라도 들여보내면 그 뒤로는 아무리 늘려도 영양소가 0에 묶인다.
    @Test func 수량을_0으로_내리면_무시된다() {
        let vm = makeVM(twoPhotoAnalysis())
        let item = vm.groups[0].items[0]

        vm.updateQuantity(0, of: item, in: vm.groups[0].id)

        #expect(vm.groups[0].items[0] == item)
    }

    /// 버그가 깨뜨렸던 왕복 — 바닥(0)을 찍으려던 시도가 무시되고 나면, 이어지는 증가가
    /// 원래 수량 기준으로 다시 비례해야 한다(0에 묶여 있으면 안 된다).
    @Test func 바닥을_찍으려다_실패한_뒤_늘리면_영양소가_비례해_돌아온다() {
        let vm = makeVM(twoPhotoAnalysis())
        let item = vm.groups[0].items[0]

        vm.updateQuantity(0, of: item, in: vm.groups[0].id)
        vm.updateQuantity(50, of: item, in: vm.groups[0].id)

        let scaled = vm.groups[0].items[0]
        #expect(scaled.quantityG == 50)
        #expect(scaled.kcal == 75)
        #expect(scaled.sodiumMg == 225)
        #expect(scaled.fiberG == 0.5)
    }

    /// **재시도로 다른 사진이 살아나도, 사용자가 고치던 사진의 편집은 그대로 남아야 한다.**
    /// 사진 1을 고치는 중에 사진 2의 재시도 결과가 도착해도 사진 1은 건드리지 않는다.
    @Test func 재시도_결과는_실패했던_사진에만_반영되고_편집중인_사진은_그대로다() {
        let vm = makeVM(partialFailureAnalysis())
        let rice = vm.groups[0].items[1]
        vm.updateQuantity(500, of: vm.groups[0].items[0], in: vm.groups[0].id)
        vm.removeItem(rice, in: vm.groups[0].id)
        let editedGroup0Items = vm.groups[0].items
        #expect(vm.hasChanges)

        let retried = makeAnalysis(photos: [
            // 사진 1 — 이미 성공했던 사진이라 서버가 다시 보내도 이 그룹은 병합 대상이 아니다.
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [analyzedItem("제육볶음"), analyzedItem("공기밥")]),
            // 사진 2 — 이번에 성공해서 새 항목을 들고 왔다.
            AnalyzedPhoto(fileId: 12, url: "u2", failed: false, items: [analyzedItem("된장찌개")])
        ])
        vm.applyRetriedAnalysis(retried)

        #expect(vm.groups[0].items == editedGroup0Items)
        #expect(vm.groups[0].items.count == 1)
        #expect(vm.groups[0].items[0].quantityG == 500)
        #expect(!vm.groups[1].failed)
        #expect(vm.groups[1].items.map(\.foodName) == ["된장찌개"])
    }

    /// **진행 중 응답은 병합하지 않는다.** 폴링이 `.pending`도 그대로 내보내는데, 그때
    /// 재시도 대상 사진이 「성공했는데 항목 0개」로 보이면 실패 표시가 지워지고, 뒤이어
    /// 도착하는 진짜 결과는 「아직 실패인 그룹」만 갱신하는 가드에 걸려 영영 무시된다.
    @Test func 인식이_끝나기_전_응답은_병합하지_않는다() {
        let vm = makeVM(partialFailureAnalysis())

        // 아직 진행 중인데 사진 2가 성공한 것처럼(항목 없이) 올라온 응답.
        let pending = MealAnalysis(id: 100, status: .pending, photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [analyzedItem("제육볶음"), analyzedItem("공기밥")]),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: false, items: [])
        ])
        vm.applyRetriedAnalysis(pending)

        #expect(vm.groups[1].failed)
        #expect(vm.groups[1].items.isEmpty)

        // 진짜 결과가 도착하면 그때 병합된다.
        let completed = MealAnalysis(id: 100, status: .completed, photos: [
            AnalyzedPhoto(fileId: 11, url: "u1", failed: false, items: [analyzedItem("제육볶음"), analyzedItem("공기밥")]),
            AnalyzedPhoto(fileId: 12, url: "u2", failed: false, items: [analyzedItem("된장찌개")])
        ])
        vm.applyRetriedAnalysis(completed)

        #expect(!vm.groups[1].failed)
        #expect(vm.groups[1].items.map(\.foodName) == ["된장찌개"])
    }

    /// 재시도해도 여전히 실패하면 아무 그룹도 건드리지 않는다.
    @Test func 재시도해도_여전히_실패하면_그대로_둔다() {
        let vm = makeVM(partialFailureAnalysis())
        let group0Before = vm.groups[0].items

        vm.applyRetriedAnalysis(partialFailureAnalysis())

        #expect(vm.groups[0].items == group0Before)
        #expect(vm.groups[1].failed)
        #expect(vm.groups[1].items.isEmpty)
    }
}

@MainActor
struct PhotolessMealTests {
    /// `photos`가 비어 있어도 화면이 그릴 것이 없을 뿐 깨지지 않는다.
    @Test func 사진이_없으면_그릴_것이_없다() {
        let vm = MealConfirmViewModel(date: Date(), mealType: .snack, analysis: nil, service: FakeDietService())

        #expect(vm.groups.count == 1)
        #expect(vm.groups[0].fileId == nil)
        #expect(vm.photoURLs.isEmpty)
        #expect(vm.failedFileIds.isEmpty)
        #expect(!vm.hasPhotos)
    }

    /// 확정 응답의 `photos`가 빈 배열이어도 상세가 깨지지 않는다.
    @Test func 사진_없는_끼니_상세도_깨지지_않는다() async {
        let service = FakeDietService()
        service.meals = [makeMeal(photos: [], items: [makeMealItem(name: "새우깡", code: nil, source: .llmEstimated)])]
        let vm = MealDetailViewModel(mealId: 1, service: service)

        await vm.load()

        #expect(vm.meal?.photos.isEmpty == true)
        #expect(vm.meal?.items.first?.source == .llmEstimated)
    }

    /// 직접 입력 경로의 주의 영양소가 확정 요청까지 살아 있다.
    @Test func 직접_입력_경로의_주의_영양소가_요청까지_살아_있다() async {
        let service = FakeDietService()
        let vm = MealConfirmViewModel(date: Date.from("2026-07-29")!, mealType: .snack, analysis: nil, service: service)
        vm.addItem(NutritionMath.manualItem(
            name: "포장 김밥", quantityG: 230, kcal: 430, carbsG: 60,
            proteinG: 12, fatG: 15, sugarG: 4, sodiumMg: 980, fiberG: 3
        ), to: vm.groups[0].id)

        await vm.save()

        let item = try! #require(service.confirmRequests.first?.items.first)
        #expect(item.sodiumMg == 980)
        #expect(item.sugarG == 4)
        #expect(item.fiberG == 3)
        #expect(item.foodCode == nil)
    }
}
