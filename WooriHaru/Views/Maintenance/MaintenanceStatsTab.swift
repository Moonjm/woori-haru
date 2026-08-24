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

    /// #2·#3 순위 리스트의 기본 선택. 서버가 이미 순위(#2는 금액, #3은 증감 절댓값)
    /// 내림차순으로 주므로 목록의 첫 행이 곧 1등이다 — `StatsPlaceSection.rankAnchor`와 같다.
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

    // MARK: - #2 최근 달 항목 구성

    /// **탭은 콜아웃만 바꾼다** — `RankBarList`가 지키는 규칙이고, 이 카드가 그 원형을
    /// 쓰는 유일한 자리라 콜아웃이 없으면 그 규칙을 지킬 자리 자체가 없었다.
    private var latestItemsCard: some View {
        let rows = vm.latestItemRows
        let selected = rankAnchor(rows.map(\.id), selected: vm.selectedRankID)
        let shown = rows.first { $0.id == selected }
        return ChartCard(title: "\(vm.latestMonthLabel) 항목 구성",
                  callout: shown.map { "\($0.label) \($0.primary)" }) {
            if rows.isEmpty {
                emptyLine("등록된 항목이 없습니다")
            } else {
                RankBarList(rows: rows, selectedID: selected) { vm.selectedRankID = $0 }
            }
        }
    }

    // MARK: - #3 전년 동월 대비

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

    // MARK: - #4 사용량 추이

    private var usageCard: some View {
        let points = vm.usagePoints
        let selected = anchor(points, selected: vm.selectedUsageID)
        return ChartCard(title: "사용량 추이",
                  callout: vm.callout(for: points, selectedID: selected,
                                      suffix: vm.usageKind.unit)) {
            VStack(spacing: 10) {
                // 단위가 달라(kWh·m³·Gcal·kg) 한 차트에 겹쳐 그리지 않고 하나씩 본다.
                Picker("사용량", selection: $vm.usageKind) {
                    ForEach(MaintenanceTrendMath.UsageKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                MonthlyLineChart(points: points,
                                 selectedID: selected) { vm.selectedUsageID = $0 }
            }
        }
    }

    // MARK: - #5 항목 하나의 월별 추이

    private var itemTrendCard: some View {
        let points = vm.itemPoints
        let selected = anchor(points, selected: vm.selectedItemID)
        return ChartCard(title: "항목별 추이",
                  callout: vm.callout(for: points, selectedID: selected, suffix: "")) {
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

                    // **차감 항목은 음수라 원형을 갈아 끼운다.** `MonthlyBarChart`는
                    // `ChartScale.ratio`로 0 이하를 전부 0으로 잘라(스물여섯 장이 그 가드에
                    // 기댄다) 「-13,790」과 「0」이 같은 막대가 된다. 부호가 뜻을 갖는
                    // 자리를 위해 만들어 둔 `DivergingMonthlyBarChart`가 그 값을 살린다.
                    //
                    // 한 항목의 부호는 달마다 바뀌지 않는다(차감은 늘 차감이다). 그래서
                    // 고른 항목에 따라 원형이 갈릴 뿐, 한 화면 안에서 섞이지 않는다 —
                    // 양수 항목까지 발산형으로 그리면 기준선이 가운데 놓여 높이를 절반만 쓴다.
                    if points.contains(where: { ($0.value ?? 0) < 0 }) {
                        DivergingMonthlyBarChart(points: points,
                                                 selectedID: selected) { vm.selectedItemID = $0 }
                    } else {
                        MonthlyBarChart(points: points,
                                        selectedID: selected) { vm.selectedItemID = $0 }
                    }
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
