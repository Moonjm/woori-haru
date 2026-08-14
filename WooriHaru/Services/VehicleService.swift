import Foundation

/// 차량 API — 월 요약(그 달 충전 목록 포함)·현재 상태·금액 미등록 목록.
/// 충전 상세와 금액 수정은 `ChargeService`가 그대로 맡는다.
struct VehicleService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func fetchSummary(yearMonth: String) async throws -> VehicleSummaryResponse {
        let response: DataResponse<VehicleSummaryResponse> =
            try await api.get("/tesla/summary", query: ["yearMonth": yearMonth])
        guard let summary = response.data else {
            throw APIError.serverError(statusCode: 200, message: "차량 요약 응답이 비어 있습니다")
        }
        return summary
    }

    func fetchStatus() async throws -> VehicleStatus {
        let response: DataResponse<VehicleStatus> = try await api.get("/tesla/status")
        guard let status = response.data else {
            throw APIError.serverError(statusCode: 200, message: "차량 상태 응답이 비어 있습니다")
        }
        return status
    }

    /// 기간이 없다. 채워 넣으려는 사람에게 필요한 것은 「빈 건 전부」다.
    func fetchMissingCost(limit: Int = 50) async throws -> MissingCostResponse {
        let response: DataResponse<MissingCostResponse> =
            try await api.get("/tesla/charges/missing-cost", query: ["limit": String(limit)])
        guard let missing = response.data else {
            throw APIError.serverError(statusCode: 200, message: "미등록 목록 응답이 비어 있습니다")
        }
        return missing
    }
}
