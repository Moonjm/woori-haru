import SwiftUI

/// 가계부 미니앱 컨테이너 — 자체 하단 탭(내역·통계·설정) + 우측 하단 FAB.
/// 디자인: 라이트 글래스 바탕 + 블루 틴트 히어로(G4).
struct LedgerView: View {
    private enum LedgerTab { case entries, stats, settings }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: LedgerTab = .entries
    @State private var viewModel = LedgerViewModel()
    @State private var showingCreate = false
    @State private var selectedEntry: LedgerEntry?
    /// 전용 검색 화면 표시 여부 — 돋보기 버튼으로 연다.
    @State private var showingSearch = false
    /// 연월 선택 시트 — 상단 연월 타이틀 탭으로 연다.
    @State private var showingMonthPicker = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            ledgerTabBar
        }
        .overlay(alignment: .bottomTrailing) {
            if tab == .entries { addButton }
        }
        .glassScreenBackground()
        .navigationBarBackButtonHidden(true) // 좌우 스와이프(월 이동)와 겹치는 엣지 제스처 차단
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
            }
            ToolbarItem(placement: .principal) { principalTitle }
            if tab == .entries {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                }
            }
        }
        .fullScreenCover(isPresented: $showingSearch) {
            LedgerSearchView { await viewModel.reload() }
        }
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(
                initialYear: viewModel.month.year,
                initialMonth: viewModel.month.month
            ) { year, month in
                viewModel.month = LedgerYearMonth(year: year, month: month)
                Task { await viewModel.reload() }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .task { await viewModel.load() }
        .sheet(item: $selectedEntry) { entry in
            LedgerEntryDetailView(entry: entry) { await viewModel.reload() }
        }
        .sheet(isPresented: $showingCreate) {
            LedgerEntryFormView(mode: .create) { await viewModel.reload() }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .entries: entriesTab
        case .stats: LedgerStatsView()
        case .settings: settingsTab
        }
    }

    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .entries:
            monthSwitcher
        case .stats:
            Text("통계").font(.subheadline).fontWeight(.bold)
        case .settings:
            Text("설정").font(.subheadline).fontWeight(.bold)
        }
    }

    // MARK: - 내역 탭

    private var entriesTab: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                summaryCard
                    .padding(.top, 8)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                if viewModel.isLoading && viewModel.entries.isEmpty {
                    ProgressView().padding(.top, 60)
                } else if viewModel.sections.isEmpty {
                    emptyState.padding(.top, 48)
                } else {
                    ForEach(viewModel.sections) { section in
                        daySection(section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120) // 하단 탭바·FAB에 가리지 않게
        }
        // 좌우 스와이프 = 월 이동. 검색은 전용 화면(LedgerSearchView)에서.
        .simultaneousGesture(monthSwipeGesture)
        .refreshable { await viewModel.reload() }
    }

    /// 블루 틴트 히어로 (G4) — 이번 달 지출 + 외화 합계
    /// 이동한 달에서는 "이번 달"이 아니라 실제 연·월로 표시한다.
    private var summaryTitle: String {
        let current = LedgerYearMonth.current()
        if viewModel.month == current { return "이번 달 지출" }
        if viewModel.month.year == current.year { return "\(viewModel.month.month)월 지출" }
        return "\(viewModel.month.year)년 \(viewModel.month.month)월 지출"
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summaryTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.8))
            Text(LedgerFormat.amount(viewModel.monthlyKRWTotal, currency: "KRW"))
                .font(.system(size: 34, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.top, 4)
                .contentTransition(.numericText())
                .animation(.snappy, value: viewModel.monthlyKRWTotal)

            if !viewModel.foreignTotals.isEmpty {
                HStack(spacing: 6) {
                    ForEach(viewModel.foreignTotals, id: \.currency) { item in
                        Text("\(item.currency) \(LedgerFormat.amount(item.amount, currency: item.currency))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Color.blue500, Color.blue700],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: Color.blue600.opacity(0.35), radius: 14, y: 8)
        .padding(.bottom, 4)
    }

    private func daySection(_ section: LedgerViewModel.DaySection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LedgerFormat.dayHeader(section.date))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)
                Spacer()
                if section.krwTotal > 0 {
                    Text(LedgerFormat.amount(section.krwTotal, currency: "KRW"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.slate400)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 16)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                        // Button 대신 onTapGesture: 월 스와이프 제스처와 조합 시
                        // 스크롤 중 상세가 열리는 문제를 막는다 (드래그 시작 시 탭 자동 실패).
                        LedgerEntryRow(entry: entry)
                            .onTapGesture { selectedEntry = entry }
                        if index < section.entries.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("이 달 내역이 없어요", systemImage: "tray")
        } description: {
            Text("오른쪽 아래 + 로 내역을 추가해 보세요")
        }
    }

    /// 좌우 스와이프로 월을 넘긴다. 수직 스크롤과 헷갈리지 않게 가로 성분이 확실할 때만 반응.
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.5 else { return }
                Task { await viewModel.shiftMonth(dx > 0 ? -1 : 1) }
            }
    }

    private var monthSwitcher: some View {
        HStack(spacing: 14) {
            Button { Task { await viewModel.shiftMonth(-1) } } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
            }
            Button { showingMonthPicker = true } label: {
                Text(viewModel.month.displayLong)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            Button { Task { await viewModel.shiftMonth(1) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
            }
        }
        .foregroundStyle(Color.slate700)
    }

    // MARK: - 설정 탭

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("자동화")
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink(value: AppDestination.ledgerRecurring) {
                            settingsRow(icon: "arrow.trianglehead.2.clockwise.rotate.90",
                                        title: "반복 관리", subtitle: "매월 자동 등록 규칙")
                        }
                        Divider().padding(.leading, 52)
                        NavigationLink(value: AppDestination.ledgerApiKeys) {
                            settingsRow(icon: "key", title: "단축어 API 키", subtitle: "카드 문자 자동 수집용 키")
                        }
                    }
                }

                sectionHeader("정보").padding(.top, 12)
                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("외화 표시")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("환산 없이 통화 그대로 표시하고, 결제 시점 환율은 메모에 기록돼요.")
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.slate500)
            .padding(.horizontal, 4)
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.blue600)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate900)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.slate400)
        }
        .padding(14)
        .contentShape(.rect)
    }

    // MARK: - 하단 탭바 + FAB

    private var ledgerTabBar: some View {
        HStack(spacing: 4) {
            tabButton(.entries, icon: "list.bullet", label: "내역")
            tabButton(.stats, icon: "chart.bar.fill", label: "통계")
            tabButton(.settings, icon: "gearshape.fill", label: "설정")
        }
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        // 글래스는 시각 효과일 뿐 터치를 잡지 않는다 — 버튼 사이·테두리 여백 터치가
        // 아래 목록으로 새서 상세가 열리는 것을 막기 위해 바 전체를 히트 영역으로 만들고
        // 빈 곳 탭은 여기서 소비한다 (버튼 탭은 자식이 우선이라 영향 없음).
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {}
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
    }

    private func tabButton(_ target: LedgerTab, icon: String, label: String) -> some View {
        let selected = tab == target
        return Button {
            withAnimation(.snappy(duration: 0.2)) { tab = target }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : Color.slate500)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: [Color.blue500, Color.blue700],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color.blue600.opacity(0.4), radius: 8, y: 3)
                }
            }
            .contentShape(.rect) // 아이콘·글자 사이 빈틈 없이 버튼 전체가 눌리게
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button { showingCreate = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(colors: [Color.blue500, Color.blue700],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .shadow(color: Color.blue600.opacity(0.45), radius: 10, y: 5)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 84)
    }
}

/// 한 줄 내역 — 구매처 + 출처 배지 + 시각 + 금액.
struct LedgerEntryRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.merchant ?? "내역")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate900)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    LedgerSourceBadge(source: entry.source)
                    Text(LedgerFormat.time(entry.date))
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
            }
            Spacer(minLength: 8)
            Text(LedgerFormat.amount(entry.amount, currency: entry.currency))
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private var amountColor: Color {
        if entry.type == .income { return Color.green600 }
        if LedgerFormat.isForeign(entry.currency) { return Color.blue600 }
        return Color.slate900
    }
}

/// 출처 배지 (문자·카카오페이·반복·수동·가져오기)
struct LedgerSourceBadge: View {
    let source: EntrySource

    var body: some View {
        Text(source.label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
    }

    private var foreground: Color {
        switch source {
        case .sms: return Color.blue600
        case .kakaoPay: return Color(red: 0.23, green: 0.18, blue: 0.0)
        case .recurring: return Color.purple500
        case .manual: return Color.slate500
        }
    }

    private var background: Color {
        switch source {
        case .sms: return Color.blue600.opacity(0.12)
        case .kakaoPay: return Color(red: 0.996, green: 0.898, blue: 0.0)
        case .recurring: return Color.purple500.opacity(0.12)
        case .manual: return Color.slate500.opacity(0.12)
        }
    }
}
