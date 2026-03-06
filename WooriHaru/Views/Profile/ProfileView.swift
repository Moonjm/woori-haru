import SwiftUI

struct ProfileView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var name: String = ""
    @State private var gender: Gender?
    @State private var birthDate: Date = .now
    @State private var hasBirthDate: Bool = false
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var showDatePicker = false
    @State private var isSaving = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var hideSuccessTask: Task<Void, Never>?


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 아이디 (읽기전용)
                fieldSection("아이디") {
                    Text(authVM.user?.username ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Color.slate400)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.slate100)
                        .cornerRadius(8)
                }

                // 이름
                fieldSection("이름") {
                    TextField("이름", text: $name)
                        .font(.subheadline)
                        .padding(12)
                        .background(.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.slate200, lineWidth: 1)
                        )
                }

                // 성별
                fieldSection("성별") {
                    HStack(spacing: 12) {
                        genderButton(.male, label: "남자", emoji: "👨")
                        genderButton(.female, label: "여자", emoji: "👩")
                    }
                }

                // 생년월일
                fieldSection("생년월일") {
                    Button {
                        showDatePicker.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundStyle(Color.slate500)
                            Text(hasBirthDate ? birthDate.formatted(.dateTime.year().month().day()) : "선택")
                                .font(.subheadline)
                                .foregroundStyle(hasBirthDate ? Color.slate700 : Color.slate400)
                            Spacer()
                        }
                        .padding(12)
                        .background(.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.slate200, lineWidth: 1)
                        )
                    }

                    if showDatePicker {
                        DatePicker(
                            "",
                            selection: $birthDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(8)
                        .background(.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                        .onChange(of: birthDate) { _, _ in
                            hasBirthDate = true
                            showDatePicker = false
                        }
                    }
                }

                Divider()

                // 기존 비밀번호
                fieldSection("기존 비밀번호") {
                    SecureField("비밀번호 변경 시 필요", text: $currentPassword)
                        .font(.subheadline)
                        .padding(12)
                        .background(.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.slate200, lineWidth: 1)
                        )
                }

                // 새 비밀번호
                fieldSection("새 비밀번호") {
                    SecureField("", text: $newPassword)
                        .font(.subheadline)
                        .padding(12)
                        .background(.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.slate200, lineWidth: 1)
                        )
                }

                if let success = successMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(Color.green700)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                // 저장 버튼
                Button {
                    Task { await save() }
                } label: {
                    Text("저장")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.slate700)
                        )
                }
                .disabled(isSaving)
                .opacity(isSaving ? 0.6 : 1)
            }
            .padding(20)
        }
        .navigationTitle("내 정보")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadUserData() }
        .onDisappear { hideSuccessTask?.cancel() }
    }

    // MARK: - Helpers

    private func loadUserData() {
        guard let user = authVM.user else { return }
        name = user.name ?? ""
        gender = user.gender
        if let birthStr = user.birthDate, let date = Date.from(birthStr) {
            birthDate = date
            hasBirthDate = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        successMessage = nil
        errorMessage = nil

        var request = UpdateMeRequest()
        request.name = name.isEmpty ? nil : name
        request.gender = gender
        if hasBirthDate {
            request.birthDate = birthDate.dateString
        }
        if !currentPassword.isEmpty || !newPassword.isEmpty {
            guard !currentPassword.isEmpty && !newPassword.isEmpty else {
                errorMessage = "비밀번호 변경 시 기존 비밀번호와 새 비밀번호 모두 입력해 주세요."
                return
            }
            request.currentPassword = currentPassword
            request.password = newPassword
        }

        do {
            try await authVM.updateProfile(request)
            successMessage = "저장되었습니다."
            currentPassword = ""
            newPassword = ""
            hideSuccessTask?.cancel()
            hideSuccessTask = Task {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { successMessage = nil }
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "저장에 실패했습니다."
        }
    }

    @ViewBuilder
    private func fieldSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            content()
        }
    }

    @ViewBuilder
    private func genderButton(_ value: Gender, label: String, emoji: String) -> some View {
        Button {
            gender = value
        } label: {
            HStack(spacing: 4) {
                Text(emoji)
                Text(label)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(gender == value ? Color.blue50 : Color.slate50)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(gender == value ? Color.blue400 : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(gender == value ? Color.blue600 : Color.slate600)
        }
    }
}
