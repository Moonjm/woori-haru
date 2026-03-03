import Foundation

struct Category: Codable, Identifiable {
    let id: Int
    let emoji: String
    let name: String
    let isActive: Bool
    let sortOrder: Int
}

struct CategoryRequest: Encodable {
    let emoji: String
    let name: String
    let isActive: Bool
}

struct ReorderCategoryRequest: Encodable {
    let targetId: Int
    let beforeId: Int?
}
