import SwiftUI

struct CategoriesView: View {
    @State private var viewModel = CategoriesViewModel()
    @State private var deleteTarget: Category?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 생성 폼
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("새 카테고리")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("CREATE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.blue500)
                    }

                    formField("이모지", placeholder: "예: 🏊") {
                        TextField("예: 🏊", text: $viewModel.newEmoji)
                            .font(.subheadline)
                            .onChange(of: viewModel.newEmoji) { _, newValue in
                                if newValue.count > 1 { viewModel.newEmoji = String(newValue.prefix(1)) }
                            }
                    }

                    formField("이름", placeholder: "예: 헬스") {
                        TextField("예: 헬스", text: $viewModel.newName)
                            .font(.subheadline)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("활성 여부")
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                        HStack(spacing: 12) {
                            activeButton("Active", isSelected: viewModel.newIsActive, selectedBg: Color.green100, selectedFg: Color.green700) {
                                viewModel.newIsActive = true
                            }
                            activeButton("Inactive", isSelected: !viewModel.newIsActive, selectedBg: Color.orange200, selectedFg: Color.orange700) {
                                viewModel.newIsActive = false
                            }
                        }
                    }

                    Button {
                        Task { await viewModel.createCategory() }
                    } label: {
                        Text("추가하기")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange300)
                            )
                    }
                }
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                // 메시지
                if let success = viewModel.successMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(Color.green700)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                // 카테고리 목록
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("카테고리 목록")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(viewModel.categories.count) items")
                            .font(.caption)
                            .foregroundStyle(Color.blue500)
                    }

                    ForEach(viewModel.categories) { category in
                        if viewModel.editingId == category.id {
                            editRow(category)
                        } else {
                            categoryRow(category)
                        }
                    }
                }
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            }
            .padding(20)
        }
        .background(Color.slate50)
        .navigationTitle("카테고리 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadCategories() }
        .alert(
            "카테고리 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("취소", role: .cancel) { deleteTarget = nil }
            Button("삭제", role: .destructive) {
                if let target = deleteTarget {
                    Task { await viewModel.deleteCategory(target) }
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("\(target.emoji) \(target.name)을(를) 삭제할까요?")
            }
        }
    }

    // MARK: - Category Row

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            Text(category.emoji).font(.title3)
            Text(category.name).font(.subheadline)

            Spacer()

            Text(category.isActive ? "ACTIVE" : "INACTIVE")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(category.isActive ? Color.green100 : Color.slate100)
                .foregroundStyle(category.isActive ? Color.green700 : Color.slate500)
                .cornerRadius(10)

            Button {
                viewModel.startEditing(category)
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            .buttonStyle(.plain)

            Button {
                deleteTarget = category
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(Color.red400)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.slate50)
        .cornerRadius(8)
    }

    // MARK: - Edit Row

    private func editRow(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            formField("이모지", placeholder: "") {
                TextField("", text: $viewModel.editEmoji)
                    .font(.subheadline)
            }

            formField("이름", placeholder: "") {
                TextField("", text: $viewModel.editName)
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("활성 여부")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                HStack(spacing: 12) {
                    activeButton("Active", isSelected: viewModel.editIsActive, selectedBg: Color.green100, selectedFg: Color.green700) {
                        viewModel.editIsActive = true
                    }
                    activeButton("Inactive", isSelected: !viewModel.editIsActive, selectedBg: Color.orange200, selectedFg: Color.orange700) {
                        viewModel.editIsActive = false
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.updateCategory() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
        }
        .padding(12)
        .background(Color.slate50)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue300, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func formField<Content: View>(_ label: String, placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            content()
                .padding(12)
                .background(.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.slate200, lineWidth: 1)
                )
        }
    }

    private func activeButton(_ label: String, isSelected: Bool, selectedBg: Color, selectedFg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? selectedBg : Color.slate50)
                )
                .foregroundStyle(isSelected ? selectedFg : Color.slate500)
        }
    }
}
