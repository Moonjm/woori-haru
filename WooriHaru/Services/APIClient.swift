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

final class APIClient {
    static let shared = APIClient()

    let baseURL = "https://tree.eunji.shop/api"
    private let session: URLSession
    private var isRefreshing = false

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = .shared
        self.session = URLSession(configuration: config)
    }

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

    func put<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        return try await request("PUT", path: path, body: body)
    }

    func putVoid(_ path: String, body: (any Encodable)? = nil) async throws {
        try await requestVoid("PUT", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        return try await request("PATCH", path: path, body: body)
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
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }

        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

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
            let refreshed = await refreshToken()
            if refreshed {
                return try await rawFetch(method, path: path, query: query, body: body, isRetry: true)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    private func refreshToken() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let url = URL(string: baseURL + "/auth/refresh") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }
}
