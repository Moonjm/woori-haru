import Foundation

@MainActor
struct HolidayService {
    private let api = APIClient.shared

    func fetchHolidays(year: String) async throws -> [String: [String]] {
        let response: DataResponse<[String: [String]]> = try await api.get("/holidays", query: ["year": year])
        return response.data ?? [:]
    }
}
