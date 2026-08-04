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
    private var postResults: [String: Any] = [:]
    private var postCreatedResults: [String: Int] = [:]
    private var patchCreatedResults: [String: Int] = [:]
    private var multipartResults: [Int] = []
    private var errors: [String: Error] = [:]
    private var putVoidError: Error?

    private var recordedGetCalls: [(path: String, query: [String: String])] = []
    private var recordedPostCalls: [(path: String, body: (any Encodable)?)] = []
    private var recordedPostCreatedCalls: [(path: String, body: (any Encodable)?)] = []
    private var recordedPatchCreatedCalls: [(path: String, body: (any Encodable)?)] = []
    private var recordedMultipartCalls: [(path: String, byteCount: Int)] = []
    private var recordedPutVoidCalls: [(path: String, body: (any Encodable)?)] = []
    private var recordedDeleteCalls: [String] = []

    // MARK: - Stub

    /// GET 경로에 대한 응답 등록
    func stubGet(_ path: String, result: Any) {
        lock.lock(); defer { lock.unlock() }
        getResults[path] = result
    }

    func stubPost(_ path: String, result: Any) {
        lock.lock(); defer { lock.unlock() }
        postResults[path] = result
    }

    func stubPostCreated(_ path: String, result: Int) {
        lock.lock(); defer { lock.unlock() }
        postCreatedResults[path] = result
    }

    func stubPatchCreated(_ path: String, result: Int) {
        lock.lock(); defer { lock.unlock() }
        patchCreatedResults[path] = result
    }

    /// 업로드가 돌려줄 fileId를 올린 순서대로 등록한다. 등록한 수보다 많이 부르면 unstubbed다.
    func stubMultipart(fileIds: [Int]) {
        lock.lock(); defer { lock.unlock() }
        multipartResults = fileIds
    }

    /// `"POST /diet/analyses"`처럼 `메서드 경로` 키로 던질 에러를 등록한다.
    /// nil을 주면 해제한다 — 재시도 테스트에서 "한 번 실패한 뒤 성공"을 만들 때 쓴다.
    func setError(_ error: Error?, for key: String) {
        lock.lock(); defer { lock.unlock() }
        errors[key] = error
    }

    /// putVoid가 던질 에러 설정 (롤백 테스트용)
    func setPutVoidError(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        putVoidError = error
    }

    // MARK: - 기록

    var getCalls: [(path: String, query: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return recordedGetCalls
    }

    var postCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPostCalls
    }

    var postCreatedCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPostCreatedCalls
    }

    var patchCreatedCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPatchCreatedCalls
    }

    var multipartCalls: [(path: String, byteCount: Int)] {
        lock.lock(); defer { lock.unlock() }
        return recordedMultipartCalls
    }

    var putVoidCalls: [(path: String, body: (any Encodable)?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedPutVoidCalls
    }

    var deleteCalls: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedDeleteCalls
    }

    // MARK: - APIClientProtocol

    func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        lock.lock()
        recordedGetCalls.append((path, query))
        let error = errors["GET \(path)"]
        let result = getResults[path]
        lock.unlock()
        if let error { throw error }
        guard let value = result as? T else { throw MockAPIError.unstubbed("GET \(path)") }
        return value
    }

    func post<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        lock.lock()
        recordedPostCalls.append((path, body))
        let error = errors["POST \(path)"]
        let result = postResults[path]
        lock.unlock()
        if let error { throw error }
        guard let value = result as? T else { throw MockAPIError.unstubbed("POST \(path)") }
        return value
    }

    func postVoid(_ path: String, body: (any Encodable)?) async throws {
        lock.lock()
        recordedPostCalls.append((path, body))
        let error = errors["POST \(path)"]
        lock.unlock()
        if let error { throw error }
    }

    func postCreated(_ path: String, body: (any Encodable)?) async throws -> Int {
        lock.lock()
        recordedPostCreatedCalls.append((path, body))
        let error = errors["POST \(path)"]
        let result = postCreatedResults[path]
        lock.unlock()
        if let error { throw error }
        guard let id = result else { throw MockAPIError.unstubbed("POST \(path)") }
        return id
    }

    /// 오류 키는 `"PATCH 경로"`다 — `postCreated`가 `"POST 경로"`를 쓰는 것과 같은 규칙이다.
    func patchCreated(_ path: String, body: (any Encodable)?) async throws -> Int {
        lock.lock()
        recordedPatchCreatedCalls.append((path, body))
        let error = errors["PATCH \(path)"]
        let result = patchCreatedResults[path]
        lock.unlock()
        if let error { throw error }
        guard let id = result else { throw MockAPIError.unstubbed("PATCH \(path)") }
        return id
    }

    func postMultipartCreated(_ path: String, fileData: Data, fileName: String, mimeType: String) async throws -> Int {
        lock.lock()
        let index = recordedMultipartCalls.count
        recordedMultipartCalls.append((path, fileData.count))
        let error = errors["POST \(path)"]
        // 장별로 다른 에러를 주려면 "POST /files#2"처럼 인덱스를 붙인 키를 쓴다.
        let indexedError = errors["POST \(path)#\(index)"]
        let result = index < multipartResults.count ? multipartResults[index] : nil
        lock.unlock()
        if let indexedError { throw indexedError }
        if let error { throw error }
        guard let id = result else { throw MockAPIError.unstubbed("POST \(path) #\(index)") }
        return id
    }

    func put<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        throw MockAPIError.unstubbed("PUT \(path)")
    }

    func putVoid(_ path: String, body: (any Encodable)?) async throws {
        lock.lock()
        recordedPutVoidCalls.append((path, body))
        let error = putVoidError ?? errors["PUT \(path)"]
        lock.unlock()
        if let error { throw error }
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T {
        throw MockAPIError.unstubbed("PATCH \(path)")
    }

    func patchVoid(_ path: String, body: (any Encodable)?) async throws {
        throw MockAPIError.unstubbed("PATCH \(path)")
    }

    func deleteVoid(_ path: String) async throws {
        lock.lock()
        recordedDeleteCalls.append(path)
        let error = errors["DELETE \(path)"]
        lock.unlock()
        if let error { throw error }
    }
}
