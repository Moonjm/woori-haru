import SwiftUI

/// 통계 탭 「주행」 섹션 — 새 차트 넷과 기존 카드 넷.
///
/// **새 차트 넷은 기간 칩을 따르지 않는다.** 12개월 추이(`trend`)에서 나오는 값이라
/// 늘 최근 12개월이고, 기존 카드 넷만 칩을 따른다. 2단계에서 서버가 `months`를 받는
/// `/tesla/insights`를 내면 둘이 같은 창을 보게 된다.
struct StatsDriveSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    @State private var selectedID: String?

    /// **헤더는 내용과 함께만 선다.** 추이를 못 받으면 「섹션이 조용히 빠질 뿐이다」라는
    /// `VehicleStatsViewModel.load` 주석의 약속을 뷰가 지켜야 한다 — 헤더만 남으면
    /// 첫 로딩 중에 빈 제목 둘이 나란히 서고, 실패는 「제목만 있고 아무것도 없다」로 보인다.
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasTrend {
                header
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

    /// **강조와 콜아웃이 같은 달을 가리키게 한다.** 아무것도 고르지 않았으면
    /// 「마지막으로 **기록이 있는** 달」이다 — 그냥 `last`를 쓰면 달 초처럼 이번 달
    /// 기록이 아직 없을 때 카드가 「—」를 띄운다. 카드마다 **자기 계열**로 기준을 잡는다:
    /// 거리는 있는데 비용은 없는 달이 있어 계열마다 마지막 기록이 다르다.
    private func anchorID(_ points: [ChartPoint]) -> String? {
        selectedID ?? points.last(where: { $0.value != nil })?.id
    }

    private var monthlyDistanceCard: some View {
        // 슬롯을 정하는 것은 막대(거리)라 기준도 거리에서 잡는다.
        let points = viewModel.distancePoints
        let anchor = anchorID(points)
        let shown = viewModel.trend.first { $0.yearMonth == anchor }
        return ChartCard(title: "월별 주행거리 · 주행횟수",
                         callout: shown.map {
                             "\(VehicleFormat.distance($0.distanceKm)) · \(DriveFormat.count($0.driveCount))"
                         }) {
            MonthlyBarLineChart(bars: points,
                                line: viewModel.driveCountPoints,
                                selectedID: anchor,
                                onSelect: { selectedID = $0 })
        }
    }

    private var drivingTimeCard: some View {
        let points = viewModel.drivingMinPoints
        let anchor = anchorID(points)
        let shown = viewModel.trend.first { $0.yearMonth == anchor }
        return ChartCard(title: "월별 주행 시간",
                         callout: shown.map { ChargeFormat.duration($0.drivingMin) }) {
            MonthlyBarChart(points: points,
                            selectedID: anchor,
                            onSelect: { selectedID = $0 })
        }
    }

    private var cumulativeDistanceCard: some View {
        let points = viewModel.cumulativeDistancePoints
        let anchor = anchorID(points)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "누적 주행거리",
                          callout: shown.map { VehicleFormat.distance($0.value) }) {
            MonthlyLineChart(points: points,
                             selectedID: anchor,
                             onSelect: { selectedID = $0 })
        }
    }

    private var efficiencyCard: some View {
        let points = viewModel.efficiencyPoints
        let anchor = anchorID(points)
        let shown = viewModel.trend.first { $0.yearMonth == anchor }
        return ChartCard(title: "효율 추세",
                         callout: shown.map { VehicleFormat.efficiency($0.efficiency) }) {
            MonthlyLineChart(points: points,
                             selectedID: anchor,
                             onSelect: { selectedID = $0 })
        }
    }
}
