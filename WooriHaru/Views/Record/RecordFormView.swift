import SwiftUI

struct RecordFormView: View {
    @Bindable var viewModel: RecordViewModel
    var onSave: () -> Void = {}

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

            // Memo + together toggle
            HStack(spacing: 8) {
                TextField("메모 (최대 20자)", text: $viewModel.memo)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white)
                            .stroke(Color.slate200, lineWidth: 1)
                    }
                    .onChange(of: viewModel.memo) { _, newValue in
                        if newValue.count > 20 { viewModel.memo = String(newValue.prefix(20)) }
                    }

                if viewModel.isPaired {
                    Button {
                        viewModel.together.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text("👫")
                            Text("같이")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(viewModel.together ? Color.blue50 : .white)
                                .stroke(viewModel.together ? Color.blue300 : Color.slate200, lineWidth: 1)
                        }
                        .foregroundStyle(viewModel.together ? Color.blue700 : Color.slate500)
                    }
                }
            }

            // Save / Cancel buttons
            HStack(spacing: 8) {
                if viewModel.editingRecord != nil {
                    Button {
                        viewModel.resetForm()
                    } label: {
                        Text("취소")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.slate700)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.slate200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    Task {
                        let success: Bool
                        if viewModel.editingRecord != nil {
                            success = await viewModel.updateRecord()
                        } else {
                            success = await viewModel.createRecord()
                        }
                        if success { onSave() }
                    }
                } label: {
                    Text(viewModel.editingRecord != nil ? "수정" : "저장")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(viewModel.selectedCategoryId != nil ? Color.blue500 : Color.slate400)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.selectedCategoryId == nil)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.slate50)
        }
    }
}
