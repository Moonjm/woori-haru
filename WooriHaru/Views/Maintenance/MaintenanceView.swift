import SwiftUI

/// 「관리비」 미니앱 — 내역·통계 두 탭. 차량과 같은 하단 글래스 탭바 구조다.
/// **탭은 둘이 상한이다** — 더 늘리려는 순간 화면을 합칠 자리를 먼저 찾는다.
struct MaintenanceView: View {
    private enum Tab { case bills, stats }

    @State private var tab: Tab = .bills
    @State private var billsViewModel = MaintenanceBillsViewModel()
    @State private var trendsViewModel = MaintenanceTrendsViewModel()
    /// 상세로 넘길 달. `navigationDestination(item:)`이 요구하는 `Hashable`을
    /// `MaintenanceBill`이 `Identifiable`로만 만족하지 못해 연월 문자열을 들고 간다.
    @State private var selectedYearMonth: String?
    @State private var showingUpload = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            tabBar
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationBarTitleDisplayMode(.inline)
        // **뒤로가기를 직접 그리지 않는다.** 이 껍데기는 `VehicleView`에서 가져왔는데,
        // 거기서 시스템 버튼을 숨기고(`navigationBarBackButtonHidden`) 손수 그린 이유는
        // **월 이동 스와이프가 엣지 뒤로가기와 겹쳐서**다. 이 화면에는 그 제스처가 없어
        // 숨길 이유가 없고, 숨기는 쪽만 빼먹고 버튼만 가져와 **뒤로가기가 둘로 보였다.**
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(tab == .bills ? "관리비" : "통계")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingUpload = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("고지서 등록")
            }
        }
        .task { await billsViewModel.load() }
        .navigationDestination(isPresented: $showingUpload) {
            MaintenanceUploadView {
                // 검수 화면(`MaintenanceBillFormView`)은 업로드 화면 **위에** 뜬다
                // (`navigationDestination(isPresented:)`가 겹으로 쌓인다). 그래서
                // 검수 화면의 `dismiss()`는 업로드 화면까지만 물러나고, 여기서
                // `showingUpload`를 내리지 않으면 저장에 성공해도 사용자는 사진
                // 미리보기와 「인식하기」 버튼이 살아 있는 업로드 화면에 남는다 —
                // 거기서 다시 누르면 유료 인식이 또 나가고 곧장 409로 막힌다.
                showingUpload = false
                Task {
                    await billsViewModel.load()
                    await refreshTrendsIfLoaded()
                }
            }
        }
        .navigationDestination(item: $selectedYearMonth) { yearMonth in
            if let bill = billsViewModel.bills.first(where: { $0.yearMonth == yearMonth }) {
                MaintenanceBillDetailView(
                    bill: bill,
                    billsViewModel: billsViewModel,
                    onChanged: { Task { await billsViewModel.load(); await refreshTrendsIfLoaded() } },
                    onDeleted: { Task { await refreshTrendsIfLoaded() } }
                )
            }
        }
    }

    /// 아직 안 열어 본 통계 탭은 그냥 둔다 — 그때는 `hasLoaded`가 false라 다음에 열 때
    /// `load()`가 처음부터 받는다. 차량 통계 탭이 같은 규칙이다.
    private func refreshTrendsIfLoaded() async {
        guard trendsViewModel.hasLoaded else { return }
        await trendsViewModel.reload()
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .bills: billsTab
        case .stats:
            MaintenanceStatsTab(vm: trendsViewModel)
        }
    }

    private var billsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if billsViewModel.bills.isEmpty, !billsViewModel.isLoading {
                    emptyState
                }
                ForEach(Array(billsViewModel.bills.enumerated()), id: \.element.yearMonth) { index, bill in
                    Button {
                        selectedYearMonth = bill.yearMonth
                    } label: {
                        MaintenanceBillCard(
                            bill: bill,
                            delta: MaintenanceTrendMath.monthOverMonth(
                                bills: billsViewModel.bills, at: index
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let message = billsViewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // 하단 탭바가 마지막 카드를 가리지 않게 띄운다.
            .padding(.bottom, 96)
        }
        .refreshable { await billsViewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(VehicleTheme.textTertiary)
            Text("등록된 관리비가 없습니다")
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textSecondary)
            Text("고지서 사진을 올려 첫 달을 등록해 보세요")
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            // 스펙(오류·빈 상태)이 요구하는 「안내 + 등록 버튼」 — 안내만 있으면
            // 사용자가 등록으로 가려면 툴바의 작은 「+」를 따로 찾아야 한다.
            Button("고지서 등록") { showingUpload = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.bills, icon: "list.bullet.rectangle", label: "내역")
            tabButton(.stats, icon: "chart.bar.fill", label: "통계")
        }
        .padding(6)
        // 다크에서는 유리를 쓰지 않는다 — 테두리가 형태를 만든다. 이 바는 목록 **위에**
        // 떠 있어서 반투명하면 지나가는 글자가 아이콘에 겹쳐 비친다.
        .background(VehicleTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(VehicleTheme.cardStroke, lineWidth: 1))
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
            .foregroundStyle(selected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(VehicleTheme.accent.opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(VehicleTheme.accent.opacity(0.45), lineWidth: 1)
                        )
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
