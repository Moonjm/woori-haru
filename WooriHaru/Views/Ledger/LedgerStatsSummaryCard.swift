import SwiftUI

/// 기간 총 지출 요약 카드 — 총액, 전기 대비 증감, 지난 기간/일평균 칩, 최대 지출 한 줄.
struct LedgerStatsSummaryCard: View {
    let title: String
    let current: Decimal
    let previous: Decimal
    /// "지난달" / "지난해"
    let previousLabel: String
    let dailyAverage: Decimal
    let deltaPercent: Int?
    let maxEntry: LedgerStatistics.MaxEntry?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate500)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LedgerFormat.amount(current, currency: "KRW"))
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                    if let delta = deltaPercent {
                        Text(delta >= 0 ? "▲ \(delta)%" : "▼ \(-delta)%")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(delta >= 0 ? Color.red500 : Color.green600)
                    }
                }
                .padding(.top, 3)

                HStack(spacing: 6) {
                    statChip(previousLabel, LedgerFormat.amount(previous, currency: "KRW"))
                    statChip("일평균", LedgerFormat.amount(dailyAverage, currency: "KRW"))
                }
                .padding(.top, 12)

                if let maxEntry {
                    HStack(spacing: 6) {
                        Text("최대 지출")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.slate500)
                        Text(maxEntry.merchant ?? "내역")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.slate900)
                            .lineLimit(1)
                        Text(LedgerFormat.amount(maxEntry.amount, currency: "KRW"))
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .monospacedDigit()
                            .foregroundStyle(Color.blue600)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statChip(_ key: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(key).foregroundStyle(Color.slate500)
            Text(value).foregroundStyle(Color.slate900).monospacedDigit()
        }
        .font(.caption2)
        .fontWeight(.bold)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.55))
        .clipShape(Capsule())
    }
}
