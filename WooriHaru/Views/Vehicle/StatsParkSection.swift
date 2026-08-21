import SwiftUI

/// 통계 탭 「주차」 섹션 — 월별 정지 시간, 요일별 정지 시간, 월별 대기 중 소모(팬텀 드레인).
///
/// **재료 셋 다 `/tesla/insights`의 같은 응답에서 온다**(`monthly`·`weekday`)라
/// 기간 칩을 따른다. `StatsDriveSection`·`StatsChargeSection`과 같은 구조다.
struct StatsParkSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    /// 월별 카드 둘(#19·#21)이 공유한다 — `StatsDriveSection`·`StatsChargeSection`의
    /// 월별 카드들과 같은 규칙이다.
    @State private var selectedID: String?

    /// 분포 카드(#20)는 **월별 `selectedID`와 상태를 나눈다.** id 네임스페이스가
    /// 달라(`"wi1"` 대 `"2026-08"`) 한 상태를 같이 쓰면 요일 칸을 탭했을 때 월별
    /// 카드 둘이 한꺼번에 콜아웃을 잃는다.
    @State private var weekdaySelectedID: String?

    /// **헤더는 내용과 함께만 선다**(다른 두 섹션과 같은 규칙). `hasParkMonths`는
    /// `monthly` 행의 존재를 그대로 본다 — 이 섹션의 재료(`idleMin`)는 non-null이라
    /// 행이 있으면 값도 있으므로, 다른 두 섹션처럼 필드마다 nil을 따로 검사할 이유가 없다.
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasParkMonths {
                header
                idleMinCard
                weekdayIdleCard
                parkDrainCard
            }
        }
    }

    private var header: some View {
        HStack {
            Text("🅿️ 주차")
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(VehicleTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: - 카드

    /// **강조와 콜아웃이 같은 달을 가리키게 한다.** 규칙은 다른 두 섹션과 같다 —
    /// 「마지막으로 **기록이 있는** 달」이고, 카드마다 **자기 계열**로 잡는다.
    /// 존재 검사도 `StatsDriveSection.anchorID`와 같다(`ChartAnchor.resolve`).
    private func anchorID(_ points: [ChartPoint]) -> String? {
        ChartAnchor.resolve(selected: selectedID, in: points.map(\.id)) {
            points.last(where: { $0.value != nil })?.id
        }
    }

    /// 분포 카드의 기본 선택. 시간 순서가 없어 「마지막」이 아무 뜻도 없다 —
    /// 아무것도 안 골랐으면 **가장 큰 칸**을 기본으로 보여 준다.
    private func distributionAnchor(_ points: [ChartPoint], selected: String?) -> String? {
        ChartAnchor.resolve(selected: selected, in: points.map(\.id)) {
            points.max { ($0.value ?? -1) < ($1.value ?? -1) }?.id
        }
    }

    /// `ChartPoint.value`가 `Decimal?`로 고정된 원형이라, 분 단위 정수를 도로 `Int?`로
    /// 되돌린다. `StatsDriveSection.intCount`와 같은 이유다.
    private func intMinutes(_ value: Decimal?) -> Int? {
        value.map { NSDecimalNumber(decimal: $0).intValue }
    }

    /// #19 월별 정지 시간. **`idleMin`은 non-null이다** — 기록이 없는 달은 「내내
    /// 서 있었다」라서 값이 있는 것이 맞고, 오히려 안 탄 달일수록 크다(빈 달 44640분).
    private var idleMinCard: some View {
        let points = viewModel.idleMinPoints
        let anchor = anchorID(points)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "월별 정지 시간",
                         callout: shown.map { ChargeFormat.duration(intMinutes($0.value)) }) {
            MonthlyBarChart(points: points,
                            selectedID: anchor,
                            onSelect: { selectedID = $0 })
        }
    }

    /// #20 요일별 정지 시간. 라벨은 `viewModel.weekdayIdlePoints`가 이미
    /// `isoWeekdayLabel`(1=월요일)로 낸다 — 여기서 요일 규약을 다시 고르지 않는다.
    private var weekdayIdleCard: some View {
        let points = viewModel.weekdayIdlePoints
        let anchor = distributionAnchor(points, selected: weekdaySelectedID)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "요일별 정지 시간",
                         callout: shown.map { "\($0.label) \(ChargeFormat.duration(intMinutes($0.value)))" }) {
            DistributionBarChart(points: points,
                                 selectedID: anchor,
                                 onSelect: { weekdaySelectedID = $0 })
        }
    }

    /// #21 월별 대기 중 소모(팬텀 드레인). **표본이 0인 달은 점이 nil이라 막대가
    /// 안 선다** — `viewModel.parkDrainPoints`가 그 갈림을 낸다. 음수도 부호 그대로
    /// 나온다(자세한 이유는 그 접근자의 주석).
    private var parkDrainCard: some View {
        let points = viewModel.parkDrainPoints
        let anchor = anchorID(points)
        let shown = points.first { $0.id == anchor }
        return ChartCard(title: "월별 대기 중 소모",
                         callout: shown.map { VehicleFormat.distance($0.value) }) {
            MonthlyBarChart(points: points,
                            selectedID: anchor,
                            onSelect: { selectedID = $0 })
        }
    }
}
