import SwiftUI

/// 월별 발산형 막대 — 기준선(0)을 가운데 두고 **양수는 위로, 음수는 아래로** 뻗는다.
/// 색도 방향에 따라 갈린다: 양수(대기 중 소모, 정상)는 다른 월별 차트와 같은 accent 계열,
/// 음수(BMS 재보정으로 정격거리가 오히려 늘어난 달)는 `VehicleTheme.warning`이다 — 팔레트에
/// 없는 색을 새로 만들지 않는다.
///
/// **`MonthlyBarChart`를 고치는 대신 새 원형을 둔 이유.** 그 원형은 `ChartScale.ratio`로
/// 음수를 0으로 자르는데, 그 가드가 나머지 스물다섯 장의 계약이다(`ChartScale.ratio` 참고).
/// 부호가 실제로 뜻을 갖는 화면은 지금 #21 「월별 대기 중 소모」 하나뿐이라, 기존 원형에
/// 발산 모드를 심는 대신 자기 원형을 따로 둔다. 기하 계산
/// (`ChartScale.maxAbsValue`·`divergingRatio`·`divergingBarHeight`)은 순수 함수로 빼서
/// SwiftUI 렌더링 없이도 테스트가 방향·크기·스케일을 직접 못박을 수 있게 했다.
///
/// **카드가 아니라 막대만 그린다** — 제목·콜아웃·`GlassCard`는 부르는 쪽이 얹는다.
/// **탭은 콜아웃만 바꾼다**(`onSelect`) — 다른 월별 차트들과 같은 규칙이다.
struct DivergingMonthlyBarChart: View {
    let points: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    /// 기준선 위·아래 각 절반의 높이. 전체 그림 높이는 이 값의 두 배 + 라벨이다.
    var halfHeight: CGFloat = 36

    var body: some View {
        let maxAbs = ChartScale.maxAbsValue(points)
        HStack(alignment: .top, spacing: ChartScale.slotSpacing(count: points.count)) {
            // **id는 offset이 아니라 점의 정체성이다** — `MonthlyBarChart`와 같은 이유로,
            // 데이터가 바뀔 때 SwiftUI가 엉뚱한 슬롯을 재사용해 탭·값이 밀리지 않게 한다.
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                bar(point, index: index, maxAbs: maxAbs)
            }
        }
        .frame(height: halfHeight * 2 + 24)
    }

    private func bar(_ point: ChartPoint, index: Int, maxAbs: Decimal) -> some View {
        let isSelected = point.id == selectedID
        let isRecordless = point.value == nil
        let signedHeight = ChartScale.divergingBarHeight(point.value, maxAbs: maxAbs, halfHeight: halfHeight)

        return VStack(spacing: 0) {
            // 위쪽 절반 — 양수(대기 중 소모)가 기준선에서 위로 자란다. 기록이 없는 달은
            // `MonthlyBarChart`와 같은 규칙으로 트랙 색 자리표시자를 남긴다 — 자리는
            // 지키되 값 색으로 그리지 않는다.
            ZStack(alignment: .bottom) {
                if isRecordless {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(VehicleTheme.trackFill)
                        .frame(height: 3)
                } else if signedHeight > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                        .frame(height: signedHeight)
                }
            }
            .frame(height: halfHeight)

            // 기준선(0). 값의 부호와 무관하게 늘 그려 「여기가 0이다」를 눈으로 준다.
            Rectangle()
                .fill(VehicleTheme.trackFill)
                .frame(height: 1)

            // 아래쪽 절반 — 음수(오히려 늘었다)가 기준선에서 아래로 자란다.
            ZStack(alignment: .top) {
                if !isRecordless, signedHeight < 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? VehicleTheme.warning : VehicleTheme.warning.opacity(0.35))
                        .frame(height: -signedHeight)
                }
            }
            .frame(height: halfHeight)

            // **감추지 않고 빈 글자로 둔다.** 라벨 뷰 자체를 없애면 남은 라벨들이 `HStack`에서
            // 다시 채워져 자기 막대에서 옆으로 밀린다 — `MonthlyBarChart`와 같은 이유다.
            Text(MonthLabel.shows(index: index, count: points.count) ? point.label : "")
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(point.id) }
    }
}

#Preview("월별 발산형 막대 — 대기 중 소모") {
    let values: [Decimal?] = [nil, 82, 104, -36, 61, 0, 118, -12, 96, 73, -58, 89]
    let points = values.enumerated().map { index, value in
        ChartPoint(id: String(format: "2026-%02d", index + 1), label: "\(index + 1)", value: value)
    }
    return VStack(spacing: 12) {
        DivergingMonthlyBarChart(points: points, selectedID: "2026-04") { _ in }
        // 음수만 있는 기간에서도 스케일이 무너지지 않는지 본다.
        DivergingMonthlyBarChart(points: points.map { ChartPoint(id: $0.id, label: $0.label, value: $0.value.map { -abs($0) }) },
                                  selectedID: nil) { _ in }
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
