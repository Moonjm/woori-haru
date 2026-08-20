import SwiftUI

/// 통계 탭 「주행」 섹션 — 새 차트 넷과 기존 카드 넷.
///
/// **새 차트 넷은 기간 칩을 따르지 않는다.** 12개월 추이(`trend`)에서 나오는 값이라
/// 늘 최근 12개월이고, 기존 카드 넷만 칩을 따른다. 2단계에서 서버가 `months`를 받는
/// `/tesla/insights`를 내면 둘이 같은 창을 보게 된다.
struct StatsDriveSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 12) {
            header

            if viewModel.hasTrend {
                monthlyDistanceCard
                drivingTimeCard
                cumulativeDistanceCard
                efficiencyCard
            }
        }
    }

    private var header: some View {
        HStack {
            Text("🚗 주행")
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

    private var monthlyDistanceCard: some View {
        ChartCard(title: "월별 주행거리 · 주행횟수",
                  callout: selected.map {
                      "\(VehicleFormat.distance($0.distanceKm)) · \(DriveFormat.count($0.driveCount))"
                  }) {
            MonthlyBarLineChart(bars: viewModel.distancePoints,
                                line: viewModel.driveCountPoints,
                                selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                                onSelect: { selectedID = $0 })
        }
    }

    private var drivingTimeCard: some View {
        ChartCard(title: "월별 주행 시간",
                  callout: selected.map { ChargeFormat.duration($0.drivingMin) }) {
            MonthlyBarChart(points: viewModel.drivingMinPoints,
                            selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                            onSelect: { selectedID = $0 })
        }
    }

    private var cumulativeDistanceCard: some View {
        let points = viewModel.cumulativeDistancePoints
        // **강조와 콜아웃이 같은 달을 가리키게 한다.** 기본값은 「마지막으로 기록이 있는 달」이라
        // 아무것도 고르지 않은 상태에서 지금까지 총 주행거리가 그대로 보이고,
        // 탭하면 그 달까지의 누적으로 바뀐다.
        let anchorID = selectedID ?? points.last(where: { $0.value != nil })?.id
        let shown = points.first { $0.id == anchorID }
        return ChartCard(title: "누적 주행거리",
                          callout: shown.map { VehicleFormat.distance($0.value) }) {
            MonthlyLineChart(points: points,
                             selectedID: anchorID,
                             onSelect: { selectedID = $0 })
        }
    }

    private var efficiencyCard: some View {
        ChartCard(title: "효율 추세",
                  callout: selected.map { VehicleFormat.efficiency($0.efficiency) }) {
            MonthlyLineChart(points: viewModel.efficiencyPoints,
                             selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                             onSelect: { selectedID = $0 })
        }
    }
}
