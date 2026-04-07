import Foundation

// MARK: - Response

struct Storage: Codable, Identifiable {
    let id: Int
    var name: String
    var sortOrder: Int
    var storageType: String?
    var sections: [StorageSection]
}

struct StorageSection: Codable, Identifiable {
    let id: Int
    var name: String
    var sortOrder: Int
    var items: [StorageItem]
}

struct StorageItem: Codable, Identifiable {
    let id: Int
    let name: String
    let quantity: Int
    let expiryDate: String?
    let category: String?
    let createdBy: Int
    let createdAt: String
}

// MARK: - Request

struct StorageCreateRequest: Encodable {
    let name: String
    let storageType: String?
}

struct StorageUpdateRequest: Encodable {
    let name: String
    let storageType: String?
}

struct SectionCreateRequest: Encodable {
    let name: String
}

struct SectionUpdateRequest: Encodable {
    let name: String
}

struct OrderRequest: Encodable {
    let targetId: Int
    let beforeId: Int?
}

struct ItemRequest: Encodable {
    let name: String
    let quantity: Int
    let expiryDate: String?
    let category: String?
    let sectionId: Int
}
