import SwiftUI

/// 사진과 인식 결과를 나란히 놓고 고친 뒤 확정한다.
struct DispatchReviewView: View {
    @State private var vm: DispatchReviewViewModel
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// 확대 배율과 이동. 놓아도 유지한다(아래 주석 참고). 두 번 탭하면 원래대로 돌아간다.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let photo: UIImage?

    init(recognition: DispatchRecognition, photo: UIImage?) {
        _vm = State(initialValue: DispatchReviewViewModel(recognition: recognition))
        self.photo = photo
    }

    var body: some View {
        List {
            if let photo {
                Section {
                    // **확대와 이동이 있어야 대조가 된다.** 배차표는 한 칸이 몇 픽셀이라
                    // 축소된 미리보기로는 사진과 목록을 맞춰 볼 수 없다. 놓아도 배율을
                    // 유지한다 — 한 곳을 들여다보다 손을 떼면 튕겨 나가는 것이 더 답답하다.
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxHeight: 220)
                        .clipped()
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = min(max(lastScale * value.magnification, 1), 6)
                                }
                                .onEnded { _ in lastScale = scale }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        .onTapGesture(count: 2) {
                            scale = 1; lastScale = 1
                            offset = .zero; lastOffset = .zero
                        }
                }
            }

            if vm.needsRowIndexWarning {
                Section {
                    Label(
                        "성명 컬럼이 없어 저장된 줄 위치로 맞췄습니다. 사진과 대조해 주세요.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            if !vm.warningMessages.isEmpty {
                Section {
                    ForEach(vm.warningMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("날짜별 근무") {
                ForEach(vm.entries) { entry in
                    dayRow(entry)
                }
            }

            if let message = vm.errorMessage {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("인식 결과 확인")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    saveTask?.cancel()
                    saveTask = Task {
                        await vm.save()
                        if vm.didSave { dismiss() }
                    }
                }
                // 보낼 날짜가 하나도 없으면 서버 `@NotEmpty`가 400을 낸다.
                .disabled(vm.isSaving || !vm.canSave)
            }
        }
        .onDisappear { saveTask?.cancel() }
    }

    private func dayRow(_ entry: DispatchReviewViewModel.DayEntry) -> some View {
        HStack {
            Text("\(entry.day)일")
                .frame(width: 40, alignment: .leading)
                .foregroundStyle(entry.recognized ? .primary : .secondary)

            // 사진의 표가 요일 머리글로 정렬돼 있어 대조할 때 실제로 쓸모가 있다.
            Text(entry.weekday)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            if entry.conflict {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()

            Menu {
                Button("휴무") { vm.setWorking(day: entry.day, working: false, slot: nil) }
                ForEach(1...4, id: \.self) { slot in
                    Button("\(slot)번") { vm.setWorking(day: entry.day, working: true, slot: slot) }
                }
                Button("순번 없이 근무") { vm.setWorking(day: entry.day, working: true, slot: nil) }
                Divider()
                Button("미인식으로 두기", role: .destructive) { vm.markUnrecognized(day: entry.day) }
            } label: {
                Text(label(for: entry))
                    .foregroundStyle(entry.recognized ? .primary : .secondary)
            }
        }
    }

    private func label(for entry: DispatchReviewViewModel.DayEntry) -> String {
        guard entry.recognized else { return "미인식" }
        if let note = entry.note, !note.isEmpty { return note }
        // 판정은 working만 본다. slot이 nil이어도 근무일 수 있다.
        guard entry.working else { return "휴무" }
        if let slot = entry.slot { return "\(slot)번" }
        return "근무"
    }
}
