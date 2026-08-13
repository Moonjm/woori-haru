import SwiftUI

/// 충전 내역 — 월 단위 목록 + 기간 합계. 항목을 누르면 상세에서 금액을 고친다.
struct ChargeListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ChargeListViewModel()
    @State private var selectedItem: ChargeItem?
    @State private var showingMonthPicker = false

    /// 히어로 금액은 Dynamic Type을 따라 커진다 (넘치면 minimumScaleFactor로 축소).
    @ScaledMetric(relativeTo: .largeTitle) private var summaryAmountSize: CGFloat = 34

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                summaryCard.padding(.top, 8)

                // 보고 있던 목록이 남아 있는 새로고침 실패는 한 줄로만 알린다.
                if let error = viewModel.errorMessage, !viewModel.items.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView().padding(.top, 60)
                } else if let error = viewModel.errorMessage {
                    // **못 불러온 것을 「기록 없음」으로 보여주지 않는다** — 둘은 다른 사실이고,
                    // 빈 화면을 본 사용자는 기록이 날아간 줄 안다.
                    errorState(error).padding(.top, 48)
                } else if viewModel.sections.isEmpty {
                    emptyState.padding(.top, 48)
                } else {
                    ForEach(viewModel.sections) { section in
                        daySection(section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        // 좌우 스와이프 = 월 이동.
        .simultaneousGesture(monthSwipeGesture)
        .refreshable { await viewModel.reload() }
        .glassScreenBackground()
        .navigationBarBackButtonHidden(true) // 월 이동 스와이프와 겹치는 엣지 뒤로가기 제스처 차단
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel("뒤로")
            }
            ToolbarItem(placement: .principal) { monthSwitcher }
        }
        .sensoryFeedback(.selection, trigger: viewModel.month)
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(
                initialYear: viewModel.month.year,
                initialMonth: viewModel.month.month
            ) { year, month in
                Task { await viewModel.selectMonth(year: year, month: month) }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        // 목록에서 아는 값(장소·시각·금액)을 먼저 그려 두고 상세를 덧입힌다 — 시트가 빈 채로 뜨지 않는다.
        // 금액을 고치고 닫으면 목록을 다시 불러 합계까지 맞춘다.
        .sheet(item: $selectedItem) { item in
            ChargeDetailView(item: item) { await viewModel.reload() }
        }
        .task { await viewModel.load() }
    }

    // MARK: - 합계 히어로

    private var summaryTitle: String {
        let current = LedgerYearMonth.current()
        if viewModel.month == current { return "이번 달 충전" }
        if viewModel.month.year == current.year { return "\(viewModel.month.month)월 충전" }
        return "\(viewModel.month.year)년 \(viewModel.month.month)월 충전"
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summaryTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.8))
            Text(ChargeFormat.summaryTotal(
                viewModel.summary.totalCost,
                count: viewModel.summary.count,
                loaded: viewModel.isMonthLoaded
            ))
                .font(.system(size: summaryAmountSize, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .padding(.top, 4)
                .contentTransition(.numericText())
                .animation(.snappy, value: viewModel.summary)

            // 응답을 받기 전에는 칩을 아예 그리지 않는다 — 「0회」는 못 받았다는 뜻이 아니라
            // 충전이 없었다는 뜻이라, 실패 안내와 나란히 놓이면 서로 어긋난다.
            if viewModel.isMonthLoaded {
                HStack(spacing: 6) {
                    summaryChip("\(viewModel.summary.count)회")
                    summaryChip(ChargeFormat.energy(viewModel.summary.totalEnergyAddedKwh))
                    // 금액이 빈 건은 이 화면에 오는 이유 그 자체라 합계 옆에 붙여 둔다.
                    if viewModel.missingCostCount > 0 {
                        summaryChip("금액 없음 \(viewModel.missingCostCount)건", emphasized: true)
                    }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Color.green600, Color.blue700],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: Color.blue600.opacity(0.35), radius: 14, y: 8)
        .padding(.bottom, 4)
    }

    private func summaryChip(_ text: String, emphasized: Bool = false) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(emphasized ? 0.32 : 0.2), in: Capsule())
    }

    // MARK: - 목록

    private func daySection(_ section: ChargeListViewModel.DaySection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LedgerFormat.dayHeader(section.date))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.slate500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 16)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        Button { selectedItem = item } label: {
                            ChargeRow(item: item)
                        }
                        .buttonStyle(.plain)
                        if index < section.items.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("이 달 충전 기록이 없어요", systemImage: "bolt.slash")
        } description: {
            Text("다른 달을 보려면 위 연월을 눌러 주세요")
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await viewModel.reload() } }
                .buttonStyle(.borderedProminent)
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
        // 화살표는 아이콘만 13pt여도 히트 영역은 44pt를 확보한다 (HIG 최소 터치 타깃).
        HStack(spacing: 0) {
            Button { Task { await viewModel.shiftMonth(-1) } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("이전 달")
            Button { showingMonthPicker = true } label: {
                Text(viewModel.month.displayLong)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 4)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("연월 선택 열기")
            Button { Task { await viewModel.shiftMonth(1) } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("다음 달")
            .disabled(viewModel.isAtCurrentMonth)
            .opacity(viewModel.isAtCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Color.slate700)
    }
}

/// 한 줄 충전 — 장소 + 시각·소요시간 + 충전량·배터리 + 금액.
struct ChargeRow: View {
    let item: ChargeItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.locationName ?? "장소 없음")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate900)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(LedgerFormat.time(item.startDate))
                    Text("·")
                    Text(ChargeFormat.duration(item.durationMin))
                    // 단가는 사용 전력이 있어야 낼 수 있다 — 없으면 자리도 만들지 않는다.
                    if let unit = item.costPerKwh {
                        Text("·")
                        Text(ChargeFormat.unitPrice(unit))
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.slate400)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ChargeFormat.cost(item.cost))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    // 금액이 빈 건은 회색으로 죽이지 않고 따로 표시한다 — 채우러 오는 화면이다.
                    .foregroundStyle(item.cost == nil ? Color.orange700 : Color.slate900)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(ChargeFormat.energy(item.energyAddedKwh))
                    Text(ChargeFormat.batteryRange(item.startBatteryLevel, item.endBatteryLevel))
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.slate400)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}
