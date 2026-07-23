import SwiftUI

/// 가계부 통계 탭 — /entries/statistics API의 서버 집계를 그대로 표시한다.
/// 월별(최근 6개월 추이)·연별(12개월 추이)을 전환할 수 있고, 기간을 앞뒤로 이동할 수 있다.
struct LedgerStatsView: View {
    /// 하단 탭바에서 통계 탭을 다시 탭하면 증가 — 맨 위로 스크롤한다.
    var scrollToTopSignal = 0

    private enum Scope: String, CaseIterable, Identifiable {
        case monthly = "월별"
        case yearly = "연별"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .monthly
    @State private var month = LedgerYearMonth.current()
    @State private var year = LedgerYearMonth.current().year
    @State private var stats: LedgerStatistics?
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 차트에서 선택한 월 (yearMonth 문자열). 로드 시 기본값이 정해진다.
    @State private var selectedMonth: String?
    /// 진행 중 로드의 세대 번호 — 기간을 오갔다 되돌아와도 최신 요청만 화면을 갱신한다.
    @State private var loadGeneration = 0

    private let ledgerService = LedgerService()

    var body: some View {
        ScrollViewReader { proxy in
            statsScroll
                .onChange(of: scrollToTopSignal) {
                    withAnimation(.snappy) { proxy.scrollTo("ledgerStatsTop", anchor: .top) }
                }
        }
        .toolbar {
            // 다른 기간을 보는 중에만 나타나는 복귀 버튼 (캘린더의 "오늘" 패턴)
            if !isAtCurrentPeriod {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(scope == .monthly ? "이번 달" : "올해") { resetToCurrentPeriod() }
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// 현재 기간(이번 달/올해)으로 즉시 복귀한다.
    private func resetToCurrentPeriod() {
        let current = LedgerYearMonth.current()
        switch scope {
        case .monthly: month = current
        case .yearly: year = current.year
        }
        reloadForPeriodChange()
    }

    private var statsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                periodHeader
                    .padding(.top, 4)
                    .id("ledgerStatsTop")

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                if let stats {
                    summaryCard(stats)
                        .padding(.top, 8)

                    HStack {
                        sectionHeader(scope == .monthly ? "최근 6개월" : "\(year)년 월별 추이")
                        Spacer()
                        if hasFx(stats) { chartLegend }
                    }
                    .padding(.top, 12)
                    chartCard(stats)

                    if !stats.topMerchants.isEmpty {
                        sectionHeader("구매금액 TOP 5").padding(.top, 12)
                        merchantCard(stats)
                    }

                    if !stats.sourceBreakdown.isEmpty {
                        sectionHeader("고정비 · 변동비").padding(.top, 12)
                        fixedVariableCard(stats)
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
        // 좌우 스와이프 = 기간 이동 (월별이면 월, 연별이면 연). 내역 탭과 같은 판정 기준.
        .simultaneousGesture(periodSwipeGesture)
        .overlay { if isLoading && stats == nil { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    /// 수직 스크롤과 헷갈리지 않게 가로 성분이 확실할 때만 반응. 미래 기간으로는 이동하지 않는다.
    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.5 else { return }
                let delta = dx > 0 ? -1 : 1
                guard delta < 0 || !isAtCurrentPeriod else { return }
                shiftPeriod(delta)
            }
    }

    // MARK: - 기간 선택 (월별/연별 + 앞뒤 이동)

    private var periodHeader: some View {
        HStack {
            scopeToggle
            Spacer()
            periodSwitcher
        }
    }

    private var scopeToggle: some View {
        HStack(spacing: 2) {
            ForEach(Scope.allCases) { item in
                Button {
                    guard scope != item else { return }
                    scope = item
                    reloadForPeriodChange()
                } label: {
                    Text(item.rawValue)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(scope == item ? .white : Color.slate500)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if scope == item {
                                Capsule()
                                    .fill(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.55), in: Capsule())
    }

    private var periodSwitcher: some View {
        HStack(spacing: 12) {
            Button { shiftPeriod(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
            }
            .disabled(isAtMinPeriod)
            .opacity(isAtMinPeriod ? 0.3 : 1)
            Text(periodTitle)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .contentTransition(.numericText())
            Button { shiftPeriod(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
            }
            .disabled(isAtCurrentPeriod)
            .opacity(isAtCurrentPeriod ? 0.3 : 1)
        }
        .foregroundStyle(Color.slate700)
    }

    private var periodTitle: String {
        scope == .monthly ? month.displayLong : "\(year)년"
    }

    private var isAtCurrentPeriod: Bool {
        let current = LedgerYearMonth.current()
        return scope == .monthly ? month == current : year == current.year
    }

    private var isAtMinPeriod: Bool {
        scope == .monthly
            ? month.year == Self.minYear && month.month == 1
            : year == Self.minYear
    }

    private func shiftPeriod(_ delta: Int) {
        switch scope {
        case .monthly:
            let next = month.adding(months: delta)
            guard next.year >= Self.minYear else { return }
            month = next
        case .yearly:
            let next = year + delta
            guard next >= Self.minYear else { return }
            year = next
        }
        reloadForPeriodChange()
    }

    /// 기간 이동 하한 — 서버가 거부하는 범위 밖 연도를 요청하지 않게 막는다.
    private static let minYear = 2000

    /// 기간이 바뀌면 이전 기간 데이터가 새 라벨 아래 보이지 않게 비우고 다시 불러온다.
    private func reloadForPeriodChange() {
        // 새 load Task가 시작되기 전에 이전 요청의 응답이 도착해도 반영되지 않도록
        // 세대를 여기서 동기적으로 무효화한다.
        loadGeneration += 1
        stats = nil
        selectedMonth = nil
        errorMessage = nil
        Task { await load() }
    }

    // MARK: - 요약

    private func summaryCard(_ stats: LedgerStatistics) -> some View {
        let current = currentTotal(stats)
        let previous = previousTotal(stats)
        return GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(summaryTitle)
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
                    statChip(scope == .monthly ? "지난달" : "지난해", LedgerFormat.amount(previous, currency: "KRW"))
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

    private var summaryTitle: String {
        switch scope {
        case .monthly:
            let current = LedgerYearMonth.current()
            if month.year == current.year { return "\(month.month)월 지출" }
            return "\(month.year)년 \(month.month)월 지출"
        case .yearly:
            return "\(year)년 지출"
        }
    }

    /// 기준 기간 총 지출(원화 + 외화 환산) — 월별이면 추이 마지막(기준월), 연별이면 12개월 합.
    private func currentTotal(_ stats: LedgerStatistics) -> Decimal {
        switch scope {
        case .monthly: return stats.monthlyTrend.last?.combinedTotal ?? 0
        case .yearly: return stats.monthlyTrend.reduce(Decimal.zero) { $0 + $1.combinedTotal }
        }
    }

    /// 직전 기간 총 지출 — 서버 값 우선, 구버전 응답이면 추이에서 지난달을 취한다.
    private func previousTotal(_ stats: LedgerStatistics) -> Decimal {
        if let previous = stats.previousTotal { return previous }
        guard scope == .monthly, stats.monthlyTrend.count >= 2 else { return 0 }
        return stats.monthlyTrend[stats.monthlyTrend.count - 2].combinedTotal
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

    // MARK: - 막대 그래프 (원화 위에 외화 환산을 쌓는 스택)

    /// 추이에 외화 환산 지출이 있는지 — 범례 표시 여부.
    private func hasFx(_ stats: LedgerStatistics) -> Bool {
        stats.monthlyTrend.contains { ($0.fxKrwTotal ?? 0) != 0 }
    }

    private var chartLegend: some View {
        HStack(spacing: 10) {
            legendItem(color: Color.blue600, label: "원화")
            legendItem(color: Color.purple500, label: "외화")
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.slate500)
        }
    }

    private func chartCard(_ stats: LedgerStatistics) -> some View {
        let maxTotal = stats.monthlyTrend.map(\.combinedTotal).max() ?? 0
        let selectedKey = selectedMonth ?? defaultSelectedMonth(stats)
        let selected = stats.monthlyTrend.first { $0.yearMonth == selectedKey }
        return GlassCard {
            VStack(spacing: 12) {
                // 선택한 월의 금액 콜아웃 — 막대를 탭하면 바뀐다.
                if let selected {
                    HStack(spacing: 6) {
                        Text("\(selected.monthNumber)월")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(Color.blue600)
                        Text(LedgerFormat.amount(selected.combinedTotal, currency: "KRW"))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if let fx = selected.fxKrwTotal, fx != 0 {
                            Text("외화 \(LedgerFormat.amount(fx, currency: "KRW"))")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(Color.purple500)
                        }
                        Spacer()
                    }
                    .animation(.snappy, value: selected.yearMonth)
                }

                HStack(alignment: .bottom, spacing: scope == .monthly ? 10 : 5) {
                    ForEach(stats.monthlyTrend) { item in
                        let isSelected = item.yearMonth == selectedKey
                        let fx = item.fxKrwTotal ?? 0
                        VStack(spacing: 5) {
                            VStack(spacing: 0) {
                                // 외화 환산분을 원화 위에 쌓는다 (음수 순액은 표시 생략)
                                if fx > 0 {
                                    Rectangle()
                                        .fill(isSelected ? AnyShapeStyle(Color.purple500)
                                            : AnyShapeStyle(Color.purple500.opacity(0.3)))
                                        .frame(height: segmentHeight(fx, max: maxTotal))
                                }
                                Rectangle()
                                    .fill(
                                        isSelected
                                            ? AnyShapeStyle(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                                           startPoint: .top, endPoint: .bottom))
                                            : AnyShapeStyle(Color.blue500.opacity(0.25))
                                    )
                                    .frame(height: barHeight(item.krwTotal, max: maxTotal))
                            }
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                            // 12개 막대(연별)는 폭이 좁아 "월" 없이 숫자만 표시
                            Text(scope == .monthly ? "\(item.monthNumber)월" : "\(item.monthNumber)")
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

    /// 콜아웃 기본 선택 — 월별은 기준월, 연별은 지출이 있는 마지막 달.
    private func defaultSelectedMonth(_ stats: LedgerStatistics) -> String? {
        switch scope {
        case .monthly:
            return stats.yearMonth
        case .yearly:
            return (stats.monthlyTrend.last { $0.combinedTotal > 0 } ?? stats.monthlyTrend.last)?.yearMonth
        }
    }

    /// 원화(바닥) 세그먼트 — 빈 달도 최소 높이로 탭 대상이 되게 한다.
    private func barHeight(_ total: Decimal, max maxTotal: Decimal) -> CGFloat {
        guard maxTotal > 0 else { return 4 }
        let ratio = (total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
        return Swift.max(4, CGFloat(ratio) * 105)
    }

    /// 외화(위) 세그먼트 — 없으면 0, 최소 높이 없이 비율 그대로.
    private func segmentHeight(_ total: Decimal, max maxTotal: Decimal) -> CGFloat {
        guard maxTotal > 0, total > 0 else { return 0 }
        let ratio = (total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
        return CGFloat(ratio) * 105
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

    // MARK: - 고정비 · 변동비

    /// 반복(고정) 지출과 나머지(변동) 지출의 비율 — 분류가 없는 앱에서 유일하게 의미 있는 구성비.
    private func fixedVariableCard(_ stats: LedgerStatistics) -> some View {
        let fixed = stats.sourceBreakdown.first { $0.source == .recurring }?.krwTotal ?? 0
        let variable = stats.sourceBreakdown
            .filter { $0.source != .recurring }
            .reduce(Decimal.zero) { $0 + $1.krwTotal }
        let total = fixed + variable
        let fixedPercent = percentOf(fixed, total: total)
        return GlassCard {
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
        loadGeneration += 1
        let generation = loadGeneration
        let requestScope = scope
        let requestMonth = month
        let requestYear = year
        isLoading = true
        // A→B→A처럼 같은 기간으로 되돌아와도 세대 번호가 다르므로 밀려난 응답은 폐기된다.
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let result: LedgerStatistics
            switch requestScope {
            case .monthly: result = try await ledgerService.fetchStatistics(yearMonth: requestMonth.apiValue)
            case .yearly: result = try await ledgerService.fetchStatistics(year: requestYear)
            }
            guard generation == loadGeneration else { return }
            stats = result
            selectedMonth = defaultSelectedMonth(result)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = "통계를 불러오지 못했습니다."
        }
    }
}
