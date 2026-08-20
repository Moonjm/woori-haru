import SwiftUI

/// 통계 탭 「충전」 섹션 — 월별 충전량·비용, 월별 충전횟수, 누적 충전비, 급속/완속 비율.
///
/// **급속/완속만 `/tesla/charges/totals`에서 온다**(전 기간 집계). 나머지 셋은 12개월 추이다.
/// 두 창이 다르므로 도넛 카드에 「전 기간」이라고 적어 둔다.
struct StatsChargeSection: View {
    @Bindable var viewModel: VehicleStatsViewModel
    @Bindable var totalsViewModel: ChargeTotalsViewModel

    @State private var selectedID: String?

    /// **헤더는 내용과 함께만 선다**(`StatsDriveSection`과 같은 규칙). 다만 이 섹션은
    /// 창이 둘이라 게이트도 둘이다 — 월별 차트 셋은 12개월 추이에서, 도넛은 전 기간
    /// 집계에서 온다. **둘 중 하나만 살아도 헤더는 선다.**
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasTrend || totalsViewModel.hasTotals {
                header
            }
            if viewModel.hasTrend {
                monthlyEnergyCard
                chargeCountCard
                cumulativeCostCard
            }
            if totalsViewModel.hasTotals {
                fastSlowCard
            }
        }
    }

    private var header: some View {
        HStack {
            Text("🔌 충전")
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(VehicleTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: - 카드

    private var selected: VehiclePeriod? {
        viewModel.trend.first { $0.yearMonth == selectedID } ?? viewModel.trend.last
    }

    private var monthlyEnergyCard: some View {
        ChartCard(title: "월별 충전량 · 비용",
                  callout: selected.map {
                      "\(ChargeFormat.energy($0.energyAddedKwh)) · \(VehicleFormat.won($0.cost))"
                  }) {
            MonthlyBarLineChart(bars: viewModel.energyPoints,
                                line: viewModel.costPoints,
                                selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                                onSelect: { selectedID = $0 })
        }
    }

    /// **0과 nil은 다르다**(`VehiclePeriod` 문서 참고) — nil을 「0회」로 뭉개지 않으려고
    /// `DriveFormat.count(_:)`를 그대로 쓴다. 「N회」는 단위와 무관해 충전 횟수에도 맞는
    /// 표기라 `ChargeFormat`에 한 줄짜리 포맷터를 또 두지 않는다.
    private var chargeCountCard: some View {
        ChartCard(title: "월별 충전 횟수",
                  callout: selected.map { DriveFormat.count($0.chargeCount) }) {
            MonthlyBarChart(points: viewModel.chargeCountPoints,
                            selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                            onSelect: { selectedID = $0 })
        }
    }

    private var cumulativeCostCard: some View {
        let points = viewModel.cumulativeCostPoints
        // **강조와 콜아웃이 같은 달을 가리키게 한다.** 기본값은 「마지막으로 기록이 있는 달」이라
        // 아무것도 고르지 않은 상태에서 지금까지 누적 충전비가 그대로 보이고,
        // 탭하면 그 달까지의 누적으로 바뀐다.
        let anchorID = selectedID ?? points.last(where: { $0.value != nil })?.id
        let shown = points.first { $0.id == anchorID }
        return ChartCard(title: "누적 충전비",
                          callout: shown.map { VehicleFormat.won($0.value) }) {
            MonthlyLineChart(points: points,
                             selectedID: anchorID,
                             onSelect: { selectedID = $0 })
        }
    }

    /// 급속/완속 — **에너지로 나눈다**(횟수가 아니라). 완속 100번과 급속 5번이 같은 kWh일 수 있고,
    /// 이 카드가 답하는 질문은 「어디서 얼마나 채웠나」다.
    private var fastSlowCard: some View {
        let fast = totalsViewModel.totals?.fast.energyAddedKwh ?? 0
        let slow = totalsViewModel.totals?.slow.energyAddedKwh ?? 0
        let total = fast + slow
        return ChartCard(title: "급속 / 완속", callout: "전 기간") {
            HStack(spacing: 16) {
                DonutChart(slices: [
                    .init(label: "급속", value: fast, color: VehicleTheme.accentBright),
                    .init(label: "완속", value: slow, color: VehicleTheme.accentMuted),
                ])
                VStack(alignment: .leading, spacing: 8) {
                    legend("급속", fast, of: total, color: VehicleTheme.accentBright,
                           price: totalsViewModel.fastWonPerKwh)
                    legend("완속", slow, of: total, color: VehicleTheme.accentMuted,
                           price: totalsViewModel.slowWonPerKwh)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func legend(_ name: String, _ value: Decimal, of total: Decimal,
                        color: Color, price: Decimal?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
            Text(ChargeFormat.energy(value))
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
            Text(ChargeFormat.unitPrice(price))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textTertiary)
        }
        .lineLimit(1)
    }
}
