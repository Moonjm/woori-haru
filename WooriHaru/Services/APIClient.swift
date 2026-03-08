import Foundation

extension Notification.Name {
    static let sessionExpired = Notification.Name("sessionExpired")
}

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

@MainActor
final class APIClient {
    static let shared = APIClient()

    let baseURL = "https://daily.eunji.shop/api"
    private let session: URLSession
    private var refreshTask: Task<Bool, Never>?

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
            print("[APIClient] 401 on \(method) \(path) → attempting token refresh")
            let refreshed = await refreshToken()
            if refreshed {
                print("[APIClient] token refresh succeeded → retrying \(method) \(path)")
                return try await rawFetch(method, path: path, query: query, body: body, isRetry: true)
            }
            print("[APIClient] token refresh failed → session expired")
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    private func refreshToken() async -> Bool {
        // 이미 refresh 진행 중이면 해당 task의 결과를 기다림
        if let existing = refreshTask {
            return await existing.value
        }

        let task = Task<Bool, Never> {
            guard let url = URL(string: baseURL + "/auth/refresh") else {
                print("[APIClient] refreshToken: invalid URL")
                return false
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // 디버깅: 현재 쿠키 확인
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                print("[APIClient] refreshToken: cookies = \(cookies.map { "\($0.name)=\($0.value.prefix(10))..." })")
            } else {
                print("[APIClient] refreshToken: no cookies for \(url)")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    print("[APIClient] refreshToken: not HTTP response")
                    return false
                }
                let success = (200...299).contains(http.statusCode)
                print("[APIClient] refreshToken: status=\(http.statusCode) success=\(success)")
                if !success {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    print("[APIClient] refreshToken failed: \(body)")
                }
                return success
            } catch {
                print("[APIClient] refreshToken error: \(error)")
                return false
            }
        }

        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }
}
