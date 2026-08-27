import Foundation

/// 등록 폼 입력 검증. 웹 JS(`book-car2.js`)의 규칙을 그대로 옮겼다.
///
/// **서버가 무엇을 막는지 확인하지 않았다.** 등록 한 건을 실제로 넣어 본 것이 전부라
/// 거절 규칙을 모른다. 그래서 앱이 먼저 막는다 — 왕복 한 번을 아끼고, 무엇이 잘못됐는지도
/// 서버의 알 수 없는 메시지 대신 이쪽 문구로 말한다.
enum VisitorCarValidation {
    /// 웹 JS의 `checkSpecial` 정규식과 같은 집합.
    private static let forbidden = CharacterSet(charactersIn: #"`~!@#$%^&*|\'";:/?"#)

    static func carNoError(_ value: String) -> String? {
        if value.isEmpty { return "차량번호를 입력해 주세요." }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return "차량번호에 공백을 넣을 수 없습니다."
        }
        if value.rangeOfCharacter(from: forbidden) != nil {
            return "차량번호에 특수문자를 넣을 수 없습니다."
        }
        if value.count > 9 { return "차량번호는 9자를 넘을 수 없습니다." }
        return nil
    }

    /// **날짜만 견준다.** 서버가 시각을 00:00:00/23:59:59로 채우므로 같은 날 안의 시각 차이는 뜻이 없다.
    /// 달력은 `VisitorCarDateFormat.seoulCalendar` 하나를 그대로 쓴다 — 여기서 따로 만들면
    /// 두 자리가 각자 「한국 시간대」를 조립하게 되고, 그중 하나만 고치는 사고가 난다.
    static func periodError(start: Date, end: Date) -> String? {
        let calendar = VisitorCarDateFormat.seoulCalendar
        if calendar.startOfDay(for: end) < calendar.startOfDay(for: start) {
            return "종료일이 시작일보다 앞설 수 없습니다."
        }
        return nil
    }

    /// **시각 자체를 견준다.** `periodError`와 짝이지만 다른 화면을 위한 규칙이다(P2) —
    /// 등록·예약 조회는 날짜만 고르므로 서버가 시각을 00:00:00/23:59:59로 채워 같은 날
    /// 안의 시각 차이가 뜻이 없지만, **차량 진입 현황 화면은 피커가 시·분까지 받고 그
    /// 정확한 시각을 그대로 서버에 보낸다.** 같은 날 안에서 시각이 거꾸로면(예: 18:00 →
    /// 09:00) `periodError`는 날짜만 보므로 통과시키지만, 그 값이 그대로 서버로 나가
    /// 오류나 「입출차 내역이 없습니다」(사실은 역전된 조회일 뿐인데 「내역이 사라졌다」로
    /// 읽힌다)를 부른다.
    ///
    /// **`periodError`와 하나로 합치지 말 것.** `periodError`가 날짜 단위로 동작함을
    /// 증명하는 테스트(`같은_날이면_시각이_거꾸로여도_통과한다`)가 따로 있다 — 합치면 그
    /// 테스트가 깨지거나, 깨지지 않도록 억지로 맞추는 과정에서 이 규칙이 다시 조용히
    /// 사라진다. 두 규칙이 다른 이유는 두 화면이 다루는 단위가 다르기 때문이다:
    /// 날짜만 고르는 화면과, 시각까지 고르는 화면.
    static func timeRangeError(start: Date, end: Date) -> String? {
        if end < start {
            return "종료 시각이 시작 시각보다 앞설 수 없습니다."
        }
        return nil
    }

    /// 방문사유 칸의 최대 길이. 웹 폼이 20자로 못박아 둔 값이다.
    static let visitReasonLimit = 20

    /// 방문사유를 제한 길이로 자른다. **여기 한 곳에 모아 둔다** — 등록 화면과 수정 시트가
    /// 같은 값을 같은 서버 필드(`address`)로 보내는데, 검증을 뷰 하나에만 두면 다른
    /// 진입점이 무제한으로 새어 나간다.
    static func clampVisitReason(_ value: String) -> String {
        value.count > visitReasonLimit ? String(value.prefix(visitReasonLimit)) : value
    }
}

/// `application/x-www-form-urlencoded` 바디를 만든다.
///
/// **`URLComponents`를 쓰지 않는다.** 그쪽은 `+`·`&`·`=`를 값 안에서 살려 두는데,
/// 그러면 차량번호나 방문사유에 든 문자가 필드 구분자로 읽힌다.
enum VisitorCarFormEncoder {
    /// 퍼센트 인코딩에서 살려 둘 문자. RFC 3986의 unreserved 집합이다.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ fields: [String: String]) -> Data {
        let body = fields
            // 키 순서를 정렬해 고정한다 — 딕셔너리 순서는 실행마다 달라 테스트가 붙잡을 수 없다.
            .sorted { $0.key < $1.key }
            .map { key, value in "\(escape(key))=\(escape(value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
