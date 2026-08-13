import Foundation

/// 배차 API. 테스트에서 대체할 수 있도록 프로토콜로 분리한다.
protocol DispatchServing: Sendable {
    /// 그 달의 근무를 조회한다. **무인증으로 열려 있고 실명이 실리지 않는다.**
    func findShifts(yearMonth: String) async throws -> [DispatchShiftDay]

    /// 사진 한 장을 인식한다. **아무것도 저장되지 않는다** — 검수를 거쳐 `saveShifts`로 확정한다.
    ///
    /// **연월을 보내지 않는다.** 배차표 사진 위에 연월이 적혀 있고 서버가 그것을 읽는다.
    /// 앱이 보내면 그 값이 기준이 되어 사진 제목을 덮으므로, 사람이 손으로 넣은 오타가
    /// 그대로 엉뚱한 달에 저장된다.
    func recognize(imageData: Data) async throws -> DispatchRecognition

    /// 검수 확정분을 저장한다. **보낸 날짜만 갱신된다.**
    func saveShifts(_ request: DispatchShiftSaveRequest) async throws

    /// 날짜 하나의 근무를 고친다. **보낸 역할만 바뀐다** — nil인 역할은 서버가 건드리지 않는다.
    ///
    /// **응답이 없다(204).** 호출자는 자기가 보낸 값을 이미 알고 있고, 안 보낸 역할은 서버도
    /// 건드리지 않아 화면에 그려진 그대로다. 두 역할이 한 트랜잭션이라 204를 받으면 보낸
    /// 것이 전부 들어갔다.
    func editDay(date: String, request: DispatchDayEditRequest) async throws
}

struct DispatchService: DispatchServing {
    private let api: APIClientProtocol

    init(api: APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func findShifts(yearMonth: String) async throws -> [DispatchShiftDay] {
        let response: DataResponse<DispatchShiftRange> = try await api.get(
            "/dispatch/shifts",
            query: ["yearMonth": yearMonth]
        )
        return response.data?.days ?? []
    }

    func recognize(imageData: Data) async throws -> DispatchRecognition {
        let response: DataResponse<DispatchRecognition> = try await api.postMultipart(
            "/dispatch/recognitions",
            query: [:],
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

    func editDay(date: String, request: DispatchDayEditRequest) async throws {
        try await api.putVoid("/dispatch/shifts/\(date)", body: request)
    }
}
