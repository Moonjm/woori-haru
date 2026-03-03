import Foundation

struct RecordService {
    private let api = APIClient.shared

    func fetchRecords(date: String? = nil, from: String? = nil, to: String? = nil) async throws -> [DailyRecord] {
        var query: [String: String] = [:]
        if let date { query["date"] = date }
        if let from { query["from"] = from }
        if let to { query["to"] = to }
        let response: DataResponse<[DailyRecord]> = try await api.get("/daily-records", query: query)
        return response.data ?? []
    }

    func createRecord(_ request: DailyRecordRequest) async throws {
        try await api.postVoid("/daily-records", body: request)
    }

    func updateRecord(id: Int, _ request: DailyRecordRequest) async throws {
        try await api.putVoid("/daily-records/\(id)", body: request)
    }

    func deleteRecord(id: Int) async throws {
        try await api.deleteVoid("/daily-records/\(id)")
    }

    func fetchOvereats(from: String, to: String) async throws -> [DailyOvereat] {
        let response: DataResponse<[DailyOvereat]> = try await api.get("/daily-overeats", query: ["from": from, "to": to])
        return response.data ?? []
    }

    func updateOvereat(_ request: UpdateOvereatRequest) async throws {
        try await api.putVoid("/daily-overeats", body: request)
    }
}
