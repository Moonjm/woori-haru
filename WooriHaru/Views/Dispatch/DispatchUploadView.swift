import PhotosUI
import SwiftUI

/// 사진을 골라 인식을 요청한다. 연월은 검수 화면에서 확인·수정한다.
///
/// **사진을 축소하지 않는다.** 식단처럼 장변 1024px로 줄이면 표가 뭉개져 인식이 망가진다.
/// 다만 앨범 원본을 **그대로** 보내지도 않는다 — `loadTransferable(type: Data.self)`는 자산의
/// 원본 포맷(아이폰 카메라 기본값은 HEIC)을 주는데 서버 `ImageIO.read`에는 HEIC 리더가 없어
/// `IMAGE_UNREADABLE`이 되고, EXIF 방향 플래그도 적용되지 않아 **화면에는 똑바로 보이는 사진을
/// 서버는 눕혀서 받아 가로로 2등분한다.** `downsampledJPEG`를 상한 없이(`.greatestFiniteMagnitude`)
/// 불러 JPEG로 다시 굽고 회전을 픽셀에 반영한다 — 그 함수가 상한을 `min(maxDimension, originalMax)`로
/// 낮추므로 **해상도는 원본 그대로다.**
struct DispatchUploadView: View {
    /// 검수 화면까지 그대로 넘긴다. 저장에 성공하면 저장된 연월과 함께 불린다 —
    /// `ContentView`가 이걸로 달력을 그 달로 띄운다.
    var onSaved: (String) -> Void = { _ in }

    @State private var vm = DispatchUploadViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var recognizeTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    /// 굽기는 `Task.detached`로 돈다 — 취소를 물려받지 않으므로 따로 붙들어 접는다.
    @State private var normalizeTask: Task<Data?, Never>?
    /// 로딩 동안 「인식하기」가 잠긴다. 왜 잠겼는지 알리지 않으면 앨범 자산이 iCloud에서
    /// 내려오는 몇 초 동안 화면이 고장 난 것처럼 보인다.
    @State private var isLoadingPhoto = false
    /// 인식이 처음 끝났을 때 한 번만 연다. `DispatchRecognition`이 `Hashable`이 아니라
    /// `navigationDestination(item:)`을 쓸 수 없어(요구하는 건 `Hashable`), `MealCaptureSheet`가
    /// `MealConfirmView`로 넘어갈 때 쓰는 `isPresented` + `onChange(of: phase)` 방식을 그대로 따른다.
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoSection
                guideText

                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    recognizeTask?.cancel()
                    recognizeTask = Task { await vm.recognize() }
                } label: {
                    if vm.phase == .recognizing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("인식하기").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canRecognize)
            }
            .padding()
        }
        .navigationTitle("배차표 등록")
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
            // 굽기가 끝까지 도는 동안 새 굽기가 시작된다.
            normalizeTask?.cancel()
            // 진행 중이던 인식도 접는다. 결과를 버리는 것은 뷰모델의 generation이 맡지만,
            // 사진을 바꾼 순간 이 요청은 이미 쓸모가 없다 — 유료 호출을 끌고 갈 이유가 없다.
            recognizeTask?.cancel()
            // 새 사진이 다 로딩될 때까지 이전 사진을 들고 있으면 그 사이에 「인식하기」가
            // 눌려 **이전 사진이 나간다.** 미리보기도 같이 지운다 — 남겨 두면 화면은 이전
            // 사진을 보여주면서 버튼만 잠겨 있어 무엇을 기다리는지 알 수 없다.
            previewImage = nil
            vm.clearImage()
            guard let item else { return }
            isLoadingPhoto = true
            loadTask = Task {
                let data = try? await item.loadTransferable(type: Data.self)
                // 굽기는 4,800만 화소에서 몇 초씩 걸린다. 이 Task는 뷰의 액터를 물려받아
                // 메인에서 도므로, 그대로 두면 그동안 화면이 멈춘다.
                //
                // **분리된 Task는 취소를 물려받지 않는다.** 붙들어 두고 사진을 바꿀 때
                // 함께 취소하지 않으면, 결과는 버려도 굽기 자체는 끝까지 돈다 — 겹친
                // 디코드·인코드가 메모리를 밀어 올려 앱이 내려갈 수 있다.
                let normalize = Task.detached(priority: .userInitiated) {
                    data.flatMap { UIImage.jpegWithinByteLimit(from: $0) }
                }
                normalizeTask = normalize
                let normalized = await normalize.value

                // 사진을 잘못 골라 곧바로 다시 고르는 건 흔한 동작이다. 앨범 읽기는 사진마다
                // 걸리는 시간이 달라 먼저 시작한 쪽이 나중에 끝날 수 있는데, 그대로 두면
                // **화면에는 새 사진이 보이는데 인식은 이전 사진으로 돈다.** 실패 갈래도
                // 마찬가지라 상태를 건드리기 전에 한 번에 막는다.
                guard !Task.isCancelled, pickerItem == item else { return }
                isLoadingPhoto = false

                // 읽기·변환 어느 쪽이 실패해도 조용히 돌아가지 않는다 — 예전에는 사진 섹션이
                // 그대로 비어 있어 사용자가 「고른 사진이 안 들어갔다」는 사실조차 몰랐다.
                guard let normalized, let preview = UIImage(data: normalized) else {
                    previewImage = nil
                    vm.setImageLoadFailed()
                    return
                }
                vm.setImage(normalized)
                previewImage = preview
            }
        }
        .onChange(of: vm.phase) { _, newPhase in
            // 인식이 처음 끝난 순간에만 연다 — 이미 검수 화면이 떠 있는데 여기서 다시 세우면
            // (지금 뷰모델엔 재시도가 없어 당장은 안 일어나지만) 화면이 다시 만들어질 수 있다.
            if newPhase == .completed, !showReview {
                showReview = true
            }
        }
        .navigationDestination(isPresented: $showReview) {
            if let recognition = vm.recognition {
                DispatchReviewView(recognition: recognition, photo: previewImage, onSaved: onSaved)
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
                    Text("사진을 불러오는 중…").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var guideText: some View {
        Text("""
        시간표만 확대해서 찍은 사진이 가장 잘 읽힙니다. \
        첫 장은 성명 컬럼이 보이게 왼쪽부터 찍어 주세요. \
        기사 줄이 잘리면 순번이 어긋납니다.
        """)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
