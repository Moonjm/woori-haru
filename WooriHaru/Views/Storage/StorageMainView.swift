import SwiftUI

struct StorageMainView: View {
    @State private var viewModel = StorageViewModel()
    @State private var collapsedSections: Set<Int> = []
    @State private var deleteItemTarget: (itemId: Int, name: String)?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.storages.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                storageTabs
                if viewModel.expiringItemCount > 0 {
                    expiryBanner
                }
                sectionList
            }
        }
        .background(Color.slate50)
        .navigationTitle("보관함 관리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        viewModel.showAddStorageSheet = true
                        viewModel.storageFormName = ""
                    } label: {
                        Image(systemName: "plus")
                    }
                    if viewModel.selectedStorage != nil {
                        Button {
                            viewModel.showStorageSettingSheet = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadStorages()
        }
        .sheet(isPresented: $viewModel.showAddStorageSheet) {
            addStorageSheet
        }
        .sheet(isPresented: $viewModel.showStorageSettingSheet) {
            StorageSettingSheet(viewModel: viewModel) {
                viewModel.showStorageSettingSheet = false
            }
        }
        .sheet(isPresented: $viewModel.showAddItemSheet) {
            StorageItemSheet(viewModel: viewModel) {
                viewModel.showAddItemSheet = false
            }
        }
        .alert(
            "품목 삭제",
            isPresented: .init(
                get: { deleteItemTarget != nil },
                set: { if !$0 { deleteItemTarget = nil } }
            )
        ) {
            Button("삭제", role: .destructive) {
                if let target = deleteItemTarget {
                    Task { await viewModel.deleteItem(target.itemId) }
                }
                deleteItemTarget = nil
            }
            Button("취소", role: .cancel) { deleteItemTarget = nil }
        } message: {
            if let target = deleteItemTarget {
                Text("\(target.name)을(를) 삭제할까요?")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "refrigerator")
                .font(.system(size: 48))
                .foregroundStyle(Color.slate300)
            Text("보관함이 없습니다")
                .font(.subheadline)
                .foregroundStyle(Color.slate500)
            Button("보관함 추가") {
                viewModel.showAddStorageSheet = true
                viewModel.storageFormName = ""
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.orange300)
            .cornerRadius(8)
            Spacer()
        }
    }

    // MARK: - Tabs

    private var storageTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.storages.enumerated()), id: \.element.id) { index, storage in
                        Button {
                            viewModel.selectedStorageIndex = index
                        } label: {
                            Text(storage.name)
                                .font(.subheadline)
                                .fontWeight(viewModel.selectedStorageIndex == index ? .semibold : .regular)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    viewModel.selectedStorageIndex == index
                                        ? Color.orange300 : Color.slate100
                                )
                                .foregroundStyle(
                                    viewModel.selectedStorageIndex == index
                                        ? .white : Color.slate600
                                )
                                .cornerRadius(20)
                        }
                        .id(storage.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(.white)
            .onChange(of: viewModel.selectedStorageIndex) {
                if let storage = viewModel.selectedStorage {
                    withAnimation { proxy.scrollTo(storage.id, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Expiry Banner

    private var expiryBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange500)
            Text("소비기한 임박 품목 \(viewModel.expiringItemCount)개")
                .font(.caption)
                .foregroundStyle(Color.orange700)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange100)
    }

    // MARK: - Section List

    private var sectionList: some View {
        ScrollView {
            if let storage = viewModel.selectedStorage {
                LazyVStack(spacing: 12) {
                    ForEach(storage.sections) { section in
                        sectionCard(section)
                    }
                }
                .padding(16)
            }
        }
    }

    private func sectionCard(_ section: StorageSection) -> some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsedSections.contains(section.id) {
                        collapsedSections.remove(section.id)
                    } else {
                        collapsedSections.insert(section.id)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: collapsedSections.contains(section.id) ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                        .frame(width: 16)

                    Text(section.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.slate700)

                    Text("\(section.items.count)")
                        .font(.caption2)
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.slate100)
                        .cornerRadius(8)

                    Spacer()

                    Button {
                        viewModel.prepareAddItem(sectionId: section.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(Color.orange500)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Items
            if !collapsedSections.contains(section.id) {
                Divider()
                if section.items.isEmpty {
                    Text("품목이 없습니다")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                        .padding(.vertical, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(section.items) { item in
                            StorageItemRow(
                                item: item,
                                sectionId: section.id,
                                onTap: { viewModel.prepareEditItem(item, sectionId: section.id) },
                                onIncrement: {
                                    Task { await viewModel.updateItemQuantity(item, sectionId: section.id, delta: 1) }
                                },
                                onDecrement: {
                                    if item.quantity <= 1 {
                                        deleteItemTarget = (itemId: item.id, name: item.name)
                                    } else {
                                        Task { await viewModel.updateItemQuantity(item, sectionId: section.id, delta: -1) }
                                    }
                                }
                            )
                            if item.id != section.items.last?.id {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                }
            }
        }
        .background(.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }

    // MARK: - Add Storage Sheet

    private var addStorageSheet: some View {
        NavigationStack {
            Form {
                Section("보관함 이름") {
                    TextField("예: 냉장고", text: $viewModel.storageFormName)
                }
            }
            .navigationTitle("보관함 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { viewModel.showAddStorageSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        Task { await viewModel.createStorage() }
                    }
                    .disabled(viewModel.storageFormName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
