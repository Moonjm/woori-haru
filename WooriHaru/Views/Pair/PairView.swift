import SwiftUI

struct PairView: View {
    @Binding var navPath: NavigationPath
    @Environment(PairStore.self) private var pairStore
    @State private var inviteCode: String?
    @State private var inputCode: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showUnpairConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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

                if isLoading {
                    ProgressView()
                } else if pairStore.isPaired {
                    connectedSection
                } else if pairStore.isPending {
                    pendingSection
                } else {
                    disconnectedSection
                }
            }
            .padding(20)
        }
        .navigationTitle("커플")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStatus()
        }
        .confirmationDialog("페어 해제", isPresented: $showUnpairConfirm, titleVisibility: .visible) {
            Button("해제", role: .destructive) {
                Task { await unpair() }
            }
        } message: {
            Text("파트너와의 연결을 해제할까요?")
        }
    }

    // MARK: - Connected

    private var connectedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.red400)

            if let name = pairStore.pairInfo?.partnerName {
                Text(name)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            if let connectedAt = pairStore.pairInfo?.connectedAt {
                Text("연결일: \(connectedAt.prefix(10))")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }

            Button {
                navPath.append(AppDestination.pairEvents)
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                    Text("기념일 관리")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue500)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                showUnpairConfirm = true
            } label: {
                Text("페어 해제")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
        }
    }

    // MARK: - Pending

    private var pendingSection: some View {
        VStack(spacing: 16) {
            Text("초대 대기 중")
                .font(.headline)

            if let code = inviteCode {
                Text(code.uppercased())
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .tracking(4)

                Button {
                    UIPasteboard.general.string = code.uppercased()
                    errorMessage = nil
                    successMessage = "코드가 복사되었습니다."
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("코드 복사")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.blue500)
                }
            } else {
                Text("초대가 발송되었습니다.\n파트너가 수락하기를 기다리는 중입니다.")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate500)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await unpair() }
            } label: {
                Text("초대 취소")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("초대 코드 생성")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Button {
                    Task { await createInvite() }
                } label: {
                    Text("코드 생성하기")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Divider()

            VStack(spacing: 12) {
                Text("초대 코드 입력")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    TextField("6자리 코드 입력", text: $inputCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: inputCode) { _, newValue in
                            if newValue.count > 6 { inputCode = String(newValue.prefix(6)) }
                        }

                    Button {
                        Task { await acceptInvite() }
                    } label: {
                        Text("수락")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(inputCode.count == 6 ? Color.blue500 : Color.slate400)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(inputCode.count != 6)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await pairStore.loadStatus()
        } catch {
            errorMessage = "페어 상태를 불러오지 못했습니다."
        }
    }

    private func createInvite() async {
        errorMessage = nil
        successMessage = nil
        do {
            inviteCode = try await pairStore.createInvite()
        } catch {
            errorMessage = "초대 코드 생성에 실패했습니다."
        }
    }

    private func acceptInvite() async {
        let code = inputCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        errorMessage = nil
        successMessage = nil
        do {
            try await pairStore.acceptInvite(code: code)
            inputCode = ""
            inviteCode = nil
            successMessage = "페어링이 완료되었습니다!"
        } catch {
            errorMessage = "초대 코드가 올바르지 않습니다."
        }
    }

    private func unpair() async {
        errorMessage = nil
        successMessage = nil
        do {
            try await pairStore.unpair()
            inviteCode = nil
            successMessage = "페어가 해제되었습니다."
        } catch {
            errorMessage = "페어 해제에 실패했습니다."
        }
    }
}
