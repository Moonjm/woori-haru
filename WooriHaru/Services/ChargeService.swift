import Foundation

/// 충전 내역 API(`/tesla/charges`) — TeslaMate DB를 서버가 대신 읽어 준다.
/// 쓰는 것은 금액 한 컬럼뿐이다.
struct ChargeService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    /// 월 단위 조회. 서버는 `yearMonth`(yyyy-MM)나 `from`/`to` 중 하나를 요구한다 —
    /// 아무것도 안 주면 400이다. 화면이 월 단위라 이쪽만 쓴다.
    func fetchCharges(yearMonth: String) async throws -> ChargeListResponse {
        let response: DataResponse<ChargeListResponse> =
            try await api.get("/tesla/charges", query: ["yearMonth": yearMonth])
        guard let list = response.data else {
            throw APIError.serverError(statusCode: 200, message: "충전 내역 응답이 비어 있습니다")
        }
        return list
    }

    func fetchDetail(id: Int) async throws -> ChargeDetail {
        let response: DataResponse<ChargeDetail> = try await api.get("/tesla/charges/\(id)")
        guard let detail = response.data else {
            throw APIError.serverError(statusCode: 200, message: "충전 상세 응답이 비어 있습니다")
        }
        return detail
    }

    /// 금액 수정 — 204. 진행 중인 충전은 서버가 404로 막는다(마감하면서 값이 덮어써지기 때문).
    func updateCost(id: Int, cost: Decimal) async throws {
        try await api.putVoid("/tesla/charges/\(id)/cost", body: ChargeCostRequest(cost: cost))
    }
}
