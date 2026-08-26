import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarValidationTests {

    // MARK: - 차량번호

    /// 웹 JS(`book-car2.js`)와 같은 규칙. **서버가 뭘 막는지 확인하지 않았으므로 앱이 먼저 막는다.**
    @Test func 멀쩡한_차량번호는_통과한다() {
        #expect(VisitorCarValidation.carNoError("12가3456") == nil)
        #expect(VisitorCarValidation.carNoError("123가4567") == nil)
    }

    @Test func 빈_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("") == "차량번호를 입력해 주세요.")
    }

    @Test func 공백이_든_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("12가 3456") == "차량번호에 공백을 넣을 수 없습니다.")
    }

    @Test func 특수문자가_든_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("12가/3456") == "차량번호에 특수문자를 넣을 수 없습니다.")
        #expect(VisitorCarValidation.carNoError("12가3456!") == "차량번호에 특수문자를 넣을 수 없습니다.")
    }

    @Test func 아홉_자를_넘는_차량번호를_막는다() {
        #expect(VisitorCarValidation.carNoError("1234가5678") == nil)          // 9자
        #expect(VisitorCarValidation.carNoError("12345가6789") == "차량번호는 9자를 넘을 수 없습니다.")
    }

    // MARK: - 기간

    @Test func 같은_날은_통과한다() {
        let day = Date(timeIntervalSince1970: 1784300400)
        #expect(VisitorCarValidation.periodError(start: day, end: day) == nil)
    }

    @Test func 종료일이_시작일보다_앞서면_막는다() {
        let start = Date(timeIntervalSince1970: 1784300400)
        let end = start.addingTimeInterval(-86_400)
        #expect(VisitorCarValidation.periodError(start: start, end: end) == "종료일이 시작일보다 앞설 수 없습니다.")
    }

    /// **날짜만 견준다.** 서버가 시각을 00:00:00/23:59:59로 채우므로 같은 날 안의 시각 차이는 뜻이 없다.
    @Test func 같은_날이면_시각이_거꾸로여도_통과한다() {
        let start = Date(timeIntervalSince1970: 1784300400 + 3600 * 20)
        let end = Date(timeIntervalSince1970: 1784300400 + 3600)
        #expect(VisitorCarValidation.periodError(start: start, end: end) == nil)
    }

    // MARK: - 폼 인코딩

    /// **`+`·`&`·`=`를 반드시 인코딩한다** — 안 하면 값에 든 문자가 필드 구분자로 읽힌다.
    @Test func 폼_바디를_인코딩한다() {
        let body = String(decoding: VisitorCarFormEncoder.encode(["b": "2", "a": "1"]), as: UTF8.self)
        // 키 순서를 정렬해 고정한다 — 그래야 테스트가 붙잡을 수 있다.
        #expect(body == "a=1&b=2")
    }

    @Test func 한글과_구분자를_퍼센트로_인코딩한다() {
        let body = String(decoding: VisitorCarFormEncoder.encode(["carNo": "12가3456"]), as: UTF8.self)
        #expect(body == "carNo=12%EA%B0%803456")
    }

    @Test func 값에_든_구분자가_필드를_쪼개지_않는다() {
        let body = String(decoding: VisitorCarFormEncoder.encode(["x": "a&b=c+d"]), as: UTF8.self)
        #expect(body == "x=a%26b%3Dc%2Bd")
    }
}
