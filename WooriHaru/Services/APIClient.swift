import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "잘못된 URL입니다."
        case .unauthorized: return "로그인이 필요합니다."
        case .serverError(let code, let message): return message ?? "서버 오류 (\(code))"
        case .decodingError: return "데이터 파싱 오류"
        case .networkError(let error): return error.localizedDescription
        }
    }
}

enum APIConfig {
    static let baseURL = "https://daily.eunji.shop/api"
}

/// APIClient 프로토콜 — 테스트 대체 가능한 인터페이스
protocol APIClientProtocol: Sendable {
    func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T
    func post<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T
    func postVoid(_ path: String, body: (any Encodable)?) async throws
    func postCreated(_ path: String, body: (any Encodable)?) async throws -> Int
    func put<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T
    func putVoid(_ path: String, body: (any Encodable)?) async throws
    func patch<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T
    func patchVoid(_ path: String, body: (any Encodable)?) async throws
    func deleteVoid(_ path: String) async throws
}

extension APIClientProtocol {
    func get<T: Decodable>(_ path: String) async throws -> T {
        try await get(path, query: [:])
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await post(path, body: nil)
    }

    func postVoid(_ path: String) async throws {
        try await postVoid(path, body: nil)
    }

    func postCreated(_ path: String) async throws -> Int {
        try await postCreated(path, body: nil)
    }

    func put<T: Decodable>(_ path: String) async throws -> T {
        try await put(path, body: nil)
    }

    func putVoid(_ path: String) async throws {
        try await putVoid(path, body: nil)
    }

    func patch<T: Decodable>(_ path: String) async throws -> T {
        try await patch(path, body: nil)
    }

    func patchVoid(_ path: String) async throws {
        try await patchVoid(path, body: nil)
    }
}

/// 순수 HTTP 통신 담당 — 세션/인증은 SessionManager가 처리
final class APIClient: APIClientProtocol, Sendable {
    static let shared = APIClient()

    private let baseURL = APIConfig.baseURL

    private init() {}

    // MARK: - Public Methods

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        return try await request("GET", path: path, query: query)
    }

    func post<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        return try await request("POST", path: path, body: body)
    }

    func postVoid(_ path: String, body: (any Encodable)? = nil) async throws {
        try await requestVoid("POST", path: path, body: body)
    }

    func postCreated(_ path: String, body: (any Encodable)? = nil) async throws -> Int {
        let (_, response) = try await rawFetchWithResponse("POST", path: path, body: body)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let idString = location.split(separator: "/").last,
              let id = Int(idString) else {
            throw APIError.serverError(statusCode: response.statusCode, message: "Location 헤더에서 ID를 찾을 수 없습니다")
        }
        return id
    }

    func put<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        return try await request("PUT", path: path, body: body)
    }

    func putVoid(_ path: String, body: (any Encodable)? = nil) async throws {
        try await requestVoid("PUT", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        return try await request("PATCH", path: path, body: body)
    }

    func patchVoid(_ path: String, body: (any Encodable)? = nil) async throws {
        try await requestVoid("PATCH", path: path, body: body)
    }

    func deleteVoid(_ path: String) async throws {
        try await requestVoid("DELETE", path: path)
    }

    // MARK: - Private

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        isRetry: Bool = false
    ) async throws -> T {
        let data = try await rawFetch(method, path: path, query: query, body: body, isRetry: isRetry)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func requestVoid(
        _ method: String,
        path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        isRetry: Bool = false
    ) async throws {
        _ = try await rawFetch(method, path: path, query: query, body: body, isRetry: isRetry)
    }

    private func rawFetch(
        _ method: String,
        path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        isRetry: Bool = false
    ) async throws -> Data {
        let (data, _) = try await rawFetchWithResponse(method, path: path, query: query, body: body, isRetry: isRetry)
        return data
    }

    private func rawFetchWithResponse(
        _ method: String,
        path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let session = SessionManager.shared.urlSession

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 && !isRetry {
            let shouldRetry = await SessionManager.shared.handleUnauthorized()
            if shouldRetry {
                return try await rawFetchWithResponse(method, path: path, query: query, body: body, isRetry: true)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return (data, httpResponse)
    }
}
