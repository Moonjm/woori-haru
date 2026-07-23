import Foundation

// MARK: - 열거형 (백엔드 enum과 1:1)

enum EntryType: String, Codable, CaseIterable {
    case expense = "EXPENSE"
    case income = "INCOME"
}

/// 내역이 어떻게 들어왔는지. 목록에서 배지로 표시한다.
enum EntrySource: String, Codable {
    case manual = "MANUAL"
    case sms = "SMS"
    case kakaoPay = "KAKAO_PAY"
    case recurring = "RECURRING"

    /// 알 수 없는 값이 와도 앱이 죽지 않도록 기본값으로 흡수한다.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EntrySource(rawValue: raw) ?? .manual
    }

    var label: String {
        switch self {
        case .manual: return "수동"
        case .sms: return "문자"
        case .kakaoPay: return "카카오페이"
        case .recurring: return "반복"
        }
    }
}

// MARK: - 모델

struct LedgerEntry: Codable, Identifiable, Hashable {
    let id: Int
    /// 서버 LocalDateTime 문자열("2026-07-19T13:55:27"). 표시·정렬 시 date로 변환한다.
    let entryAt: String
    let amount: Decimal
    let currency: String
    let type: EntryType
    let merchant: String?
    let description: String?
    let source: EntrySource

    var date: Date { LedgerFormat.parseDateTime(entryAt) ?? .distantPast }

    /// 메모에 기록된 결제 시점 환율 문구 전체. 예) "환율 1 JPY ≈ 9.15원 (약 9,150원)"
    var fxNote: String? {
        guard let description,
              let range = description.range(of: LedgerFormat.fxNotePattern, options: .regularExpression)
        else { return nil }
        return String(description[range])
    }

    /// 환율 메모의 원화 환산 부분만. 예) "약 9,150원"
    var fxConvertedText: String? {
        guard let fxNote,
              let range = fxNote.range(of: #"약 -?[\d,]+원"#, options: .regularExpression)
        else { return nil }
        return String(fxNote[range])
    }

    /// 환산 금액만 숫자로. 예) "약 9,150원" → 9150 — 외화 지출을 원화로 합산할 때 사용.
    var fxConvertedAmount: Decimal? {
        guard let fxConvertedText,
              let range = fxConvertedText.range(of: #"-?[\d,]+"#, options: .regularExpression)
        else { return nil }
        return Decimal(string: fxConvertedText[range].replacingOccurrences(of: ",", with: ""))
    }

    /// 환율 문구를 제거한 순수 메모 (없으면 nil) — 상세에서 환율을 별도 줄로 빼서 보여줄 때 사용.
    var descriptionWithoutFxNote: String? {
        guard let description else { return nil }
        let stripped = description
            .replacingOccurrences(of: LedgerFormat.fxNotePattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*·\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*·\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : stripped
    }
}

struct LedgerEntryRequest: Encodable {
    let entryAt: String
    let amount: Decimal
    let currency: String
    let type: EntryType
    let merchant: String?
    let description: String?
}

struct RecurringRule: Codable, Identifiable, Hashable {
    let id: Int
    let dayOfMonth: Int
    let amount: Decimal
    let currency: String
    let type: EntryType
    let merchant: String?
    let description: String?
    let active: Bool
}

struct RecurringCreateRequest: Encodable {
    let entryId: Int
    let dayOfMonth: Int?
}

struct RecurringUpdateRequest: Encodable {
    let dayOfMonth: Int
    let amount: Decimal
    let currency: String
    let type: EntryType
    let merchant: String?
    let description: String?
    let active: Bool
}

struct LedgerApiKey: Codable, Identifiable {
    let id: Int
    let name: String
    let createdAt: String
}

/// 발급 직후 1회만 원본 키가 내려온다.
struct IssuedLedgerApiKey: Codable, Identifiable {
    let id: Int
    let name: String
    let key: String
}

// MARK: - 통계

struct LedgerStatistics: Codable {
    /// 기준 기간 — 월별이면 "2026-07", 연별이면 "2026"
    let yearMonth: String
    let monthlyTrend: [MonthlyTotal]
    /// 직전 기간(지난달/지난해) 원화 합계. 구버전 서버 응답에는 없어 옵셔널.
    let previousTotal: Decimal?
    let sourceBreakdown: [SourceTotal]
    let foreignTotals: [CurrencyTotal]
    let topMerchants: [MerchantTotal]
    let maxEntry: MaxEntry?
    let dailyAverage: Decimal

    struct MonthlyTotal: Codable, Identifiable {
        let yearMonth: String
        let krwTotal: Decimal
        var id: String { yearMonth }
        /// "2026-07" → 7
        var monthNumber: Int { Int(yearMonth.suffix(2)) ?? 0 }
    }

    struct SourceTotal: Codable {
        let source: EntrySource
        let krwTotal: Decimal
    }

    struct CurrencyTotal: Codable {
        let currency: String
        let total: Decimal
    }

    struct MerchantTotal: Codable, Identifiable {
        let merchant: String
        let krwTotal: Decimal
        let count: Int
        var id: String { merchant }
    }

    struct MaxEntry: Codable {
        let merchant: String?
        let amount: Decimal
        let entryAt: String
    }
}

// MARK: - 연월

/// 월 이동을 다루는 값 타입 (연·월만).
struct LedgerYearMonth: Equatable, Comparable {
    var year: Int
    var month: Int

    static func < (lhs: LedgerYearMonth, rhs: LedgerYearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    static func current() -> LedgerYearMonth {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return LedgerYearMonth(year: c.year ?? 2026, month: c.month ?? 1)
    }

    func adding(months delta: Int) -> LedgerYearMonth {
        let total = (year * 12 + (month - 1)) + delta
        return LedgerYearMonth(year: total / 12, month: total % 12 + 1)
    }

    /// 백엔드 쿼리 파라미터 형식 "yyyy-MM"
    var apiValue: String { String(format: "%04d-%02d", year, month) }
    /// "2026년 7월"
    var displayLong: String { "\(year)년 \(month)월" }
}

// MARK: - 표시 형식

/// 가계부 전용 금액·일시 표시 헬퍼. 외화는 환산하지 않고 통화별 기호/소수 자리로만 표시한다.
enum LedgerFormat {
    static let currencies = ["KRW", "JPY", "USD", "EUR", "CNY", "GBP"]

    /// 백엔드 fxNote 형식과 일치하는 환율 메모 패턴. 예) "환율 1 JPY ≈ 9.15원 (약 9,150원)"
    static let fxNotePattern = #"환율 1 [A-Z]{3} ≈ [\d.,]+원 \(약 -?[\d,]+원\)"#

    private static let symbols: [String: String] = [
        "KRW": "₩", "JPY": "¥", "USD": "$", "EUR": "€", "CNY": "¥", "GBP": "£",
    ]
    private static let fractionDigits: [String: Int] = [
        "KRW": 0, "JPY": 0, "USD": 2, "EUR": 2, "CNY": 2, "GBP": 2,
    ]

    static func isForeign(_ currency: String) -> Bool { currency.uppercased() != "KRW" }

    static func symbol(for currency: String) -> String {
        symbols[currency.uppercased()] ?? currency.uppercased()
    }

    static func integerAmount(_ currency: String) -> Bool {
        fractionDigits[currency.uppercased(), default: 2] == 0
    }

    /// 예) 5800 KRW → "₩5,800", 1200 JPY → "¥1,200", 4.99 USD → "$4.99"
    static func amount(_ value: Decimal, currency: String) -> String {
        let upper = currency.uppercased()
        let digits = fractionDigits[upper, default: 2]
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let text = formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        if let symbol = symbols[upper] { return "\(symbol)\(text)" }
        return "\(upper) \(text)"
    }

    // MARK: 일시 (서버 LocalDateTime ↔ Date)

    private static let parsePatterns = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
    ]

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = pattern
        return f
    }

    static func parseDateTime(_ raw: String) -> Date? {
        for pattern in parsePatterns {
            if let date = formatter(pattern).date(from: raw) { return date }
        }
        return nil
    }

    static func formatDateTime(_ date: Date) -> String {
        formatter("yyyy-MM-dd'T'HH:mm:ss").string(from: date)
    }

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("Md EEE")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("a h:mm")
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("yMMMd EEE a h:mm")
        return f
    }()

    private static let dayWithYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("yMd EEE")
        return f
    }()

    /// "7월 19일 토"
    static func dayHeader(_ date: Date) -> String { dayHeaderFormatter.string(from: date) }
    /// "2025년 7월 19일 토" — 전체 기간을 다루는 검색 결과용
    static func dayWithYear(_ date: Date) -> String { dayWithYearFormatter.string(from: date) }
    /// "오후 2:30"
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    /// 상세 화면용 전체 표기
    static func full(_ date: Date) -> String { fullFormatter.string(from: date) }
}

extension Decimal {
    /// 소수부가 없는 정수인지 — KRW·JPY처럼 소수 없는 통화의 금액 검증에 쓴다.
    var isWholeNumber: Bool {
        var value = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == self
    }
}
