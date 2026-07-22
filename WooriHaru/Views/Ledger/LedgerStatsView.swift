import SwiftUI

/// 가계부 통계 탭 — /entries/statistics API의 서버 집계를 그대로 표시한다.
/// 월별 추이(6개월)·지난달 비교·가맹점 TOP·출처 구성·최대 단건·일평균·외화.
struct LedgerStatsView: View {
    @State private var stats: LedgerStatistics?
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 차트에서 선택한 월 (yearMonth 문자열). 기본은 기준월.
    @State private var selectedMonth: String?

    private let ledgerService = LedgerService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                if let stats {
                    summaryCard(stats)
                        .padding(.top, 8)

                    sectionHeader("최근 6개월").padding(.top, 12)
                    chartCard(stats)

                    if !stats.topMerchants.isEmpty {
                        sectionHeader("가맹점 TOP 5").padding(.top, 12)
                        merchantCard(stats)
                    }

                    if !stats.sourceBreakdown.isEmpty {
                        sectionHeader("어떻게 쓰였나").padding(.top, 12)
                        sourceCard(stats)
                    }

                    if !stats.foreignTotals.isEmpty {
                        sectionHeader("외화").padding(.top, 12)
                        foreignCard(stats)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .overlay { if isLoading && stats == nil { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 요약

    private func summaryCard(_ stats: LedgerStatistics) -> some View {
        let current = stats.monthlyTrend.last?.krwTotal ?? 0
        let previous = stats.monthlyTrend.count >= 2 ? stats.monthlyTrend[stats.monthlyTrend.count - 2].krwTotal : 0
        return GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(stats.monthlyTrend.last?.monthNumber ?? 0)월 지출")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate500)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LedgerFormat.amount(current, currency: "KRW"))
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                    if let delta = deltaPercent(current: current, previous: previous) {
                        Text(delta >= 0 ? "▲ \(delta)%" : "▼ \(-delta)%")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(delta >= 0 ? Color.red500 : Color.green600)
                    }
                }
                .padding(.top, 3)

                HStack(spacing: 6) {
                    statChip("지난달", LedgerFormat.amount(previous, currency: "KRW"))
                    statChip("일평균", LedgerFormat.amount(stats.dailyAverage, currency: "KRW"))
                }
                .padding(.top, 12)

                if let maxEntry = stats.maxEntry {
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

    private func deltaPercent(current: Decimal, previous: Decimal) -> Int? {
        guard previous > 0 else { return nil }
        let ratio = ((current - previous) as NSDecimalNumber).doubleValue
            / (previous as NSDecimalNumber).doubleValue
        return Int((ratio * 100).rounded())
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

    private func chartCard(_ stats: LedgerStatistics) -> some View {
        let maxTotal = stats.monthlyTrend.map(\.krwTotal).max() ?? 0
        let selected = stats.monthlyTrend.first { $0.yearMonth == (selectedMonth ?? stats.yearMonth) }
        return GlassCard {
            VStack(spacing: 12) {
                // 선택한 월의 금액 콜아웃 — 막대를 탭하면 바뀐다.
                if let selected {
                    HStack(spacing: 6) {
                        Text("\(selected.monthNumber)월")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(Color.blue600)
                        Text(LedgerFormat.amount(selected.krwTotal, currency: "KRW"))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Spacer()
                    }
                    .animation(.snappy, value: selected.yearMonth)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(stats.monthlyTrend) { item in
                        let isSelected = item.yearMonth == (selectedMonth ?? stats.yearMonth)
                        VStack(spacing: 5) {
                            Rectangle()
                                .fill(
                                    isSelected
                                        ? AnyShapeStyle(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                                       startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Color.blue500.opacity(0.25))
                                )
                                .frame(height: barHeight(item.krwTotal, max: maxTotal))
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                            Text("\(item.monthNumber)월")
                                .font(.system(size: 9, weight: isSelected ? .heavy : .bold))
                                .foregroundStyle(isSelected ? Color.blue600 : Color.slate400)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect) // 막대가 낮아도 열 전체가 탭되게
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) { selectedMonth = item.yearMonth }
                        }
                    }
                }
                .frame(height: 130, alignment: .bottom)
            }
        }
    }

    private func barHeight(_ total: Decimal, max maxTotal: Decimal) -> CGFloat {
        guard maxTotal > 0 else { return 4 }
        let ratio = (total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
        return Swift.max(4, CGFloat(ratio) * 105)
    }

    // MARK: - 가맹점 TOP

    private func merchantCard(_ stats: LedgerStatistics) -> some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(stats.topMerchants.enumerated()), id: \.element.id) { index, item in
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
                    if index < stats.topMerchants.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 출처 구성

    private func sourceCard(_ stats: LedgerStatistics) -> some View {
        let total = stats.sourceBreakdown.reduce(Decimal.zero) { $0 + $1.krwTotal }
        return GlassCard {
            VStack(spacing: 12) {
                ForEach(stats.sourceBreakdown, id: \.source) { item in
                    let percent = percentOf(item.krwTotal, total: total)
                    VStack(spacing: 4) {
                        HStack {
                            Text(item.source.label)
                                .font(.caption)
                                .fontWeight(.bold)
                            Spacer()
                            Text("\(LedgerFormat.amount(item.krwTotal, currency: "KRW")) · \(percent)%")
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
                                    .frame(width: geo.size.width * CGFloat(percent) / 100)
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
    }

    private func percentOf(_ amount: Decimal, total: Decimal) -> Int {
        guard total > 0 else { return 0 }
        let ratio = (amount as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue
        return Int((ratio * 100).rounded())
    }

    private func barColor(_ source: EntrySource) -> AnyShapeStyle {
        switch source {
        case .sms, .kakaoPay:
            return AnyShapeStyle(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                startPoint: .leading, endPoint: .trailing))
        case .recurring:
            return AnyShapeStyle(Color.purple500)
        case .manual:
            return AnyShapeStyle(Color.slate400)
        }
    }

    // MARK: - 외화

    private func foreignCard(_ stats: LedgerStatistics) -> some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(stats.foreignTotals.enumerated()), id: \.element.currency) { index, item in
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
                    if index < stats.foreignTotals.count - 1 {
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

    // MARK: - 로드

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await ledgerService.fetchStatistics(yearMonth: LedgerYearMonth.current().apiValue)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "통계를 불러오지 못했습니다."
        }
    }
}
