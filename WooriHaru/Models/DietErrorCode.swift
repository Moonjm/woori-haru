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

private struct ServerErrorBody: Decodable {
    let message: String?
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

    /// 같은 본문에서 사용자용 `message`만 꺼낸다.
    ///
    /// `APIError.serverError(message:)`에는 **서버 메시지가 아니라 응답 본문 전체**가 들어간다
    /// (`APIClient`가 `String(data: data, encoding: .utf8)`을 그대로 싣는다). 그래서
    /// `localizedDescription`을 그대로 띄우면 `{"status":400,"message":"...","code":"400", ...}`가
    /// 사용자 눈앞에 나온다. 본문이 JSON이 아니거나 `message`가 비어 있으면 nil —
    /// 호출부는 기존처럼 `localizedDescription`으로 떨어진다.
    var serverMessage: String? {
        guard let apiError = self as? APIError,
              case let .serverError(_, message) = apiError,
              let data = message?.data(using: .utf8),
              let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data),
              let text = body.message,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}
