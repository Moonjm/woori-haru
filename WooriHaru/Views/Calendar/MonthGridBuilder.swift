import Foundation

/// 한 달의 달력 칸을 만든다. 일요일 시작이고 앞뒤를 이웃 달 날짜로 채워 7의 배수로 맞춘다.
///
/// **기본 달력과 스케줄표가 함께 쓴다.** 규칙이 갈라지면 같은 날짜가 두 화면에서 다른
/// 자리에 놓인다. 순수 함수라 어느 쪽에도 상태를 만들지 않는다.
///
/// **계산은 전부 넘겨받은 `calendar`로 한다.** `Date+Extensions`의 `.yearMonth`·`.weekday`·
/// `.daysInMonth()`·`.day`·`.dateString`은 전부 `Calendar.current`(기기 설정)를 쓴다.
/// 여기서 그대로 쓰면 `calendar` 인자는 날짜를 더하고 빼는 데만 쓰이고 「앞 패딩이 몇
/// 칸인가」·「이 달이 며칠까지인가」 같은 좌표 계산은 여전히 기기 달력을 따른다 — 기기
/// 달력이 비그레고리력인 사용자에게는 서버로 나가는 연월만 그레고리력이고 화면 칸은
/// 어긋난 자리에 놓인다.
enum MonthGridBuilder {
    static func cells(for startOfMonth: Date, calendar: Calendar) -> [MonthData.DayCell] {
        let id = yearMonthString(for: startOfMonth, calendar: calendar)
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingEmpties = firstWeekday - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)!.count

        var cells: [MonthData.DayCell] = []

        // 이전 월 날짜 (leading)
        for i in (0..<leadingEmpties).reversed() {
            let prevDate = calendar.date(byAdding: .day, value: -(i + 1), to: startOfMonth)!
            cells.append(.init(
                id: "\(id)-prev-\(dateString(for: prevDate, calendar: calendar))",
                date: prevDate,
                day: calendar.component(.day, from: prevDate),
                month: calendar.component(.month, from: prevDate),
                isCurrentMonth: false
            ))
        }

        // 현재 월 날짜
        let month = calendar.component(.month, from: startOfMonth)
        for day in 1...daysInMonth {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            cells.append(.init(id: dateString(for: dayDate, calendar: calendar), date: dayDate, day: day, month: month, isCurrentMonth: true))
        }

        // 다음 월 날짜 (trailing) - 마지막 주만 채움 (7의 배수)
        let remainder = cells.count % 7
        if remainder > 0 {
            let trailingCount = 7 - remainder
            let lastDay = calendar.date(byAdding: .day, value: daysInMonth - 1, to: startOfMonth)!
            for i in 1...trailingCount {
                let nextDate = calendar.date(byAdding: .day, value: i, to: lastDay)!
                cells.append(.init(
                    id: "\(id)-next-\(dateString(for: nextDate, calendar: calendar))",
                    date: nextDate,
                    day: calendar.component(.day, from: nextDate),
                    month: calendar.component(.month, from: nextDate),
                    isCurrentMonth: false
                ))
            }
        }

        return cells
    }

    private static func yearMonthString(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year!, comps.month!)
    }

    private static func dateString(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
    }
}
