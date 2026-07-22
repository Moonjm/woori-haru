import SwiftUI

/// 가계부 통계 탭 — 월별 추이(6개월)·지난달 비교·출처별 구성·외화.
/// 분류가 없으므로 출처(문자/반복/수동)와 시계열 중심으로 구성한다.
struct LedgerStatsView: View {
    private struct MonthTotal: Identifiable {
        let id: String
        let month: LedgerYearMonth
        let total: Decimal
    }

    @State private var monthTotals: [MonthTotal] = []
    @State private var currentEntries: [LedgerEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let ledgerService = LedgerService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                summaryCard
                    .padding(.top, 8)

                sectionHeader("최근 6개월").padding(.top, 12)
                chartCard

                sectionHeader("어떻게 쓰였나").padding(.top, 12)
                sourceCard

                if !foreignTotals.isEmpty {
                    sectionHeader("외화 (이번 달)").padding(.top, 12)
                    foreignCard
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .overlay { if isLoading && monthTotals.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 요약

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(currentMonth.month)월 지출")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate500)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LedgerFormat.amount(currentTotal, currency: "KRW"))
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
                    statChip("지난달", LedgerFormat.amount(previousTotal, currency: "KRW"))
                    statChip("월평균", LedgerFormat.amount(averageTotal, currency: "KRW"))
                }
                .padding(.top, 12)
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

    // MARK: - 막대 그래프

    private var chartCard: some View {
        GlassCard {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(monthTotals) { item in
                    let isCurrent = item.month == currentMonth
                    VStack(spacing: 5) {
                        Rectangle()
                            .fill(
                                isCurrent
                                    ? AnyShapeStyle(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                                   startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(Color.blue500.opacity(0.25))
                            )
                            .frame(height: barHeight(item.total))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                        Text("\(item.month.month)월")
                            .font(.system(size: 9, weight: isCurrent ? .heavy : .bold))
                            .foregroundStyle(isCurrent ? Color.blue600 : Color.slate400)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
    }

    private func barHeight(_ total: Decimal) -> CGFloat {
        let maxTotal = monthTotals.map(\.total).max() ?? 0
        guard maxTotal > 0 else { return 4 }
        let ratio = (total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
        return max(4, CGFloat(ratio) * 105)
    }

    // MARK: - 출처 구성

    private var sourceCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                ForEach(sourceBreakdown, id: \.source) { item in
                    VStack(spacing: 4) {
                        HStack {
                            Text(item.source.label)
                                .font(.caption)
                                .fontWeight(.bold)
                            Spacer()
                            Text("\(LedgerFormat.amount(item.amount, currency: "KRW")) · \(item.percent)%")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(Color.slate500)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.slate900.opacity(0.06))
                                Capsule()
                                    .fill(barColor(item.source))
                                    .frame(width: geo.size.width * CGFloat(item.percent) / 100)
                            }
                        }
                        .frame(height: 7)
                    }
                }
                if sourceBreakdown.isEmpty {
                    Text("이번 달 원화 지출이 없어요")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barColor(_ source: EntrySource) -> AnyShapeStyle {
        switch source {
        case .sms, .kakaoPay:
            return AnyShapeStyle(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                startPoint: .leading, endPoint: .trailing))
        case .recurring:
            return AnyShapeStyle(Color.purple500)
        case .manual, .imported:
            return AnyShapeStyle(Color.slate400)
        }
    }

    // MARK: - 외화

    private var foreignCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(foreignTotals.enumerated()), id: \.element.currency) { index, item in
                    HStack {
                        Text(item.currency)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(LedgerFormat.amount(item.amount, currency: item.currency))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(Color.blue600)
                    }
                    .padding(14)
                    if index < foreignTotals.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.slate500)
            .padding(.horizontal, 4)
    }

    // MARK: - 파생 값

    private var currentMonth: LedgerYearMonth { LedgerYearMonth.current() }

    private var currentTotal: Decimal { monthTotals.last?.total ?? 0 }

    private var previousTotal: Decimal {
        guard monthTotals.count >= 2 else { return 0 }
        return monthTotals[monthTotals.count - 2].total
    }

    /// 지난달 대비 증감률(%). 지난달이 0이면 표시하지 않는다.
    private var deltaPercent: Int? {
        guard previousTotal > 0 else { return nil }
        let ratio = ((currentTotal - previousTotal) as NSDecimalNumber).doubleValue
            / (previousTotal as NSDecimalNumber).doubleValue
        return Int((ratio * 100).rounded())
    }

    private var averageTotal: Decimal {
        let nonZero = monthTotals.map(\.total).filter { $0 > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.reduce(Decimal.zero, +) / Decimal(nonZero.count)
    }

    private var sourceBreakdown: [(source: EntrySource, amount: Decimal, percent: Int)] {
        var map: [EntrySource: Decimal] = [:]
        for entry in currentEntries where entry.type == .expense && entry.currency.uppercased() == "KRW" {
            map[entry.source, default: .zero] += entry.amount
        }
        let total = map.values.reduce(Decimal.zero, +)
        guard total > 0 else { return [] }
        return map
            .sorted { $0.value > $1.value }
            .map { source, amount in
                let percent = Int((((amount / total) as NSDecimalNumber).doubleValue * 100).rounded())
                return (source: source, amount: amount, percent: percent)
            }
    }

    private var foreignTotals: [(currency: String, amount: Decimal)] {
        var map: [String: Decimal] = [:]
        for entry in currentEntries where entry.type == .expense && LedgerFormat.isForeign(entry.currency) {
            map[entry.currency.uppercased(), default: .zero] += entry.amount
        }
        return map.sorted { $0.key < $1.key }.map { (currency: $0.key, amount: $0.value) }
    }

    // MARK: - 로드

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let now = LedgerYearMonth.current()
        do {
            var totals: [MonthTotal] = []
            for delta in stride(from: 5, through: 0, by: -1) {
                let month = now.adding(months: -delta)
                let entries = try await ledgerService.fetchEntries(yearMonth: month.apiValue)
                var sum = Decimal.zero
                for entry in entries where entry.type == .expense && entry.currency.uppercased() == "KRW" {
                    sum += entry.amount
                }
                totals.append(MonthTotal(id: month.apiValue, month: month, total: sum))
                if delta == 0 { currentEntries = entries }
            }
            monthTotals = totals
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "통계를 불러오지 못했습니다."
        }
    }
}
