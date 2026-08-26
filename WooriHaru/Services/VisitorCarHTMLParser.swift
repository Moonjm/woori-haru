import Foundation

/// 사이트가 JSON으로 주지 않는 값을 페이지에서 긁는다.
///
/// **여기가 이 기능에서 가장 부서지기 쉬운 자리다.** 남의 사이트 마크업에 기대고 있어서
/// 저쪽이 화면을 손보면 조용히 죽는다. 그래서 서비스에서 떼어내 순수 함수로 두고
/// 실제 응답 조각으로 테스트를 건다 — 깨졌을 때 어디가 깨졌는지 테스트가 먼저 말하게 한다.
///
/// **HTML 파서를 의존성으로 들이지 않는다.** 찾는 게 히든 인풋 넷뿐이라 정규식으로 족하다.
enum VisitorCarHTMLParser {

    /// 충전 잔여시간(분). 바닥나면 **음수로 온다.**
    static func remainingMinutes(html: String) -> Int? {
        let id = "reservedVehiclePointValue"
        // 속성 순서가 보장되지 않아 양쪽을 다 본다.
        let patterns = [
            #"id="\#(id)"[^>]*?value="(-?\d+)""#,
            #"value="(-?\d+)"[^>]*?id="\#(id)""#,
        ]
        for pattern in patterns {
            if let raw = firstCapture(in: html, pattern: pattern) { return Int(raw) }
        }
        return nil
    }

    /// 등록 폼에 되돌려 보낼 세대 정보.
    ///
    /// **동·호가 하나라도 없으면 `nil`이다.** 빈 값으로 등록하면 다른 세대 이름으로
    /// 예약이 들어갈 수 있어, 반쯤 읽은 결과를 돌려주느니 실패를 알리는 편이 낫다.
    static func household(html: String) -> VisitorCarHousehold? {
        guard let dong = inputValue(in: html, name: "compName"), !dong.isEmpty,
              let ho = inputValue(in: html, name: "deptName"), !ho.isEmpty
        else { return nil }

        return VisitorCarHousehold(
            dong: dong,
            ho: ho,
            // 사이트가 하나뿐이면 `<select>`가 통째로 빠질 수 있다. 실제 응답의 기본값이 `1`이다.
            parkingLot: selectedOptionValue(in: html, name: "parkingLot") ?? "1",
            parkingZone: selectedOptionValue(in: html, name: "parkingZone") ?? "1"
        )
    }

    /// 로그인 실패 리다이렉트의 `result` 쿼리. **이미 사용자용 한국어라 그대로 띄운다.**
    static func loginErrorMessage(location: String) -> String? {
        guard let components = URLComponents(string: location),
              let raw = components.queryItems?.first(where: { $0.name == "result" })?.value,
              !raw.isEmpty
        else { return nil }

        // `URLComponents`는 퍼센트 인코딩만 되돌린다 — 폼 인코딩의 `+`는 직접 공백으로 바꾼다.
        return raw.replacingOccurrences(of: "+", with: " ")
    }

    // MARK: - Private

    private static func inputValue(in html: String, name: String) -> String? {
        firstCapture(in: html, pattern: #"name="\#(name)"[^>]*?value="([^"]*)""#)
    }

    /// `<select name="…">` 블록 안에서 `selected`가 붙은 `<option>`의 값.
    /// **첫 번째 옵션을 집으면 안 된다** — 그 자리는 「선택」·「전체」 같은 빈 값이다.
    private static func selectedOptionValue(in html: String, name: String) -> String? {
        guard let block = firstMatch(in: html, pattern: #"<select[^>]*name="\#(name)"[\s\S]*?</select>"#)
        else { return nil }

        // 실제 응답은 `<option`과 `value=` 사이가 줄바꿈으로 쪼개져 있다 — `[\s\S]`로 받는다.
        // 하지만 `selected` 속성을 찾을 때는 같은 `<option>` 태그 안에서만 찾아야 다른 옵션의 빈 값을 집지 않는다.
        return firstCapture(in: block, pattern: #"<option[\s\S]*?value="([^"]*)"[^>]*?selected"#)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
