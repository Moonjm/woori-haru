import SwiftUI

/// 「관리비」 미니앱 — 내역·통계 두 탭. 차량과 같은 하단 글래스 탭바 구조다.
/// **탭은 둘이 상한이다** — 더 늘리려는 순간 화면을 합칠 자리를 먼저 찾는다.
struct MaintenanceView: View {
    private enum Tab { case bills, stats }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .bills
    @State private var billsViewModel = MaintenanceBillsViewModel()
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel("뒤로")
            }
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
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .bills: billsTab
        case .stats:
            // Task 11이 `MaintenanceStatsTab(...)`으로 갈아 끼운다.
            Text("통계")
                .foregroundStyle(VehicleTheme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
