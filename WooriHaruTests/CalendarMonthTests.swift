import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct CalendarMonthTests {
    private func makeViewModel() -> CalendarViewModel {
        let mock = MockAPIClient()
        return CalendarViewModel(
            recordService: RecordService(api: mock),
            holidayService: HolidayService(api: mock),
            pairService: PairService(api: mock),
            pairEventService: PairEventService(api: mock)
        )
    }

    @Test func 이월_2026은_패딩_없이_정확히_4주() {
        let month = makeViewModel().buildMonthData(Date.from("2026-02-01")!)
        #expect(month.id == "2026-02")
        #expect(month.year == 2026)
        #expect(month.month == 2)
        #expect(month.cells.count == 28)  // 일요일 시작 + 28일 = 패딩 없음
        #expect(month.cells.allSatisfy { $0.isCurrentMonth })
        #expect(month.cells.first?.day == 1)
        #expect(month.cells.last?.day == 28)
    }

    @Test(arguments: ["2026-01-01", "2026-07-01", "2024-02-01", "2025-12-01", "2026-08-01"])
    func 월_그리드_불변식(startString: String) {
        let start = Date.from(startString)!
        let month = makeViewModel().buildMonthData(start)

        // 그리드는 항상 7의 배수
        #expect(month.cells.count % 7 == 0)
        // 현재 월 셀 수 == 해당 월의 실제 일수
        #expect(month.cells.filter(\.isCurrentMonth).count == start.daysInMonth())
        // 앞쪽 패딩 수 == 시작 요일 오프셋 (일요일 시작 달력)
        let leading = month.cells.prefix(while: { !$0.isCurrentMonth }).count
        #expect(leading == start.weekday - 1)
        // 셀 id는 모두 유일
        #expect(Set(month.cells.map(\.id)).count == month.cells.count)
        // 셀 날짜는 하루 간격으로 연속
        for (a, b) in zip(month.cells, month.cells.dropFirst()) {
            let next = Calendar.current.date(byAdding: .day, value: 1, to: a.date)!
            #expect(next.dateString == b.date.dateString)
        }
        // 현재 월 셀의 day는 1부터 일수까지 순서대로
        let currentDays = month.cells.filter(\.isCurrentMonth).map(\.day)
        #expect(currentDays == Array(1...start.daysInMonth()))
    }
}
