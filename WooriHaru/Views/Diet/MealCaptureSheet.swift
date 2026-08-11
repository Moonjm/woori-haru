import PhotosUI
import SwiftUI

/// 카메라/앨범에서 1~5장 선택 → 끼니 종류 선택 → 업로드 → 인식 진행 표시.
/// 인식이 끝나면 시트를 닫지 않고 **`MealConfirmView`로 이어진다.**
struct MealCaptureSheet: View {
    let date: Date
    /// 확정이 끝났을 때 mealId를 넘긴다.
    var onConfirmed: (Int) -> Void

    @State private var vm = MealCaptureViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    /// **`vm.phase`에서 파생하지 않는다.** 재시도 중 `phase`가 `.analyzing → .completed`로
    /// 다시 바뀌는데, 그때마다 `navigationDestination`이 이 값으로 열림·닫힘을 판정하면
    /// 재시도가 끝나는 순간 확인 화면이 통째로 다시 만들어져 사용자가 고치던 내용을 잃는다.
    /// 최초로 인식이 끝났을 때 한 번만 세우고, 재시도가 도는 동안은 그대로 둔다.
    @State private var showConfirm = false
    /// **시트와 함께 죽어야 한다.** 그냥 `Task { }`로 띄우면 닫은 뒤에도 사진 업로드와
    /// 인식 요청이 계속 나간다 — 인식은 LLM 호출이라 실제 비용이 붙는다.
    @State private var captureTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// 시뮬레이터나 카메라가 막힌 기기(MDM·스크린타임 제한 등)에서는 `false`다.
    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GlassTokens.cardSpacing) {
                    mealTypePicker
                    photoSection
                    statusSection
                }
                .padding(16)
            }
            .glassScreenBackground()
            .navigationTitle("사진으로 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 닫기를 막지 않는다 — 업로드가 느릴 때 갇히는 편이 더 나쁘다.
                    // 대신 나가면서 진행 중인 작업을 확실히 끊는다.
                    Button("닫기") {
                        captureTask?.cancel()
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showConfirm) {
                if let analysis = vm.analysis {
                    MealConfirmView(
                        date: date,
                        mealType: vm.mealType,
                        analysis: analysis,
                        isRetrying: vm.isRetrying,
                        retryPhase: vm.phase,
                        retryErrorMessage: vm.errorMessage
                    ) { mealId in
                        onConfirmed(mealId)
                        dismiss()
                    } onRetryPhoto: {
                        await vm.retry()
                    }
                }
            }
            .onChange(of: vm.phase) { _, newPhase in
                // 인식이 처음 끝난 순간에만 연다. 재시도가 다시 `.completed`를 만들어도 이미
                // 확인 화면이 떠 있으므로 다시 열지 않는다.
                if newPhase == .completed, !showConfirm {
                    showConfirm = true
                }
            }
            .onChange(of: showConfirm) { wasShown, isShown in
                // 확인 화면에서 저장 없이 나온 경우에만 해당한다 — 저장했을 때는 `onSaved`가
                // 이 시트 자체를 닫으므로 이 전이를 보기 전에 화면이 통째로 사라진다.
                if wasShown, !isShown {
                    vm.discard()
                }
            }
            .onChange(of: pickerItems) { _, items in
                // 다 읽은 뒤 목록을 비우는데, 그 변경도 여기로 돌아온다 — 빈 선택은 흘려보낸다.
                guard !items.isEmpty else { return }
                Task {
                    await vm.loadPicks { await downsampled(items) }
                    pickerItems = []
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    if let downsampled = UIImage.downsampledJPEG(from: data) {
                        vm.append([downsampled])
                    }
                }
            }
            .alert("오류", isPresented: .init(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        // 아래로 쓸어 내려 닫는 경우까지 잡는다 — 「닫기」 버튼만으로는 그 경로가 새어 나간다.
        // **`NavigationStack` 바깥에 붙인다** — 안쪽에 붙이면 확인 화면으로 밀고 들어갈 때도
        // 불려서, 아직 볼 사람이 있는 작업까지 끊는다.
        .onDisappear { captureTask?.cancel() }
    }

    private var mealTypePicker: some View {
        Picker("끼니", selection: $vm.mealType) {
            ForEach(MealType.allCases) { Text($0.label).tag(Optional($0)) }
        }
        .pickerStyle(.segmented)
        .disabled(vm.isBusy)
    }

    private var photoSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.photoDataList.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 88, height: 88)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                if !vm.isBusy {
                                    Button {
                                        vm.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, Color.slate500)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    // **상한 5장을 애초에 더 못 고르게 한다.**
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: vm.remainingSlots,
                        matching: .images
                    ) {
                        Label("앨범", systemImage: "photo.on.rectangle")
                            .font(.caption)
                    }
                    // **읽는 동안 잠근다** — `remainingSlots`는 다 읽어 담기 전까지 그대로라
                    // 이걸 안 걸면 5장을 고른 직후 5장을 더 고를 수 있다.
                    .disabled(vm.remainingSlots == 0 || vm.isBusy || vm.isLoadingPicks)

                    Button {
                        showCamera = true
                    } label: {
                        Label("카메라", systemImage: "camera")
                            .font(.caption)
                    }
                    // 시뮬레이터나 MDM·스크린타임으로 카메라가 막힌 기기에서는 `.camera`
                    // 소스타입 자체가 없다 — 이 상태에서 시트를 열면 `UIImagePickerController`가
                    // 크래시한다. 버튼을 아예 눌러도 반응하지 않게 막아 그 경로를 없앤다.
                    // 앨범(`PhotosPicker`)은 이 조건과 무관하게 계속 쓸 수 있다.
                    .disabled(vm.remainingSlots == 0 || vm.isBusy || vm.isLoadingPicks || !isCameraAvailable)

                    Spacer()

                    Text("최대 \(DietPolicy.maxPhotos)장")
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch vm.phase {
        case .idle, .failed, .delayed, .llmUnavailable:
            if vm.phase == .llmUnavailable {
                // 인식만 못 쓴다 — 나머지 기능은 전부 정상이다.
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("지금은 사진 인식을 쓸 수 없어요")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.slate700)
                        Text("음식을 검색하거나 직접 입력해서 기록할 수 있어요. 하루 요약 화면의 「직접 추가」를 눌러 주세요.")
                            .font(.caption)
                            .foregroundStyle(Color.slate400)
                    }
                }
            }

            if vm.phase == .delayed {
                Text("인식이 지연되고 있어요. 잠시 후 새로고침해 주세요.")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }

            // **둘을 함께 띄우지 않는다.** `canRetry`는 지금 화면의 사진들로 만든 인식이
            // 서버에 남아 있다는 뜻이고(사진을 바꾸면 꺼진다), 그 상태의 「인식 시작」은
            // 사진을 전부 다시 올려 **이미 낸 LLM 비용을 한 번 더 내는** 길이다. 강조 버튼이
            // 그쪽이면 눈에 띄는 쪽이 비싼 쪽이 된다. 지연(`.delayed`)일 때는 더 그렇다 —
            // 재시도는 서버가 처리 중이면 유료 호출 없이 폴링만 재개한다.
            if vm.canRetry {
                Button {
                    captureTask?.cancel()
                    captureTask = Task { await vm.retry() }
                } label: {
                    Text("다시 인식")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .appGlassProminentButton()
                .disabled(vm.isRetrying)
            } else {
                Button {
                    captureTask?.cancel()
                    captureTask = Task { await vm.start() }
                } label: {
                    Text("인식 시작")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .appGlassProminentButton()
                .disabled(vm.photoDataList.isEmpty)
            }

        case .uploading, .analyzing:
            HStack(spacing: 10) {
                ProgressView()
                Text(vm.progressText ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

        case .completed:
            EmptyView()
        }
    }

    /// **다운샘플이 업로드 앞에 온다** — 원본은 12MP·수 MB급이라 그대로 올리면 느리고
    /// 서버가 큰 이미지를 LLM에 넘겨 토큰 비용이 몇 배로 뛴다.
    private func downsampled(_ items: [PhotosPickerItem]) async -> [Data] {
        var result: [Data] = []
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let jpeg = UIImage.downsampledJPEG(from: raw) else { continue }
            result.append(jpeg)
        }
        return result
    }
}

/// `UIImagePickerController` 래퍼 — SwiftUI에 카메라 캡처가 없다.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1.0) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
