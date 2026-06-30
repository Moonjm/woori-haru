import SwiftUI

struct SideDrawerView: View {
    static let width: CGFloat = 260
    @Binding var isOpen: Bool
    @Binding var navPath: NavigationPath
    var dragOffset: CGFloat = 0
    @Environment(AuthViewModel.self) private var authVM
    @State private var showLogoutConfirm = false

    private var revealedWidth: CGFloat {
        if isOpen { return Self.width }
        return max(0, dragOffset)
    }

    private var overlayOpacity: Double {
        Double(min(revealedWidth / Self.width, 1)) * 0.3
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(overlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(isOpen)
                .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { isOpen = false } }

            drawerContent
                .frame(width: Self.width)
                .frame(maxHeight: .infinity, alignment: .top)
                .background {
                    // Color.clear는 크기 앵커일 뿐, glassEffect가 패널의 모든 시각 재질을 제공한다.
                    // ignoresSafeArea로 글래스를 화면 끝까지 확장(내용은 세이프에어리어 유지).
                    Color.clear
                        .glassEffect(.regular, in: Rectangle())
                        .ignoresSafeArea()
                }
                .offset(x: revealedWidth - Self.width)
        }
        .allowsHitTesting(isOpen || dragOffset > 0)
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(authVM.user?.name ?? "사용자")
                    .font(.headline)
                Text(authVM.user?.username ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            .padding(20)

            Divider()

            VStack(spacing: 0) {
                drawerItem(icon: "person.2", label: "커플") { isOpen = false; navPath.append(AppDestination.pair) }
                drawerItem(icon: "chart.bar", label: "통계") { isOpen = false; navPath.append(AppDestination.stats) }
                drawerItem(icon: "timer", label: "공부 타이머") { isOpen = false; navPath.append(AppDestination.studyTimer) }
                drawerItem(icon: "refrigerator", label: "보관함 관리") { isOpen = false; navPath.append(AppDestination.storage) }
                drawerItem(icon: "person.circle", label: "내 정보") { isOpen = false; navPath.append(AppDestination.profile) }

                if authVM.user?.authority == .admin {
                    Divider().padding(.vertical, 4)
                    drawerItem(icon: "gearshape", label: "관리") { isOpen = false; navPath.append(AppDestination.admin) }
                }
            }

            Spacer()

            Button {
                showLogoutConfirm = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("로그아웃")
                }
                .font(.subheadline)
                .foregroundStyle(Color.red500)
                .padding(20)
            }
            .alert("로그아웃", isPresented: $showLogoutConfirm) {
                Button("로그아웃", role: .destructive) {
                    Task {
                        await authVM.logout()
                        isOpen = false
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("로그아웃 하시겠습니까?")
            }
        }
    }

    private func drawerItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(label)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(Color.slate700)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}
