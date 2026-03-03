import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("우리 하루")
                .font(.system(size: 36, weight: .bold))

            VStack(spacing: 16) {
                TextField("아이디", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("비밀번호", text: $password)
                    .textFieldStyle(.roundedBorder)

                if let error = authVM.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await authVM.login(username: username, password: password)
                    }
                } label: {
                    if authVM.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    } else {
                        Text("로그인")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty || authVM.isLoading)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}
