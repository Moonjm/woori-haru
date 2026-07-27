import SwiftUI

/// 가계부 통계 탭 — /entries/statistics API의 서버 집계를 그대로 표시한다.
/// 기간 상태·로드·파생 값은 LedgerStatsViewModel, 카드 UI는 LedgerStats*Card 컴포넌트가 담당한다.
struct LedgerStatsView: View {
    /// 하단 탭바에서 통계 탭을 다시 탭하면 증가 — 맨 위로 스크롤한다.
    var scrollToTopSignal = 0

    @State private var vm = LedgerStatsViewModel()
    /// 기간 타이틀 탭으로 여는 선택 시트 — 월별은 연월, 연별은 연도.
    @State private var showingPeriodPicker = false

    var body: some View {
        ScrollViewReader { proxy in
            statsScroll
                .onChange(of: scrollToTopSignal) {
                    withAnimation(.snappy) { proxy.scrollTo("ledgerStatsTop", anchor: .top) }
                }
        }
        .overlay(alignment: .bottom) {
            // 다른 기간을 보는 중에만 탭바 위에 떠 있는 복귀 캡슐 — 내역 탭과 동일한 패턴.
            if !vm.isAtCurrentPeriod {
                LedgerReturnPill(label: vm.scope == .monthly ? "이번 달" : "올해") { vm.resetToCurrentPeriod() }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy(duration: 0.2), value: vm.isAtCurrentPeriod)
        // 스와이프·화살표·피커·월별↔연별 전환 어느 쪽으로 기간을 바꿔도 촉각 신호를 준다.
        // periodTitle은 scope·month·year를 모두 반영하므로 트리거 하나로 충분하다.
        .sensoryFeedback(.selection, trigger: vm.periodTitle)
        .sheet(isPresented: $showingPeriodPicker) {
            Group {
                switch vm.scope {
                case .monthly:
                    MonthPickerSheet(initialYear: vm.month.year, initialMonth: vm.month.month) { pickedYear, pickedMonth in
                        vm.selectMonthlyPeriod(year: pickedYear, month: pickedMonth)
                    }
                case .yearly:
                    YearPickerSheet(
                        initialYear: vm.year,
                        range: LedgerStatsViewModel.minYear...LedgerYearMonth.current().year
                    ) { pickedYear in
                        vm.selectYearlyPeriod(pickedYear)
                    }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }

    private var statsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                periodHeader
                    .padding(.top, 4)
                    .id("ledgerStatsTop")

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                if let stats = vm.stats {
                    LedgerStatsSummaryCard(
                        title: vm.summaryTitle,
                        current: vm.currentTotal,
                        previous: vm.previousTotal,
                        previousLabel: vm.scope == .monthly ? "지난달" : "지난해",
                        dailyAverage: stats.dailyAverage,
                        deltaPercent: vm.deltaPercent,
                        maxEntry: stats.maxEntry
                    )
                    .padding(.top, 8)

                    HStack {
                        sectionHeader(vm.scope == .monthly ? "최근 6개월" : "\(vm.year)년 월별 추이")
                        Spacer()
                        if vm.hasFx { LedgerStatsChartLegend() }
                    }
                    .padding(.top, 12)
                    LedgerStatsChartCard(
                        trend: stats.monthlyTrend,
                        isMonthlyScope: vm.scope == .monthly,
                        selectedKey: vm.selectedTrendKey,
                        onSelectMonth: { vm.selectedMonth = $0 }
                    )

                    if !stats.topMerchants.isEmpty {
                        sectionHeader("구매금액 TOP 5").padding(.top, 12)
                        LedgerMerchantCard(merchants: stats.topMerchants)
                    }

                    if !stats.sourceBreakdown.isEmpty {
                        sectionHeader("고정비 · 변동비").padding(.top, 12)
                        LedgerFixedVariableCard(breakdown: stats.sourceBreakdown)
                    }

                    if !stats.foreignTotals.isEmpty {
                        sectionHeader("외화").padding(.top, 12)
                        LedgerForeignCard(totals: stats.foreignTotals)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        // 좌우 스와이프 = 기간 이동 (월별이면 월, 연별이면 연). 내역 탭과 같은 판정 기준.
        .simultaneousGesture(periodSwipeGesture)
        .overlay { if vm.isLoading && vm.stats == nil { ProgressView() } }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    /// 수직 스크롤과 헷갈리지 않게 가로 성분이 확실할 때만 반응. 미래 기간으로는 이동하지 않는다.
    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.5 else { return }
                let delta = dx > 0 ? -1 : 1
                guard delta < 0 || !vm.isAtCurrentPeriod else { return }
                vm.shiftPeriod(delta)
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
            ForEach(LedgerStatsViewModel.Scope.allCases) { item in
                Button {
                    vm.selectScope(item)
                } label: {
                    Text(item.rawValue)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(vm.scope == item ? .white : Color.slate500)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if vm.scope == item {
                                Capsule()
                                    .fill(LinearGradient(colors: [Color.blue500, Color.blue700],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(vm.scope == item ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(.white.opacity(0.55), in: Capsule())
    }

    private var periodSwitcher: some View {
        // 내역 탭 monthSwitcher와 동일하게, 아이콘은 12pt여도 히트 영역은 44pt를 확보한다.
        let unit = vm.scope == .monthly ? "달" : "해"
        return HStack(spacing: 0) {
            Button { vm.shiftPeriod(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("이전 \(unit)")
            .disabled(vm.isAtMinPeriod)
            .opacity(vm.isAtMinPeriod ? 0.3 : 1)
            Button { showingPeriodPicker = true } label: {
                Text(vm.periodTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 4)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(vm.scope == .monthly ? "연월 선택 열기" : "연도 선택 열기")
            Button { vm.shiftPeriod(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("다음 \(unit)")
            .disabled(vm.isAtCurrentPeriod)
            .opacity(vm.isAtCurrentPeriod ? 0.3 : 1)
        }
        .foregroundStyle(Color.slate700)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.slate500)
            .padding(.horizontal, 4)
    }
}
