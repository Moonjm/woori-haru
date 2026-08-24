import PhotosUI
import SwiftUI

/// 고지서 사진을 골라 인식을 요청한다. 연월은 검수 화면에서 확인·수정한다.
///
/// **사진을 축소하지 않는다** — `jpegWithinByteLimit`이 상한을 `min(maxDimension, originalMax)`로
/// 낮추므로 해상도는 원본 그대로고, HEIC→JPEG 재인코딩과 EXIF 회전 반영만 일어난다.
/// 이걸 건너뛰면 서버가 `IMAGE_UNREADABLE`을 내거나 눕힌 사진을 읽는다.
struct MaintenanceUploadView: View {
    /// 서버 multipart 한도는 10MB다. **`jpegWithinByteLimit`의 기본 한도와 같은 값을
    /// 여기 다시 적는다** — 그 함수는 한도를 못 맞춰도 nil이 아니라 가장 작은 데이터를
    /// 돌려주므로, 넘겼는지는 부르는 쪽이 직접 봐야 한다.
    private static let byteLimit = 9 * 1024 * 1024

    /// 저장까지 끝나면 불린다 — 목록 화면이 이걸로 목록을 다시 받는다. 검수 화면까지 그대로 넘긴다.
    var onSaved: () -> Void = {}

    @State private var vm = MaintenanceUploadViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var recognizeTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    /// 굽기는 `Task.detached`로 돈다 — 취소를 물려받지 않으므로 따로 붙들어 접는다.
    @State private var normalizeTask: Task<Data?, Never>?
    /// 로딩 동안 「인식하기」가 잠긴다. 왜 잠겼는지 알리지 않으면 앨범 자산이 iCloud에서
    /// 내려오는 몇 초 동안 화면이 고장 난 것처럼 보인다.
    @State private var isLoadingPhoto = false
    /// 인식이 처음 끝났을 때 한 번만 연다. `MaintenanceRecognition`이 `Hashable`이 아니라
    /// `navigationDestination(item:)`을 쓸 수 없다.
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoSection
                guideText

                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    recognizeTask?.cancel()
                    recognizeTask = Task { await vm.recognize() }
                } label: {
                    if vm.phase == .recognizing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("인식하기").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canRecognize)
            }
            .padding()
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle("관리비 등록")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            recognizeTask?.cancel()
            loadTask?.cancel()
            normalizeTask?.cancel()
            // 취소된 Task는 아래 가드에서 돌아가므로 이 값을 스스로 내리지 못한다. 그대로
            // 두면 화면으로 돌아왔을 때 스피너가 남고 「인식하기」가 잠긴 채로 있는다.
            isLoadingPhoto = false
        }
        .onChange(of: pickerItem) { _, item in
            loadTask?.cancel()
            // 굽기는 분리된 Task라 위 취소가 닿지 않는다. 따로 접지 않으면 이전 사진의
            // 굽기가 끝까지 도는 동안 새 굽기가 시작돼 메모리가 밀린다.
            normalizeTask?.cancel()
            // 진행 중이던 인식도 접는다 — 사진을 바꾼 순간 이 요청은 이미 쓸모가 없다.
            recognizeTask?.cancel()
            // 새 사진이 로딩되는 사이 「인식하기」가 눌리면 **이전 사진이 나간다.**
            previewImage = nil
            vm.clearImage()
            guard let item else { return }
            isLoadingPhoto = true
            loadTask = Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let normalize = Task.detached(priority: .userInitiated) {
                    // **`dimensions`를 원본 하나로 못 박는다.** 기본값은
                    // `[.greatestFiniteMagnitude, 4000, 3000, 2400]`이라, 원본 해상도에서
                    // 품질을 넷까지 낮춰도 한도를 못 맞추면 **말없이 2400px까지 줄인다.**
                    // 이 화면이 존재하는 이유가 「줄이면 인식이 망가진다」인데 그 폴백은
                    // 그것을 조용히 되돌린다. 못 맞추면 줄이는 대신 아래에서 막는다.
                    data.flatMap {
                        UIImage.jpegWithinByteLimit(from: $0, dimensions: [.greatestFiniteMagnitude])
                    }
                }
                normalizeTask = normalize
                let normalized = await normalize.value

                // 앨범 읽기는 사진마다 걸리는 시간이 달라 먼저 시작한 쪽이 나중에 끝날 수 있다.
                // 그대로 두면 **화면에는 새 사진이 보이는데 인식은 이전 사진으로 돈다.**
                guard !Task.isCancelled, pickerItem == item else { return }
                isLoadingPhoto = false

                guard let normalized, let preview = UIImage(data: normalized) else {
                    previewImage = nil
                    vm.setImageLoadFailed()
                    return
                }
                // **`jpegWithinByteLimit`은 한도를 못 맞춰도 nil을 안 준다** — 그때까지
                // 구운 것 중 가장 작은 데이터를 그대로 돌려준다. 위 가드만 두면 한도를
                // 넘긴 사진이 그대로 올라가 서버 multipart 한도(10MB)에서 튕긴다.
                guard normalized.count <= Self.byteLimit else {
                    previewImage = nil
                    vm.setImageTooLarge()
                    return
                }
                vm.setImage(normalized)
                previewImage = preview
            }
        }
        .onChange(of: vm.phase) { _, newPhase in
            if newPhase == .completed, !showReview { showReview = true }
        }
        .navigationDestination(isPresented: $showReview) {
            if let recognition = vm.recognition {
                MaintenanceBillFormView(mode: .create(recognition), onSaved: onSaved)
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(previewImage == nil ? "사진 고르기" : "사진 바꾸기", systemImage: "photo")
            }
            if isLoadingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("사진을 불러오는 중…")
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.textTertiary)
                }
            }
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var guideText: some View {
        Text("""
        고지서 표 전체가 한 장에 들어오게 찍어 주세요. \
        금액 열이 잘리면 항목이 어긋납니다. \
        연월이 적힌 제목 줄도 함께 담아 주세요. \
        인식에는 1~2분 걸립니다.
        """)
        .font(.footnote)
        .foregroundStyle(VehicleTheme.textTertiary)
    }
}
