import Foundation

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case sedentary = "SEDENTARY"
    case light = "LIGHT"
    case moderate = "MODERATE"
    case active = "ACTIVE"
    case veryActive = "VERY_ACTIVE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedentary: "거의 안 움직임"
        case .light: "가벼운 활동"
        case .moderate: "보통 활동"
        case .active: "활발한 활동"
        case .veryActive: "매우 활발함"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "종일 앉아서 지냄"
        case .light: "주 1~3회 가벼운 운동"
        case .moderate: "주 3~5회 운동"
        case .active: "주 6~7회 운동"
        case .veryActive: "매일 고강도 운동 또는 육체노동"
        }
    }
}

enum DietGoal: String, Codable, CaseIterable, Identifiable, Hashable {
    case lose = "LOSE"
    case maintain = "MAINTAIN"
    case gain = "GAIN"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lose: "감량"
        case .maintain: "유지"
        case .gain: "증량"
        }
    }
}

/// 서버가 받아 주는 키·몸무게 범위. **양끝을 포함한다**(`@DecimalMin`/`@DecimalMax`).
///
/// 앱이 같은 값을 들고 있는 이유는 **밖의 값으로 저장을 시도하지 않게 하려는 것**이다 —
/// 보내 봐야 400이고, 그때는 화면이 이미 닫힌 뒤라 고칠 자리를 잃는다. 서버 제약이 바뀌면
/// 여기도 같이 바꿔야 한다(`toy-back`의 `NutritionProfileDtos.kt`가 주인이다).
enum NutritionProfileLimits {
    static let heightCm: ClosedRange<Double> = 100...250
    static let weightKg: ClosedRange<Double> = 20...300

    static var heightHint: String { "키는 100~250cm 사이로 넣어 주세요." }
    static var weightHint: String { "몸무게는 20~300kg 사이로 넣어 주세요." }
}

/// 목표는 서버가 계산해 저장한다 — 앱은 표시만 한다.
struct NutritionProfile: Codable, Hashable {
    let heightCm: Double
    let weightKg: Double
    let activityLevel: ActivityLevel
    let goal: DietGoal
    let targetKcal: Int
    let targetCarbsG: Int
    let targetProteinG: Int
    let targetFatG: Int
    let targetSugarG: Int
    let targetSodiumMg: Int
    let targetFiberG: Int
}

struct NutritionProfileRequest: Encodable {
    let heightCm: Double
    let weightKg: Double
    let activityLevel: ActivityLevel
    let goal: DietGoal
}

/// 몸무게는 매일 재는 값이라 프로필 전체를 다시 보내지 않는다.
struct WeightUpdateRequest: Encodable {
    let weightKg: Double
}
