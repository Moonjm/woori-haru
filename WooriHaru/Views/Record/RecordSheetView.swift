import SwiftUI

struct RecordSheetView: View {
    @Bindable var viewModel: RecordViewModel
    @Environment(PairStore.self) private var pairStore
    var holidayNames: [String] = []
    let onChanged: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var keyboardVisible = false

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

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
            .onTapGesture { hideKeyboard() }

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
                                    Task {
                                        await viewModel.deleteRecord(record)
                                        onChanged()
                                    }
                                },
                                onTap: { record in
                                    viewModel.startEditing(record)
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                            RecordFormView(viewModel: viewModel, onSave: onChanged)
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
                        .padding(.bottom, 34)
                        .background {
                            Color.white.opacity(0.001)
                                .onTapGesture { hideKeyboard() }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        keyboardVisible = true
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("recordForm", anchor: .bottom)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        keyboardVisible = false
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
    }
}
