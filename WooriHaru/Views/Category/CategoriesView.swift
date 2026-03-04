import SwiftUI

struct CategoriesView: View {
    @State private var viewModel = CategoriesViewModel()
    @State private var deleteTarget: Category?

    var body: some View {
        VStack(spacing: 0) {
            // 생성 폼
            VStack(spacing: 12) {
                Text("새 카테고리")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    TextField("😀", text: $viewModel.newEmoji)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.newEmoji) { _, newValue in
                            if newValue.count > 2 { viewModel.newEmoji = String(newValue.prefix(2)) }
                        }

                    TextField("이름", text: $viewModel.newName)
                        .textFieldStyle(.roundedBorder)

                    Toggle("활성", isOn: $viewModel.newIsActive)
                        .labelsHidden()

                    Button {
                        Task { await viewModel.createCategory() }
                    } label: {
                        Text("추가")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue500)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(16)
            .font(.subheadline)

            Divider()

            // 메시지
            if let success = viewModel.successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(Color.green700)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red500)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // 리스트
            List {
                ForEach(viewModel.categories) { category in
                    if viewModel.editingId == category.id {
                        editRow(category)
                    } else {
                        categoryRow(category)
                    }
                }
                .onMove { source, destination in
                    viewModel.moveCategory(from: source, to: destination)
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        deleteTarget = viewModel.categories[index]
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("카테고리 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadCategories() }
        .confirmationDialog(
            "카테고리 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
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

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            Text(category.emoji).font(.title3)
            Text(category.name).font(.subheadline)
            Spacer()
            Text(category.isActive ? "활성" : "비활성")
                .font(.caption2)
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
        }
        .contentShape(Rectangle())
    }

    private func editRow(_ category: Category) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("😀", text: $viewModel.editEmoji)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                TextField("이름", text: $viewModel.editName)
                    .textFieldStyle(.roundedBorder)
                Toggle("활성", isOn: $viewModel.editIsActive)
                    .labelsHidden()
            }
            HStack {
                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                Button {
                    Task { await viewModel.updateCategory() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8).fill(Color.slate50)
        }
        .font(.subheadline)
    }
}
