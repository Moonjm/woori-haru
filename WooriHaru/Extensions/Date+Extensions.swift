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
        "\(year). \(month)"
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

    private static let isoParserWithFraction: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        f.timeZone = .current
        return f
    }()

    private static let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    /// 서버 ISO 날짜 문자열 파싱 (마이크로초 포함/미포함 모두 지원)
    static func fromISO(_ string: String) -> Date? {
        isoParserWithFraction.date(from: string) ?? isoParser.date(from: string)
    }

    // MARK: - Date Range

    /// 연/월 기반 날짜 범위 반환 (month=0이면 연간 전체)
    static func monthRange(year: Int, month: Int) -> (from: String, to: String) {
        if month == 0 { return ("\(year)-01-01", "\(year)-12-31") }
        let from = String(format: "%04d-%02d-01", year, month)
        let cal = Calendar.current
        guard let startDate = cal.date(from: DateComponents(year: year, month: month)),
              let range = cal.range(of: .day, in: .month, for: startDate) else {
            return ("\(year)-01-01", "\(year)-12-31")
        }
        let to = String(format: "%04d-%02d-%02d", year, month, range.count)
        return (from, to)
    }
}
