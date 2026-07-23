import Foundation

/// 가계부 API — 내역·반복 규칙·단축어 API 키.
struct LedgerService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    // MARK: - 내역

    func fetchEntries(yearMonth: String? = nil, keyword: String? = nil) async throws -> [LedgerEntry] {
        var query: [String: String] = [:]
        if let yearMonth { query["yearMonth"] = yearMonth }
        if let keyword, !keyword.isEmpty { query["keyword"] = keyword }
        let response: DataResponse<[LedgerEntry]> = try await api.get("/entries", query: query)
        return response.data ?? []
    }

    func createEntry(_ request: LedgerEntryRequest) async throws {
        try await api.postVoid("/entries", body: request)
    }

    func updateEntry(id: Int, _ request: LedgerEntryRequest) async throws {
        try await api.putVoid("/entries/\(id)", body: request)
    }

    func deleteEntry(id: Int) async throws {
        try await api.deleteVoid("/entries/\(id)")
    }

    func fetchStatistics(yearMonth: String) async throws -> LedgerStatistics {
        let response: DataResponse<LedgerStatistics> =
            try await api.get("/entries/statistics", query: ["yearMonth": yearMonth])
        guard let statistics = response.data else {
            throw APIError.serverError(statusCode: 200, message: "통계 응답이 비어 있습니다")
        }
        return statistics
    }

    /// 연별 통계 — 기준연 12개월 추이·집계.
    func fetchStatistics(year: Int) async throws -> LedgerStatistics {
        let response: DataResponse<LedgerStatistics> =
            try await api.get("/entries/statistics/yearly", query: ["year": String(year)])
        guard let statistics = response.data else {
            throw APIError.serverError(statusCode: 200, message: "통계 응답이 비어 있습니다")
        }
        return statistics
    }

    // MARK: - 반복 규칙

    func fetchRecurringRules() async throws -> [RecurringRule] {
        let response: DataResponse<[RecurringRule]> = try await api.get("/recurring-rules", query: [:])
        return response.data ?? []
    }

    func createRecurringRule(entryId: Int, dayOfMonth: Int?) async throws {
        try await api.postVoid("/recurring-rules", body: RecurringCreateRequest(entryId: entryId, dayOfMonth: dayOfMonth))
    }

    /// 서버가 중복 리소스(이미 같은 반복 규칙 존재)로 거절했는지 — 에러 바디의 코드명으로 판별.
    static func isDuplicateError(_ error: Error) -> Bool {
        if case let APIError.serverError(_, message) = error {
            return message?.contains("DUPLICATE_RESOURCE") == true
        }
        return false
    }

    // MARK: - 수신 실패 (파싱 실패 문자)

    func fetchInboundFailures() async throws -> [LedgerInboundFailure] {
        let response: DataResponse<[LedgerInboundFailure]> = try await api.get("/inbound/failures", query: [:])
        return response.data ?? []
    }

    /// 보존된 원문 재처리 — 성공 시 내역이 생성된다. 재실패는 MESSAGE_PARSE_FAILED(400).
    func retryInbound(id: Int) async throws {
        try await api.postVoid("/inbound/\(id)/retry")
    }

    func deleteInboundFailure(id: Int) async throws {
        try await api.deleteVoid("/inbound/\(id)")
    }

    /// 재시도했지만 여전히 파싱 불가인지 — 에러 바디의 코드명으로 판별.
    static func isParseFailedError(_ error: Error) -> Bool {
        if case let APIError.serverError(_, message) = error {
            return message?.contains("MESSAGE_PARSE_FAILED") == true
        }
        return false
    }

    func updateRecurringRule(id: Int, _ request: RecurringUpdateRequest) async throws {
        try await api.putVoid("/recurring-rules/\(id)", body: request)
    }

    func deleteRecurringRule(id: Int) async throws {
        try await api.deleteVoid("/recurring-rules/\(id)")
    }

    // MARK: - 단축어 API 키

    func fetchApiKeys() async throws -> [LedgerApiKey] {
        let response: DataResponse<[LedgerApiKey]> = try await api.get("/api-keys", query: [:])
        return response.data ?? []
    }

    /// 원본 키는 이 응답에서만 확인할 수 있다.
    func issueApiKey(name: String) async throws -> IssuedLedgerApiKey {
        struct NameRequest: Encodable { let name: String }
        let response: DataResponse<IssuedLedgerApiKey> = try await api.post("/api-keys", body: NameRequest(name: name))
        guard let issued = response.data else {
            throw APIError.serverError(statusCode: 200, message: "발급 응답이 비어 있습니다")
        }
        return issued
    }

    func deleteApiKey(id: Int) async throws {
        try await api.deleteVoid("/api-keys/\(id)")
    }
}
