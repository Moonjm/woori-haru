import Foundation

enum StorageType: String, CaseIterable, Identifiable {
    case fridge = "fridge"
    case freezer = "freezer"
    case kimchi = "kimchi"
    case pantry = "pantry"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fridge: "냉장"
        case .freezer: "냉동"
        case .kimchi: "김치냉장고"
        case .pantry: "팬트리"
        }
    }

    var emoji: String {
        switch self {
        case .fridge: "🧊"
        case .freezer: "❄️"
        case .kimchi: "🥬"
        case .pantry: "🗄️"
        }
    }
}
