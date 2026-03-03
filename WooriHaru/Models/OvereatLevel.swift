import Foundation

enum OvereatLevel: String, Codable {
    case none = "NONE"
    case mild = "MILD"
    case moderate = "MODERATE"
    case severe = "SEVERE"
    case extreme = "EXTREME"
}

struct DailyOvereat: Codable {
    let date: String
    let overeatLevel: OvereatLevel
}

struct UpdateOvereatRequest: Encodable {
    let date: String
    let overeatLevel: OvereatLevel
}
