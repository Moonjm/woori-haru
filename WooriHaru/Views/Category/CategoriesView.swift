import SwiftUI

struct CategoriesView: View {
    @Environment(CategoryStore.self) private var categoryStore
    @State private var viewModel = CategoriesViewModel()
    @State private var deleteTarget: Category?
    @State private var draggingId: Int?

    var body: some View {
        VStack(spacing: 0) {
            createFormSection
            categoryListSection
        }
        .background(Color.slate50)
        .navigationTitle("카테고리 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(categoryStore: categoryStore)
            await viewModel.loadCategories()
        }
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

    // MARK: - Create Form

    private var createFormSection: some View {
        ScrollView {
            VStack(spacing: 16) {
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

                    formField("이모지") {
                        TextField("예: 🏊", text: $viewModel.newEmoji)
                            .font(.subheadline)
                            .onChange(of: viewModel.newEmoji) { _, newValue in
                                if newValue.count > 1 { viewModel.newEmoji = String(newValue.prefix(1)) }
                            }
                    }

                    formField("이름") {
                        TextField("예: 헬스", text: $viewModel.newName)
                            .font(.subheadline)
                    }

                    activeToggleSection(isActive: $viewModel.newIsActive)

                    Button {
                        Task { await viewModel.createCategory() }
                    } label: {
                        Text("추가하기")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange300))
                    }
                }
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                messageSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .layoutPriority(0)
    }

    // MARK: - Messages

    @ViewBuilder
    private var messageSection: some View {
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
    }

    // MARK: - Category List

    private var categoryListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("카테고리 목록")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(categoryStore.categories.count) items")
                    .font(.caption)
                    .foregroundStyle(Color.blue500)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(categoryStore.categories) { category in
                        if viewModel.editingId == category.id {
                            editRow(category)
                        } else {
                            categoryRow(category)
                                .opacity(draggingId == category.id ? 0.5 : 1)
                                .onDrag {
                                    draggingId = category.id
                                    return NSItemProvider(object: String(category.id) as NSString)
                                }
                                .onDrop(of: [.text], delegate: CategoryRowDrop(
                                    targetId: category.id,
                                    categoryStore: categoryStore,
                                    draggingId: $draggingId,
                                    onDone: { viewModel.syncCategoryOrder(movedId: $0) }
                                ))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.2), value: categoryStore.categories.map(\.id))
            }
        }
        .background(.white)
    }

    // MARK: - Category Row

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(Color.slate400)

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
            formField("이모지") {
                TextField("", text: $viewModel.editEmoji)
                    .font(.subheadline)
            }

            formField("이름") {
                TextField("", text: $viewModel.editName)
                    .font(.subheadline)
            }

            activeToggleSection(isActive: $viewModel.editIsActive)

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

    // MARK: - Shared Helpers

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func activeToggleSection(isActive: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("활성 여부")
                .font(.caption)
                .foregroundStyle(Color.slate500)
            HStack(spacing: 12) {
                activeButton("Active", isSelected: isActive.wrappedValue, selectedBg: Color.green100, selectedFg: Color.green700) {
                    isActive.wrappedValue = true
                }
                activeButton("Inactive", isSelected: !isActive.wrappedValue, selectedBg: Color.orange200, selectedFg: Color.orange700) {
                    isActive.wrappedValue = false
                }
            }
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

@MainActor
private struct CategoryRowDrop: DropDelegate {
    let targetId: Int
    let categoryStore: CategoryStore
    @Binding var draggingId: Int?
    let onDone: (Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingId, draggingId != targetId,
              let from = categoryStore.categories.firstIndex(where: { $0.id == draggingId }),
              let to = categoryStore.categories.firstIndex(where: { $0.id == targetId }) else { return }
        categoryStore.move(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let draggingId { onDone(draggingId) }
        draggingId = nil
        return true
    }
}
