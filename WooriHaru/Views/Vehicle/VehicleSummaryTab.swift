import SwiftUI

/// 요약 탭 — 그 달 주행·충전, 지표, 12개월 추이, 미등록 배지, 그 달 충전 목록.
struct VehicleSummaryTab: View {
    @Bindable var viewModel: VehicleSummaryViewModel
    let onOpenQueue: () -> Void

    @State private var selectedItem: ChargeItem?
    @State private var selectedTrendKey: String?

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 30

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                heroCard.padding(.top, 8)
                metricsCard.padding(.top, 12)

                if let summary = viewModel.summary {
                    VehicleTrendChart(
                        trend: summary.trend,
                        selectedKey: selectedTrendKey ?? viewModel.month.apiValue,
                        onSelect: { selectedTrendKey = $0 }
                    )
                    .padding(.top, 12)
                }

                if viewModel.missingCostCount > 0 {
                    missingCostBadge.padding(.top, 12)
                }

                if let error = viewModel.errorMessage, viewModel.summary != nil {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                if viewModel.isLoading && viewModel.summary == nil {
                    ProgressView().padding(.top, 60)
                } else if let error = viewModel.errorMessage, viewModel.summary == nil {
                    // 못 불러온 것을 「기록 없음」으로 그리지 않는다.
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
            .padding(.bottom, 110) // 하단 탭바에 가리지 않게
        }
        .refreshable {
            await viewModel.reload()
            // 당겨서 새로고침해도 배지가 맞아야 한다 — 목록만 새로고침하면 미등록 수가 벌어진다.
            await viewModel.refreshMissingCount()
        }
        .sheet(item: $selectedItem) { item in
            ChargeDetailView(item: item) {
                await viewModel.reload()
                // 상세 시트에서 금액을 채우는 것도 등록 경로다 — 배지를 같이 맞춘다.
                await viewModel.refreshMissingCount()
            }
        }
        .onChange(of: viewModel.month) { selectedTrendKey = nil }
    }

    // MARK: - 카드

    private var heroTitle: String {
        let current = LedgerYearMonth.current()
        if viewModel.month == current { return "이번 달" }
        if viewModel.month.year == current.year { return "\(viewModel.month.month)월" }
        return viewModel.month.displayLong
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heroTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(loaded ? VehicleFormat.distance(viewModel.summary?.month.distanceKm) : ChargeFormat.placeholder)
                Text(loaded
                     ? ChargeFormat.summaryTotal(viewModel.summary?.month.cost,
                                                 count: viewModel.summary?.month.chargeCount ?? 0,
                                                 loaded: true)
                     : ChargeFormat.placeholder)
            }
            .font(.system(size: heroSize, weight: .heavy))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.top, 4)

            if loaded {
                HStack(spacing: 6) {
                    chip("\(viewModel.summary?.month.chargeCount ?? 0)회 충전")
                    chip(ChargeFormat.energy(viewModel.summary?.month.energyAddedKwh))
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
    }

    private var loaded: Bool { viewModel.isMonthLoaded }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.2), in: Capsule())
    }

    private var metricsCard: some View {
        let month = viewModel.summary?.month
        let delta = VehicleMath.deltaPercent(current: month?.costPerKm,
                                             previous: viewModel.summary?.previous?.costPerKm)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    metric("km당 비용", VehicleFormat.costPerKm(loaded ? month?.costPerKm : nil))
                    Divider().frame(height: 28)
                    metric("전비", VehicleFormat.efficiency(loaded ? month?.efficiency : nil))
                }
                if let delta {
                    Text(delta >= 0 ? "지난달보다 ▲ \(delta)%" : "지난달보다 ▼ \(-delta)%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(delta >= 0 ? Color.red500 : Color.green600)
                }
                Text("그 달 충전량을 그 달 주행으로 나눈 값이라 월 경계에서 조금 흔들려요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missingCostBadge: some View {
        Button(action: onOpenQueue) {
            HStack(spacing: 8) {
                Image(systemName: "wonsign.circle")
                Text("금액 미등록 \(viewModel.missingCostCount)건")
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(Color.orange700)
            .padding(14)
            .background(Color.orange100, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func daySection(_ section: VehicleSummaryViewModel.DaySection) -> some View {
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
                        // Button 대신 onTapGesture — 월 스와이프와 함께 두면 Button은
                        // 끌고 놓는 동안에도 눌린 것으로 쳐서 상세가 열린다.
                        ChargeRow(item: item)
                            .onTapGesture { selectedItem = item }
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
            Label("이 달 충전 기록이 없어요", systemImage: "car")
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
}
