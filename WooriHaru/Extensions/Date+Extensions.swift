import Foundation

extension Date {
    // MARK: - Thread-safe Formatter Helpers
    // DateFormatter is NOT thread-safe when mutating dateFormat on a shared instance.
    // Each property uses its own dedicated static formatter to avoid race conditions.

    private static func makeKoreanFormatter(dateFormat: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = dateFormat
        return f
    }

    private static let dateStringFormatter = makeKoreanFormatter(dateFormat: "yyyy-MM-dd")
    private static let yearMonthFormatter = makeKoreanFormatter(dateFormat: "yyyy-MM")
    private static let sheetHeaderFormatter = makeKoreanFormatter(dateFormat: "M월 d일 EEEE")

    // MARK: - Formatted Strings

    var dateString: String {
        Date.dateStringFormatter.string(from: self)
    }

    var yearMonth: String {
        Date.yearMonthFormatter.string(from: self)
    }

    // MARK: - Calendar Components

    var year: Int { Calendar.current.component(.year, from: self) }
    var month: Int { Calendar.current.component(.month, from: self) }
    var day: Int { Calendar.current.component(.day, from: self) }
    var weekday: Int { Calendar.current.component(.weekday, from: self) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isSunday: Bool { weekday == 1 }
    var isSaturday: Bool { weekday == 7 }

    // MARK: - Display Text

    var monthDisplayText: String {
        "\(year)년 \(month)월"
    }

    var sheetHeaderText: String {
        Date.sheetHeaderFormatter.string(from: self)
    }

    // MARK: - Date Calculations

    func startOfMonth() -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))!
    }

    func daysInMonth() -> Int {
        Calendar.current.range(of: .day, in: .month, for: self)!.count
    }

    func addingMonths(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self)!
    }

    // MARK: - Parsing

    static func from(_ string: String) -> Date? {
        dateStringFormatter.date(from: string)
    }
}
