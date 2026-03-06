import SwiftUI

struct RecordSheetView: View {
    @Bindable var viewModel: RecordViewModel
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                .padding(.top, 24)
                .padding(.bottom, 14)

                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        // Overeat selector
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

                        // Record list
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

                        // Record form
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
                    .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // CalendarView에서 미리 로드하지만, 타임아웃 등으로 미완료 시 재로드
            if viewModel.categories.isEmpty {
                await viewModel.loadData()
            }
        }
        .onDisappear {
            viewModel.resetForm()
        }
    }
}
