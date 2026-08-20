import SwiftUI

/// 통계 탭 「주행」 섹션 — 새 차트 넷과 기존 카드 넷.
///
/// **여덟 장이 같은 창을 본다.** 재료가 `/tesla/insights` 한 응답의 `monthly`로 옮겨져
/// 월별 차트도 기간 칩을 따른다 — 1단계에서 이 넷만 12개월로 고정이던 것이 풀렸다.
struct StatsDriveSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    @State private var selectedID: String?

    /// **헤더는 내용과 함께만 선다.** 주행 값이 있는 달이 하나도 없으면(아직 못 받았거나,
    /// 그 기간에 안 탔거나) 섹션째 빠진다 — 헤더만 남으면 첫 로딩 중에 빈 제목 둘이
    /// 나란히 서고, 실패는 「제목만 있고 아무것도 없다」로 보인다.
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasDriveMonths {
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
        let shown = viewModel.monthly.first { $0.yearMonth == anchor }
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
        let shown = viewModel.monthly.first { $0.yearMonth == anchor }
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

    /// **콜아웃을 점에서 읽는다** — 전비는 응답에 없는 값이라 뷰모델이 나눠서 낸다.
    /// 여기서 다시 나누면 차트와 콜아웃이 서로 다른 코드로 같은 값을 말하게 된다.
    ///
    /// **종합 효율 줄을 차트 위에 둔다.** `ChartCard.callout`(오른쪽 위)은 이미 선택한
    /// 달의 전비를 말하고, 종합 효율은 기간 전체 한 값이라 서로 다른 질문에 답한다 —
    /// 같은 줄에 나란히 두면 어느 쪽이 「지금 고른 달」이고 어느 쪽이 「기간 전체」인지
    /// 헷갈린다. 차트보다 먼저 두면 「기간 전체 감」을 먼저 준 다음 달마다 추이를 읽게
    /// 되어 순서가 자연스럽다. 값이 없으면 줄째 감춘다.
    private var efficiencyCard: some View {
        let points = viewModel.efficiencyPoints
        let anchor = anchorID(points)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "효율 추세",
                         callout: shown.map { VehicleFormat.efficiency($0.value) }) {
            VStack(alignment: .leading, spacing: 6) {
                if let ratio = viewModel.overallEfficiencyRatio {
                    // **「전 기간」이라 쓰지 않는다** — 이 값은 기간 칩을 따르므로
                    // 범위를 주장하지 않는 말을 쓴다.
                    Text("정격 대비 \(ChargeFormat.percent(ratio))")
                        .font(.caption2)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
                MonthlyLineChart(points: points,
                                 selectedID: anchor,
                                 onSelect: { selectedID = $0 })
            }
        }
    }
}
