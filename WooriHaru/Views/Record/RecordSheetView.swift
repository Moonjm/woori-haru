import SwiftUI

struct RecordSheetView: View {
    @Bindable var viewModel: RecordViewModel
    let onChanged: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

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

                if !viewModel.holidayNames.isEmpty {
                    Text(viewModel.holidayNames.joined(separator: ", "))
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

            // Scrollable content
            if viewModel.isLoading {
                Spacer()
            } else {
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
                            partnerName: viewModel.partnerName,
                            isPaired: viewModel.isPaired,
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

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Color.red500)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 34)
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
