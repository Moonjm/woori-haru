import SwiftUI

/// 「차량」 미니앱 — 요약·상태 두 탭. 가계부와 같은 하단 글래스 탭바 구조다.
struct VehicleView: View {
    private enum Tab { case summary, status }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .summary
    @State private var summaryViewModel = VehicleSummaryViewModel()
    @State private var statusViewModel = VehicleStatusViewModel()
    @State private var showingMonthPicker = false
    @State private var showingQueue = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            tabBar
        }
        .glassScreenBackground()
        // 좌우 스와이프 = 월 이동. 상태 탭에는 월이 없으므로 마스크로 끈다
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
        .fullScreenCover(isPresented: $showingQueue) {
            ChargeCostQueueView {
                await summaryViewModel.reload()
                await summaryViewModel.refreshMissingCount()
            }
        }
        .task { await summaryViewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .summary:
            VehicleSummaryTab(viewModel: summaryViewModel) { showingQueue = true }
        case .status:
            VehicleStatusTab(viewModel: statusViewModel)
                .task { await statusViewModel.load() }
        }
    }

    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .summary: monthSwitcher
        case .status: Text("차량 상태").font(.subheadline).fontWeight(.bold)
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
            tabButton(.summary, icon: "chart.bar.fill", label: "요약")
            tabButton(.status, icon: "car.fill", label: "상태")
        }
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        // 버튼 사이 여백 탭이 아래 목록으로 새지 않게 바 전체를 히트 영역으로 만든다.
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {}
        .padding(.horizontal, 60)
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
