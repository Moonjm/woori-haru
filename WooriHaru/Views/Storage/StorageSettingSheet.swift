import SwiftUI

struct StorageSettingSheet: View {
    @Bindable var viewModel: StorageViewModel
    let onDismiss: () -> Void
    @State private var editingName: String = ""
    @State private var showDeleteConfirm = false
    @State private var showDeleteSectionConfirm: Int?

    var body: some View {
        NavigationStack {
            Form {
                if let storage = viewModel.selectedStorage {
                    Section("보관함 이름") {
                        HStack {
                            TextField("이름", text: $editingName)
                            Button("저장") {
                                Task { await viewModel.updateStorageName(editingName) }
                            }
                            .disabled(editingName.trimmingCharacters(in: .whitespaces).isEmpty || editingName == storage.name)
                        }
                    }

                    Section("구역 관리") {
                        ForEach(storage.sections) { section in
                            HStack {
                                if viewModel.editingSectionForRename?.id == section.id {
                                    TextField("이름", text: $viewModel.sectionRenameName)
                                    Button("저장") {
                                        Task { await viewModel.updateSectionName() }
                                    }
                                    Button("취소") {
                                        viewModel.editingSectionForRename = nil
                                    }
                                } else {
                                    Text(section.name)
                                    Spacer()
                                    Button {
                                        viewModel.editingSectionForRename = section
                                        viewModel.sectionRenameName = section.name
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(Color.slate500)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        showDeleteSectionConfirm = section.id
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(Color.red400)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        HStack {
                            TextField("새 구역 이름", text: $viewModel.newSectionName)
                            Button("추가") {
                                Task { await viewModel.createSection() }
                            }
                            .disabled(viewModel.newSectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    Section {
                        Button("보관함 삭제", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle("보관함 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { onDismiss() }
                }
            }
            .onAppear {
                editingName = viewModel.selectedStorage?.name ?? ""
            }
            .alert("보관함 삭제", isPresented: $showDeleteConfirm) {
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
                    get: { showDeleteSectionConfirm != nil },
                    set: { if !$0 { showDeleteSectionConfirm = nil } }
                )
            ) {
                Button("삭제", role: .destructive) {
                    if let id = showDeleteSectionConfirm {
                        Task { await viewModel.deleteSection(id) }
                    }
                    showDeleteSectionConfirm = nil
                }
                Button("취소", role: .cancel) { showDeleteSectionConfirm = nil }
            } message: {
                Text("구역과 하위 품목이 모두 삭제됩니다.")
            }
        }
    }
}
