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
                    Color(.systemBackground)
                        .ignoresSafeArea()
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 2, y: 0)
                }
                .offset(x: revealedWidth - Self.width)
        }
        .allowsHitTesting(isOpen || dragOffset > 0)
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(authVM.user?.name ?? "사용자")
                        .font(.headline)
                    Text(authVM.user?.username ?? "")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                }
                Spacer()
                Button {
                    showLogoutConfirm = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.body)
                        .foregroundStyle(Color.red500)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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

            Divider()

            VStack(spacing: 0) {
                drawerItem(icon: "person.2", label: "커플") { isOpen = false; navPath.append(AppDestination.pair) }
                drawerItem(icon: "chart.bar", label: "통계") { isOpen = false; navPath.append(AppDestination.stats) }
                drawerItem(icon: "person.circle", label: "내 정보") { isOpen = false; navPath.append(AppDestination.profile) }

                if authVM.user?.authority == .admin {
                    Divider().padding(.vertical, 4)
                    drawerItem(icon: "gearshape", label: "관리") { isOpen = false; navPath.append(AppDestination.admin) }
                }
            }

            Spacer()

            Divider()

            HStack(spacing: 0) {
                shortcutItem(icon: "refrigerator", label: "보관함 관리") { isOpen = false; navPath.append(AppDestination.storage) }
                shortcutItem(icon: "wonsign.circle", label: "가계부") { isOpen = false; navPath.append(AppDestination.ledger) }
                shortcutItem(icon: "timer", label: "공부 타이머") { isOpen = false; navPath.append(AppDestination.studyTimer) }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)
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

    /// 하단 바로가기 — 네이버 캘린더 드로어 하단 버튼처럼 아이콘 위 + 라벨 아래.
    private func shortcutItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(Color.slate700)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
