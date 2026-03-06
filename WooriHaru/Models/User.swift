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
}

struct UpdateMeRequest: Encodable {
    var name: String?
    var gender: Gender?
    var birthDate: String?
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
