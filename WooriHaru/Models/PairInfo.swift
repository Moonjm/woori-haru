import Foundation

enum PairStatus: String, Codable {
    case pending = "PENDING"
    case connected = "CONNECTED"
}

struct PairInfo: Codable, Identifiable {
    let id: Int
    let status: PairStatus
    let partnerName: String?
    let connectedAt: String?
    let partnerGender: Gender?
    let partnerBirthDate: String?
}

struct PairInviteResponse: Codable {
    let inviteCode: String
}

struct AcceptInviteRequest: Encodable {
    let inviteCode: String
}
