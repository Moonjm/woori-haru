import Foundation

/// 차량 API — 월 요약(그 달 충전 목록 포함)·현재 상태·배터리 건강·주행 인사이트·금액 미등록 목록.
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

    /// **파라미터가 없다.** 전 기간 월별 표본이 오고, 몇 개월을 그릴지는 화면이 정한다.
    /// `/tesla/status`와 독립이다 — 하나가 실패해도 다른 카드는 그린다.
    func fetchBatteryHealth() async throws -> BatteryHealthResponse {
        let response: DataResponse<BatteryHealthResponse> = try await api.get("/tesla/battery-health")
        guard let health = response.data else {
            throw APIError.serverError(statusCode: 200, message: "배터리 건강 응답이 비어 있습니다")
        }
        return health
    }

    /// 네 카드가 **한 응답**에 온다 — 나누면 같은 화면이 네 번 부르고 그중 셋은
    /// 나머지 하나를 기다린다. `months`는 응답에 되돌아 실려 온다.
    func fetchDriveInsights(months: Int) async throws -> DriveInsightsResponse {
        let response: DataResponse<DriveInsightsResponse> =
            try await api.get("/tesla/drive-insights", query: ["months": String(months)])
        guard let insights = response.data else {
            throw APIError.serverError(statusCode: 200, message: "주행 인사이트 응답이 비어 있습니다")
        }
        return insights
    }

    /// 통계 탭 스물여섯 장이 **한 응답**에 온다. `months`는 `0`(전체)과 `1...60`이고
    /// 응답에 되돌아 실려 온다.
    ///
    /// `fetchDriveInsights`는 아직 지우지 않는다 — 서버가 두 엔드포인트를 함께 내는 동안
    /// 앱만 먼저 옮기고, 통계 탭이 이쪽만 쓰게 된 뒤에 지운다.
    func fetchInsights(months: Int) async throws -> InsightsResponse {
        let response: DataResponse<InsightsResponse> =
            try await api.get("/tesla/insights", query: ["months": String(months)])
        guard let insights = response.data else {
            throw APIError.serverError(statusCode: 200, message: "통계 응답이 비어 있습니다")
        }
        return insights
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

    /// 최근 `hours`시간의 상태·주행·충전 구간. **세 배열이 겹친 채로 온다** — 서버가 합치지 않는다.
    /// 범위는 **자정에 맞춰지지 않는다** — `to`가 요청 시각이라 화면의 오른쪽 끝이 「지금」이 된다.
    func fetchStateTimeline(hours: Int = 24) async throws -> StateTimelineResponse {
        let response: DataResponse<StateTimelineResponse> =
            try await api.get("/tesla/state-timeline", query: ["hours": String(hours)])
        guard let timeline = response.data else {
            throw APIError.serverError(statusCode: 200, message: "상태 타임라인 응답이 비어 있습니다")
        }
        return timeline
    }
}
