import SwiftUI

struct PairView: View {
    @Binding var navPath: NavigationPath
    @State private var viewModel = PairViewModel()
    @State private var showUnpairConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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

                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.isPaired {
                    connectedSection
                } else if viewModel.isPending {
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
            await viewModel.loadStatus()
        }
        .confirmationDialog("페어 해제", isPresented: $showUnpairConfirm, titleVisibility: .visible) {
            Button("해제", role: .destructive) {
                Task { await viewModel.unpair() }
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

            if let name = viewModel.pairInfo?.partnerName {
                Text(name)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            if let connectedAt = viewModel.pairInfo?.connectedAt {
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

            if let code = viewModel.inviteCode {
                Text(code.uppercased())
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .tracking(4)

                Button {
                    UIPasteboard.general.string = code.uppercased()
                    viewModel.successMessage = "코드가 복사되었습니다."
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("코드 복사")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.blue500)
                }
            } else {
                Text("초대 코드를 생성했습니다.\n파트너에게 코드를 공유해주세요.")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate500)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.unpair() }
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
                    Task { await viewModel.createInvite() }
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
                    TextField("6자리 코드 입력", text: $viewModel.inputCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: viewModel.inputCode) { _, newValue in
                            if newValue.count > 6 { viewModel.inputCode = String(newValue.prefix(6)) }
                        }

                    Button {
                        Task { await viewModel.acceptInvite() }
                    } label: {
                        Text("수락")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(viewModel.inputCode.count == 6 ? Color.blue500 : Color.slate400)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(viewModel.inputCode.count != 6)
                }
            }
        }
    }
}
