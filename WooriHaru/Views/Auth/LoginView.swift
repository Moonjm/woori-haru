import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case password
    }

    var body: some View {
        ZStack {
            Color.slate50
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Text("우리 하루")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.slate900)

                    Text("우리의 하루를 기록해요")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.slate500)
                }

                VStack(spacing: 14) {
                    inputField(
                        title: "아이디",
                        text: $username,
                        isSecure: false,
                        submitLabel: .next,
                        field: .username
                    )

                    inputField(
                        title: "비밀번호",
                        text: $password,
                        isSecure: true,
                        submitLabel: .go,
                        field: .password
                    )

                    Button {
                        login()
                    } label: {
                        Group {
                            if authVM.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("로그인")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.slate900)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || authVM.isLoading)
                    .opacity(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || authVM.isLoading ? 0.55 : 1)
                }
                .padding(22)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.slate200, lineWidth: 1)
                }
                .padding(.horizontal, 24)

                Text("기록은 가볍게, 하루는 선명하게")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.slate400)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 24)
        }
        .alert("로그인 실패", isPresented: .init(
            get: { authVM.errorMessage != nil },
            set: { if !$0 { authVM.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(authVM.errorMessage ?? "")
        }
        .onSubmit {
            switch focusedField {
            case .username:
                focusedField = .password
            case .password:
                login()
            case nil:
                break
            }
        }
    }

    @ViewBuilder
    private func inputField(
        title: String,
        text: Binding<String>,
        isSecure: Bool,
        submitLabel: SubmitLabel,
        field: Field
    ) -> some View {
        Group {
            if isSecure {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .focused($focusedField, equals: field)
        .submitLabel(submitLabel)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color.slate100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.slate200, lineWidth: focusedField == field ? 1.5 : 1)
        }
    }

    private func login() {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty,
              !authVM.isLoading else { return }

        Task {
            await authVM.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
        }
    }
}
