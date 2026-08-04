import SwiftUI

/// 사진 삭제 결과. **실패 이유를 뷰어까지 들고 온다** — 전체화면 뷰어가 상세 화면을 덮고
/// 있어 상세가 띄우는 오류 알럿이 화면에 나타나지 않기 때문이다.
enum PhotoDeleteOutcome: Equatable {
    case deleted
    case failed(String)
}

/// 끼니 사진 한 장을 전체화면으로 본다. 확대·이동, 사진 앱 저장, 사진 삭제가 여기 있다.
struct PhotoViewerSheet: View {
    @State private var vm: PhotoViewerViewModel
    /// 지울 수 있는 곳에서만 준다 — 확인 화면(확정 전)에는 지울 API가 없어 nil이다.
    /// nil이면 삭제 버튼 자체가 없다.
    private let onDelete: (@MainActor () async -> PhotoDeleteOutcome)?
    /// 확대 배율. 놓으면 원래 크기로 돌아가지 않고 그 배율을 유지한다 — 한 곳을 들여다보다
    /// 손을 떼면 튕겨 나가는 것이 더 답답하다.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    /// 아래로 끌어 닫는 중의 세로 이동. **확대 팬(`offset`)과 섞지 않는다** — 둘은 서로 다른
    /// 상황에서만 움직이고, 한 값에 담으면 확대 상태를 벗어날 때 화면이 튄다.
    @State private var dismissDragY: CGFloat = 0
    /// 삭제 실패 이유. 상세 화면의 알럿은 이 화면에 가려 보이지 않으므로 여기서 띄운다.
    @State private var deleteError: String?
    @Environment(\.dismiss) private var dismiss

    init(
        url: String?,
        saver: any PhotoLibrarySaving = PhotoLibrarySaver(),
        refreshURL: (@MainActor () async -> String?)? = nil,
        onDelete: (@MainActor () async -> PhotoDeleteOutcome)? = nil
    ) {
        _vm = State(initialValue: PhotoViewerViewModel(url: url, saver: saver, refreshURL: refreshURL))
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .opacity(PhotoDragDismiss.backgroundOpacity(translationY: dismissDragY))
                    .ignoresSafeArea()
                content
            }
            .toolbar { toolbarContent }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await vm.load() }
            .alert("사진 저장", isPresented: .init(
                get: { vm.saveState == .saved || isSaveFailed },
                set: { if !$0 { vm.clearSaveState() } }
            )) {
                Button("확인", role: .cancel) { vm.clearSaveState() }
            } message: {
                Text(saveMessage)
            }
            .alert("사진을 삭제할까요?", isPresented: $showDeleteAlert) {
                Button("삭제", role: .destructive) { delete() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제하면 되돌릴 수 없어요. 먹은 기록과 점수는 그대로예요.")
            }
            .alert("사진 삭제", isPresented: .init(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func delete() {
        guard let onDelete else { return }
        Task {
            isDeleting = true
            let outcome = await onDelete()
            isDeleting = false
            switch outcome {
            case .deleted: dismiss()
            case let .failed(message): deleteError = message
            }
        }
    }

    private var isSaveFailed: Bool {
        if case .failed = vm.saveState { return true }
        return false
    }

    private var saveMessage: String {
        if case let .failed(message) = vm.saveState { return message }
        return "사진 앱에 저장했어요."
    }

    /// `imageData`는 이미 이미지로 열리는 것만 들어온다(VM이 걸러 낸다).
    private var loadedImage: UIImage? {
        vm.imageData.flatMap(UIImage.init(data:))
    }

    @ViewBuilder
    private var content: some View {
        if let image = loadedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * PhotoDragDismiss.imageScale(translationY: dismissDragY))
                .offset(x: offset.width, y: offset.height + PhotoDragDismiss.offsetY(translationY: dismissDragY))
                .gesture(magnification)
                // 확대했을 때는 끌어서 사진을 옮기고, 원래 크기에서는 끌어서 닫는다.
                // **한 자리를 나눠 쓴다** — 원래 크기에서 팬을 열어 두면 화면이 헛돌았다.
                .gesture(scale > 1 ? AnyGesture(drag.map { _ in () }) : AnyGesture(dismissDrag.map { _ in () }))
                .onTapGesture(count: 2) { resetZoom() }
        } else if vm.isLoading {
            ProgressView().tint(.white)
        } else if vm.loadFailed {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(Color.slate400)
                Text("사진을 불러오지 못했습니다.")
                    .font(.footnote)
                    .foregroundStyle(Color.slate400)
                // **`load()`가 아니라 `retry()`다** — 만료된 주소로 다시 받아 봐야 같은 실패다.
                Button("다시 시도") { Task { await vm.retry() } }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.blue500)
                    .buttonStyle(.plain)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .tint(.white)
            .accessibilityLabel("닫기")
        }
        if onDelete != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    if isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .tint(.white)
                .disabled(isDeleting)
                .accessibilityLabel("사진 삭제")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await vm.save() }
            } label: {
                if vm.saveState == .saving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .tint(.white)
            .disabled(!vm.canSave)
            .accessibilityLabel("사진 앱에 저장")
        }
    }

    // MARK: - 확대·이동

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // 1배 아래로는 줄지 않고 6배 위로는 커지지 않는다 — 둘 다 넘어가면
                // 되돌아올 방법이 두 번 탭밖에 없다.
                scale = min(max(lastScale * value.magnification, 1), 6)
            }
            .onEnded { _ in
                lastScale = scale
                if scale == 1 { resetPan() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    /// 원래 크기에서 아래로 끌어 닫는다. **위로 끄는 것은 화면에도 안 비친다**
    /// (`PhotoDragDismiss.offsetY`) — 따라오게 해 놓고 안 닫는 것이 가장 나쁘다.
    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                dismissDragY = value.translation.height
            }
            .onEnded { value in
                // 거리만 보면 휙 튕기는 동작이 빠진다 — 사용자는 그것도 닫히길 기대한다.
                if PhotoDragDismiss.shouldDismiss(
                    translationY: value.translation.height,
                    velocityY: value.velocity.height
                ) {
                    dismiss()
                } else {
                    withAnimation(.snappy) { dismissDragY = 0 }
                }
            }
    }

    private func resetZoom() {
        withAnimation(.snappy) {
            scale = scale > 1 ? 1 : 2
            lastScale = scale
            if scale == 1 { resetPan() }
        }
    }

    private func resetPan() {
        offset = .zero
        lastOffset = .zero
    }
}
