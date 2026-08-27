import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarModelTests {

    /// 실제 `/nxpmsc/web/book-car/pageList` 응답을 그대로 옮긴 것.
    /// 필드가 하나라도 어긋나면 디코딩이 깨진다.
    ///
    /// **유닉스 초를 눈으로 읽지 말 것.** `1784300400` = 2026-07-18 00:00:00 KST,
    /// `1784386799` = 같은 날 23:59:59다. 기대값을 고칠 일이 생기면 `date -r`로 먼저 검산한다.
    static let bookingJSON = """
    {"data":{"content":[{"id":25752,"compName":"1001","deptName":"0101","name":"",
      "carNo":"12가3456","tel":"","startDate":1784300400,"endDate":1784386799,
      "updateDate":1784356046,"userName":"10010101","insertType":"W","address":"택배"}],
      "totalElements":1,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
    """

    /// 실제 `/nxpmsc/web/car/reserved-vehicle-entry-status-by-generation-page` 응답.
    /// **`message: "200"`이 붙는다** — 등록 내역 쪽에는 없다. 읽지 않고 흘린다.
    static let entryJSON = """
    {"message":"200","data":{"content":[
      {"id":354751,"inDate":1784357197,"outDate":1784374505,"outChk":2,
       "carNo":"12가3456","name":"","startDate":1784300400,"endDate":1784386799,
       "updateDate":1784356046},
      {"id":354752,"inDate":1784380000,"outDate":null,"outChk":0,
       "carNo":"12가3456","name":"","startDate":1784300400,"endDate":1784386799,
       "updateDate":1784356046}],
      "totalElements":2,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
    """

    @Test func 등록_내역을_디코딩한다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarBooking>.self, from: Data(Self.bookingJSON.utf8))
            .data
        let booking = try #require(page.content.first)

        #expect(page.totalElements == 1)
        #expect(booking.id == 25752)
        #expect(booking.carNo == "12가3456")
        #expect(booking.dong == "1001")
        #expect(booking.ho == "0101")
        #expect(booking.registrant == "10010101")
        #expect(booking.insertType == .preVisit)
        // `address`가 방문사유다. 이름이 어긋나 있어 모델에서 바꿔 받는다.
        #expect(booking.visitReason == "택배")
        #expect(booking.startDate == Date(timeIntervalSince1970: 1784300400))
        #expect(booking.updateDate == Date(timeIntervalSince1970: 1784356046))
    }

    /// 사이트가 새 등록구분을 늘려도 화면이 죽지 않아야 한다.
    @Test func 모르는_등록구분은_unknown이다() {
        #expect(VisitorCarInsertType(rawValue: "Z") == nil)
        #expect(VisitorCarInsertType.from("Z") == .unknown)
        #expect(VisitorCarInsertType.from("K") == .kiosk)
        #expect(VisitorCarInsertType.kiosk.label == "키오스크")
    }

    @Test func 진입_현황을_디코딩한다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(Self.entryJSON.utf8))
            .data

        #expect(page.content.count == 2)
        #expect(page.content[0].status == .exited)
        #expect(page.content[0].outDate == Date(timeIntervalSince1970: 1784374505))
    }

    /// **아직 안 나간 차는 `outDate`가 `null`이다.** 0으로 접으면 1970년에 나간 차가 된다.
    @Test func 출차_전이면_outDate가_nil이다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(Self.entryJSON.utf8))
            .data
        let parked = page.content[1]

        #expect(parked.outDate == nil)
        #expect(parked.status == .entered)
    }

    /// 주차시간은 저장하지 않고 그릴 때 센다 — 안 나간 차는 계속 흘러야 한다.
    @Test func 주차시간은_출차_전이면_지금까지_센다() throws {
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(Self.entryJSON.utf8))
            .data
        let now = Date(timeIntervalSince1970: 1784383600)

        #expect(page.content[0].parkingSeconds(now: now) == 1784374505 - 1784357197)
        #expect(page.content[1].parkingSeconds(now: now) == 1784383600 - 1784380000)
    }

    /// `outChk`가 0~5 밖이면 화면에 빈칸을 둔다 — 웹의 `default` 분기와 같게.
    @Test func 모르는_차량상태는_nil이다() throws {
        let json = """
        {"data":{"content":[{"id":1,"inDate":1784357197,"outDate":null,"outChk":9,
          "carNo":"12가3456","name":"","startDate":1,"endDate":2,"updateDate":3}],
          "totalElements":1,"totalPages":1,"number":0,"size":10,"first":true,"last":true}}
        """
        let page = try JSONDecoder()
            .decode(VisitorCarPageResponse<VisitorCarEntry>.self, from: Data(json.utf8))
            .data

        #expect(page.content[0].status == nil)
    }

    @Test func 등록_응답의_성공을_가른다() throws {
        let ok = try JSONDecoder().decode(
            VisitorCarResult.self,
            from: Data(#"{"result":"success","message":"성공적으로 등록되었습니다."}"#.utf8)
        )
        let ng = try JSONDecoder().decode(
            VisitorCarResult.self,
            from: Data(#"{"result":"fail","message":"입차 후 수정/삭제 불가능합니다."}"#.utf8)
        )

        #expect(ok.isSuccess)
        #expect(!ng.isSuccess)
        #expect(ng.message == "입차 후 수정/삭제 불가능합니다.")
    }

    /// **두 엔드포인트의 날짜 형식이 다르다.** 진입 현황에 날짜만 보내면 500이 떨어진다.
    @Test func 날짜_포맷이_엔드포인트별로_갈린다() {
        let date = Date(timeIntervalSince1970: 1784300400) // 2026-07-18 00:00:00 KST

        #expect(VisitorCarDateFormat.day.string(from: date) == "2026-07-18")
        #expect(VisitorCarDateFormat.second.string(from: date) == "2026-07-18 00:00:00")
    }

    // MARK: - 한국 시간대

    /// 날짜 선택기에 주입하는 값이 실제로 `Asia/Seoul`인지 못 박아 둔다.
    /// (선택기 환경 주입 자체는 SwiftUI 뷰 안의 일이라 유닛 테스트로 붙잡을 수 없다 —
    /// 여기서 붙잡는 것은 그 값의 **정체**뿐이다.)
    @Test func seoulTimeZone은_아시아_서울이다() {
        #expect(VisitorCarDateFormat.seoulTimeZone.identifier == "Asia/Seoul")
    }

    /// `seoulCalendar`가 `seoulTimeZone`과 다른 시간대를 들고 있으면, 선택기와
    /// 포맷터가 같은 값을 주입받고도 서로 다른 하루를 계산하게 된다.
    @Test func seoulCalendar와_seoulTimeZone은_같은_시간대를_가리킨다() {
        #expect(VisitorCarDateFormat.seoulCalendar.timeZone == VisitorCarDateFormat.seoulTimeZone)
        #expect(VisitorCarDateFormat.seoulCalendar.identifier == .gregorian)
    }

    /// **선택기 환경 주입은 SwiftUI 뷰 안의 일이라 유닛 테스트로 확인할 수 없다.**
    /// 대신 여기서 확인하는 것: 서울 달력 성분으로 만든 `Date`가 `VisitorCarDateFormat.day`를
    /// 거쳐도 같은 연-월-일 숫자로 되돌아온다 — 선택기가 `seoulCalendar`로 값을 만들기만
    /// 하면(뷰가 실제로 그렇게 하는지는 코드 검사로 확인했다) 포맷터와 어긋나지 않는다.
    @Test func 서울_달력_성분으로_만든_날짜는_day_포맷터를_왕복한다() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 18
        let date = try #require(VisitorCarDateFormat.seoulCalendar.date(from: components))

        #expect(VisitorCarDateFormat.day.string(from: date) == "2026-07-18")
    }
}
