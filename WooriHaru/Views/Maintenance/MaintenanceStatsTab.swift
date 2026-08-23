import SwiftUI

/// 통계 탭 — 차트 다섯 장이 한 응답 위에 올라간다.
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
                latestItemsCard
                yearOverYearCard
                usageCard
                itemTrendCard
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

    // MARK: - #1 월별 부과액 추이

    private var chargedCard: some View {
        ChartCard(title: "월별 관리비",
                  callout: vm.callout(for: vm.chargedPoints,
                                      selectedID: vm.selectedMonthID, suffix: "")) {
            MonthlyBarChart(points: vm.chargedPoints,
                            selectedID: vm.selectedMonthID) { vm.selectedMonthID = $0 }
        }
    }

    // MARK: - #2 최근 달 항목 구성

    private var latestItemsCard: some View {
        ChartCard(title: "\(vm.latestMonthLabel) 항목 구성", callout: nil) {
            if vm.latestItemRows.isEmpty {
                emptyLine("등록된 항목이 없습니다")
            } else {
                RankBarList(rows: vm.latestItemRows,
                            selectedID: vm.selectedRankID) { vm.selectedRankID = $0 }
            }
        }
    }

    // MARK: - #3 전년 동월 대비

    private var yearOverYearCard: some View {
        ChartCard(title: "전년 동월 대비", callout: nil) {
            if let rows = vm.yearOverYearRows, !rows.isEmpty {
                DivergingRankList(rows: rows,
                                  selectedID: vm.selectedDeltaID) { vm.selectedDeltaID = $0 }
            } else if vm.yearOverYearRows != nil {
                emptyLine("작년 이맘때와 달라진 항목이 없습니다")
            } else {
                // **카드를 지우지 않는다** — 통째로 사라지면 「왜 없지」가 남는다.
                emptyLine("전년 동월 자료가 쌓이면 보여드립니다")
            }
        }
    }

    // MARK: - #4 사용량 추이

    private var usageCard: some View {
        ChartCard(title: "사용량 추이",
                  callout: vm.callout(for: vm.usagePoints,
                                      selectedID: vm.selectedUsageID,
                                      suffix: vm.usageKind.unit)) {
            VStack(spacing: 10) {
                // 단위가 달라(kWh·m³·Gcal·kg) 한 차트에 겹쳐 그리지 않고 하나씩 본다.
                Picker("사용량", selection: $vm.usageKind) {
                    ForEach(MaintenanceTrendMath.UsageKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                MonthlyLineChart(points: vm.usagePoints,
                                 selectedID: vm.selectedUsageID) { vm.selectedUsageID = $0 }
            }
        }
    }

    // MARK: - #5 항목 하나의 월별 추이

    private var itemTrendCard: some View {
        ChartCard(title: "항목별 추이",
                  callout: vm.callout(for: vm.itemPoints,
                                      selectedID: vm.selectedItemID, suffix: "")) {
            VStack(alignment: .leading, spacing: 10) {
                if vm.itemNames.isEmpty {
                    emptyLine("등록된 항목이 없습니다")
                } else {
                    Menu {
                        // **13개월에 한 번이라도 나온 이름을 전부 올린다** — 최근 달에만 있는
                        // 이름으로 좁히면 표기가 바뀐 항목이 피커에서 사라진다.
                        ForEach(vm.itemNames, id: \.self) { name in
                            Button(name) {
                                vm.selectedItemName = name
                                vm.selectedItemID = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.effectiveItemName ?? "항목 고르기")
                                .font(.caption)
                                .fontWeight(.bold)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(VehicleTheme.accentBright)
                    }

                    MonthlyBarChart(points: vm.itemPoints,
                                    selectedID: vm.selectedItemID) { vm.selectedItemID = $0 }
                }
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
