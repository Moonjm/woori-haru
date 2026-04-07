import SwiftUI

struct StorageMainView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = StorageViewModel()
    @State private var collapsedSections: Set<Int> = []
    @State private var deleteItemTarget: (itemId: Int, name: String)?
    @State private var isAddingSectionInline = false
    @State private var inlineSectionName = ""
    @State private var renamingSectionId: Int?
    @State private var renamingSectionName = ""
    @State private var deleteSectionTarget: (sectionId: Int, name: String)?
    @State private var showEditStorageSheet = false
    @State private var editStorageName = ""
    @State private var editStorageType: StorageType = .fridge
    @State private var showDeleteStorageConfirm = false
    @State private var draggingSectionId: Int?
    @State private var draggingStorageId: Int?
    @State private var isExpiryBannerExpanded = false
    @FocusState private var isSectionFieldFocused: Bool
    @FocusState private var isRenameFieldFocused: Bool

    private static let sectionDotColors: [LinearGradient] = [
        LinearGradient(colors: [Color(red: 0.40, green: 0.49, blue: 0.92), Color(red: 0.46, green: 0.30, blue: 0.64)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.26, green: 0.91, blue: 0.48), Color(red: 0.22, green: 0.98, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.98, green: 0.44, blue: 0.60), Color(red: 0.96, green: 0.34, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.96, green: 0.69, blue: 0.10), Color(red: 0.95, green: 0.46, blue: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.31, green: 0.67, blue: 1.0), Color(red: 0.0, green: 0.95, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.63, green: 0.55, blue: 0.82), Color(red: 0.98, green: 0.76, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing),
    ]

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.purple50.ignoresSafeArea())
        .navigationTitle("보관함 관리")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("뒤로")
                    }
                    .foregroundStyle(Color.purple500)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showAddStorageSheet = true
                    viewModel.storageFormName = ""
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.purple500)
                }
            }
        }
        .task {
            await viewModel.loadStorages()
        }
        .sheet(isPresented: $viewModel.showAddStorageSheet) {
            addStorageSheet
        }
        .sheet(isPresented: $showEditStorageSheet) {
            NavigationStack {
                Form {
                    Section("보관함 종류") {
                        Picker("종류", selection: $editStorageType) {
                            ForEach(StorageType.allCases) { type in
                                Text("\(type.emoji) \(type.label)").tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Section("보관함 이름") {
                        TextField("이름", text: $editStorageName)
                    }
                }
                .navigationTitle("보관함 편집")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { showEditStorageSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            let name = editStorageName.trimmingCharacters(in: .whitespaces)
                            let type = editStorageType.rawValue
                            showEditStorageSheet = false
                            Task { await viewModel.updateStorage(name: name, storageType: type) }
                        }
                        .disabled(editStorageName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showAddItemSheet) {
            StorageItemSheet(viewModel: viewModel) {
                viewModel.showAddItemSheet = false
            }
        }
        .alert("보관함 삭제", isPresented: $showDeleteStorageConfirm) {
            Button("삭제", role: .destructive) {
                Task { await viewModel.deleteStorage() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("보관함과 모든 구역, 품목이 삭제됩니다.")
        }
        .alert(
            "구역 삭제",
            isPresented: .init(
                get: { deleteSectionTarget != nil },
                set: { if !$0 { deleteSectionTarget = nil } }
            )
        ) {
            Button("삭제", role: .destructive) {
                if let target = deleteSectionTarget {
                    Task { await viewModel.deleteSection(target.sectionId) }
                }
                deleteSectionTarget = nil
            }
            Button("취소", role: .cancel) { deleteSectionTarget = nil }
        } message: {
            if let target = deleteSectionTarget {
                Text("\(target.name) 구역과 하위 품목이 모두 삭제됩니다.")
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
        .alert("오류", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("확인") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "refrigerator")
                .font(.system(size: 48))
                .foregroundStyle(Color.purple200)
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
            .background(Color.purple500)
            .cornerRadius(10)
            Spacer()
        }
    }

    // MARK: - Tabs

    private var storageTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.storages.enumerated()), id: \.element.id) { index, storage in
                        storageTab(index: index, storage: storage)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(.white)
            .overlay(alignment: .bottom) {
                Divider().foregroundStyle(Color.purple100)
            }
            .onChange(of: viewModel.selectedStorageIndex) {
                if let storage = viewModel.selectedStorage {
                    withAnimation { proxy.scrollTo(storage.id, anchor: .center) }
                }
            }
        }
    }

    private func storageTab(index: Int, storage: Storage) -> some View {
        let isSelected = viewModel.selectedStorageIndex == index
        let typeEmoji = storage.storageType.flatMap { StorageType(rawValue: $0) }?.emoji
        return Button {
            viewModel.selectedStorageIndex = index
        } label: {
            HStack(spacing: 4) {
                if let emoji = typeEmoji {
                    Text(emoji).font(.caption)
                }
                Text(storage.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.purple500.opacity(0.1) : Color.purple100)
                .foregroundStyle(isSelected ? Color.purple500 : Color.slate500)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.purple500.opacity(0.25) : .clear, lineWidth: 1)
                )
        }
        .onDrag {
            draggingStorageId = storage.id
            return NSItemProvider(object: String(storage.id) as NSString)
        }
        .onDrop(of: [.text], delegate: ReorderDropDelegate(
            itemId: storage.id,
            draggingId: $draggingStorageId,
            onMove: { fromId, toId in withAnimation(.easeInOut(duration: 0.2)) { viewModel.moveStorageLocally(fromId: fromId, toId: toId) } },
            onDrop: { targetId in Task { await viewModel.commitStorageOrder(targetId: targetId) } }
        ))
        .contextMenu {
            Button {
                viewModel.selectedStorageIndex = index
                editStorageName = storage.name
                editStorageType = storage.storageType.flatMap { StorageType(rawValue: $0) } ?? .fridge
                showEditStorageSheet = true
            } label: {
                Label("편집", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                viewModel.selectedStorageIndex = index
                showDeleteStorageConfirm = true
            } label: {
                Label("보관함 삭제", systemImage: "trash")
            }
        }
        .id(storage.id)
    }

    // MARK: - Expiry Banner

    private var expiryBanner: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpiryBannerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange500)
                    Text("소비기한 임박 품목 \(viewModel.expiringItemCount)개")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.orange700)
                    Spacer()
                    Image(systemName: isExpiryBannerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Color.orange500)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)

            if isExpiryBannerExpanded {
                VStack(spacing: 0) {
                    let items = viewModel.expiringItems
                    ForEach(Array(items.enumerated()), id: \.element.item.id) { index, entry in
                        HStack(spacing: 10) {
                            InitialIconView(name: entry.item.name, size: 30)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.item.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.slate700)
                                Text(entry.sectionName)
                                    .font(.caption2)
                                    .foregroundStyle(Color.slate400)
                            }

                            Spacer()

                            if let days = StorageViewModel.daysUntilExpiry(entry.item.expiryDate) {
                                Text(days < 0 ? "D+\(-days)" : days == 0 ? "D-Day" : "D-\(days)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(days <= 1 ? Color.red500.opacity(0.1) : Color.orange500.opacity(0.1))
                                    .foregroundStyle(days <= 1 ? Color.red600 : Color.orange700)
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        if index < items.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.orange100.opacity(0.6))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.orange200),
            alignment: .bottom
        )
    }

    // MARK: - Section List

    private var sectionList: some View {
        ScrollView {
            if let storage = viewModel.selectedStorage {
                LazyVStack(spacing: 14) {
                    ForEach(Array(storage.sections.enumerated()), id: \.element.id) { index, section in
                        sectionCard(section, dotIndex: index)
                    }
                    addSectionCard
                }
                .padding(16)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 80)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) * 3, abs(vertical) < 30 else { return }
                    if horizontal < -80, viewModel.selectedStorageIndex < viewModel.storages.count - 1 {
                        withAnimation { viewModel.selectedStorageIndex += 1 }
                    } else if horizontal > 80, viewModel.selectedStorageIndex > 0 {
                        withAnimation { viewModel.selectedStorageIndex -= 1 }
                    }
                }
        )
    }

    // MARK: - Section Card

    private func sectionCard(_ section: StorageSection, dotIndex: Int) -> some View {
        VStack(spacing: 0) {
            if renamingSectionId == section.id {
                sectionRenameHeader(section)
            } else {
                sectionHeader(section, dotIndex: dotIndex)
            }

            if !collapsedSections.contains(section.id) {
                Divider().foregroundStyle(Color.purple100)
                if section.items.isEmpty {
                    Text("품목을 추가해보세요")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                        .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(section.items) { item in
                            StorageItemCell(
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
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.02), lineWidth: 1)
        )
        .onDrag {
            draggingSectionId = section.id
            return NSItemProvider(object: String(section.id) as NSString)
        }
        .onDrop(of: [.text], delegate: ReorderDropDelegate(
            itemId: section.id,
            draggingId: $draggingSectionId,
            onMove: { fromId, toId in withAnimation(.easeInOut(duration: 0.2)) { viewModel.moveSectionLocally(fromId: fromId, toId: toId) } },
            onDrop: { targetId in Task { await viewModel.commitSectionOrder(targetId: targetId) } }
        ))
    }

    private func sectionHeader(_ section: StorageSection, dotIndex: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsedSections.contains(section.id) {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                // Gradient dot
                Circle()
                    .fill(Self.sectionDotColors[dotIndex % Self.sectionDotColors.count])
                    .frame(width: 8, height: 8)

                Text(section.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.slate700)

                Text("\(section.items.count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.slate500)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.purple100)
                    .cornerRadius(8)

                Spacer()

                Button {
                    viewModel.prepareAddItem(sectionId: section.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(Color.purple500)
                }
                .buttonStyle(.plain)

                Image(systemName: collapsedSections.contains(section.id) ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renamingSectionId = section.id
                renamingSectionName = section.name
                isRenameFieldFocused = true
            } label: {
                Label("이름 변경", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleteSectionTarget = (sectionId: section.id, name: section.name)
            } label: {
                Label("구역 삭제", systemImage: "trash")
            }
        }
    }

    private func sectionRenameHeader(_ section: StorageSection) -> some View {
        HStack(spacing: 8) {
            TextField("구역 이름", text: $renamingSectionName)
                .font(.subheadline)
                .focused($isRenameFieldFocused)
                .onSubmit { Task { await submitRenameSection(section) } }

            Button {
                Task { await submitRenameSection(section) }
            } label: {
                Text("저장")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        renamingSectionName.trimmingCharacters(in: .whitespaces).isEmpty
                            || renamingSectionName == section.name
                            ? Color.slate300 : Color.purple500
                    )
                    .cornerRadius(6)
            }
            .disabled(
                renamingSectionName.trimmingCharacters(in: .whitespaces).isEmpty
                    || renamingSectionName == section.name
            )

            Button {
                renamingSectionId = nil
                renamingSectionName = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitRenameSection(_ section: StorageSection) async {
        let name = renamingSectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != section.name else { return }
        viewModel.editingSectionForRename = section
        viewModel.sectionRenameName = name
        await viewModel.updateSectionName()
        renamingSectionId = nil
        renamingSectionName = ""
    }

    // MARK: - Add Section Inline

    private var addSectionCard: some View {
        Group {
            if isAddingSectionInline {
                HStack(spacing: 10) {
                    TextField("구역 이름 입력", text: $inlineSectionName)
                        .font(.subheadline)
                        .focused($isSectionFieldFocused)
                        .onSubmit { Task { await submitInlineSection() } }

                    Button {
                        Task { await submitInlineSection() }
                    } label: {
                        Text("추가")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                inlineSectionName.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.slate300 : Color.purple500
                            )
                            .cornerRadius(6)
                    }
                    .disabled(inlineSectionName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        isAddingSectionInline = false
                        inlineSectionName = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(Color.slate400)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
            } else {
                Button {
                    isAddingSectionInline = true
                    inlineSectionName = ""
                    isSectionFieldFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline)
                        Text("구역 추가")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.purple500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.purple500.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )
                    .background(Color.purple500.opacity(0.02))
                    .cornerRadius(16)
                }
            }
        }
    }

    private func submitInlineSection() async {
        let name = inlineSectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        viewModel.newSectionName = name
        await viewModel.createSection()
        inlineSectionName = ""
        isAddingSectionInline = false
    }

    // MARK: - Add Storage Sheet

    private var addStorageSheet: some View {
        NavigationStack {
            Form {
                Section("보관함 종류") {
                    Picker("종류", selection: $viewModel.storageFormType) {
                        ForEach(StorageType.allCases) { type in
                            Text("\(type.emoji) \(type.label)").tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
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

// MARK: - Drag & Drop

private struct ReorderDropDelegate: DropDelegate {
    let itemId: Int
    @Binding var draggingId: Int?
    let onMove: (Int, Int) -> Void
    let onDrop: (Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingId, dragging != itemId else { return }
        onMove(dragging, itemId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let targetId = draggingId
        draggingId = nil
        if let targetId { onDrop(targetId) }
        return true
    }

    func dropExited(info: DropInfo) {}
    func validateDrop(info: DropInfo) -> Bool { true }
}
