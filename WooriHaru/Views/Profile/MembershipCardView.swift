import CoreImage.CIFilterBuiltins
import SwiftUI

/// 회원카드 바코드 시트 — 사용자 정보에 저장된 번호로 Code 128 바코드를 생성해 표시한다.
/// 스캐너가 읽기 쉽도록 표시 중에는 화면 밝기를 최대로 올렸다가 닫히면 복원한다.
struct MembershipCardView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var numberInput = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedBrightness: CGFloat = 1

    private var barcodeNumber: String? {
        guard let value = authVM.user?.membershipBarcode, !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let number = barcodeNumber, !isEditing {
                    barcodeCard(number: number)
                } else {
                    editCard
                }
                Spacer()
            }
            .padding(20)
            .glassScreenBackground()
            .navigationTitle("회원카드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                if barcodeNumber != nil, !isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("번호 수정") {
                            numberInput = barcodeNumber ?? ""
                            isEditing = true
                        }
                    }
                }
            }
        }
        .onAppear {
            guard let screen = Self.activeScreen else { return }
            savedBrightness = screen.brightness
            screen.brightness = 1
        }
        .onDisappear {
            Self.activeScreen?.brightness = savedBrightness
        }
    }

    /// UIScreen.main이 iOS 26에서 deprecated라 포그라운드 윈도우 씬에서 스크린을 찾는다.
    private static var activeScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }

    // MARK: - 바코드 표시

    private func barcodeCard(number: String) -> some View {
        VStack(spacing: 16) {
            if let image = Self.code128Image(from: number) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
            } else {
                Text("바코드를 생성할 수 없는 번호입니다.")
                    .font(.caption)
                    .foregroundStyle(Color.red500)
            }
            Text(number)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        // 다크 모드에서도 스캔 대비를 위해 바코드 영역은 항상 흰색을 유지한다.
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    // MARK: - 번호 등록/수정

    private var editCard: some View {
        GlassCard(alignment: .leading) {
            VStack(alignment: .leading, spacing: 16) {
                Text("바코드 번호")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)

                TextField("회원카드 번호", text: $numberInput)
                    .font(.subheadline)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .glassInputField()

                Text("카드 바코드 아래 적힌 번호를 그대로 입력하면 같은 바코드가 만들어져요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                HStack(spacing: 12) {
                    if barcodeNumber != nil {
                        Button("취소") { isEditing = false }
                            .font(.subheadline)
                            .foregroundStyle(Color.slate500)
                    }
                    Spacer()
                    Button {
                        Task { await save() }
                    } label: {
                        Text("저장")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .appGlassProminentButton()
                    .disabled(isSaving || numberInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(isSaving ? 0.6 : 1)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        var request = UpdateMeRequest()
        request.membershipBarcode = numberInput.trimmingCharacters(in: .whitespaces)
        do {
            try await authVM.updateProfile(request)
            isEditing = false
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "저장에 실패했습니다."
        }
    }

    // MARK: - Code 128 생성

    /// 번호 문자열로 Code 128 바코드를 만든다. 같은 문자열이면 원본 카드와 동일한 패턴이 나온다.
    static func code128Image(from string: String) -> UIImage? {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(string.utf8)
        filter.quietSpace = 4
        guard let output = filter.outputImage else { return nil }
        // 저해상도 원본을 그대로 키우면 흐려지므로 미리 확대해 픽셀을 또렷하게 유지한다.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
