import Foundation
@testable import WooriHaru

/// 경로별 응답을 미리 등록해 두고 호출을 기록하는 테스트 대역.
/// 등록되지 않은 경로 호출은 unstubbed 에러로 실패한다.
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    enum MockAPIError: Error {
        case unstubbed(String)
        case forced
    }

    private let lock = NSLock()

    private var getResults: [String: Any] = [:]
    private var putVoidError: Error?
    private var recordedPutVoidCalls: [(path: String, body: (any Encodable)?)] = []

    /// GET 경로에 대한 응답 등록
    func stubGet(_ path: String, result: Any) {
        lock.lock(); defer { lock.unlock() }
        getResults[path] = result
    }

    /// putVoid가 던질 에러 설정 (롤백 테스트용)
    func setPutVoidError(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        putVoidError = error
    }

    var putVoidCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPutVoidCalls
    }

    // MARK: - APIClientProtocol

    func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard let result = getResults[path] as? T else { throw MockAPIError.unstubbed("GET \(path)") }
        return result
    }

    func putVoid(_ path: String, body: (any Encodable)?) async throws {
        lock.lock()
        recordedPutVoidCalls.append((path, body))
        let error = putVoidError
        lock.unlock()
        if let error { throw error }
    }

    func post<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        throw MockAPIError.unstubbed("POST \(path)")
    }

    func postVoid(_ path: String, body: (any Encodable)?) async throws {
        throw MockAPIError.unstubbed("POST \(path)")
    }

    func postCreated(_ path: String, body: (any Encodable)?) async throws -> Int {
        throw MockAPIError.unstubbed("POST \(path)")
    }

    func put<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        throw MockAPIError.unstubbed("PUT \(path)")
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        throw MockAPIError.unstubbed("PATCH \(path)")
    }

    func patchVoid(_ path: String, body: (any Encodable)?) async throws {
        throw MockAPIError.unstubbed("PATCH \(path)")
    }

    func deleteVoid(_ path: String) async throws {
        throw MockAPIError.unstubbed("DELETE \(path)")
    }
}
