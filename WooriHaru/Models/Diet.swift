import Foundation

// MARK: - Enum (rawValue는 서버 값 그대로)

enum MealType: String, Codable, CaseIterable, Identifiable, Hashable {
    case breakfast = "BREAKFAST"
    case lunch = "LUNCH"
    case dinner = "DINNER"
    case snack = "SNACK"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "아침"
        case .lunch: "점심"
        case .dinner: "저녁"
        case .snack: "간식"
        }
    }

    var iconName: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "cup.and.saucer"
        }
    }

    /// 같은 날 다시 기록하면 서버가 기존 끼니에 **합치는** 종류인가. 간식만 아니다 —
    /// 본래 여러 번이라 묶으면 점수가 뒤섞인다.
    ///
    /// **판단의 주인은 서버다**(`MealType.mergesWithinDay`). 앱은 저장 전에 안내 한 줄을
    /// 띄우는 데만 쓰므로, 서버 규칙이 바뀌면 여기도 같이 바꿔야 안내가 거짓말이 되지 않는다.
    var mergesWithinDay: Bool { self != .snack }
}

/// `MealAnalysis`에서는 인식 진행 상태, `Meal`에서는 피드백 생성 상태를 뜻한다.
enum AnalysisStatus: String, Codable, Hashable {
    case pending = "PENDING"
    case completed = "COMPLETED"
    case failed = "FAILED"
}

enum NutritionSource: String, Codable, Hashable {
    case dbMatched = "DB_MATCHED"
    case llmEstimated = "LLM_ESTIMATED"
}

enum MacroStatus: String, Codable, Hashable {
    case under = "UNDER"
    case inRange = "IN_RANGE"
    case over = "OVER"
}

enum NutrientStatus: String, Codable, Hashable {
    case ok = "OK"
    case warn = "WARN"
}

// MARK: - 점수 근거 (서버가 판정한 값을 그대로 표시한다)

struct MacroBasis: Codable, Hashable, Identifiable {
    let name: String
    let percent: Double
    let rangeMin: Int
    let rangeMax: Int
    let status: MacroStatus
    let penalty: Double

    var id: String { name }
}

struct MealScoreBasis: Codable, Hashable {
    let standard: String
    let macros: [MacroBasis]
}

struct CalorieBasis: Codable, Hashable {
    let intakeKcal: Double
    let targetKcal: Int
    let ratio: Double
    let calorieScore: Int
}

struct MacroAmountBasis: Codable, Hashable, Identifiable {
    let name: String
    let intakeG: Double
    let targetG: Int
    let ratio: Double
    let score: Int

    var id: String { name }
}

/// 하루 점수 근거. `standard`가 자체 기준이라고 밝히므로 국가 기준과 같은 무게로 제시하지 않는다.
struct DayScoreBasis: Codable, Hashable {
    let standard: String
    let calorie: CalorieBasis
    let macros: [MacroAmountBasis]
    let calorieWeight: Double
    let macroWeight: Double
}

// MARK: - 끼니

struct MealItem: Codable, Hashable, Identifiable {
    let id: Int
    let foodName: String
    let foodCode: String?
    let quantityG: Double
    let kcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
    let source: NutritionSource
}

struct MealPhoto: Codable, Hashable, Identifiable {
    let fileId: Int
    /// presigned URL — 10분 만료라 오래 캐시하지 않는다. 화면을 다시 열 때 조회한다.
    let url: String?
    let sortOrder: Int

    var id: Int { fileId }
}

struct Meal: Codable, Hashable, Identifiable {
    let id: Int
    /// "yyyy-MM-dd"
    let date: String
    let mealType: MealType
    /// **피드백 생성 상태**다. 점수는 확정 시점에 이미 계산돼 있다.
    let status: AnalysisStatus
    let score: Int?
    let scoreBasis: MealScoreBasis?
    let totalKcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
    let feedback: String?
    /// 확정 시점 스냅샷 — 몸무게를 고쳐도 과거 점수가 흔들리지 않는 근거다.
    let weightKg: Double
    let targetKcal: Int
    /// 사진 없이 기록한 끼니는 **빈 배열**이다.
    let photos: [MealPhoto]
    let items: [MealItem]
}

// MARK: - 하루

/// **앱이 판정하지 않는다.** `status`가 `WARN`이면 강조하고 `OK`면 평범하게 둔다.
/// `standardText`는 서버 문구를 그대로 쓴다(기준이 개정되면 앱 배포 없이 따라간다).
struct NutrientLimit: Codable, Hashable, Identifiable {
    let name: String
    let intake: Double
    let unit: String
    let standardText: String
    let status: NutrientStatus

    var id: String { name }
}

struct DailyDiet: Codable, Hashable {
    /// "yyyy-MM-dd"
    let date: String
    let dayScore: Int?
    let scoreBasis: DayScoreBasis?
    /// `null`이면 서버가 뒤에서 만들고 있다는 뜻이다 — 폴링 대상이지 실패가 아니다.
    let feedback: String?
    let totalKcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    // `syncActivity()`가 방금 업로드한 값을 새로고침 없이 화면에 반영할 수 있도록 `var`다.
    var activeEnergyKcal: Int?
    /// `mealType` 순(아침→점심→저녁→간식)으로 온다. **앱이 다시 정렬하지 않는다.**
    let meals: [Meal]
    let nutrientLimits: [NutrientLimit]
    /// 그날 LLM 추정 항목 수. 0보다 크면 「추정 N건 포함」을 단다. 기록이 없는 날도 0이다.
    let estimatedItemCount: Int
}

// MARK: - Request

/// 확인 화면에서 편집하는 단위이자 서버로 보내는 본문. `id`는 로컬 식별용이라 전송하지 않는다
/// (`CodingKeys`에 없다) — 같은 음식이 여러 사진에서 중복으로 잡혀도 행을 구분해야 한다.
struct MealItemRequest: Codable, Hashable, Identifiable {
    var id = UUID()
    var foodName: String
    /// **직접 입력에는 `""`가 아니라 `nil`을 넣는다.** 서버 검증(`@Size(max=30)`)이 빈 문자열을
    /// 막지 않고, 자주 먹는 음식 집계가 코드로 묶으므로 애초에 안 보내는 편이 안전하다.
    var foodCode: String?
    var quantityG: Double
    var kcal: Double
    var carbsG: Double
    var proteinG: Double
    var fatG: Double
    /// 주의 영양소 3필드. **여기가 빠지면 서버가 검증 오류 없이 0으로 저장한다.**
    var sugarG: Double
    var sodiumMg: Double
    var fiberG: Double
    var source: NutritionSource

    private enum CodingKeys: String, CodingKey {
        case foodName, foodCode, quantityG, kcal, carbsG, proteinG, fatG, sugarG, sodiumMg, fiberG, source
    }
}

/// `PATCH /diet/meals/{id}` 본문. **끼니 타입 한 칸뿐이다** — 항목을 같이 보내지 않는다.
///
/// 항목을 안 보내기 때문에 **낡은 화면에서도 이 요청은 안전하다** — 항목 교체(`PUT`)와 달리
/// 덮어쓸 목록 자체가 없다.
struct MealTypeRequest: Encodable {
    let mealType: MealType
}

/// `analysisId`가 `nil`이면 사진 없이 기록한다 — `encodeIfPresent`라 키 자체가 빠진다.
struct MealConfirmRequest: Encodable {
    let date: String
    let mealType: MealType
    let analysisId: Int?
    let items: [MealItemRequest]
}

struct MealItemsRequest: Encodable {
    let items: [MealItemRequest]
}

struct ActivityUpsertRequest: Encodable {
    let date: String
    let activeEnergyKcal: Int
}

struct AnalysisCreateRequest: Encodable {
    let fileIds: [Int]
}

// MARK: - 정책 상수

enum DietPolicy {
    /// 서버가 사진마다 LLM을 호출하므로 장수가 곧 비용·대기시간이다.
    static let maxPhotos = 5
    static let pollInterval: Duration = .seconds(2)
    static let pollTimeout: Duration = .seconds(60)
}
