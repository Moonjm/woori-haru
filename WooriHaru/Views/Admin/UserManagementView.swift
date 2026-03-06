import SwiftUI

struct UserManagementView: View {
    @State private var viewModel = UserManagementViewModel()
    @State private var deleteTarget: User?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Create form
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("새 사용자")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("CREATE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.blue500)
                    }

                    formField("아이디") { TextField("예: user1", text: $viewModel.newUsername).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    formField("이름") { TextField("예: 홍길동", text: $viewModel.newName) }
                    formField("비밀번호") { SecureField("초기 비밀번호", text: $viewModel.newPassword) }

                    Button {
                        Task { await viewModel.createUser() }
                    } label: {
                        Text("사용자 추가")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.slate700)
                            )
                    }

                    Text("생성된 계정은 기본 권한이 USER이며, 권한은 오른쪽에서 수정할 수 있어요.")
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                // Messages
                if let success = viewModel.successMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(Color.green700)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                // User list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("사용자 목록")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(viewModel.users.count) users")
                            .font(.caption)
                            .foregroundStyle(Color.blue500)
                    }

                    ForEach(viewModel.users) { user in
                        if viewModel.editingId == user.id {
                            editUserRow(user)
                        } else {
                            userRow(user)
                        }
                    }
                }
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            }
            .padding(20)
        }
        .background(Color.slate50)
        .navigationTitle("사용자 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadUsers() }
        .alert(
            "사용자 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("취소", role: .cancel) { deleteTarget = nil }
            Button("삭제", role: .destructive) {
                if let target = deleteTarget {
                    Task { await viewModel.deleteUser(target) }
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("\(target.name ?? target.username)을(를) 삭제할까요?")
            }
        }
    }

    // MARK: - User Row

    private func userRow(_ user: User) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name ?? user.username)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(user.username)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }

            Spacer()

            Text(user.authority.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(user.authority == .admin ? Color.blue50 : Color.slate100)
                .foregroundStyle(user.authority == .admin ? Color.blue600 : Color.slate500)
                .cornerRadius(10)

            Button {
                viewModel.startEditing(user)
            } label: {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(Color.slate400)
            }
            .buttonStyle(.plain)

            Button {
                deleteTarget = user
            } label: {
                Image(systemName: "trash.circle")
                    .foregroundStyle(Color.red400)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.slate50)
        .cornerRadius(8)
    }

    // MARK: - Edit Row

    private func editUserRow(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name ?? user.username)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(user.username)
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }
                Spacer()
            }

            formField("이름") { TextField("", text: $viewModel.editName) }
            formField("비밀번호 변경") { SecureField("새 비밀번호", text: $viewModel.editPassword) }

            VStack(alignment: .leading, spacing: 6) {
                Text("권한")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Menu {
                    Button("USER") { viewModel.editAuthority = .user }
                    Button("ADMIN") { viewModel.editAuthority = .admin }
                } label: {
                    HStack {
                        Text(viewModel.editAuthority.rawValue)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.slate700)
                    .padding(12)
                    .background(.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.slate200, lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.updateUser() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
        }
        .padding(12)
        .background(Color.slate50)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue300, lineWidth: 1)
        )
    }

    // MARK: - Form Fields

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            content()
                .font(.subheadline)
                .padding(12)
                .background(.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.slate200, lineWidth: 1)
                )
        }
    }
}
