import Foundation

/// 식단 API. 테스트에서 대체할 수 있도록 프로토콜로 분리한다.
protocol DietServing: Sendable {
    /// 프로필이 없으면 nil — 서버는 `PROFILE_NOT_FOUND`(404)로 답한다.
    func fetchProfile() async throws -> NutritionProfile?
    func saveProfile(_ request: NutritionProfileRequest) async throws
    func updateWeight(_ weightKg: Double) async throws

    /// **한 장 단위다.** 여러 장은 호출부가 순차로 여러 번 부른다 — 진행률을 보여줄 수 있고,
    /// 중간에 실패했을 때 어디까지 올라갔는지가 흐려지지 않는다.
    func uploadPhoto(_ jpegData: Data) async throws -> Int
    func createAnalysis(fileIds: [Int]) async throws -> Int
    func fetchAnalysis(id: Int) async throws -> MealAnalysis
    /// 실패한 사진만 다시 인식한다.
    func retryAnalysis(id: Int) async throws

    func confirmMeal(_ request: MealConfirmRequest) async throws -> Int
    func fetchMeal(id: Int) async throws -> Meal
    func updateMealItems(id: Int, items: [MealItemRequest]) async throws
    func deleteMeal(id: Int) async throws
    /// 사진 한 장만 지운다. **끼니는 남는다** — 항목·점수·피드백도 그대로다(사진이 줄어도
    /// 먹은 것은 그대로라 서버가 재계산하지 않는다). 마지막 한 장을 지워도 막지 않는다.
    func deleteMealPhoto(mealId: Int, fileId: Int) async throws

    func fetchDay(date: String) async throws -> DailyDiet
    func upsertActivity(date: String, activeEnergyKcal: Int) async throws

    func searchFoods(query: String) async throws -> [Food]
    func fetchFrequentItems() async throws -> [FrequentItem]
    func fetchStats(from: String, to: String) async throws -> DietStats
}

/// **`POST /diet/meals/{id}/retry`(피드백 재생성)는 여기 없다.** 서버에 있지만 앱은 부르지 않는다 —
/// 생성이 실패하면 서버가 끼니가 바뀔 때까지 다시 부르지 않으므로(비용 방어) 사용자가 끼니를
/// 추가·수정하면 자연히 다시 만들어진다.
struct DietService: DietServing {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    // MARK: - 프로필

    func fetchProfile() async throws -> NutritionProfile? {
        do {
            let response: DataResponse<NutritionProfile> = try await api.get("/diet/profile")
            return response.data
        } catch {
            guard error.dietErrorCode == .profileNotFound else { throw error }
            return nil
        }
    }

    func saveProfile(_ request: NutritionProfileRequest) async throws {
        try await api.putVoid("/diet/profile", body: request)
    }

    func updateWeight(_ weightKg: Double) async throws {
        try await api.putVoid("/diet/profile/weight", body: WeightUpdateRequest(weightKg: weightKg))
    }

    // MARK: - 인식

    func uploadPhoto(_ jpegData: Data) async throws -> Int {
        try await api.postMultipartCreated(
            "/files",
            fileData: jpegData,
            fileName: "meal.jpg",
            mimeType: "image/jpeg"
        )
    }

    func createAnalysis(fileIds: [Int]) async throws -> Int {
        try await api.postCreated("/diet/analyses", body: AnalysisCreateRequest(fileIds: fileIds))
    }

    func fetchAnalysis(id: Int) async throws -> MealAnalysis {
        let response: DataResponse<MealAnalysis> = try await api.get("/diet/analyses/\(id)")
        guard let analysis = response.data else {
            throw APIError.serverError(statusCode: 200, message: "인식 응답이 비어 있습니다")
        }
        return analysis
    }

    func retryAnalysis(id: Int) async throws {
        try await api.postVoid("/diet/analyses/\(id)/retry")
    }

    // MARK: - 끼니

    func confirmMeal(_ request: MealConfirmRequest) async throws -> Int {
        try await api.postCreated("/diet/meals", body: request)
    }

    func fetchMeal(id: Int) async throws -> Meal {
        let response: DataResponse<Meal> = try await api.get("/diet/meals/\(id)")
        guard let meal = response.data else {
            throw APIError.serverError(statusCode: 200, message: "끼니 응답이 비어 있습니다")
        }
        return meal
    }

    func updateMealItems(id: Int, items: [MealItemRequest]) async throws {
        try await api.putVoid("/diet/meals/\(id)/items", body: MealItemsRequest(items: items))
    }

    func deleteMeal(id: Int) async throws {
        try await api.deleteVoid("/diet/meals/\(id)")
    }

    func deleteMealPhoto(mealId: Int, fileId: Int) async throws {
        try await api.deleteVoid("/diet/meals/\(mealId)/photos/\(fileId)")
    }

    // MARK: - 하루

    func fetchDay(date: String) async throws -> DailyDiet {
        let response: DataResponse<DailyDiet> = try await api.get("/diet/days/\(date)")
        guard let day = response.data else {
            throw APIError.serverError(statusCode: 200, message: "하루 응답이 비어 있습니다")
        }
        return day
    }

    func upsertActivity(date: String, activeEnergyKcal: Int) async throws {
        try await api.putVoid("/diet/activity", body: ActivityUpsertRequest(date: date, activeEnergyKcal: activeEnergyKcal))
    }

    // MARK: - 식품·통계

    /// **`size`는 서버 상한인 50이다.** 필터 칩이 받아 온 페이지를 앱에서 거르기 때문에
    /// 페이지가 작으면 「음식」 칩이 빈 목록을 보여준다. 근본 해법은 서버 `dataset`
    /// 파라미터이고 그건 백엔드 작업이다.
    func searchFoods(query: String) async throws -> [Food] {
        let response: DataResponse<[Food]> = try await api.get("/diet/foods", query: ["q": query, "size": "50"])
        return response.data ?? []
    }

    func fetchFrequentItems() async throws -> [FrequentItem] {
        let response: DataResponse<[FrequentItem]> =
            try await api.get("/diet/items/frequent", query: ["days": "30", "size": "20"])
        return response.data ?? []
    }

    func fetchStats(from: String, to: String) async throws -> DietStats {
        let response: DataResponse<DietStats> =
            try await api.get("/diet/stats", query: ["from": from, "to": to])
        guard let stats = response.data else {
            throw APIError.serverError(statusCode: 200, message: "통계 응답이 비어 있습니다")
        }
        return stats
    }
}
