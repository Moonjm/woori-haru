import Foundation
import Testing
@testable import WooriHaru

struct DateExtensionsTests {
    @Test func dateString_파싱_왕복() {
        let date = Date.from("2026-02-14")
        #expect(date != nil)
        #expect(date?.dateString == "2026-02-14")
    }

    @Test func from_잘못된_문자열은_nil() {
        #expect(Date.from("not-a-date") == nil)
        #expect(Date.from("") == nil)
    }

    @Test func fromISO_마이크로초_포함_미포함_모두_파싱() {
        #expect(Date.fromISO("2026-07-24T10:30:00") != nil)
        #expect(Date.fromISO("2026-07-24T10:30:00.123456") != nil)
        #expect(Date.fromISO("2026-07-24") == nil)
    }

    @Test func monthRange_일반_월() {
        let range = Date.monthRange(year: 2026, month: 2)
        #expect(range.from == "2026-02-01")
        #expect(range.to == "2026-02-28")
    }

    @Test func monthRange_윤년_2월() {
        let range = Date.monthRange(year: 2024, month: 2)
        #expect(range.to == "2024-02-29")
    }

    @Test func monthRange_31일_월과_30일_월() {
        #expect(Date.monthRange(year: 2026, month: 7).to == "2026-07-31")
        #expect(Date.monthRange(year: 2026, month: 4).to == "2026-04-30")
    }

    @Test func monthRange_month_0은_연간_전체() {
        let range = Date.monthRange(year: 2026, month: 0)
        #expect(range.from == "2026-01-01")
        #expect(range.to == "2026-12-31")
    }

    @Test func durationText_경계값() {
        #expect(0.durationText == "1분 미만")
        #expect(59.durationText == "1분 미만")
        #expect(60.durationText == "1분")
        #expect(3599.durationText == "59분")
        #expect(3600.durationText == "1시간 0분")
        #expect(5400.durationText == "1시간 30분")
    }

    @Test func 달력_구성요소() {
        let date = Date.from("2026-02-01")!
        #expect(date.year == 2026)
        #expect(date.month == 2)
        #expect(date.day == 1)
        #expect(date.isSunday)  // 2026-02-01은 일요일
        #expect(date.daysInMonth() == 28)
        #expect(date.startOfMonth().dateString == "2026-02-01")
    }

    @Test func addingMonths_연도_경계() {
        let date = Date.from("2026-12-15")!
        #expect(date.addingMonths(1).yearMonth == "2027-01")
        #expect(date.addingMonths(-12).yearMonth == "2025-12")
    }
}
