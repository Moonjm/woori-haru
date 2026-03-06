import SwiftUI

struct RecordSheetView: View {
    @Bindable var viewModel: RecordViewModel
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Text(viewModel.selectedDate.sheetHeaderText)
                            .font(.headline)
                            .fontWeight(.bold)

                        if !viewModel.holidayNames.isEmpty {
                            Text(viewModel.holidayNames.joined(separator: ", "))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.red500)
                        }
                    }
                    .frame(maxWidth: .infinity)

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

                    // Record form
                    RecordFormView(viewModel: viewModel, onSave: onChanged)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red500)
                    }
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadData()
        }
        .onDisappear {
            viewModel.resetForm()
        }
    }
}
