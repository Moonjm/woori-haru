import SwiftUI

// MARK: - 가맹점 TOP

/// 구매금액 TOP 5 가맹점 리스트 카드.
struct LedgerMerchantCard: View {
    let merchants: [LedgerStatistics.MerchantTotal]

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(merchants.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(index == 0 ? Color.blue600 : Color.slate400)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.merchant)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.slate900)
                                .lineLimit(1)
                            Text("\(item.count)회")
                                .font(.caption2)
                                .foregroundStyle(Color.slate400)
                        }
                        Spacer(minLength: 8)
                        Text(LedgerFormat.amount(item.krwTotal, currency: "KRW"))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if index < merchants.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 고정비 · 변동비

/// 반복(고정) 지출과 나머지(변동) 지출의 비율 — 분류가 없는 앱에서 유일하게 의미 있는 구성비.
struct LedgerFixedVariableCard: View {
    let breakdown: [LedgerStatistics.SourceTotal]

    var body: some View {
        let fixed = breakdown.first { $0.source == .recurring }?.krwTotal ?? 0
        let variable = breakdown
            .filter { $0.source != .recurring }
            .reduce(Decimal.zero) { $0 + $1.krwTotal }
        let total = fixed + variable
        let fixedPercent = percentOf(fixed, total: total)
        GlassCard {
            VStack(spacing: 14) {
                // 한 줄 비율 바 — 보라(고정) + 파랑(변동)
                GeometryReader { geo in
                    HStack(spacing: fixed > 0 && variable > 0 ? 3 : 0) {
                        if fixed > 0 {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.purple500)
                                .frame(width: max(geo.size.width * CGFloat(fixedPercent) / 100 - 1.5, 0))
                        }
                        if variable > 0 {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                     startPoint: .leading, endPoint: .trailing))
                        }
                    }
                }
                .frame(height: 10)

                VStack(spacing: 8) {
                    ratioRow(color: Color.purple500, label: "고정비 (반복)",
                             amount: fixed, percent: fixedPercent)
                    ratioRow(color: Color.blue600, label: "변동비",
                             amount: variable, percent: total > 0 ? 100 - fixedPercent : 0)
                }
            }
        }
    }

    private func ratioRow(color: Color, label: String, amount: Decimal, percent: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
            Spacer()
            Text("\(LedgerFormat.amount(amount, currency: "KRW")) · \(percent)%")
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.slate500)
        }
    }

    private func percentOf(_ amount: Decimal, total: Decimal) -> Int {
        guard total > 0 else { return 0 }
        let ratio = (amount as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue
        return Int((ratio * 100).rounded())
    }
}

// MARK: - 외화

/// 통화별 외화 지출 합계 리스트 카드 (환산 없이 원 통화 그대로).
struct LedgerForeignCard: View {
    let totals: [LedgerStatistics.CurrencyTotal]

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(totals.enumerated()), id: \.element.currency) { index, item in
                    HStack {
                        Text(item.currency)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(LedgerFormat.amount(item.total, currency: item.currency))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(Color.blue600)
                    }
                    .padding(14)
                    if index < totals.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }
}
