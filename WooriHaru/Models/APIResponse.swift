import Foundation

struct DataResponse<T: Codable>: Codable {
    let data: T?
}
