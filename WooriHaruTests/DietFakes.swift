import Foundation
@testable import WooriHaru

/// 특정 호출을 테스트가 원할 때까지 붙잡아 두는 게이트. 기본은 어떤 호출에도 연결돼 있지
/// 않아 있으나 마나다 — `generation` 토큰처럼 "응답이 늦게 돌아왔을 때"를 실제로 재현하고
/// 싶은 테스트만 opt-in으로 특정 호출에 연결한다. sleep 기반 지연은 타이밍에 기대게 되어
/// 경합 자체가 아니라 그 재현 여부가 다시 불안정해지므로, continuation으로 결정적으로 멈췄다
/// 푼다.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var hasArrived = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    /// 테스트 쪽: 대역 호출이 이미 게이트 안에서 멈췄다는 확인을 받고 나서 다음 단계로 넘어간다.
    func waitUntilBlocked() async {
        if hasArrived || isOpen { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    /// 대역 쪽: 여기서 멈춘다(이미 열려 있으면 바로 통과).
    func hold() async {
        if isOpen { return }
        hasArrived = true
        let toResume = arrivalWaiters
        arrivalWaiters.removeAll()
        toResume.forEach { $0.resume() }

        await withCheckedContinuation { waiters.append($0) }
    }

    /// 테스트 쪽: 멈춰 있던 호출을 풀어 준다.
    func open() {
        isOpen = true
        let toResume = waiters
        waiters.removeAll()
        toResume.forEach { $0.resume() }
    }
}

/// 호출을 기록하고 미리 넣어 둔 값을 돌려주는 식단 서비스 대역.
/// **응답을 배열로 넣으면 부를 때마다 다음 것을 준다** — 폴링 전이(PENDING → COMPLETED)를 만드는 데 쓴다.
/// 마지막 값에 도달하면 그 값을 계속 돌려준다(폴링이 몇 번 돌지 테스트가 알 필요 없게).
final class FakeDietService: DietServing, @unchecked Sendable {
    enum FakeError: Error { case unstubbed(String) }

    private let lock = NSLock()

    // 응답
    var profile: NutritionProfile?
    var analyses: [MealAnalysis] = []
    var meals: [Meal] = []
    var days: [DailyDiet] = []
    var foods: [Food] = []
    /// 키는 `searchFoods`에 넘어온 검색어. 있으면 그 검색어만 `foods` 대신 이 값을 준다 —
    /// 두 검색이 겹칠 때 어느 응답이 화면에 남았는지 구분하려는 테스트만 opt-in으로 채운다.
    var foodsByQuery: [String: [Food]] = [:]
    /// 키는 `searchFoods`에 넘어온 검색어. 있으면 그 검색만 값을 돌려주기 직전에 멈춘다 —
    /// 먼저 나간 검색을 실제로 붙잡아 두어 늦게 돌아온 옛 응답이 최신 결과를 덮어쓰지
    /// 않는지(`searchGeneration` 토큰) 검증하는 테스트만 opt-in으로 채운다.
    var searchGates: [String: AsyncGate] = [:]
    var frequentItems: [FrequentItem] = []
    var stats: DietStats?
    /// 키는 `fetchStats`에 넘어온 `from` 값. 있으면 그 범위만 `stats` 대신 이 값을 준다 —
    /// 토글이 응답을 기다리는 도중 다시 바뀌어도 최신 선택의 응답이 이기는지, 범위별로
    /// 서로 다른 응답을 구분해서 검증하고 싶은 테스트만 opt-in으로 채운다.
    var statsByFrom: [String: DietStats] = [:]
    /// 키는 `fetchStats`에 넘어온 `from` 값. 있으면 그 범위의 호출만 값을 돌려주기 직전에
    /// 멈춘다 — 위 시나리오에서 먼저 나간 호출을 실제로 붙잡아 두는 데 쓴다.
    var statsGates: [String: AsyncGate] = [:]
    var uploadFileIds: [Int] = []
    var createdAnalysisId = 100
    var confirmedMealId = 200

    // 던질 에러 — 키는 메서드 이름
    var errors: [String: Error] = [:]
    /// `retryAnalysis`가 첫 호출에만 던지게 한다(연타 테스트).
    var retryErrorOnce: Error?
    /// 키는 `fetchDay(date:)`에 실제로 넘어온 날짜 문자열. 있으면 그 날짜의 호출만 값을
    /// 돌려주기 직전에 멈춘다 — 두 날짜의 조회가 실제로 겹치게 만들어 `generation` 토큰이
    /// 늦게 돌아온 이전 응답을 버리는지 검증하는 테스트만 opt-in으로 채운다.
    var fetchDayGates: [String: AsyncGate] = [:]
    /// 키는 `uploadPhoto` 호출 순번(0부터). 있으면 그 순번의 업로드만 값을 돌려주기 직전에
    /// 멈춘다 — 업로드가 진행 중인 순간의 진행률 표시를 실제로 관찰하는 테스트만 opt-in으로 채운다.
    var uploadGates: [Int: AsyncGate] = [:]
    /// 있으면 `updateMealItems` 호출이 값을 돌려주기 직전에 멈춘다 — 첫 번째 항목 변경이
    /// 응답을 받기 전에 두 번째 변경을 시도해도 요청이 실제로 겹치지 않는지(진행 중 가드)
    /// 검증하는 테스트만 opt-in으로 채운다.
    var updateMealItemsGate: AsyncGate?
    /// 있으면 `updateWeight` 호출이 값을 돌려주기 직전에 멈춘다 — 몸무게 저장·재조회가 끝나기
    /// 전에 더 새로운 `load()`가 끼어들어도 늦게 도착한 몸무게 갱신 결과가 화면을 덮어쓰지
    /// 않는지(generation 가드) 검증하는 테스트만 opt-in으로 채운다.
    var updateWeightGate: AsyncGate?
    /// 있으면 `deleteMealPhoto` 호출이 돌아가기 직전에 멈춘다 — 삭제가 진행 중일 때 두 번째
    /// 삭제를 실제로 시도해 보는(진행 중 가드) 테스트만 opt-in으로 채운다.
    var deleteMealPhotoGate: AsyncGate?

    // 기록
    private(set) var uploadedByteCounts: [Int] = []
    private(set) var createdFileIds: [[Int]] = []
    private(set) var fetchedAnalysisIds: [Int] = []
    private(set) var retriedAnalysisIds: [Int] = []
    private(set) var confirmRequests: [MealConfirmRequest] = []
    private(set) var fetchedMealIds: [Int] = []
    private(set) var updatedItems: [(id: Int, items: [MealItemRequest])] = []
    private(set) var deletedMealIds: [Int] = []
    private(set) var deletedPhotos: [(mealId: Int, fileId: Int)] = []
    private(set) var fetchedDates: [String] = []
    private(set) var activityCalls: [(date: String, kcal: Int)] = []
    private(set) var searchQueries: [String] = []
    private(set) var frequentCallCount = 0
    private(set) var statsRanges: [(from: String, to: String)] = []
    private(set) var savedProfiles: [NutritionProfileRequest] = []
    private(set) var savedWeights: [Double] = []

    private var analysisCursor = 0
    private var mealCursor = 0
    private var dayCursor = 0

    private func next<T>(_ values: [T], cursor: inout Int, label: String) throws -> T {
        guard !values.isEmpty else { throw FakeError.unstubbed(label) }
        let value = values[min(cursor, values.count - 1)]
        cursor += 1
        return value
    }

    private func check(_ key: String) throws {
        lock.lock()
        let error = errors[key]
        lock.unlock()
        if let error { throw error }
    }

    // MARK: - DietServing

    func fetchProfile() async throws -> NutritionProfile? {
        try check("fetchProfile")
        return profile
    }

    func saveProfile(_ request: NutritionProfileRequest) async throws {
        lock.lock(); savedProfiles.append(request); lock.unlock()
        try check("saveProfile")
    }

    func updateWeight(_ weightKg: Double) async throws {
        lock.lock(); savedWeights.append(weightKg); lock.unlock()
        if let updateWeightGate { await updateWeightGate.hold() }
        try check("updateWeight")
    }

    func uploadPhoto(_ jpegData: Data) async throws -> Int {
        lock.lock()
        let index = uploadedByteCounts.count
        uploadedByteCounts.append(jpegData.count)
        let gate = uploadGates[index]
        lock.unlock()

        if let gate { await gate.hold() }

        try check("uploadPhoto#\(index)")
        try check("uploadPhoto")
        guard index < uploadFileIds.count else { throw FakeError.unstubbed("uploadPhoto #\(index)") }
        return uploadFileIds[index]
    }

    func createAnalysis(fileIds: [Int]) async throws -> Int {
        lock.lock(); createdFileIds.append(fileIds); lock.unlock()
        try check("createAnalysis")
        return createdAnalysisId
    }

    func fetchAnalysis(id: Int) async throws -> MealAnalysis {
        lock.lock(); fetchedAnalysisIds.append(id); lock.unlock()
        try check("fetchAnalysis")
        lock.lock(); defer { lock.unlock() }
        return try next(analyses, cursor: &analysisCursor, label: "fetchAnalysis")
    }

    func retryAnalysis(id: Int) async throws {
        // `retryErrorOnce`의 읽기·클리어(read-and-clear)를 같은 락 안에서 원자적으로 처리한다 —
        // 그렇지 않으면 동시에 두 번 호출됐을 때 둘 다 nil이 아님을 보고 둘 다 던지거나,
        // "한 번만 던진다" 계약이 아예 지켜지지 않을 수 있다(연타 테스트가 이 경합을 잡아낸다).
        lock.lock()
        retriedAnalysisIds.append(id)
        let once = retryErrorOnce
        retryErrorOnce = nil
        let error = once ?? errors["retryAnalysis"]
        lock.unlock()
        if let error { throw error }
    }

    func confirmMeal(_ request: MealConfirmRequest) async throws -> Int {
        lock.lock(); confirmRequests.append(request); lock.unlock()
        try check("confirmMeal")
        return confirmedMealId
    }

    func fetchMeal(id: Int) async throws -> Meal {
        lock.lock(); fetchedMealIds.append(id); lock.unlock()
        try check("fetchMeal")
        lock.lock(); defer { lock.unlock() }
        return try next(meals, cursor: &mealCursor, label: "fetchMeal")
    }

    func updateMealItems(id: Int, items: [MealItemRequest]) async throws {
        lock.lock(); updatedItems.append((id, items)); lock.unlock()
        if let gate = updateMealItemsGate { await gate.hold() }
        try check("updateMealItems")
    }

    func deleteMeal(id: Int) async throws {
        lock.lock(); deletedMealIds.append(id); lock.unlock()
        try check("deleteMeal")
    }

    func deleteMealPhoto(mealId: Int, fileId: Int) async throws {
        lock.lock(); deletedPhotos.append((mealId, fileId)); lock.unlock()
        if let gate = deleteMealPhotoGate { await gate.hold() }
        try check("deleteMealPhoto")
    }

    func fetchDay(date: String) async throws -> DailyDiet {
        lock.lock(); fetchedDates.append(date); lock.unlock()
        try check("fetchDay")

        // 이 호출이 쓸 응답을 "도착한 순서"대로 먼저 확정해 둔다 — 게이트에 걸려 반환이
        // 늦어지는 호출이 있어도, 커서 진행 순서는 실제 요청 순서를 그대로 따른다.
        lock.lock()
        var result: DailyDiet?
        var thrown: Error?
        do {
            result = try next(days, cursor: &dayCursor, label: "fetchDay")
        } catch {
            thrown = error
        }
        let gate = fetchDayGates[date]
        lock.unlock()

        if let gate { await gate.hold() }
        if let thrown { throw thrown }
        return result!
    }

    func upsertActivity(date: String, activeEnergyKcal: Int) async throws {
        lock.lock(); activityCalls.append((date, activeEnergyKcal)); lock.unlock()
        try check("upsertActivity")
    }

    func searchFoods(query: String) async throws -> [Food] {
        lock.lock()
        searchQueries.append(query)
        let gate = searchGates[query]
        let override = foodsByQuery[query]
        lock.unlock()

        if let gate { await gate.hold() }
        try check("searchFoods")
        return override ?? foods
    }

    func fetchFrequentItems() async throws -> [FrequentItem] {
        lock.lock(); frequentCallCount += 1; lock.unlock()
        try check("fetchFrequentItems")
        return frequentItems
    }

    func fetchStats(from: String, to: String) async throws -> DietStats {
        lock.lock(); statsRanges.append((from, to)); lock.unlock()
        try check("fetchStats")

        lock.lock()
        let gate = statsGates[from]
        let override = statsByFrom[from]
        lock.unlock()

        if let gate { await gate.hold() }
        guard let result = override ?? stats else { throw FakeError.unstubbed("fetchStats") }
        return result
    }
}

/// 하루 활동 에너지 대역.
final class FakeActiveEnergyFetcher: ActiveEnergyFetching, @unchecked Sendable {
    var kcal: Double = 2400
    var errorToThrow: Error?
    /// `requestActiveEnergyAuthorization()`이 던질 에러 — 기기가 건강 데이터를 지원하지 않을 때를 흉내낸다.
    var authorizationErrorToThrow: Error?
    /// 있으면 값을 돌려주기 전에 여기서 멈춘다. 기본은 nil이라 아무 지연도 없다 — 조회 중에
    /// 날짜가 바뀌어도 시작한 날짜로 업로드하는지 확인하는 경합 테스트만 opt-in으로 채운다.
    var gate: AsyncGate?
    private(set) var requestedDates: [Date] = []
    private(set) var didRequestAuthorization = false

    func requestActiveEnergyAuthorization() async throws {
        didRequestAuthorization = true
        if let authorizationErrorToThrow { throw authorizationErrorToThrow }
    }

    func fetchActiveEnergy(on date: Date) async throws -> Double {
        requestedDates.append(date)
        if let gate { await gate.hold() }
        if let errorToThrow { throw errorToThrow }
        return kcal
    }
}

// MARK: - 픽스처

func makeMealItem(
    id: Int = 1,
    name: String = "제육볶음",
    code: String? = "D000001",
    quantityG: Double = 250,
    kcal: Double = 375,
    carbs: Double = 30,
    protein: Double = 25,
    fat: Double = 17,
    sugar: Double = 7,
    sodium: Double = 1000,
    fiber: Double = 3,
    source: NutritionSource = .dbMatched
) -> MealItem {
    MealItem(
        id: id, foodName: name, foodCode: code, quantityG: quantityG, kcal: kcal,
        carbsG: carbs, proteinG: protein, fatG: fat,
        sugarG: sugar, sodiumMg: sodium, fiberG: fiber, source: source
    )
}

func makeMeal(
    id: Int = 1,
    date: String = "2026-07-29",
    mealType: MealType = .lunch,
    status: AnalysisStatus = .completed,
    score: Int? = 76,
    feedback: String? = "단백질이 조금 부족합니다.",
    photos: [MealPhoto] = [MealPhoto(fileId: 11, url: "https://example.com/1.jpg", sortOrder: 0)],
    items: [MealItem] = [makeMealItem()]
) -> Meal {
    Meal(
        id: id, date: date, mealType: mealType, status: status, score: score,
        scoreBasis: MealScoreBasis(standard: "2025 한국인 영양소 섭취기준(KDRIs) 에너지적정비율", macros: [
            MacroBasis(name: "탄수화물", percent: 75, rangeMin: 50, rangeMax: 65, status: .over, penalty: 20),
            MacroBasis(name: "단백질", percent: 8, rangeMin: 10, rangeMax: 20, status: .under, penalty: 4),
            MacroBasis(name: "지방", percent: 17, rangeMin: 15, rangeMax: 30, status: .inRange, penalty: 0)
        ]),
        totalKcal: items.reduce(0) { $0 + $1.kcal },
        carbsG: items.reduce(0) { $0 + $1.carbsG },
        proteinG: items.reduce(0) { $0 + $1.proteinG },
        fatG: items.reduce(0) { $0 + $1.fatG },
        sugarG: items.reduce(0) { $0 + $1.sugarG },
        sodiumMg: items.reduce(0) { $0 + $1.sodiumMg },
        fiberG: items.reduce(0) { $0 + $1.fiberG },
        feedback: feedback, weightKg: 70, targetKcal: 2509,
        photos: photos, items: items
    )
}

func makeDay(
    date: String = "2026-07-29",
    dayScore: Int? = 74,
    feedback: String? = "오늘은 나트륨이 많았습니다.",
    meals: [Meal] = [makeMeal()],
    /// nil이면 `meals`의 합으로 채운다 — 명시적으로 넘기면 그 값을 그대로 쓴다(합과 어긋나는
    /// 값을 일부러 테스트하고 싶을 때).
    nutrientLimits: [NutrientLimit]? = nil,
    estimatedItemCount: Int = 0,
    activeEnergyKcal: Int? = 2400
) -> DailyDiet {
    // 실제 서버 응답에서 하루 합계는 끼니들의 합이다 — makeMeal()이 항목(items)의 합으로
    // 끼니 합계를 만드는 것과 같은 이유로, 여기서도 하루 합계를 meals에서 도출한다.
    let totalKcal = meals.reduce(0) { $0 + $1.totalKcal }
    let carbsG = meals.reduce(0) { $0 + $1.carbsG }
    let proteinG = meals.reduce(0) { $0 + $1.proteinG }
    let fatG = meals.reduce(0) { $0 + $1.fatG }
    let sugarG = meals.reduce(0) { $0 + $1.sugarG }
    let sodiumMg = meals.reduce(0) { $0 + $1.sodiumMg }
    let fiberG = meals.reduce(0) { $0 + $1.fiberG }
    let targetKcal = 2509

    let resolvedNutrientLimits = nutrientLimits ?? [
        NutrientLimit(name: "나트륨", intake: sodiumMg, unit: "mg", standardText: "2,300mg 이하", status: .warn),
        NutrientLimit(name: "식이섬유", intake: fiberG, unit: "g", standardText: "30g 이상", status: .warn),
        NutrientLimit(name: "당류", intake: sugarG, unit: "g", standardText: "125g 이하", status: .ok)
    ]

    return DailyDiet(
        date: date, dayScore: dayScore,
        scoreBasis: DayScoreBasis(
            standard: "자체 기준(칼로리 40% + 매크로 60%)",
            // `dayScore`·`calorieScore`·매크로별 `score`는 서버가 계산해 내려주는 값이라
            // 픽스처에서 다시 계산하지 않고 리터럴로 둔다 — intakeKcal/ratio만 meals 합에서 도출한다.
            calorie: CalorieBasis(
                intakeKcal: totalKcal, targetKcal: targetKcal,
                ratio: totalKcal / Double(targetKcal), calorieScore: 78
            ),
            macros: [
                MacroAmountBasis(name: "탄수화물", intakeG: 250.1, targetG: 345, ratio: 0.72, score: 72),
                MacroAmountBasis(name: "단백질", intakeG: 78.4, targetG: 94, ratio: 0.83, score: 83),
                MacroAmountBasis(name: "지방", intakeG: 62, targetG: 84, ratio: 0.74, score: 74)
            ],
            calorieWeight: 0.4, macroWeight: 0.6
        ),
        feedback: feedback, totalKcal: totalKcal, carbsG: carbsG, proteinG: proteinG, fatG: fatG,
        activeEnergyKcal: activeEnergyKcal, meals: meals,
        nutrientLimits: resolvedNutrientLimits, estimatedItemCount: estimatedItemCount
    )
}

func makeProfile(weightKg: Double = 70) -> NutritionProfile {
    NutritionProfile(
        heightCm: 175, weightKg: weightKg, activityLevel: .moderate, goal: .maintain,
        targetKcal: 2509, targetCarbsG: 345, targetProteinG: 94, targetFatG: 84,
        targetSugarG: 125, targetSodiumMg: 2300, targetFiberG: 30
    )
}

func makeAnalysis(
    id: Int = 100,
    status: AnalysisStatus = .completed,
    photos: [AnalyzedPhoto] = [
        AnalyzedPhoto(fileId: 11, url: "https://example.com/1.jpg", failed: false, items: [
            AnalyzedItem(
                foodName: "제육볶음", foodCode: "D000001", quantityG: 250, kcal: 375,
                carbsG: 30, proteinG: 25, fatG: 17, sugarG: 7, sodiumMg: 1000, fiberG: 3,
                source: .dbMatched
            )
        ])
    ]
) -> MealAnalysis {
    MealAnalysis(id: id, status: status, photos: photos)
}

func dietServerError(_ code: String, status: Int = 400) -> Error {
    APIError.serverError(
        statusCode: status,
        message: #"{"status":\#(status),"message":"...","code":"\#(status)","error":"\#(code)"}"#
    )
}
