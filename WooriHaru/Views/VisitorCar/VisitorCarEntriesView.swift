import SwiftUI

/// 우리 세대 차량의 입출차 현황.
///
/// **아직 안 나간 차는 주차시간이 흐른다** — 화면이 떠 있는 동안 1분마다 다시 그린다.
struct VisitorCarEntriesView: View {
    @State private var viewModel = VisitorCarEntriesViewModel()

    /// 1분이면 족하다. 화면에 분 단위까지만 적는다.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                conditionCard

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.entries.isEmpty && !viewModel.isLoading {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(VehicleTheme.textTertiary)
                            Text("입출차 내역이 없습니다.")
                                .font(.footnote)
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(viewModel.entries) { entry in
                        row(entry)
                    }
                    if viewModel.hasMore {
                        Button { Task { await viewModel.loadMore() } } label: {
                            Text("더 보기")
                                .font(.subheadline)
                                .foregroundStyle(VehicleTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("차량 진입 현황")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.search() }
        .onReceive(ticker) { _ in viewModel.tick() }
    }

    private var conditionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("조회 조건", systemImage: "line.3.horizontal.decrease")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                DatePicker("시작", selection: $viewModel.from, displayedComponents: [.date, .hourAndMinute])
                Divider().overlay(VehicleTheme.cardStroke)
                DatePicker("종료", selection: $viewModel.to, displayedComponents: [.date, .hourAndMinute])

                Button { Task { await viewModel.search() } } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView().tint(VehicleTheme.background)
                        } else {
                            Label("조회", systemImage: "magnifyingglass").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(VehicleTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(VehicleTheme.background)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .font(.subheadline)
            .foregroundStyle(VehicleTheme.textSecondary)
        }
    }

    private func row(_ entry: VisitorCarEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.carNo)
                        .font(.headline)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Spacer(minLength: 0)
                    if let status = entry.status {
                        Text(status.label)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                // 아직 안 나간 차만 강조한다 — 나머지는 지난 일이다.
                                (status.isParked ? VehicleTheme.accent.opacity(0.20) : VehicleTheme.tileFill),
                                in: Capsule()
                            )
                            .foregroundStyle(status.isParked ? VehicleTheme.accent : VehicleTheme.textSecondary)
                    }
                }

                HStack {
                    Text("입차 \(VisitorCarDateFormat.second.string(from: entry.inDate))")
                    Spacer(minLength: 0)
                    Text(VisitorCarEntriesViewModel.parkingText(seconds: entry.parkingSeconds(now: viewModel.now)))
                }
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)

                if let outDate = entry.outDate {
                    Text("출차 \(VisitorCarDateFormat.second.string(from: outDate))")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { VisitorCarEntriesView() }
}
