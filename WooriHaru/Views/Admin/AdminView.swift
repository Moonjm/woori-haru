import SwiftUI

struct AdminView: View {
    @Binding var navPath: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("카테고리와 사용자를 관리하세요.")
                .font(.subheadline)
                .foregroundStyle(Color.slate500)
                .padding(.horizontal, 20)

            adminCard(
                icon: "folder",
                title: "카테고리 관리",
                subtitle: "이모지/이름/활성 상태",
                destination: .categories
            )

            adminCard(
                icon: "person.2",
                title: "사용자 관리",
                subtitle: "계정/권한/비밀번호",
                destination: .userManagement
            )

            Spacer()
        }
        .padding(.top, 8)
        .navigationTitle("관리")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func adminCard(icon: String, title: String, subtitle: String, destination: AppDestination) -> some View {
        Button {
            navPath.append(destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.slate500)
                    .frame(width: 36, height: 36)
                    .background(Color.slate100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.slate700)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
            .padding(16)
            .background(.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        }
        .padding(.horizontal, 20)
    }
}
