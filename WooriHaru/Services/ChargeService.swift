import Foundation

/// 충전 상세와 금액 수정. 월 목록은 `/tesla/summary`가 함께 내려주므로 여기 없다.
struct ChargeService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
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

    /// 파라미터가 없다. 전 기간이다. **`/tesla/charges/missing-cost`의 `totalCount`와 다른 수를 낸다** —
    /// 그쪽은 최근 한 달 창이라 배지에 섞어 쓰면 어긋난다.
    func fetchTotals() async throws -> ChargeTotalsResponse {
        let response: DataResponse<ChargeTotalsResponse> = try await api.get("/tesla/charges/totals")
        guard let totals = response.data else {
            throw APIError.serverError(statusCode: 200, message: "충전 누적 응답이 비어 있습니다")
        }
        return totals
    }

    /// 그 세션의 kW 곡선. **끝난 충전만 온다** — 진행 중이면 서버가 404다.
    func fetchCurve(id: Int) async throws -> ChargeCurveResponse {
        let response: DataResponse<ChargeCurveResponse> = try await api.get("/tesla/charges/\(id)/curve")
        guard let curve = response.data else {
            throw APIError.serverError(statusCode: 200, message: "충전 곡선 응답이 비어 있습니다")
        }
        return curve
    }
}
