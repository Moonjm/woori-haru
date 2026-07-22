import SwiftUI

struct LedgerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = LedgerViewModel()
    @State private var showingCreate = false
    @State private var selectedEntry: LedgerEntry?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !viewModel.isSearching {
                    summaryCard
                        .padding(.top, 8)
                }

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
            .padding(.bottom, 24)
        }
        // 좌우 스와이프 = 월 이동. 시스템 뒤로가기 엣지 제스처와 겹치지 않도록
        // 시스템 뒤로가기는 끄고(제스처 포함) 커스텀 뒤로가기 버튼으로 대체한다.
        .simultaneousGesture(monthSwipeGesture)
        .navigationBarBackButtonHidden(true)
        .glassScreenBackground()
        .navigationTitle(viewModel.isSearching ? "검색" : "가계부")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
            }
            if !viewModel.isSearching {
                ToolbarItem(placement: .principal) { monthSwitcher }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(value: AppDestination.ledgerRecurring) {
                        Label("반복 관리", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
                    NavigationLink(value: AppDestination.ledgerApiKeys) {
                        Label("단축어 API 키", systemImage: "key")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "구매처·내용 검색")
        .onSubmit(of: .search) {
            viewModel.isSearching = true
            Task { await viewModel.reload() }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespaces).isEmpty, viewModel.isSearching {
                viewModel.isSearching = false
                Task { await viewModel.reload() }
            }
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.load() }
        .sheet(item: $selectedEntry) { entry in
            LedgerEntryDetailView(entry: entry) { await viewModel.reload() }
        }
        .sheet(isPresented: $showingCreate) {
            LedgerEntryFormView(mode: .create) { await viewModel.reload() }
        }
    }

    // MARK: - 상단 합계

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("이번 달 지출")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate500)
                Text(LedgerFormat.amount(viewModel.monthlyKRWTotal, currency: "KRW"))
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
                    .padding(.top, 4)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: viewModel.monthlyKRWTotal)

                HStack(spacing: 8) {
                    statChip(key: "거래", value: "\(viewModel.expenseCount)건")
                    ForEach(viewModel.foreignTotals, id: \.currency) { item in
                        statChip(key: item.currency, value: LedgerFormat.amount(item.amount, currency: item.currency))
                    }
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statChip(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.slate500)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 날짜 섹션

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
                        // Button 대신 onTapGesture: simultaneousGesture(월 스와이프)와 조합 시
                        // 스크롤 중에도 Button 터치가 살아 상세가 열리는 문제를 막는다.
                        // (탭 제스처는 드래그가 시작되면 자동으로 실패한다)
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
            Label(
                viewModel.isSearching ? "검색 결과가 없어요" : "이 달 내역이 없어요",
                systemImage: viewModel.isSearching ? "magnifyingglass" : "tray"
            )
        } description: {
            if !viewModel.isSearching {
                Text("오른쪽 위 + 로 내역을 추가해 보세요")
            }
        }
    }

    // MARK: - 월 이동

    /// 좌우 스와이프로 월을 넘긴다. 수직 스크롤과 헷갈리지 않게 가로 성분이 확실할 때만 반응.
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard !viewModel.isSearching else { return }
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
            Text(viewModel.month.displayLong)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .contentTransition(.numericText())
            Button { Task { await viewModel.shiftMonth(1) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
            }
        }
        .foregroundStyle(Color.slate700)
    }
}

/// 한 줄 내역 — 구매처 + 출처 배지 + 금액.
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
        case .manual, .imported: return Color.slate500
        }
    }

    private var background: Color {
        switch source {
        case .sms: return Color.blue600.opacity(0.12)
        case .kakaoPay: return Color(red: 0.996, green: 0.898, blue: 0.0)
        case .recurring: return Color.purple500.opacity(0.12)
        case .manual, .imported: return Color.slate500.opacity(0.12)
        }
    }
}
