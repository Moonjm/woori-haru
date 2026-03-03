import Foundation

struct DailyRecord: Codable, Identifiable {
    let id: Int
    let date: String
    let memo: String?
    let category: Category
    let together: Bool
}

struct DailyRecordRequest: Encodable {
    let date: String
    let categoryId: Int
    let memo: String?
    let together: Bool
}
