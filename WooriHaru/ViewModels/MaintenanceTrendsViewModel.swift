import SwiftUI

/// 통계 탭 — 차트 다섯 장이 한 응답(`/maintenance/trends`) 위에 올라간다.
///
/// **13개월을 받는다.** 전년 동월이 범위에 들어오게 하려는 것이다 — 난방비처럼 계절을
/// 타는 항목은 전월이 아니라 전년 동월과 견줘야 뜻이 있다.
@MainActor
@Observable
final class MaintenanceTrendsViewModel {
    private static let monthWindow = 13

    private let service: any MaintenanceServing

    /// **늘 `yearMonth` 오름차순이다** — 받자마자 한 번만 정렬한다. 차트 다섯 장이 전부
    /// 시간축이라 순서가 뒤집히면 전부 거짓말이 된다.
    private(set) var months: [MaintenanceTrendMonth] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    /// **차트마다 선택이 따로다.** 한 곳에 두면 #1에서 8월을 고른 순간 #5의 콜아웃까지
    /// 바뀌어, 관계없는 두 차트가 이어져 있다고 잘못 읽힌다.
    var selectedMonthID: String?
    var selectedRankID: String?
    var selectedDeltaID: String?
    var selectedUsageID: String?
    var selectedItemID: String?

    var usageKind: MaintenanceTrendMath.UsageKind = .electricity
    /// nil이면 항목 목록의 첫째를 쓴다 — 화면이 열리자마자 빈 차트를 보이지 않으려는 것이다.
    var selectedItemName: String?

    init(service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
    }

    /// **이미 받아 뒀으면 아무것도 하지 않는다** — 탭을 오갈 때마다 13개월을 다시 받지 않는다.
    func load() async {
        guard !hasLoaded else { return }
        await fetch()
    }

    /// 저장·수정·삭제 뒤. 낡은 값을 버리고 다시 받는다.
    func reload() async {
        await fetch()
    }

    private func fetch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            months = MaintenanceTrendMath.sorted(
                try await service.fetchTrends(months: Self.monthWindow)
            )
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            // 실패는 `hasLoaded`를 세우지 않는다 — 다시 열면 재시도해야 한다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
    }

    // MARK: - 파생

    var latestMonthLabel: String {
        months.last.map { MaintenanceFormat.monthTitle($0.yearMonth) } ?? "—"
    }

    /// #1 월별 부과액 추이.
    var chargedPoints: [ChartPoint] { MaintenanceTrendMath.chargedPoints(months) }

    /// #2 최근 달 항목 구성 — 금액 큰 순.
    var latestItemRows: [RankBarList.Row] {
        guard let latest = months.last else { return [] }
        let total = latest.items.reduce(Decimal(0)) { $0 + $1.amount }
        return latest.items
            .sorted { $0.amount > $1.amount }
            .map { item in
                let share = total > 0 ? item.amount / total : 0
                return RankBarList.Row(
                    id: item.name,
                    label: item.name,
                    value: item.amount,
                    primary: MaintenanceFormat.won(item.amount),
                    // 비율은 부호 없이 적는다 — 구성비지 증감이 아니다.
                    secondary: MaintenanceFormat.percent(share).replacingOccurrences(of: "+", with: ""),
                    note: nil
                )
            }
    }

    /// #3 전년 동월 대비 항목별 증감. **전년 동월이 범위에 없으면 nil이다.**
    var yearOverYearRows: [DivergingRankList.Row]? {
        MaintenanceTrendMath.yearOverYearDeltas(months).map { deltas in
            deltas.map { delta in
                DivergingRankList.Row(
                    id: delta.name,
                    label: delta.name,
                    value: delta.delta,
                    detail: MaintenanceFormat.signedWon(delta.delta)
                )
            }
        }
    }

    /// #4 사용량 추이.
    var usagePoints: [ChartPoint] {
        MaintenanceTrendMath.usagePoints(months, kind: usageKind)
    }

    /// #5 항목 하나의 월별 추이.
    var itemNames: [String] { MaintenanceTrendMath.itemNames(months) }

    var effectiveItemName: String? {
        selectedItemName ?? itemNames.first
    }

    var itemPoints: [ChartPoint] {
        guard let name = effectiveItemName else { return [] }
        return MaintenanceTrendMath.itemPoints(months, name: name)
    }

    // MARK: - 콜아웃

    /// 고른 점의 값을 한 줄로.
    ///
    /// **고른 것이 없으면 「값이 있는 마지막 점」이다.** 그냥 `points.last`를 쓰면 계절
    /// 토글에서 걸린다 — 여름에 「난방」을 고르면 마지막 달(예: 8월)의 `value`가 `nil`이라,
    /// 차트는 겨울 막대로 가득한데 콜아웃만 「8월 기록 없음」을 말하는 모순이 생긴다.
    /// 차량 통계 탭(`StatsDriveSection.anchorID`)이 같은 규칙을 쓴다.
    ///
    /// **`point.label`이 아니라 `point.id`로 달을 적는다.** `label`은 `MonthLabel.axis`가
    /// 만든 x축 표기(`"8"`)라 13개월 창의 양 끝(2025-08과 2026-08)이 똑같이 「8」로
    /// 보인다 — 13개월 창을 고른 이유가 정확히 전년 동월 비교인데, 그 비교의 두 달이
    /// 콜아웃에서 구분되지 않으면 창을 고른 의미가 없다. `point.id`는 이미 `yearMonth`
    /// 전체(`"2026-08"`)라 `MaintenanceFormat.monthTitle`이 연도까지 적는다.
    func callout(for points: [ChartPoint], selectedID: String?, suffix: String) -> String? {
        let point = points.first { $0.id == selectedID }
            ?? points.last(where: { $0.value != nil })
        guard let point else { return nil }
        let month = MaintenanceFormat.monthTitle(point.id)
        guard let value = point.value else { return "\(month) 기록 없음" }
        let text = suffix.isEmpty
            ? MaintenanceFormat.won(value)
            : "\(NSDecimalNumber(decimal: value).stringValue) \(suffix)"
        return "\(month) \(text)"
    }
}
