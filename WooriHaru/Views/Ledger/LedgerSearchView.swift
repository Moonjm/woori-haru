import SwiftUI

/// 전용 검색 화면 (풀스크린) — 최근 검색어, 결과 건수·합계, 매칭 하이라이트.
struct LedgerSearchView: View {
    /// 검색 화면에서 내역을 수정·삭제했을 때 메인 목록을 갱신하기 위한 콜백.
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    @State private var searchText = ""
    @State private var results: [LedgerEntry] = []
    @State private var hasSearched = false
    @State private var isLoading = false
    /// 진행 중 검색의 세대 번호 — 새 검색이 제출되면 이전 요청은 결과 반영·로딩 해제에서 손을 뗀다.
    @State private var searchGeneration = 0
    @State private var errorMessage: String?
    @State private var selectedEntry: LedgerEntry?
    @State private var recentSearches: [String] =
        UserDefaults.standard.stringArray(forKey: LedgerSearchView.recentKey) ?? []

    private let ledgerService = LedgerService()
    private static let recentKey = "ledgerRecentSearches"
    private static let recentLimit = 8

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red500)
                            .padding(.top, 8)
                    }

                    if !hasSearched {
                        recentSection
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 40)
                    } else {
                        resultSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .glassScreenBackground()
        .onAppear { fieldFocused = true }
        .sheet(item: $selectedEntry) { entry in
            LedgerEntryDetailView(entry: entry) {
                await onChanged()
                await search()
            }
        }
    }

    // MARK: - 헤더

    private var searchHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.slate400)
                TextField("구매처·내용 검색", text: $searchText)
                    .font(.subheadline)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        hasSearched = false
                        results = []
                        isLoading = false
                        searchGeneration += 1 // 진행 중이던 검색 응답은 폐기
                        fieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.slate400)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))

            Button("취소") { dismiss() }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.blue600)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 최근 검색

    @ViewBuilder private var recentSection: some View {
        if !recentSearches.isEmpty {
            HStack {
                Text("최근 검색")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)
                Spacer()
                Button("지우기") {
                    recentSearches = []
                    UserDefaults.standard.removeObject(forKey: Self.recentKey)
                }
                .font(.caption2)
                .foregroundStyle(Color.slate400)
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)

            FlowLayoutChips(
                items: recentSearches,
                onTap: { keyword in
                    searchText = keyword
                    Task { await search() }
                },
                onDelete: { keyword in removeRecent(keyword) }
            )
        }
    }

    // MARK: - 결과

    private var resultSection: some View {
        let krwTotal = results
            .filter { $0.type == .expense && $0.currency.uppercased() == "KRW" }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 8) {
            Text("결과 \(results.count)건 · \(LedgerFormat.amount(krwTotal, currency: "KRW"))")
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate500)
                .padding(.horizontal, 4)
                .padding(.top, 10)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        Button { selectedEntry = entry } label: { resultRow(entry) }
                            .buttonStyle(.plain)
                        if index < results.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func resultRow(_ entry: LedgerEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(highlighted(entry.merchant ?? "내역"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate900)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    LedgerSourceBadge(source: entry.source)
                    Text(LedgerFormat.dayWithYear(entry.date))
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(LedgerFormat.amount(entry.amount, currency: entry.currency))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(LedgerFormat.isForeign(entry.currency) ? Color.blue600 : Color.slate900)
                    .lineLimit(1)
                if let converted = entry.fxConvertedText {
                    Text(converted)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.slate400)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    /// 검색어와 일치하는 부분을 하이라이트한다.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty, let range = attributed.range(of: keyword, options: .caseInsensitive) {
            attributed[range].backgroundColor = Color.blue500.opacity(0.22)
        }
        return attributed
    }

    // MARK: - 검색 실행

    private func search() async {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        searchGeneration += 1
        let generation = searchGeneration
        fieldFocused = false
        isLoading = true
        hasSearched = true
        // 입력값만 고쳐진 상태라면 이 요청이 여전히 최신이라 로딩이 갇히지 않고,
        // 새 검색이 제출됐다면 결과 반영·로딩 해제를 그쪽이 이어받는다.
        defer {
            if generation == searchGeneration { isLoading = false }
        }
        do {
            let list = try await ledgerService.fetchEntries(keyword: keyword)
            guard generation == searchGeneration else { return } // 밀려난 검색의 응답은 폐기
            results = list
            errorMessage = nil
            saveRecent(keyword)
        } catch is CancellationError {
            return
        } catch {
            guard generation == searchGeneration else { return }
            results = []
            errorMessage = "검색하지 못했습니다."
        }
    }

    private func saveRecent(_ keyword: String) {
        var list = recentSearches.filter { $0 != keyword }
        list.insert(keyword, at: 0)
        list = Array(list.prefix(Self.recentLimit))
        recentSearches = list
        UserDefaults.standard.set(list, forKey: Self.recentKey)
    }

    private func removeRecent(_ keyword: String) {
        recentSearches.removeAll { $0 == keyword }
        UserDefaults.standard.set(recentSearches, forKey: Self.recentKey)
    }
}

/// 최근 검색어 칩을 줄바꿈하며 배치하는 간단한 플로우 레이아웃.
private struct FlowLayoutChips: View {
    let items: [String]
    let onTap: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        LedgerFlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { keyword in
                HStack(spacing: 6) {
                    Button { onTap(keyword) } label: {
                        Text(keyword)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.slate900)
                    }
                    .buttonStyle(.plain)
                    Button { onDelete(keyword) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.slate400)
                            .padding(2) // 터치 여유
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.7), in: Capsule())
            }
        }
    }
}

/// 좌→우로 채우다 넘치면 줄바꿈하는 레이아웃.
private struct LedgerFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
