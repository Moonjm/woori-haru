import PhotosUI
import SwiftUI

/// 연월과 사진을 골라 인식을 요청한다.
///
/// **사진을 축소하지 않는다.** 식단처럼 장변 1024px로 줄이면 표가 뭉개져 인식이 망가진다.
/// 다만 앨범 원본을 **그대로** 보내지도 않는다 — `loadTransferable(type: Data.self)`는 자산의
/// 원본 포맷(아이폰 카메라 기본값은 HEIC)을 주는데 서버 `ImageIO.read`에는 HEIC 리더가 없어
/// `IMAGE_UNREADABLE`이 되고, EXIF 방향 플래그도 적용되지 않아 **화면에는 똑바로 보이는 사진을
/// 서버는 눕혀서 받아 가로로 2등분한다.** `downsampledJPEG`를 상한 없이(`.greatestFiniteMagnitude`)
/// 불러 JPEG로 다시 굽고 회전을 픽셀에 반영한다 — 그 함수가 상한을 `min(maxDimension, originalMax)`로
/// 낮추므로 **해상도는 원본 그대로다.**
struct DispatchUploadView: View {
    @State private var vm = DispatchUploadViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var recognizeTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
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
        .onDisappear {
            recognizeTask?.cancel()
            loadTask?.cancel()
        }
        .onChange(of: pickerItem) { _, item in
            loadTask?.cancel()
            guard let item else { return }
            loadTask = Task {
                let data = try? await item.loadTransferable(type: Data.self)
                // 사진을 잘못 골라 곧바로 다시 고르는 건 흔한 동작이다. 앨범 읽기는 사진마다
                // 걸리는 시간이 달라 먼저 시작한 쪽이 나중에 끝날 수 있는데, 그대로 두면
                // **화면에는 새 사진이 보이는데 인식은 이전 사진으로 돈다.** 실패 갈래도
                // 마찬가지라 상태를 건드리기 전에 한 번에 막는다.
                guard !Task.isCancelled, pickerItem == item else { return }

                // 읽기·변환 어느 쪽이 실패해도 조용히 돌아가지 않는다 — 예전에는 사진 섹션이
                // 그대로 비어 있어 사용자가 「고른 사진이 안 들어갔다」는 사실조차 몰랐다.
                guard let data,
                      let normalized = UIImage.downsampledJPEG(
                          from: data,
                          maxDimension: .greatestFiniteMagnitude,
                          quality: 0.95
                      ),
                      let preview = UIImage(data: normalized) else {
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
                .keyboardType(.numbersAndPunctuation)
            // 기본값은 이번 달이라 평소엔 안전하지만, 월말에 다음 달 배차표를 미리 올리려면
            // 이 칸을 손으로 고치게 된다. `2026-3`은 서버 `YearMonth` 파싱이 400을 낸다.
            if !vm.isYearMonthValid {
                Text("연월은 2026-08처럼 네 자리 연도와 두 자리 월로 적어 주세요.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
