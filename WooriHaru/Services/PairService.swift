import Foundation

struct PairService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func getStatus() async throws -> PairInfo? {
        let response: DataResponse<PairInfo?> = try await api.get("/pair", query: [:])
        return response.data ?? nil
    }

    func createInvite() async throws -> PairInviteResponse {
        let response: DataResponse<PairInviteResponse> = try await api.post("/pair/invite", body: nil)
        guard let data = response.data else { throw APIError.decodingError(URLError(.cannotParseResponse)) }
        return data
    }

    func acceptInvite(code: String) async throws -> PairInfo {
        let response: DataResponse<PairInfo> = try await api.post("/pair/accept", body: AcceptInviteRequest(inviteCode: code))
        guard let data = response.data else { throw APIError.decodingError(URLError(.cannotParseResponse)) }
        return data
    }

    func unpair() async throws {
        try await api.deleteVoid("/pair")
    }

    func fetchPartnerRecords(date: String? = nil, from: String? = nil, to: String? = nil) async throws -> [DailyRecord] {
        var query: [String: String] = [:]
        if let date { query["date"] = date }
        if let from { query["from"] = from }
        if let to { query["to"] = to }
        let response: DataResponse<[DailyRecord]> = try await api.get("/pair/daily-records", query: query)
        return response.data ?? []
    }
}
