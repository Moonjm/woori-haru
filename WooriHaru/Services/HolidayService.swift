import Foundation

struct HolidayService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func fetchHolidays(year: String) async throws -> [String: [String]] {
        let response: DataResponse<[String: [String]]> = try await api.get("/holidays", query: ["year": year])
        return response.data ?? [:]
    }
}
