import SwiftUI

/// 통계 탭 「충전」 섹션 — 월별 충전량·비용, 월별 충전횟수, 누적 충전비, 급속/완속 비율.
///
/// **급속/완속만 `/tesla/charges/totals`에서 온다**(전 기간 집계). 나머지 셋은
/// `/tesla/insights`의 `monthly`라 기간 칩을 따른다 — 두 창이 다르므로 도넛 카드에
/// 「전 기간」이라고 적어 둔다.
struct StatsChargeSection: View {
    @Bindable var viewModel: VehicleStatsViewModel
    @Bindable var totalsViewModel: ChargeTotalsViewModel

    @State private var selectedID: String?

    /// **헤더는 내용과 함께만 선다**(`StatsDriveSection`과 같은 규칙). 다만 이 섹션은
    /// 창이 둘이라 게이트도 둘이다 — 월별 차트 셋은 기간 칩을 따르는 `monthly`에서,
    /// 도넛은 전 기간 집계에서 온다. **둘 중 하나만 살아도 헤더는 선다.**
    ///
    /// **월별 게이트가 주행 섹션의 것과 다르다**(`hasChargeMonths`) — 충전은 주행 없이도
    /// 하므로, 안 타고 충전만 한 기간에 이 섹션까지 사라지면 안 된다.
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasChargeMonths || totalsViewModel.hasTotals {
                header
            }
            if viewModel.hasChargeMonths {
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

    /// **강조와 콜아웃이 같은 달을 가리키게 한다.** 규칙은 `StatsDriveSection`과 같다 —
    /// 「마지막으로 **기록이 있는** 달」이고, 카드마다 **자기 계열**로 잡는다.
    /// 그냥 `last`를 쓰면 달 초에 이웃 카드 셋만 「—」가 되고 하나만 지난달을 가리킨다.
    private func anchorID(_ points: [ChartPoint]) -> String? {
        selectedID ?? points.last(where: { $0.value != nil })?.id
    }

    private var monthlyEnergyCard: some View {
        // 슬롯을 정하는 것은 막대(충전량)라 기준도 충전량에서 잡는다.
        let points = viewModel.energyPoints
        let anchor = anchorID(points)
        let shown = viewModel.monthly.first { $0.yearMonth == anchor }
        return ChartCard(title: "월별 충전량 · 비용",
                         callout: shown.map {
                             "\(ChargeFormat.energy($0.energyAddedKwh)) · \(VehicleFormat.won($0.cost))"
                         }) {
            MonthlyBarLineChart(bars: points,
                                line: viewModel.costPoints,
                                selectedID: anchor,
                                onSelect: { selectedID = $0 })
        }
    }

    /// **0과 nil은 다르다**(`VehiclePeriod` 문서 참고) — nil을 「0회」로 뭉개지 않으려고
    /// `DriveFormat.count(_:)`를 그대로 쓴다. 「N회」는 단위와 무관해 충전 횟수에도 맞는
    /// 표기라 `ChargeFormat`에 한 줄짜리 포맷터를 또 두지 않는다.
    private var chargeCountCard: some View {
        let points = viewModel.chargeCountPoints
        let anchor = anchorID(points)
        let shown = viewModel.monthly.first { $0.yearMonth == anchor }
        return ChartCard(title: "월별 충전 횟수",
                         callout: shown.map { DriveFormat.count($0.chargeCount) }) {
            MonthlyBarChart(points: points,
                            selectedID: anchor,
                            onSelect: { selectedID = $0 })
        }
    }

    private var cumulativeCostCard: some View {
        let points = viewModel.cumulativeCostPoints
        let anchor = anchorID(points)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "누적 충전비",
                          callout: shown.map { VehicleFormat.won($0.value) }) {
            MonthlyLineChart(points: points,
                             selectedID: anchor,
                             onSelect: { selectedID = $0 })
        }
    }

    /// 급속/완속 — **에너지로 나눈다**(횟수가 아니라). 완속 100번과 급속 5번이 같은 kWh일 수 있고,
    /// 이 카드가 답하는 질문은 「어디서 얼마나 채웠나」다.
    private var fastSlowCard: some View {
        let fast = totalsViewModel.totals?.fast.energyAddedKwh ?? 0
        let slow = totalsViewModel.totals?.slow.energyAddedKwh ?? 0
        return ChartCard(title: "급속 / 완속", callout: "전 기간") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    DonutChart(slices: [
                        .init(label: "급속", value: fast, color: VehicleTheme.accentBright),
                        .init(label: "완속", value: slow, color: VehicleTheme.accentMuted),
                    ])
                    VStack(alignment: .leading, spacing: 8) {
                        legend("급속", fast, color: VehicleTheme.accentBright,
                               price: totalsViewModel.fastWonPerKwh)
                        legend("완속", slow, color: VehicleTheme.accentMuted,
                               price: totalsViewModel.slowWonPerKwh)
                    }
                    Spacer(minLength: 0)
                }

                // 한 줄에 놓인 kWh와 단가는 **분모가 다르다** — kWh는 충전량(차에 들어간 양),
                // 단가는 사용량(벽에서 뽑은 양)이 분모다. 둘을 곱해도 비용이 안 나온다.
                // `CostBreakdownCard`가 같은 함정에 캡션을 다는 것과 같은 이유다.
                Text("단가는 사용량 1kWh당 금액이에요. 왼쪽 kWh는 충전량이라 분모가 달라요.")
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    /// 비율은 도넛이 말한다 — 범례는 양과 단가만 적는다.
    private func legend(_ name: String, _ value: Decimal,
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
