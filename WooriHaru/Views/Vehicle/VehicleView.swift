import SwiftUI

/// 「차량」 미니앱 — 상태·주행·요약 세 탭. 가계부와 같은 하단 글래스 탭바 구조다.
/// **여는 순간 상태 화면이 먼저 뜬다** — 첫 화면이 답을 하나 해야 한다.
///
/// **첫 탭 이름이 「건강」에서 「상태」로 돌아왔다.** 1단계에서 상태 표를 배터리 건강 대시보드로
/// 갈아끼우며 「건강」이 됐는데, 4단계가 현재 상태를 열화 위로 올리고 5단계가 24시간 띠를
/// 더하면서 무게중심이 다시 옮겨갔다 — 이 탭이 그리는 아홉 중 「건강」인 것은 잔존율 카드와
/// 열화 추이 둘뿐이다. 탭 이름은 첫 화면이 답하는 질문을 따라간다.
/// **세 개가 상한이다** — 더 늘리려는 순간 화면을 합칠 자리를 먼저 찾는다.
struct VehicleView: View {
    private enum Tab { case status, drive, summary }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .status
    @State private var summaryViewModel = VehicleSummaryViewModel()
    @State private var statusViewModel = VehicleStatusViewModel()
    @State private var healthViewModel = VehicleHealthViewModel()
    @State private var totalsViewModel = ChargeTotalsViewModel()
    @State private var timelineViewModel = StateTimelineViewModel()
    @State private var driveViewModel = VehicleDriveViewModel()
    @State private var showingMonthPicker = false
    @State private var showingQueue = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            tabBar
        }
        .glassScreenBackground()
        // 좌우 스와이프 = 월 이동. 상태·주행 탭에는 월이 없으므로 마스크로 끈다
        // (`nil`을 넘길 수 없는 API라 including으로 제어한다).
        .simultaneousGesture(monthSwipeGesture, including: tab == .summary ? .all : .subviews)
        .navigationBarBackButtonHidden(true) // 월 이동 스와이프와 겹치는 엣지 뒤로가기 차단
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel("뒤로")
            }
            ToolbarItem(placement: .principal) { principalTitle }
        }
        .sensoryFeedback(.selection, trigger: summaryViewModel.month)
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(
                initialYear: summaryViewModel.month.year,
                initialMonth: summaryViewModel.month.month
            ) { year, month in
                Task { await summaryViewModel.selectMonth(year: year, month: month) }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        // 갱신은 화면이 닫힌 **뒤에** 여기서 한다 — 등록 화면이 요청 두 번을 기다리다
        // 멎어 보이지 않게 하려는 것이다.
        .fullScreenCover(isPresented: $showingQueue, onDismiss: {
            Task {
                await summaryViewModel.reload()
                await summaryViewModel.refreshMissingCount()
                await healthViewModel.refreshMissingCount()
                // 금액을 채우면 누적 충전비·단가·「N건 기준」이 다 움직인다 — 채워진 에너지가
                // 「금액 없음」 분모에서 빠져나오기 때문이다. 배지만 갱신하면 0건이 된 배지와
                // 낡은 누적 카드가 상태 탭 같은 화면에 나란히 남는다.
                await totalsViewModel.reload()
            }
        }) {
            ChargeCostQueueView()
        }
        .task { await summaryViewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .status:
            VehicleStatusTab(healthViewModel: healthViewModel,
                             statusViewModel: statusViewModel,
                             totalsViewModel: totalsViewModel,
                             timelineViewModel: timelineViewModel) { showingQueue = true }
                // 상태와 타임라인은 탭에 들어올 때마다 새로 받는다 — 「지금」과 「최근 7일」은
                // 둘 다 창이 움직인다. 배터리 건강·충전 누적은 전 기간 집계라 뷰모델이 한 번만
                // 받고, 배지 수만 매번 맞춘다.
                .task {
                    async let status: Void = statusViewModel.load()
                    async let health: Void = healthViewModel.load()
                    async let totals: Void = totalsViewModel.load()
                    async let timeline: Void = timelineViewModel.load()
                    _ = await (status, health, totals, timeline)
                }
        case .drive:
            VehicleDriveTab(viewModel: driveViewModel)
                .task { await driveViewModel.load() }
        case .summary:
            VehicleSummaryTab(viewModel: summaryViewModel,
                              onCostSaved: { await totalsViewModel.reload() }) { showingQueue = true }
        }
    }

    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .status: Text("차량 상태").font(.subheadline).fontWeight(.bold)
        case .drive: Text("주행").font(.subheadline).fontWeight(.bold)
        case .summary: monthSwitcher
        }
    }

    private var monthSwitcher: some View {
        HStack(spacing: 0) {
            Button { Task { await summaryViewModel.shiftMonth(-1) } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("이전 달")
            Button { showingMonthPicker = true } label: {
                Text(summaryViewModel.month.displayLong)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 4)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("연월 선택 열기")
            Button { Task { await summaryViewModel.shiftMonth(1) } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("다음 달")
            .disabled(summaryViewModel.isAtCurrentMonth)
            .opacity(summaryViewModel.isAtCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Color.slate700)
    }

    /// 수직 스크롤과 헷갈리지 않게 가로 성분이 확실할 때만 반응한다.
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.5 else { return }
                Task { await summaryViewModel.shiftMonth(dx > 0 ? -1 : 1) }
            }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.status, icon: "bolt.batteryblock.fill", label: "상태")
            tabButton(.drive, icon: "steeringwheel", label: "주행")
            tabButton(.summary, icon: "chart.bar.fill", label: "요약")
        }
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        // 버튼 사이 여백 탭이 아래 목록으로 새지 않게 바 전체를 히트 영역으로 만든다.
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {}
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func tabButton(_ target: Tab, icon: String, label: String) -> some View {
        let selected = tab == target
        return Button {
            withAnimation(.snappy(duration: 0.2)) { tab = target }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : Color.slate500)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: [Color.blue500, Color.blue700],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color.blue600.opacity(0.4), radius: 8, y: 3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
