import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarHTMLParserTests {

    /// 실제 `/nxpmsc/book-car` 응답에서 잘라 온 조각. 앞뒤 잡동사니를 남겨 둔 이유는
    /// **파서가 페이지 통째에서 찾아내야** 하기 때문이다 — 깔끔한 한 줄만 주면 시험이 안 된다.
    static let bookCarHTML = """
    <li class="nav-item" data-toggle="tooltip" title="충전 잔여시간">
      <a class="nav-link" href="#"> <i class="fa fa-fw fa-money"></i>
        <span class="nav-link-text">100시 0분 남음</span>
      </a>
    </li>
    <input type="hidden" id="bookcarSiteName" value="none">
    <input type="hidden" id="reservedVehiclePointValue" value="6000"/>
    <table id="bookCarTable" width="100%"></table>
    """

    /// 실제 `/nxpmsc/book-car/getOriginal` 응답에서 잘라 온 조각.
    /// **`parkingZone`의 `<option>`은 줄바꿈으로 쪼개져 있다** — 실제 응답이 그렇다.
    static let registerFormHTML = """
    <form method="post" class="col-lg-12" id="bookCar" action="/nxpmsc/book-car/add">
      <input type="hidden" name="id" id="id" value="" />
      <input type="hidden" name="siteName" id="siteName" value="none" />
      <select class="form-control" name="parkingLot" id="parkingLot">
        <option value="">선택</option>
        <option value="1" selected="selected">○○아파트</option>
      </select>
      <select class="form-control" name="parkingZone" id="parkingZone">
        <option value="">전체</option>
        <option
            value="2"
            selected="selected">기본 구역</option>
      </select>
      <input class="form-control" type="text" name="name" id="name" value="" />
      <input class="form-control" type="text" name="compName" id="compName" value="1001" readonly="readonly" />
      <input class="form-control" type="text" name="deptName" id="deptName" value="0101" readonly="readonly" />
    </form>
    """

    // MARK: - 잔여시간

    /// **화면에 보이는 「100시 0분 남음」이 아니라 이 숫자를 읽는다.**
    /// 문구는 현장마다 갈리지만 히든 필드는 값 하나다.
    @Test func 잔여시간을_분으로_읽는다() {
        #expect(VisitorCarHTMLParser.remainingMinutes(html: Self.bookCarHTML) == 6000)
    }

    /// 잔여시간이 바닥나면 음수가 온다. 웹은 「N분 초과 사용하였습니다」 모달을 띄운다.
    @Test func 초과_사용은_음수로_온다() {
        let html = #"<input type="hidden" id="reservedVehiclePointValue" value="-120"/>"#
        #expect(VisitorCarHTMLParser.remainingMinutes(html: html) == -120)
    }

    /// 속성 순서는 보장되지 않는다 — `value`가 `id`보다 앞설 수도 있다.
    @Test func 속성_순서가_뒤바뀌어도_읽는다() {
        let html = #"<input value="30" type="hidden" id="reservedVehiclePointValue"/>"#
        #expect(VisitorCarHTMLParser.remainingMinutes(html: html) == 30)
    }

    /// **마크업이 바뀌면 크래시가 아니라 nil이다.** 화면은 「잔여시간을 불러오지 못했습니다」를 띄운다.
    @Test func 필드가_없으면_nil이다() {
        #expect(VisitorCarHTMLParser.remainingMinutes(html: "<html><body>로그인</body></html>") == nil)
    }

    // MARK: - 세대 정보

    @Test func 동_호_주차장_구역을_읽는다() throws {
        let household = try #require(VisitorCarHTMLParser.household(html: Self.registerFormHTML))

        #expect(household.dong == "1001")
        #expect(household.ho == "0101")
        #expect(household.parkingLot == "1")
        // 선택된 `<option>`을 골라야 한다 — 첫 번째(빈 값 "전체")를 집으면 등록이 엉뚱한 구역으로 간다.
        #expect(household.parkingZone == "2")
    }

    /// **동·호를 못 읽으면 등록을 막는다** — 빈 동·호로 보내면 다른 세대 이름으로 예약이 들어갈 수 있다.
    @Test func 동이_없으면_nil이다() {
        let html = #"<input name="deptName" value="0101" />"#
        #expect(VisitorCarHTMLParser.household(html: html) == nil)
    }

    /// 주차장·구역은 사이트가 하나뿐이면 `<select>` 없이 올 수도 있다. 그때는 `1`로 둔다 —
    /// 등록 폼이 이 값을 반드시 요구하고, 실제 응답의 기본값이 `1`이다.
    @Test func 주차장_select가_없으면_1로_둔다() throws {
        let html = """
        <input name="compName" value="1001" />
        <input name="deptName" value="0101" />
        """
        let household = try #require(VisitorCarHTMLParser.household(html: html))

        #expect(household.parkingLot == "1")
        #expect(household.parkingZone == "1")
    }

    // MARK: - 로그인 오류

    /// 로그인 성공·실패가 **둘 다 302**다. `Location`으로 갈라야 하고,
    /// 실패 쪽 `result`에는 **이미 사용자용 한국어**가 실려 온다.
    @Test func 로그인_실패_메시지를_뽑는다() {
        let location = "http://example.org/nxpmsc/login;jsessionid=ABC?result="
            + "%EC%95%84%EC%9D%B4%EB%94%94+%EB%98%90%EB%8A%94+"
            + "%EB%B9%84%EB%B0%80%EB%B2%88%ED%98%B8%EA%B0%80+"
            + "%EC%9E%98%EB%AA%BB%EB%90%98%EC%97%88%EC%8A%B5%EB%8B%88%EB%8B%A4."

        #expect(VisitorCarHTMLParser.loginErrorMessage(location: location)
                == "아이디 또는 비밀번호가 잘못되었습니다.")
    }

    /// 성공 쪽 `Location`에는 `result`가 없다.
    @Test func 성공_리다이렉트에는_메시지가_없다() {
        #expect(VisitorCarHTMLParser.loginErrorMessage(location: "http://example.org/nxpmsc/book-car") == nil)
    }
}
