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

    /// 분포 두 장은 **월별 `selectedID`와 상태를 나눈다**(`StatsDriveSection`과 같은 이유) —
    /// id 네임스페이스가 달라(`"cs0"`·`"ce90"` 대 `"2026-08"`) 한 상태를 같이 쓰면
    /// 분포 칸을 탭했을 때 월별 카드 넷이 한꺼번에 콜아웃을 잃는다.
    @State private var chargeStartSelectedID: String?
    @State private var chargeEndSelectedID: String?

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
                chargingTimeCard
                chargeCountCard
                cumulativeCostCard
                chargeHeatmapCard
                chargeStartLevelCard
                chargeEndLevelCard
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

    /// #12 월별 충전 시간. 콜아웃만 시·분으로 적는다(`ChargeFormat.duration`) — 막대 값은
    /// `drivingMinPoints`와 같은 이유로 분 그대로 둔다(막대 높이는 비율이라 단위 무관).
    private var chargingTimeCard: some View {
        let points = viewModel.chargingMinPoints
        let anchor = anchorID(points)
        let shown = viewModel.monthly.first { $0.yearMonth == anchor }
        return ChartCard(title: "월별 충전 시간",
                         callout: shown.map { ChargeFormat.duration($0.chargingMin) }) {
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

    // MARK: - 카드(분포)

    /// 분포 두 장의 기본 선택. **월별 `anchorID`의 규칙이 안 맞는다** — 분포에는 시간
    /// 순서가 없어 「마지막」이 아무 뜻도 없다. `StatsDriveSection.distributionAnchor`와
    /// 같은 규칙: 아무것도 안 골랐으면 **가장 큰 칸**을 기본으로 보여 준다.
    private func distributionAnchor(_ points: [ChartPoint], selected: String?) -> String? {
        selected ?? points.max { ($0.value ?? -1) < ($1.value ?? -1) }?.id
    }

    /// `ChartPoint.value`가 `Decimal?`로 고정된 원형이라, 건수를 실어 온 점을 도로
    /// `Int?`로 되돌린다. `StatsDriveSection.intCount`와 같다.
    private func intCount(_ value: Decimal?) -> Int? {
        value.map { NSDecimalNumber(decimal: $0).intValue }
    }

    /// #15 충전 시간대×요일. `HeatmapGrid`는 #6 「언제 타나」(`DriveTimeHeatmap`)에서
    /// 뽑아낸 원형을 그대로 쓴다 — 여기가 그 두 번째 소비자다.
    ///
    /// **`chargeTimes`는 0=일요일**(`driveTimes`와 같은 규약)이라 `weekdayLabel`을 쓰는
    /// `HeatmapGrid`를 그대로 넘기면 맞는다. 직전 태스크가 `weekday` 배열(1=월요일,
    /// `isoWeekdayLabel`)을 쓴 것과 헷갈리지 않는다.
    private var chargeHeatmapCard: some View {
        ChartCard(title: "충전 시간대", callout: DriveFormat.count(viewModel.totalChargeHeatCount)) {
            HeatmapGrid(count: { viewModel.chargeHeatCount(weekday: $0, hour: $1) },
                       maxCount: viewModel.maxChargeHeatCount,
                       accessibilityLabel: chargeHeatmapAccessibilityLabel)
        }
    }

    /// `DriveTimeHeatmap.rowAccessibilityLabel`과 같은 모양이다 — `HeatmapGrid`는
    /// 렌더링만 하고 문구는 호출부(도메인)에 남기기로 했으므로, 말만 「주행」에서
    /// 「충전」으로 바꿔 여기 둔다.
    private func chargeHeatmapAccessibilityLabel(_ weekday: Int) -> String {
        var total = 0
        var peakHour = 0
        var peakCount = 0
        for hour in 0..<24 {
            let value = viewModel.chargeHeatCount(weekday: weekday, hour: hour)
            total += value
            if value > peakCount {
                peakCount = value
                peakHour = hour
            }
        }
        let weekdayName = "\(DriveFormat.weekdayLabel(weekday))요일"
        guard total > 0 else { return "\(weekdayName) 충전 없음" }
        return "\(weekdayName) 총 \(DriveFormat.count(total)), 가장 많은 시각 "
            + "\(DriveFormat.hourLabel(peakHour)) \(DriveFormat.count(peakCount))"
    }

    /// #16 충전 시작 SoC 분포. 예외 없이 열 칸 전부 「미만」 경계다(#17과 다른 점).
    private var chargeStartLevelCard: some View {
        let points = viewModel.chargeStartLevelPoints
        let anchor = distributionAnchor(points, selected: chargeStartSelectedID)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "충전 시작 SoC 분포",
                         callout: shown.map { "\($0.label)% \(DriveFormat.count(intCount($0.value)))" }) {
            DistributionBarChart(points: points,
                                 selectedID: anchor,
                                 onSelect: { chargeStartSelectedID = $0 })
        }
    }

    /// #17 충전 종료 SoC 분포. **마지막 칸(`90~100`)만 라벨이 범위다** —
    /// `chargeEndLevelPoints`가 그 칸만 양끝이 닫힌 사실을 라벨로 드러낸다.
    private var chargeEndLevelCard: some View {
        let points = viewModel.chargeEndLevelPoints
        let anchor = distributionAnchor(points, selected: chargeEndSelectedID)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "충전 종료 SoC 분포",
                         callout: shown.map { "\($0.label)% \(DriveFormat.count(intCount($0.value)))" }) {
            DistributionBarChart(points: points,
                                 selectedID: anchor,
                                 onSelect: { chargeEndSelectedID = $0 })
        }
    }

    // MARK: - 카드(전 기간)

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
