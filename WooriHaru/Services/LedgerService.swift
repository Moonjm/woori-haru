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

    // MARK: - 반복 규칙

    func fetchRecurringRules() async throws -> [RecurringRule] {
        let response: DataResponse<[RecurringRule]> = try await api.get("/recurring-rules", query: [:])
        return response.data ?? []
    }

    func createRecurringRule(entryId: Int, dayOfMonth: Int?) async throws {
        try await api.postVoid("/recurring-rules", body: RecurringCreateRequest(entryId: entryId, dayOfMonth: dayOfMonth))
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
