import SwiftUI

/// 「방문차량」 미니앱의 홈. 잔여시간 카드 한 장 + 갈 곳 카드 셋.
///
/// **탭바를 두지 않는다.** 차량·관리비는 한 화면 안에서 오가는 탭이 필요했지만
/// 여기는 셋 다 「들어갔다 나오는」 일이라 목록이 맞다.
///
/// **`vehicleDarkTheme()`을 쓰지 않는다.** 차량·관리비는 계기판처럼 읽는 화면이라 다크가
/// 맞지만, 여기는 입력과 목록이 전부다 — 가계부·식단과 같은 밝은 팔레트(`Color.slate*`,
/// `blue600`, `red500`)를 쓴다. 이 미니앱의 뷰 여섯은 `VehicleTheme`을 참조하지 않는다.
struct VisitorCarView: View {
    @Binding var navPath: NavigationPath
    @State private var viewModel = VisitorCarHomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                switch viewModel.state {
                case .needsLogin:
                    VisitorCarLoginCard(
                        error: viewModel.loginError,
                        isSubmitting: viewModel.isSubmitting
                    ) { id, password in
                        Task { await viewModel.login(id: id, password: password) }
                    }
                default:
                    remainingCard
                    menuCard(
                        icon: "plus.circle",
                        title: "신규 차량 등록",
                        detail: "방문 차량 정보와 방문 기간을 입력해 등록합니다.",
                        destination: .visitorCarRegister
                    )
                    menuCard(
                        icon: "list.bullet.rectangle",
                        title: "등록 내역 조회",
                        detail: "기간별 방문 차량 등록 내역을 확인하고 수정합니다.",
                        destination: .visitorCarBookings
                    )
                    menuCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "차량 진입 현황",
                        detail: "우리 세대의 차량 입출차 현황을 확인합니다.",
                        destination: .visitorCarEntries
                    )
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .glassScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("방문차량")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(Color.slate900)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { navPath.append(AppDestination.visitorCarSettings) } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("설정")
            }
        }
        // **화면에 돌아올 때마다 다시 읽는다** — 등록하고 나오면 잔여시간이 달라져 있다.
        .task { await viewModel.load() }
    }

    private var remainingCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(Color.blue600)
                    .frame(width: 44, height: 44)
                    .background(Color.slate500.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("충전 잔여 시간")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)

                    switch viewModel.state {
                    case .ready(let minutes):
                        Text(VisitorCarHomeViewModel.remainingText(minutes: minutes))
                            .font(.title3).fontWeight(.semibold)
                            // 초과분은 붉게 — 「남음」과 눈으로 갈려야 한다.
                            .foregroundStyle(minutes < 0 ? Color.red500 : Color.slate900)
                    case .failed(let message):
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.red500)
                    default:
                        Text("불러오는 중")
                            .font(.footnote)
                            .foregroundStyle(Color.slate500)
                    }
                }

                Spacer(minLength: 0)

                Button { Task { await viewModel.load() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.slate700)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("잔여시간 새로고침")
            }
        }
    }

    private func menuCard(
        icon: String,
        title: String,
        detail: String,
        destination: AppDestination
    ) -> some View {
        Button { navPath.append(destination) } label: {
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(Color.blue600)
                        .frame(width: 44, height: 44)
                        .background(Color.slate500.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Color.slate900)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.slate500)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
