import SwiftUI

struct RecordSheetView: View {
    @Bindable var viewModel: RecordViewModel
    @Environment(PairStore.self) private var pairStore
    let holidayNames: [String]
    let onChanged: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var recordToDelete: DailyRecord?
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var memoFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.slate400)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Fixed header
            VStack(spacing: 8) {
                Text(viewModel.selectedDate.sheetHeaderText)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate900)

                if !holidayNames.isEmpty {
                    Text(holidayNames.joined(separator: ", "))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.red500)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.red500.opacity(0.08))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
            .onTapGesture { memoFocused = false }

            // Scrollable content
            if viewModel.isLoading {
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            OvereatSelectorView(
                                currentLevel: viewModel.overeatLevel,
                                onSelect: { level in
                                    Task {
                                        await viewModel.updateOvereat(level)
                                        onChanged()
                                    }
                                }
                            )
                            .padding(.horizontal, 16)

                            RecordListView(
                                records: viewModel.records,
                                partnerRecords: viewModel.partnerRecords,
                                partnerName: pairStore.partnerName,
                                isPaired: pairStore.isPaired,
                                onDelete: { record in
                                    recordToDelete = record
                                },
                                onTap: { record in
                                    viewModel.startEditing(record)
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                            RecordFormView(viewModel: viewModel, memoFocused: $memoFocused, onSave: onChanged)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .id("recordForm")

                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(Color.red500)
                                    .padding(.top, 8)
                            }
                        }
                        // 키보드 나왔을 때 저장 버튼까지 가시 영역 위로 올라오도록
                        // 실제 키보드 높이만큼 하단 여백을 추가해 스크롤 가능 범위를 확장.
                        .padding(.bottom, 34 + keyboardHeight)
                        .background {
                            Color.white.opacity(0.001)
                                .onTapGesture { memoFocused = false }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                        // 패딩만 먼저 애니메이트 — SwiftUI 자동 TextField 가시화와 충돌하지 않도록
                        // scrollTo는 여기서 호출하지 않는다.
                        withAnimation(.easeOut(duration: 0.25)) {
                            keyboardHeight = frame.height
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        // 키보드가 완전히 떠서 ScrollView 가시 영역이 최종 크기로 정착한 뒤
                        // 저장 버튼까지 보이도록 한 번만 부드럽게 스크롤.
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("recordForm", anchor: .bottom)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            keyboardHeight = 0
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        onDismiss()
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                }
        )
        .task {
            await viewModel.loadData()
        }
        .alert("삭제 확인", isPresented: .init(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("삭제", role: .destructive) {
                guard let record = recordToDelete else { return }
                Task {
                    await viewModel.deleteRecord(record)
                    onChanged()
                }
            }
            Button("취소", role: .cancel) { recordToDelete = nil }
        } message: {
            Text("이 기록을 삭제하시겠습니까?")
        }
    }
}
