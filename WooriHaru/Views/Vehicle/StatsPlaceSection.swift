import SwiftUI

/// 통계 탭 「위치」 섹션 — 다녀온 지역 수(#23), 자주 가는 곳(#24), 충전소별 비용 TOP(#25).
///
/// `RankBarList`를 쓴다 — 막대 길이(`Row.value`)는 서버 정렬 기준과 같은 건수로 맞춘다.
struct StatsPlaceSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    /// #24·#25는 id 네임스페이스가 겹치지 않아도, 한 상태를 같이 쓰면 한쪽을
    /// 탭했을 때 다른 쪽 강조가 조용히 사라진다 — 그래서 나눈다.
    @State private var placeSelectedID: String?
    @State private var chargerSelectedID: String?

    /// 헤더는 내용과 함께만 선다. `showsPlaceSection`은 `places`·`chargers`·`regions`
    /// 셋이 다 빈 경우만 거짓이다.
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.showsPlaceSection {
                header
                regionTiles
                placeCard
                chargerCard
            }
        }
    }

    private var header: some View {
        HStack {
            Text("📍 위치")
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(VehicleTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: - #23 지역 수

    /// 나라가 1이면 그 타일을 감춘다 — 국내에서만 탄 차량의 기본 상태라 「나라 1」은
    /// 아무것도 말하지 않는다.
    ///
    /// 행 전체는 셋(`cities`·`states`·`countries`) 중 하나라도 0보다 클 때 선다.
    /// `cities` 하나만 보지 않는다 — 역지오코딩이 시골길·경계 지역에서 `city`만 NULL이고
    /// `state`·`country`는 채우는 행이 실제로 나온다.
    @ViewBuilder private var regionTiles: some View {
        if let regions = viewModel.insights?.regions,
           regions.cities > 0 || regions.states > 0 || regions.countries > 0 {
            GlassCard {
                HStack(spacing: 10) {
                    tile("\(regions.cities)", "도시")
                    tile("\(regions.states)", "시도")
                    if regions.countries != 1 {
                        tile("\(regions.countries)", "나라")
                    }
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - #24·#25 순위 막대

    /// 아무것도 안 골랐으면 1등을 기본으로 보여 준다 — 서버가 이미 건수 내림차순으로
    /// 주므로 목록의 첫 행이 곧 1등이다.
    ///
    /// id가 실재하는지 검사한다(`ChartAnchor.resolve`). 여기 id는 장소·충전소 이름이라
    /// 다른 섹션의 달·분포 칸과 달리 상위 N 목록 자체가 기간에 따라 바뀐다 — 기간을
    /// 바꿔 옛 1등이 목록에서 빠질 수 있어서다.
    private func rankAnchor(_ rows: [RankBarList.Row], selected: String?) -> String? {
        ChartAnchor.resolve(selected: selected, in: rows.map(\.id)) {
            rows.first?.id
        }
    }

    /// #24 자주 가는 곳. 행이 비면 카드째 감춘다 — `showsPlaceSection`이 참이어도
    /// `chargers`·`regions`만으로 참일 수 있어, 이 카드 혼자는 빈 채로 설 수 있다.
    @ViewBuilder private var placeCard: some View {
        let rows = viewModel.placeRows
        if !rows.isEmpty {
            let anchor = rankAnchor(rows, selected: placeSelectedID)
            let shown = rows.first { $0.id == anchor }
            ChartCard(title: "자주 가는 곳",
                     callout: shown.map { "\($0.label) \($0.primary)" }) {
                RankBarList(rows: rows, selectedID: anchor,
                           onSelect: { placeSelectedID = $0 })
            }
        }
    }

    /// #25 충전소별 비용 TOP. 막대 길이는 비용이 아니라 충전 횟수다 — 제목에 끌려
    /// `cost`를 넣으면 금액 미입력이 섞인 충전소가 실제보다 짧게 나와 순위와 어긋난다.
    /// 금액은 `primary`에 문자열로만 싣고, 미입력 건수는 `note`로 드러낸다.
    @ViewBuilder private var chargerCard: some View {
        let rows = viewModel.chargerRows
        if !rows.isEmpty {
            let anchor = rankAnchor(rows, selected: chargerSelectedID)
            let shown = rows.first { $0.id == anchor }
            ChartCard(title: "충전소별 비용",
                     callout: shown.map { "\($0.label) \($0.primary)" }) {
                RankBarList(rows: rows, selectedID: anchor,
                           onSelect: { chargerSelectedID = $0 })
            }
        }
    }
}
