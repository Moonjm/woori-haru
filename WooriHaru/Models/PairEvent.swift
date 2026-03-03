import Foundation

struct PairEvent: Codable, Identifiable {
    let id: Int
    let title: String
    let emoji: String
    let eventDate: String
    let recurring: Bool
}

struct PairEventRequest: Encodable {
    let title: String
    let emoji: String
    let eventDate: String
    let recurring: Bool
}
