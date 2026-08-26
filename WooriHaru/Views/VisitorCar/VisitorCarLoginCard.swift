import SwiftUI

/// 자격증명이 없을 때 홈이 카드 대신 띄우는 것.
///
/// **한 번만 보이는 화면이다** — 성공하면 Keychain에 들어가고, 세션이 끊겨도
/// 서비스가 조용히 다시 붙는다. 여기까지 되돌아왔다면 계정이 바뀌었거나 지워진 것이다.
struct VisitorCarLoginCard: View {
    let error: String?
    let isSubmitting: Bool
    let onSubmit: (String, String) -> Void

    @State private var id = ""
    @State private var password = ""

    private var canSubmit: Bool {
        !id.isEmpty && !password.isEmpty && !isSubmitting
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("주차관제 로그인", systemImage: "person.badge.key")
                    .font(.headline)
                    .foregroundStyle(VehicleTheme.textPrimary)

                Text("아파트 주차관제 계정으로 한 번만 로그인하면 됩니다.")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textTertiary)

                TextField("아이디", text: $id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                SecureField("비밀번호", text: $password)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 10))

                if let error {
                    // 서버가 준 한국어를 그대로 띄운다.
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                }

                Button {
                    onSubmit(id, password)
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(VehicleTheme.background)
                        } else {
                            Text("로그인").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(
                        canSubmit ? VehicleTheme.accent : VehicleTheme.trackFill,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(canSubmit ? VehicleTheme.background : VehicleTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
    }
}
