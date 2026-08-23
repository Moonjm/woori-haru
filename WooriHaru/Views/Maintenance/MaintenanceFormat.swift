import Foundation

/// 관리비 화면 넷이 함께 쓰는 표기. **화면마다 포매터를 새로 만들지 않는다** —
/// 그러면 어떤 화면은 「168,620원」, 어떤 화면은 「₩168,620」이 된다.
enum MaintenanceFormat {
    /// `NumberFormatter`는 만드는 값이 비싸다. 목록이 스크롤될 때마다 새로 만들지 않는다.
    private static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func won(_ value: Decimal) -> String {
        let text = decimal.string(from: value as NSDecimalNumber) ?? "\(value)"
        return "\(text)원"
    }

    /// 증감 표기. **부호를 반드시 붙인다** — 「12,300원」만 적으면 오른 건지 내린 건지 모른다.
    static func signedWon(_ value: Decimal) -> String {
        let sign = value < 0 ? "-" : "+"
        let text = decimal.string(from: abs(value) as NSDecimalNumber) ?? "\(abs(value))"
        return "\(sign)\(text)원"
    }

    /// 비율 그대로(0.0787)를 받아 `+7.9%`로 낸다.
    static func percent(_ ratio: Decimal) -> String {
        let scaled = ratio * 100
        let sign = scaled < 0 ? "-" : "+"
        let text = percentFormatter.string(from: abs(scaled) as NSDecimalNumber) ?? "\(abs(scaled))"
        return "\(sign)\(text)%"
    }

    /// `"2026-08"` → `"2026년 8월"`. **형식이 틀리면 원문 그대로 낸다** — 화면이 비는 것보다 낫다.
    static func monthTitle(_ yearMonth: String) -> String {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
            return yearMonth
        }
        return "\(year)년 \(month)월"
    }

    /// `"2026-08-31"` → `"8월 31일"`. 해는 카드 제목이 이미 말한다.
    static func dueDate(_ isoDate: String) -> String {
        let parts = isoDate.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return isoDate
        }
        return "\(month)월 \(day)일"
    }
}
