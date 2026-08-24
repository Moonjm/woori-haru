import Foundation

/// 관리비 API. 테스트에서 대체할 수 있도록 프로토콜로 분리한다(`DispatchServing`과 같은 꼴).
protocol MaintenanceServing: Sendable {
    /// 저장된 달 전부. **최근 달부터 온다** — 목록 화면이 그 순서를 그대로 쓴다.
    func fetchBills() async throws -> [MaintenanceBill]

    func fetchBill(yearMonth: String) async throws -> MaintenanceBill

    /// 고지서 사진 한 장을 인식한다. **아무것도 저장되지 않는다** — 검수를 거쳐 `saveBill`로 확정한다.
    ///
    /// **연월을 보내지 않는다.** 고지서에 적힌 것을 서버가 읽는다. 앱이 보내면 사람이 손으로
    /// 넣은 오타가 그대로 엉뚱한 달에 저장된다(배차표에서 같은 판단을 했다).
    func recognize(imageData: Data) async throws -> MaintenanceRecognition

    /// 검수 확정분을 저장한다. **같은 달이 이미 있으면 409다** — 호출부가 「기존 내역 수정」으로 잇는다.
    func saveBill(_ request: MaintenanceBillSaveRequest) async throws

    /// 한 달을 통째로 갈아 끼운다. 항목은 병합이 아니라 교체다.
    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws

    func deleteBill(yearMonth: String) async throws

    /// 항목·사용량 월별 추이. **13이 기본인 이유는 전년 동월이 범위에 들어오게 하려는 것이다.**
    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth]
}

struct MaintenanceService: MaintenanceServing {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func fetchBills() async throws -> [MaintenanceBill] {
        let response: DataResponse<MaintenanceBillList> =
            try await api.get("/maintenance/bills", query: [:])
        return response.data?.bills ?? []
    }

    func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
        let response: DataResponse<MaintenanceBill> =
            try await api.get("/maintenance/bills/\(yearMonth)", query: [:])
        guard let bill = response.data else {
            throw APIError.serverError(statusCode: 200, message: "관리비 응답이 비어 있습니다")
        }
        return bill
    }

    func recognize(imageData: Data) async throws -> MaintenanceRecognition {
        let response: DataResponse<MaintenanceRecognition> = try await api.postMultipart(
            "/maintenance/recognitions",
            query: [:],
            fileData: imageData,
            fileName: "maintenance.jpg",
            mimeType: "image/jpeg"
        )
        guard let recognition = response.data else {
            throw APIError.serverError(statusCode: 200, message: "인식 응답이 비어 있습니다")
        }
        return recognition
    }

    func saveBill(_ request: MaintenanceBillSaveRequest) async throws {
        // 201 본문에 문자열이 실려 오지만 쓰지 않는다 — 저장한 연월은 호출부가 이미 안다.
        try await api.postVoid("/maintenance/bills", body: request)
    }

    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {
        try await api.putVoid("/maintenance/bills/\(yearMonth)", body: request)
    }

    func deleteBill(yearMonth: String) async throws {
        try await api.deleteVoid("/maintenance/bills/\(yearMonth)")
    }

    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] {
        let response: DataResponse<MaintenanceTrend> =
            try await api.get("/maintenance/trends", query: ["months": String(months)])
        return response.data?.months ?? []
    }
}
