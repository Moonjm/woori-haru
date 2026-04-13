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
    @FocusState private var isSectionFieldFocused: Bool
    @FocusState private var isRenameFieldFocused: Bool

    private static let sectionAccentColors: [Color] = [
        Color.blue400,
        Color.green600,
        Color.red400,
        Color.orange500,
        Color.blue300,
        Color.purple400,
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if viewModel.storages.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    storageTabs
                    expiryPills
                    sectionList
                }
            }

            if viewModel.isMutating {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                ProgressView()
                    .tint(Color.slate500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.slate50.ignoresSafeArea())
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
                    .foregroundStyle(Color.slate700)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showAddStorageSheet = true
                    viewModel.storageFormName = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.slate600)
                        .frame(width: 34, height: 34)
                        .background(Color.white)
                        .cornerRadius(17)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
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
            editStorageSheetView
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
                .foregroundStyle(Color.slate200)
            Text("보관함이 없습니다")
                .font(.subheadline)
                .foregroundStyle(Color.slate400)
            Button("보관함 추가") {
                viewModel.showAddStorageSheet = true
                viewModel.storageFormName = ""
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.slate700)
            .cornerRadius(10)
            Spacer()
        }
    }

    // MARK: - Tabs

    private var storageTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.storages, id: \.id) { storage in
                        storageTab(storage: storage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(.white)
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
            .onChange(of: viewModel.selectedStorageId) {
                if let id = viewModel.selectedStorageId {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func storageTab(storage: Storage) -> some View {
        let isSelected = viewModel.selectedStorageId == storage.id
        let typeEmoji = storage.storageType.flatMap { StorageType(rawValue: $0) }?.emoji
        return Button {
            viewModel.selectedStorageId = storage.id
        } label: {
            HStack(spacing: 5) {
                if let emoji = typeEmoji {
                    Text(emoji).font(.caption)
                }
                Text(storage.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.slate700 : Color.slate100)
            .foregroundStyle(isSelected ? .white : Color.slate500)
            .cornerRadius(20)
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
                viewModel.selectedStorageId = storage.id
                editStorageName = storage.name
                editStorageType = storage.storageType.flatMap { StorageType(rawValue: $0) } ?? .fridge
                showEditStorageSheet = true
            } label: {
                Label("편집", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                viewModel.selectedStorageId = storage.id
                showDeleteStorageConfirm = true
            } label: {
                Label("보관함 삭제", systemImage: "trash")
            }
        }
        .id(storage.id)
    }

    // MARK: - Expiry Summary Pills

    private var expiryPills: some View {
        let s = viewModel.expirySummary

        return HStack(spacing: 8) {
            Text("총 \(s.total)개")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.slate600)

            Spacer()

            if s.expired > 0 {
                expiryPill(color: Color.red500, bgColor: Color(red: 1.0, green: 0.93, blue: 0.93), label: "만료", count: s.expired)
            }
            if s.imminent > 0 {
                expiryPill(color: Color.orange500, bgColor: Color.orange100, label: "임박", count: s.imminent)
            }
            expiryPill(color: Color.green600, bgColor: Color.green100, label: "여유", count: s.safe)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.white)
    }

    private func expiryPill(color: Color, bgColor: Color, label: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(bgColor)
        .cornerRadius(14)
    }

    // MARK: - Section List

    private var sectionList: some View {
        ScrollView {
            if let storage = viewModel.selectedStorage {
                LazyVStack(spacing: 10) {
                    ForEach(Array(storage.sections.enumerated()), id: \.element.id) { index, section in
                        sectionCard(section, dotIndex: index)
                    }
                    addSectionCard
                }
                .padding(14)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 80)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) * 2.5, abs(vertical) < 50 else { return }
                    guard let currentIndex = viewModel.selectedStorageIndex else { return }
                    if horizontal < -80, currentIndex < viewModel.storages.count - 1 {
                        withAnimation { viewModel.selectedStorageId = viewModel.storages[currentIndex + 1].id }
                    } else if horizontal > 80, currentIndex > 0 {
                        withAnimation { viewModel.selectedStorageId = viewModel.storages[currentIndex - 1].id }
                    }
                }
        )
    }

    // MARK: - Section Card

    private func sectionCard(_ section: StorageSection, dotIndex: Int) -> some View {
        let accentColor = Self.sectionAccentColors[dotIndex % Self.sectionAccentColors.count]

        return VStack(spacing: 0) {
            if renamingSectionId == section.id {
                sectionRenameHeader(section)
            } else {
                sectionHeader(section, dotIndex: dotIndex, accentColor: accentColor)
            }

            if !collapsedSections.contains(section.id) {
                if section.items.isEmpty {
                    HStack {
                        Text("품목을 추가해보세요")
                            .font(.caption)
                            .foregroundStyle(Color.slate300)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                } else {
                    Rectangle()
                        .fill(Color.slate100)
                        .frame(height: 1)
                        .padding(.leading, 18)

                    VStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
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

                            if index < section.items.count - 1 {
                                Rectangle()
                                    .fill(Color.slate100)
                                    .frame(height: 1)
                                    .padding(.leading, 82)
                            }
                        }
                    }
                }
            }
        }
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: collapsedSections.contains(section.id) ? 16 : (section.items.isEmpty ? 16 : 0),
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(accentColor)
            .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

    private func sectionHeader(_ section: StorageSection, dotIndex: Int, accentColor: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsedSections.contains(section.id) {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(section.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate700)

                Text("\(section.items.count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.1))
                    .cornerRadius(8)

                Spacer()

                Button {
                    viewModel.prepareAddItem(sectionId: section.id)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(accentColor.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Image(systemName: collapsedSections.contains(section.id) ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.slate300)
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
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
                            ? Color.slate300 : Color.slate700
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
                                    ? Color.slate300 : Color.slate700
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white)
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
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
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.slate200, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )
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

    // MARK: - Edit Storage Sheet

    private var editStorageSheetView: some View {
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
