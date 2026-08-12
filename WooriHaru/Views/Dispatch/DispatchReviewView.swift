import SwiftUI

/// 사진과 인식 결과를 나란히 놓고 고친 뒤 확정한다.
struct DispatchReviewView: View {
    @State private var vm: DispatchReviewViewModel
    @State private var saveTask: Task<Void, Never>?

    /// 확대 배율과 이동. 놓아도 유지한다(아래 주석 참고). 두 번 탭하면 원래대로 돌아간다.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let photo: UIImage?
    /// 저장에 성공하면 **저장된 연월**과 함께 부른다. 이 화면은 `navigationDestination(isPresented:)`로
    /// 떠서 `dismiss()`는 업로드 화면까지만 물러난다 — 달력으로 돌아가 저장한 달을 띄우는
    /// 일은 이 화면이 스스로 못 하고, 업로드 화면을 거쳐 `ContentView`가 `path`에서
    /// `.dispatchUpload`를 빼는 방식으로만 된다(그러면 이 화면도 함께 사라진다).
    private let onSaved: (String) -> Void

    init(recognition: DispatchRecognition, photo: UIImage?, onSaved: @escaping (String) -> Void) {
        _vm = State(initialValue: DispatchReviewViewModel(recognition: recognition))
        self.photo = photo
        self.onSaved = onSaved
    }

    var body: some View {
        // **저장 중에는 못 고치게 막는다.** `save()`는 요청을 보내기 전에 연월과 `entries`를
        // 찍어 두므로, 저장을 누른 뒤 고친 값은 화면에만 반영되고 요청에는 빠진다. 연월
        // 칸도 예외가 아니다 — 저장 중에 연월을 고치면 이전 값으로 저장된 요청과 화면에
        // 보이는 새 연월이 어긋나, 다른 달 값이 이번 달을 덮는 «그럴듯하게 틀린 저장»이
        // 된다. 그래서 `List` 전체를 잠근다.
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("연월").font(.footnote).foregroundStyle(.secondary)
                    TextField(
                        "2026-08",
                        text: Binding(get: { vm.yearMonth }, set: { vm.setYearMonth($0) })
                    )
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    if !vm.isYearMonthValid {
                        // 비어 있는 경우와 형식이 틀린 경우를 가른다 — 사진에서 잘 읽었는데
                        // 사용자가 한 글자 지운 순간까지 「못 읽었다」고 하면 상황과 안 맞는다.
                        if vm.yearMonth.isEmpty {
                            // 사진 제목이 잘리면 서버가 못 읽는다. 사진을 보고 채워야 한다.
                            Text("사진에서 연월을 읽지 못했습니다. 2026-08처럼 적어 주세요.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("연월은 2026-08처럼 네 자리 연도와 두 자리 월로 적어 주세요.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

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
        .disabled(vm.isSaving)
        .navigationTitle("인식 결과 확인")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    saveTask?.cancel()
                    saveTask = Task {
                        await vm.save()
                        if vm.didSave { onSaved(vm.yearMonth) }
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
