import Foundation

enum Gender: String, Codable {
    case male = "MALE"
    case female = "FEMALE"
}

enum Authority: String, Codable {
    case user = "USER"
    case admin = "ADMIN"
}

struct User: Codable, Identifiable {
    let id: Int
    let username: String
    let name: String?
    let authority: Authority
    let gender: Gender?
    let birthDate: String?
    /// 회원카드 바코드 번호 — 앱에서 Code 128 바코드를 생성해 표시한다.
    let membershipBarcode: String?
}

struct UpdateMeRequest: Encodable {
    var name: String?
    var gender: Gender?
    var birthDate: String?
    /// nil이면 서버가 기존 값을 유지하고, 빈 문자열이면 삭제한다.
    var membershipBarcode: String?
    var currentPassword: String?
    var password: String?
}

struct CreateUserRequest: Encodable {
    let username: String
    let name: String
    let password: String
}

struct AdminUpdateUserRequest: Encodable {
    var name: String?
    var password: String?
    var authority: Authority?
}
