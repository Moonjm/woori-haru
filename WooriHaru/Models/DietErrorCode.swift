import Foundation

/// 식단 도메인 에러. **분기 기준은 응답 바디의 `error` 필드다** —
/// `code`는 HTTP 상태를 문자열로 담을 뿐이라(`"400"`) 종류를 가르지 못한다.
enum DietErrorCode: String {
    case profileNotFound = "PROFILE_NOT_FOUND"
    case photoLimitExceeded = "PHOTO_LIMIT_EXCEEDED"
    case llmUnavailable = "LLM_UNAVAILABLE"
    case analysisNotConfirmable = "ANALYSIS_NOT_CONFIRMABLE"
    case analysisNotRetryable = "ANALYSIS_NOT_RETRYABLE"
    case analysisInProgress = "ANALYSIS_IN_PROGRESS"
    /// 코치가 답을 만들지 못했다(503). **재시도가 옳은 실패다** — 서버가 질문도 저장하지 않는다.
    case chatFailed = "CHAT_FAILED"
    case resourceNotFound = "RESOURCE_NOT_FOUND"
    case invalidRequest = "INVALID_REQUEST"
}

private struct DietErrorBody: Decodable {
    let error: String
}

extension Error {
    /// `APIError.serverError`의 message에 실려 온 JSON 본문에서 `error`를 읽는다.
    /// 본문이 JSON이 아니거나 아는 코드가 아니면 nil — 호출부는 일반 오류로 다룬다.
    var dietErrorCode: DietErrorCode? {
        guard let apiError = self as? APIError,
              case let .serverError(_, message) = apiError,
              let data = message?.data(using: .utf8),
              let body = try? JSONDecoder().decode(DietErrorBody.self, from: data) else {
            return nil
        }
        return DietErrorCode(rawValue: body.error)
    }
}
