import SwiftUI

struct SideDrawerView: View {
    @Binding var isOpen: Bool
    @Binding var navPath: NavigationPath
    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isOpen = false } }

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
                    drawerItem(icon: "magnifyingglass", label: "검색") { isOpen = false; navPath.append(AppDestination.search) }
                    drawerItem(icon: "folder", label: "카테고리 관리") { isOpen = false; navPath.append(AppDestination.categories) }
                    drawerItem(icon: "person.circle", label: "내 정보") { isOpen = false }
                }

                Spacer()

                Button {
                    Task {
                        await authVM.logout()
                        isOpen = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("로그아웃")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
                    .padding(20)
                }
            }
            .frame(width: 260)
            .background(.white)
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
