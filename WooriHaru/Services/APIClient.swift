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
    /// `PATCH` 응답의 `Location`에서 id를 뽑는다. **본문이 아니라 헤더다** — 끼니 확정·분석
    /// 생성·사진 업로드가 이미 같은 방식이라 새 응답 DTO를 만들지 않는다.
    ///
    /// **상태코드를 보지 않는다.** 앞의 셋은 201로 오고 이쪽은 200으로 오는데, 둘을 구분할
    /// 이유가 없다(`rawFetchWithResponse`가 이미 `200...299`만 통과시킨다).
    func patchCreated(_ path: String, body: (any Encodable)?) async throws -> Int
    func put<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T
    func putVoid(_ path: String, body: (any Encodable)?) async throws
    func patch<T: Decodable>(_ path: String, body: (any Encodable)?) async throws -> T
    func patchVoid(_ path: String, body: (any Encodable)?) async throws
    func deleteVoid(_ path: String) async throws

    /// `/files` 단건 업로드. 201 + Location에서 fileId를 파싱해 돌려준다.
    /// **multipart를 쓰는 곳은 여기 한 군데뿐이고 나머지 식단 API는 전부 JSON이다.**
    /// 여러 장은 이 메서드를 순차로 여러 번 부르는 것으로 처리한다 — 서버 `/files`가 단건이고,
    /// 병렬로 밀어넣으면 실패했을 때 어디까지 올라갔는지 추적이 지저분해진다.
    func postMultipartCreated(_ path: String, fileData: Data, fileName: String, mimeType: String) async throws -> Int

    /// multipart로 보내고 **JSON 본문을 돌려받는다.** 기존 `postMultipartCreated`는
    /// 201 + Location에서 id만 꺼내는 형태라 배차 인식(200 + 결과 JSON)에는 쓸 수 없다.
    func postMultipart<T: Decodable>(
        _ path: String,
        query: [String: String],
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> T
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

    func patchCreated(_ path: String) async throws -> Int {
        try await patchCreated(path, body: nil)
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

    func patchCreated(_ path: String, body: (any Encodable)? = nil) async throws -> Int {
        let (_, response) = try await rawFetchWithResponse("PATCH", path: path, body: body)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let idString = location.split(separator: "/").last,
              let id = Int(idString) else {
            throw APIError.serverError(statusCode: response.statusCode, message: "Location 헤더에서 ID를 찾을 수 없습니다")
        }
        return id
    }

    func postMultipartCreated(_ path: String, fileData: Data, fileName: String, mimeType: String) async throws -> Int {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartBody(boundary: boundary, fileData: fileData, fileName: fileName, mimeType: mimeType)

        let (_, response) = try await rawMultipartFetch(path, body: body, boundary: boundary)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let idString = location.split(separator: "/").last,
              let id = Int(idString) else {
            throw APIError.serverError(statusCode: response.statusCode, message: "Location 헤더에서 ID를 찾을 수 없습니다")
        }
        return id
    }

    func postMultipart<T: Decodable>(
        _ path: String,
        query: [String: String],
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartBody(boundary: boundary, fileData: fileData, fileName: fileName, mimeType: mimeType)
        let pathWithQuery = Self.appending(query: query, to: path)
        let (data, _) = try await rawMultipartFetch(pathWithQuery, body: body, boundary: boundary)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 쿼리를 경로에 붙인다. `rawMultipartFetch`가 경로 문자열만 받기 때문이다.
    static func appending(query: [String: String], to path: String) -> String {
        guard !query.isEmpty else { return path }
        let encoded = query
            .map { key, value in
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(escaped)"
            }
            .joined(separator: "&")
        return path.contains("?") ? "\(path)&\(encoded)" : "\(path)?\(encoded)"
    }

    /// multipart 본문을 순수 함수로 뽑아 둔다 — 서버 `FileController.upload`의
    /// `@RequestParam("file")`과 필드 이름이 어긋나면 사진 업로드가 매번 400으로 죽는데,
    /// 네트워크 계층 전체를 목으로 세우지 않고도 이 이름 하나를 테스트에서 확인할 수 있어야 한다.
    static func multipartBody(boundary: String, fileData: Data, fileName: String, mimeType: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
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
        } catch let error as URLError where error.code == .cancelled {
            // Task 취소로 인한 URLSession 취소는 Swift 표준 CancellationError로 변환
            // 호출자가 `catch is CancellationError`로 일관되게 처리 가능
            throw CancellationError()
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

    private func rawMultipartFetch(
        _ path: String,
        body: Data,
        boundary: String,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let session = SessionManager.shared.urlSession

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 && !isRetry {
            let shouldRetry = await SessionManager.shared.handleUnauthorized()
            if shouldRetry {
                return try await rawMultipartFetch(path, body: body, boundary: boundary, isRetry: true)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8))
        }

        return (data, httpResponse)
    }
}
