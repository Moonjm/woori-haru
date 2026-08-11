import Foundation

/// 확정 전 인식 결과. 저장하지 않고 나가면 아무것도 남지 않는다 — 서버가 24시간 뒤 정리한다.
struct MealAnalysis: Codable, Hashable, Identifiable {
    let id: Int
    let status: AnalysisStatus
    let photos: [AnalyzedPhoto]

    /// 사진 일부만 실패한 상태. 그 사진만 다시 시도할 수 있다.
    var hasFailedPhoto: Bool { photos.contains(where: \.failed) }
}

struct AnalyzedPhoto: Codable, Hashable, Identifiable {
    let fileId: Int
    let url: String?
    /// 실패한 사진도 **감추지 않는다** — 5장 올린 사용자가 4장 분량만 보면 나머지를 찾을 수 없다.
    let failed: Bool
    let items: [AnalyzedItem]

    var id: Int { fileId }
}

struct AnalyzedItem: Codable, Hashable {
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
