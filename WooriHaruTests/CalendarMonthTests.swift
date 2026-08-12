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

    /// 서버는 한 해치를 한 번에 주고, 뷰모델이 달별로 나눠 담는다.
    private func makeViewModel(mock: MockAPIClient) -> CalendarViewModel {
        CalendarViewModel(
            recordService: RecordService(api: mock),
            holidayService: HolidayService(api: mock),
            pairService: PairService(api: mock),
            pairEventService: PairEventService(api: mock)
        )
    }

    private func stubMonthData(_ mock: MockAPIClient, holidays: [String: [String]]) {
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: holidays))
        mock.stubGet("/daily-records", result: DataResponse<[DailyRecord]>(data: []))
        mock.stubGet("/daily-overeats", result: DataResponse<[DailyOvereat]>(data: []))
    }

    @Test func 초기_로드가_이번_달_공휴일을_채운다() async {
        let mock = MockAPIClient()
        let today = Date()
        let monthId = String(format: "%04d-%02d", today.year, today.month)
        let holidayDate = "\(monthId)-15"
        stubMonthData(mock, holidays: [holidayDate: ["광복절"]])

        let vm = makeViewModel(mock: mock)
        vm.configure(pairStore: PairStore())
        await vm.initialLoad()

        #expect(vm.months.first { $0.id == monthId }?.holidays[holidayDate] == ["광복절"])
    }

    @Test func 다시_불러와도_공휴일이_남는다() async {
        let mock = MockAPIClient()
        let today = Date()
        let monthId = String(format: "%04d-%02d", today.year, today.month)
        let holidayDate = "\(monthId)-15"
        stubMonthData(mock, holidays: [holidayDate: ["광복절"]])

        let vm = makeViewModel(mock: mock)
        vm.configure(pairStore: PairStore())
        await vm.initialLoad()
        // 화면이 다시 떠서 `.task`가 한 번 더 도는 경우. months는 새로 만들어진다.
        await vm.initialLoad()

        #expect(vm.months.first { $0.id == monthId }?.holidays[holidayDate] == ["광복절"])
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

/// 기본 달력과 스케줄표가 같은 규칙으로 칸을 만든다. 한쪽만 고쳐 어긋나면
/// 두 화면의 날짜가 서로 다른 자리에 놓인다.
@MainActor
struct MonthGridBuilderTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func 일요일_시작으로_앞을_채운다() throws {
        // 2026-08-01은 토요일이라 앞에 6칸이 붙는다.
        let cells = MonthGridBuilder.cells(for: Date.from("2026-08-01")!, calendar: calendar)

        #expect(cells.count % 7 == 0)
        #expect(cells.prefix(while: { !$0.isCurrentMonth }).count == 6)
        #expect(cells.filter(\.isCurrentMonth).count == 31)
    }

    @Test func 패딩이_없는_달도_있다() {
        // 2026-02-01은 일요일이고 28일까지라 정확히 4주다.
        let cells = MonthGridBuilder.cells(for: Date.from("2026-02-01")!, calendar: calendar)

        #expect(cells.count == 28)
        #expect(cells.allSatisfy { $0.isCurrentMonth })
    }

    @Test func 셀_id는_유일하다() {
        let cells = MonthGridBuilder.cells(for: Date.from("2026-08-01")!, calendar: calendar)
        #expect(Set(cells.map(\.id)).count == cells.count)
    }

    @Test func 기본_달력과_같은_칸을_만든다() {
        // 기본 달력이 이 빌더를 쓰도록 바꿨는지 확인한다. 한쪽만 고치면 어긋난다.
        let vm = CalendarViewModel()
        let start = Date.from("2026-08-01")!

        let fromViewModel = vm.buildMonthData(start).cells
        let fromBuilder = MonthGridBuilder.cells(for: start, calendar: Calendar.current)

        #expect(fromViewModel.map(\.id) == fromBuilder.map(\.id))
    }

    @Test func 비그레고리력을_넘겨도_패딩과_날짜_수가_같다() {
        // 불교력은 그레고리력과 연도 표기만 다르고 달의 길이·요일 배치는 같다.
        // 계산이 주입받은 calendar가 아니라 기기 달력(Calendar.current)을 새 나가면
        // 이 값들이 기기 설정에 따라 달라진다 — 서버로 나가는 연월만 그레고리력이고
        // 화면 칸은 기기 달력을 따르는 어긋남이 여기서 드러난다.
        let start = Date.from("2026-08-01")!
        let gregorian = Calendar(identifier: .gregorian)
        let buddhist = Calendar(identifier: .buddhist)

        let gregorianCells = MonthGridBuilder.cells(for: start, calendar: gregorian)
        let buddhistCells = MonthGridBuilder.cells(for: start, calendar: buddhist)

        #expect(buddhistCells.count == gregorianCells.count)
        let gregorianLeading = gregorianCells.prefix(while: { !$0.isCurrentMonth }).count
        let buddhistLeading = buddhistCells.prefix(while: { !$0.isCurrentMonth }).count
        #expect(buddhistLeading == gregorianLeading)
        #expect(buddhistCells.filter(\.isCurrentMonth).count == gregorianCells.filter(\.isCurrentMonth).count)
        #expect(buddhistCells.map(\.day) == gregorianCells.map(\.day))
        #expect(buddhistCells.map(\.date) == gregorianCells.map(\.date))
    }
}
