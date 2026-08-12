import Foundation

/// 배차 API. 테스트에서 대체할 수 있도록 프로토콜로 분리한다.
protocol DispatchServing: Sendable {
    /// 사진 한 장을 인식한다. **아무것도 저장되지 않는다** — 검수를 거쳐 `saveShifts`로 확정한다.
    ///
    /// `yearMonth`(`2026-08`)를 함께 보낸다. 서버가 사진에서 연월을 읽어 정하면 「읽기 전에는
    /// 어느 달 기준을 조회할지 모른다」는 순환에 빠지고, 현재 달로 대신하면 8월 말에 9월
    /// 배차표를 미리 올릴 때 엉뚱한 달의 기준을 본다.
    func recognize(imageData: Data, yearMonth: String) async throws -> DispatchRecognition

    /// 검수 확정분을 저장한다. **보낸 날짜만 갱신된다.**
    func saveShifts(_ request: DispatchShiftSaveRequest) async throws
}

struct DispatchService: DispatchServing {
    private let api: APIClientProtocol

    init(api: APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func recognize(imageData: Data, yearMonth: String) async throws -> DispatchRecognition {
        let response: DataResponse<DispatchRecognition> = try await api.postMultipart(
            "/dispatch/recognitions",
            query: ["yearMonth": yearMonth],
            fileData: imageData,
            fileName: "dispatch.jpg",
            mimeType: "image/jpeg"
        )
        guard let recognition = response.data else {
            throw APIError.serverError(statusCode: 200, message: "인식 응답이 비어 있습니다")
        }
        return recognition
    }

    func saveShifts(_ request: DispatchShiftSaveRequest) async throws {
        try await api.postVoid("/dispatch/shifts", body: request)
    }
}
