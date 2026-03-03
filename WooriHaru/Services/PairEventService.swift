import Foundation

struct PairEventService {
    private let api = APIClient.shared

    func fetchEvents(from: String? = nil, to: String? = nil) async throws -> [PairEvent] {
        var query: [String: String] = [:]
        if let from { query["from"] = from }
        if let to { query["to"] = to }
        let response: DataResponse<[PairEvent]> = try await api.get("/pair/events", query: query)
        return response.data ?? []
    }

    func createEvent(_ request: PairEventRequest) async throws {
        try await api.postVoid("/pair/events", body: request)
    }

    func deleteEvent(id: Int) async throws {
        try await api.deleteVoid("/pair/events/\(id)")
    }
}
