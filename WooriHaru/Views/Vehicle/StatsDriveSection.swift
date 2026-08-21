import SwiftUI

/// 통계 탭 「주행」 섹션 — 월별 차트 넷(#1·#2·#3·#10)과 분포 셋(#4·#7·#8)이 한 카드
/// 무더기를 이룬다. #5·#6·#9(거리 분포·시간대 히트맵·온도별 전비)는 이 섹션 밖,
/// `VehicleStatsTab`의 다른 자리에 그대로 산다.
///
/// 월별 넷은 `/tesla/insights`의 `monthly`를 봐서 기간 칩을 따른다.
/// 분포 셋은 기간 창을 보되 시간축이 없다 — 달력이 아니라 요일·속도로 칸을 나눈다.
struct StatsDriveSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    @State private var selectedID: String?

    /// 분포 세 장은 월별 `selectedID`와 상태를 나눈다. 한 상태를 같이 쓰면 분포 칸을
    /// 탭했을 때 그 id(`"wd2"` 등)가 월별 카드의 `anchorID`에도 넘어가 버려
    /// (`"2026-08"` 대신 `"wd2"`를 찾다가 실패) 월별 카드 넷이 한꺼번에 콜아웃을 잃는다.
    @State private var weekdaySelectedID: String?
    @State private var speedSelectedID: String?
    @State private var speedEfficiencySelectedID: String?

    /// 헤더(「🚗 주행」)는 이 파일 밖 `VehicleStatsTab`에 산다 — `hasDriveMonths`와
    /// `hasDrives`를 함께 봐야 하는 판단이라 이 뷰 하나로는 못 낸다. 이 뷰는 월별
    /// 카드 묶음의 게이트(`hasDriveMonths`)만 쥐고 `content`의 게이트(`hasDrives`)와
    /// 합치지 않는다.
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasDriveMonths {
                monthlyDistanceCard
                drivingTimeCard
                cumulativeDistanceCard
                weekdayDistanceCard
                efficiencyCard
                speedCard
                // #9 온도별 전비와 같은 재료 결측(cars.efficiency 없음)에 같은 방식으로
                // 반응하게 게이트를 건다 — `showsSpeedEfficiency` 문서 참고.
                if viewModel.showsSpeedEfficiency {
                    speedEfficiencyCard
                }
            }
        }
    }

    // MARK: - 카드

    /// 강조와 콜아웃이 같은 달을 가리키게 한다. 기본값은 「마지막으로 기록이 있는」
    /// 달이다 — 그냥 `last`를 쓰면 달 초처럼 이번 달 기록이 아직 없을 때 카드가 「—」를
    /// 띄운다. 카드마다 자기 계열로 기준을 잡는다 — 계열마다 마지막 기록이 다르다.
    ///
    /// 선택된 id가 지금 배열에 있을 때만 쓴다(`ChartAnchor.resolve`) — 기간 칩을
    /// 바꾸면 `selectedID`는 옛 기간의 달을 그대로 든 채 남기 때문이다.
    private func anchorID(_ points: [ChartPoint]) -> String? {
        ChartAnchor.resolve(selected: selectedID, in: points.map(\.id)) {
            points.last(where: { $0.value != nil })?.id
        }
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

    /// 콜아웃은 점 값을 그대로 읽는다 — 전비는 뷰모델이 이미 나눠서 낸 값이라
    /// 여기서 다시 나누면 차트와 콜아웃이 다른 코드로 같은 값을 말하게 된다.
    ///
    /// 종합 효율 줄은 차트 위, `ChartCard.callout`과 별도로 둔다 — 하나는 「고른 달」,
    /// 하나는 「기간 전체」라 같은 줄에 두면 헷갈린다. 값이 없으면 줄째 감춘다.
    private var efficiencyCard: some View {
        let points = viewModel.efficiencyPoints
        let anchor = anchorID(points)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "효율 추세",
                         callout: shown.map { VehicleFormat.efficiency($0.value) }) {
            VStack(alignment: .leading, spacing: 6) {
                if let ratio = viewModel.overallEfficiencyRatio {
                    // 「전 기간」이라 쓰지 않는다 — 이 값은 기간 칩을 따르므로
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

    // MARK: - 카드(분포)

    /// 분포 세 장의 기본 선택 — 월별 `anchorID`의 「마지막 값 있는 점」 규칙이 안
    /// 맞는다(분포엔 시간 순서가 없다). 대신 가장 큰 칸을 기본으로 보여 준다.
    /// 존재 검사는 `anchorID`와 같은 규칙(`ChartAnchor.resolve`)을 쓴다.
    private func distributionAnchor(_ points: [ChartPoint], selected: String?) -> String? {
        ChartAnchor.resolve(selected: selected, in: points.map(\.id)) {
            points.max { ($0.value ?? -1) < ($1.value ?? -1) }?.id
        }
    }

    /// `ChartPoint.value`가 `Decimal?`로 고정된 원형이라, 건수를 실어 온 점을 도로
    /// `Int?`로 되돌린다.
    private func intCount(_ value: Decimal?) -> Int? {
        value.map { NSDecimalNumber(decimal: $0).intValue }
    }

    /// #4 요일별 평균 주행거리. 라벨은 `viewModel.weekdayDistancePoints`가 이미
    /// `isoWeekdayLabel`로 낸다 — 여기서 요일 규약을 다시 고르지 않는다.
    private var weekdayDistanceCard: some View {
        let points = viewModel.weekdayDistancePoints
        let anchor = distributionAnchor(points, selected: weekdaySelectedID)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "요일별 평균 주행거리",
                         callout: shown.map { "\($0.label) \(VehicleFormat.distance($0.value))" }) {
            DistributionBarChart(points: points,
                                 selectedID: anchor,
                                 onSelect: { weekdaySelectedID = $0 })
        }
    }

    /// #7 최고속도 분포. 주행 한 건의 최고 속도라 #8과 모집단이 다르다.
    private var speedCard: some View {
        let points = viewModel.speedPoints
        let anchor = distributionAnchor(points, selected: speedSelectedID)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "최고속도 분포",
                         callout: shown.map { "\($0.label)km/h \(DriveFormat.count(intCount($0.value)))" }) {
            DistributionBarChart(points: points,
                                 selectedID: anchor,
                                 onSelect: { speedSelectedID = $0 })
        }
    }

    /// #8 속도별 전비. `driveCount`가 없는 배열이다 — #7과 모집단이 달라
    /// 콜아웃에 「N회 기준」을 적지 않는다.
    private var speedEfficiencyCard: some View {
        let points = viewModel.speedEfficiencyPoints
        let anchor = distributionAnchor(points, selected: speedEfficiencySelectedID)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "속도별 전비",
                         callout: shown.map { "\($0.label)km/h \(VehicleFormat.efficiency($0.value))" }) {
            DistributionBarChart(points: points,
                                 selectedID: anchor,
                                 onSelect: { speedEfficiencySelectedID = $0 })
        }
    }
}
