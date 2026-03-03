import SwiftUI

struct RecordFormView: View {
    @Bindable var viewModel: RecordViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category selection
            FlowLayout(spacing: 8) {
                ForEach(viewModel.categories) { category in
                    Button {
                        viewModel.selectedCategoryId = category.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(category.emoji)
                            Text(category.name)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(viewModel.selectedCategoryId == category.id ? Color.blue50 : .white)
                                .stroke(
                                    viewModel.selectedCategoryId == category.id ? Color.blue300 : Color.slate200,
                                    lineWidth: 1
                                )
                        }
                        .foregroundStyle(
                            viewModel.selectedCategoryId == category.id ? Color.blue700 : Color.slate700
                        )
                    }
                }
            }

            // Memo + save
            HStack(spacing: 8) {
                TextField("메모 (최대 20자)", text: $viewModel.memo)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.memo) { _, newValue in
                        if newValue.count > 20 { viewModel.memo = String(newValue.prefix(20)) }
                    }

                Button {
                    Task {
                        if viewModel.editingRecord != nil {
                            await viewModel.updateRecord()
                        } else {
                            await viewModel.createRecord()
                        }
                    }
                } label: {
                    Text(viewModel.editingRecord != nil ? "수정" : "저장")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(viewModel.selectedCategoryId != nil ? Color.blue500 : Color.slate400)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(viewModel.selectedCategoryId == nil)
            }

            // Cancel editing
            if viewModel.editingRecord != nil {
                Button("취소") {
                    viewModel.resetForm()
                }
                .font(.caption)
                .foregroundStyle(Color.slate500)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.slate50)
                .stroke(Color.slate200, lineWidth: 1)
        }
    }
}
