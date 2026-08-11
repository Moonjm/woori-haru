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
    /// 저장된 끼니의 타입을 바꾼다. **돌려주는 것은 「살아남은 끼니」의 id다** — 대상 타입에
    /// 기존 끼니가 있으면 서버가 항목·사진을 그쪽으로 옮기고 이 끼니를 지운다. 그때 돌아오는
    /// id는 요청한 id와 **다르다.**
    func changeMealType(id: Int, to mealType: MealType) async throws -> Int
    func deleteMeal(id: Int) async throws
    /// 사진 한 장만 지운다. **끼니는 남는다** — 항목·점수·피드백도 그대로다(사진이 줄어도
    /// 먹은 것은 그대로라 서버가 재계산하지 않는다). 마지막 한 장을 지워도 막지 않는다.
    func deleteMealPhoto(mealId: Int, fileId: Int) async throws

    func fetchDay(date: String) async throws -> DailyDiet
    func upsertActivity(date: String, activeEnergyKcal: Int) async throws

    /// **`dataset`을 서버로 넘긴다.** 앱에서 거르면 상위 50건이 전부 가공식품일 때 「음식」
    /// 칩이 빈 목록이 된다 — 거르기는 페이징 **전에** 일어나야 한다.
    ///
    /// **프로토콜에는 기본값을 두지 않는다** — 두면 기존 호출부가 그대로 컴파일되어
    /// 「고쳤는데 안 부르는」 상태가 조용히 남는다. 없으면 컴파일러가 호출부를 짚어 준다.
    func searchFoods(query: String, dataset: FoodDataset?) async throws -> [Food]
    func fetchFrequentItems() async throws -> [FrequentItem]
    func fetchStats(from: String, to: String) async throws -> DietStats

    /// 코치 타임라인 한 장. 최신이 먼저 온다 — 앱이 뒤집어 아래에 붙인다.
    /// **`before`가 nil이면 첫 장이다.**
    ///
    /// **프로토콜에 기본 구현을 두지 않는다** — `searchFoods`의 `dataset`과 같은 이유로,
    /// 두면 대역이 그대로 컴파일되어 「고쳤는데 안 부르는」 상태가 조용히 남는다.
    func fetchChatPage(before: Int?, size: Int) async throws -> ChatPage
    /// 질문 한 건. **응답은 저장된 답 한 건뿐이다** — 질문 행도 서버가 함께 저장하지만
    /// 질문은 앱이 이미 갖고 있다. **LLM 호출이라 수 초가 걸린다.**
    func askChat(date: String, message: String) async throws -> ChatMessage
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

    func changeMealType(id: Int, to mealType: MealType) async throws -> Int {
        try await api.patchCreated("/diet/meals/\(id)", body: MealTypeRequest(mealType: mealType))
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

    /// **`size`는 서버 상한인 50이다.**
    ///
    /// **`dataset`은 서버가 페이징 전에 거른다** — 앱에서 걸렀을 때는 상위 50건이 전부
    /// 가공식품이면 「음식」 칩이 빈 목록이었다. 뒤에 매칭되는 조리 음식이 있는데도 그랬다.
    func searchFoods(query: String, dataset: FoodDataset? = nil) async throws -> [Food] {
        var parameters = ["q": query, "size": "50"]
        // `.unknown`은 서버에 없는 값이다 — 보내면 enum 변환에 실패해 400이 온다.
        if let dataset, dataset != .unknown {
            parameters["dataset"] = dataset.rawValue
        }
        let response: DataResponse<[Food]> = try await api.get("/diet/foods", query: parameters)
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

    // MARK: - 코치 채팅

    /// **첫 장은 `before`를 아예 보내지 않는다.** 빈 문자열을 보내면 서버가 `Long` 변환에
    /// 실패해 400을 준다.
    func fetchChatPage(before: Int?, size: Int) async throws -> ChatPage {
        var parameters = ["size": String(size)]
        if let before {
            parameters["before"] = String(before)
        }
        let response: DataResponse<ChatPage> = try await api.get("/diet/chat", query: parameters)
        guard let page = response.data else {
            throw APIError.serverError(statusCode: 200, message: "대화 응답이 비어 있습니다")
        }
        return page
    }

    /// **201이 아니라 200 + 바디다.** 서버가 관례에서 의도적으로 벗어난 자리다 — 답을 다시
    /// 조회하게 만들면 사용자가 화면에서 기다리는 시간이 두 배가 된다.
    func askChat(date: String, message: String) async throws -> ChatMessage {
        let response: DataResponse<ChatMessage> =
            try await api.post("/diet/days/\(date)/chat", body: ChatAskRequest(message: message))
        guard let answer = response.data else {
            throw APIError.serverError(statusCode: 200, message: "답변이 비어 있습니다")
        }
        return answer
    }
}
