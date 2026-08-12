import Foundation

/// 한 달의 달력 칸을 만든다. 일요일 시작이고 앞뒤를 이웃 달 날짜로 채워 7의 배수로 맞춘다.
///
/// **기본 달력과 스케줄표가 함께 쓴다.** 규칙이 갈라지면 같은 날짜가 두 화면에서 다른
/// 자리에 놓인다. 순수 함수라 어느 쪽에도 상태를 만들지 않는다.
enum MonthGridBuilder {
    static func cells(for startOfMonth: Date, calendar: Calendar) -> [MonthData.DayCell] {
        let id = startOfMonth.yearMonth
        let firstWeekday = startOfMonth.weekday
        let leadingEmpties = firstWeekday - 1
        let daysInMonth = startOfMonth.daysInMonth()

        var cells: [MonthData.DayCell] = []

        // 이전 월 날짜 (leading)
        for i in (0..<leadingEmpties).reversed() {
            let prevDate = calendar.date(byAdding: .day, value: -(i + 1), to: startOfMonth)!
            cells.append(.init(id: "\(id)-prev-\(prevDate.dateString)", date: prevDate, day: prevDate.day, isCurrentMonth: false))
        }

        // 현재 월 날짜
        for day in 1...daysInMonth {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            cells.append(.init(id: dayDate.dateString, date: dayDate, day: day, isCurrentMonth: true))
        }

        // 다음 월 날짜 (trailing) - 마지막 주만 채움 (7의 배수)
        let remainder = cells.count % 7
        if remainder > 0 {
            let trailingCount = 7 - remainder
            let lastDay = calendar.date(byAdding: .day, value: daysInMonth - 1, to: startOfMonth)!
            for i in 1...trailingCount {
                let nextDate = calendar.date(byAdding: .day, value: i, to: lastDay)!
                cells.append(.init(id: "\(id)-next-\(nextDate.dateString)", date: nextDate, day: nextDate.day, isCurrentMonth: false))
            }
        }

        return cells
    }
}
