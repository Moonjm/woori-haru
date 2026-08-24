import SwiftUI

/// 통계 탭 — 차트 세 장이 한 응답 위에 올라간다.
///
/// 목록·상세와 같은 `chargedAmount`를 그리므로 기준을 따로 적지 않는다 — 서버가 청구액을
/// 지우면서 「이 숫자는 무엇인가」가 화면마다 갈릴 여지가 사라졌다.
struct MaintenanceStatsTab: View {
    @Bindable var vm: MaintenanceTrendsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                chargedCard
                yearOverYearCard
                usageCard
                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96)   // 하단 탭바가 마지막 카드를 가리지 않게
        }
        .task { await vm.load() }
    }

    private var header: some View {
        HStack {
            Text("최근 13개월")
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            Spacer()
            if vm.isLoading { ProgressView().controlSize(.small) }
        }
    }

    // MARK: - 강조·콜아웃 앵커

    /// 강조와 콜아웃이 같은 달을 가리키게 한다. 기본값은 **값이 있는 마지막 점**이다 —
    /// 그냥 `points.last`를 쓰면 계절 토글(예: 여름에 「난방」)에서 마지막 달이 `nil`인
    /// 채 걸려, 차트는 겨울 막대로 가득한데 콜아웃만 「기록 없음」을 말하는 모순이 생긴다.
    /// 차량 통계 탭 `StatsDriveSection.anchorID`와 같은 규칙(`ChartAnchor.resolve`)이다.
    private func anchor(_ points: [ChartPoint], selected: String?) -> String? {
        ChartAnchor.resolve(selected: selected, in: points.map(\.id)) {
            points.last(where: { $0.value != nil })?.id
        }
    }

    /// 순위 리스트(#2 전년 동월 대비)의 기본 선택. 증감 절댓값 내림차순으로 이미
    /// 정렬돼 오므로 목록의 첫 행이 곧 1등이다 — `StatsPlaceSection.rankAnchor`와 같다.
    private func rankAnchor(_ ids: [String], selected: String?) -> String? {
        ChartAnchor.resolve(selected: selected, in: ids) { ids.first }
    }

    // MARK: - #1 월별 부과액 추이

    private var chargedCard: some View {
        let points = vm.chargedPoints
        let selected = anchor(points, selected: vm.selectedMonthID)
        return ChartCard(title: "월별 관리비",
                  callout: vm.callout(for: points, selectedID: selected, suffix: "")) {
            MonthlyBarChart(points: points,
                            selectedID: selected) { vm.selectedMonthID = $0 }
        }
    }

    // MARK: - #2 전년 동월 대비 항목별 증감

    private var yearOverYearCard: some View {
        let rows = vm.yearOverYearRows
        let selected = rows.flatMap { rankAnchor($0.map(\.id), selected: vm.selectedDeltaID) }
        let shown = rows?.first { $0.id == selected }
        return ChartCard(title: "전년 동월 대비",
                  callout: shown.map { "\($0.label) \($0.detail)" }) {
            if let rows, !rows.isEmpty {
                DivergingRankList(rows: rows, selectedID: selected) { vm.selectedDeltaID = $0 }
            } else if rows != nil {
                emptyLine("작년 이맘때와 달라진 항목이 없습니다")
            } else {
                // **카드를 지우지 않는다** — 통째로 사라지면 「왜 없지」가 남는다.
                emptyLine("전년 동월 자료가 쌓이면 보여드립니다")
            }
        }
    }

    // MARK: - #3 사용량 · 금액 추이

    private var usageCard: some View {
        let points = vm.usagePoints
        let selected = anchor(points, selected: vm.selectedUsageID)
        return ChartCard(title: "사용량 · 금액 추이",
                  callout: vm.usageCallout(selectedID: selected)) {
            VStack(spacing: 10) {
                // 다섯 종은 단위가 달라(kWh·m³·Gcal·kg) 한 차트에 겹치지 않고 토글로 하나씩 본다.
                Picker("사용량", selection: $vm.usageKind) {
                    ForEach(MaintenanceTrendMath.UsageKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                // **막대는 사용량, 선은 금액이다.** 「많이 썼나」와 「많이 냈나」는 따로
                // 움직인다 — 단가가 오르면 덜 쓰고도 더 낸다. 겹쳐 그려야 그 어긋남이 보인다.
                // 두 계열의 눈금은 적지 않는다(원형의 규칙) — 정확한 값은 콜아웃이 말한다.
                MonthlyBarLineChart(bars: points,
                                    line: vm.usageAmountPoints,
                                    selectedID: selected) { vm.selectedUsageID = $0 }
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(VehicleTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}
