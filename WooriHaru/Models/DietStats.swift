import Foundation

struct DailyScore: Codable, Hashable, Identifiable {
    /// "yyyy-MM-dd"
    let date: String
    let dayScore: Int

    var id: String { date }
}

struct NutritionTotals: Codable, Hashable {
    let kcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let fiberG: Double
}

struct NutritionTargets: Codable, Hashable {
    let kcal: Int
    let carbsG: Int
    let proteinG: Int
    let fatG: Int
    let sugarG: Int
    let sodiumMg: Int
    let fiberG: Int
}

/// 기록이 0건이면 `averageDayScore`·`averageIntake`·`averageTargets`가 `null`이고
/// `dailyScores`는 빈 배열이다. `recordedDays`만 0으로 온다.
struct DietStats: Codable, Hashable {
    let from: String
    let to: String
    /// 평균의 분모. **안 적은 날을 0으로 세지 않으므로 화면에 함께 보여줘야 평균이 읽힌다.**
    let recordedDays: Int
    let averageDayScore: Int?
    /// **기록한 날만 들어간다** — 추이 차트의 x축을 배열 인덱스로 잡으면 날짜 간격이 뭉개진다.
    let dailyScores: [DailyScore]
    let averageIntake: NutritionTotals?
    let averageTargets: NutritionTargets?
    /// `FrequentItem`과 같은 모양이라 자주 먹는 음식 목록 컴포넌트를 그대로 쓴다.
    let topFoods: [FrequentItem]
}
