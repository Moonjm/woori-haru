import PhotosUI
import SwiftUI

/// 연월과 사진을 골라 인식을 요청한다.
///
/// **사진을 축소하지 않는다.** `PhotosPickerItem`에서 받은 원본 `Data`를 그대로 넘긴다 —
/// 식단처럼 `downsampledJPEG`를 거치면 표가 뭉개져 인식이 망가진다.
struct DispatchUploadView: View {
    @State private var vm = DispatchUploadViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var recognizeTask: Task<Void, Never>?
    /// 인식이 처음 끝났을 때 한 번만 연다. `DispatchRecognition`이 `Hashable`이 아니라
    /// `navigationDestination(item:)`을 쓸 수 없어(요구하는 건 `Hashable`), `MealCaptureSheet`가
    /// `MealConfirmView`로 넘어갈 때 쓰는 `isPresented` + `onChange(of: phase)` 방식을 그대로 따른다.
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearMonthField
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
        .onDisappear { recognizeTask?.cancel() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                vm.setImage(data)
                previewImage = UIImage(data: data)
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
                DispatchReviewView(recognition: recognition, photo: previewImage)
            }
        }
    }

    private var yearMonthField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("연월").font(.footnote).foregroundStyle(.secondary)
            TextField("2026-08", text: $vm.yearMonth)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(previewImage == nil ? "사진 고르기" : "사진 바꾸기", systemImage: "photo")
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
