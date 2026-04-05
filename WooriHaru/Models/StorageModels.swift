import Foundation

// MARK: - Response

struct Storage: Codable, Identifiable {
    let id: Int
    let name: String
    let sortOrder: Int
    let sections: [StorageSection]
}

struct StorageSection: Codable, Identifiable {
    let id: Int
    let name: String
    let sortOrder: Int
    let items: [StorageItem]
}

struct StorageItem: Codable, Identifiable {
    let id: Int
    let name: String
    let quantity: Int
    let expiryDate: String?
    let createdBy: Int
    let createdAt: String
}

// MARK: - Request

struct StorageCreateRequest: Encodable {
    let name: String
}

struct StorageUpdateRequest: Encodable {
    let name: String
}

struct SectionCreateRequest: Encodable {
    let name: String
}

struct SectionUpdateRequest: Encodable {
    let name: String
}

struct ItemRequest: Encodable {
    let name: String
    let quantity: Int
    let expiryDate: String?
    let sectionId: Int
}
