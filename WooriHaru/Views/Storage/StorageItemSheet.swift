import SwiftUI

struct StorageItemSheet: View {
    @Bindable var viewModel: StorageViewModel
    let onDismiss: () -> Void

    private var isEditing: Bool { viewModel.editingItem != nil }
    private var sections: [StorageSection] { viewModel.selectedStorage?.sections ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section("품목 정보") {
                    TextField("이름", text: $viewModel.itemFormName)

                    Stepper("수량: \(viewModel.itemFormQuantity)", value: $viewModel.itemFormQuantity, in: 1...999)

                    Toggle("소비기한 설정", isOn: Binding(
                        get: { viewModel.itemFormExpiryDate != nil },
                        set: { viewModel.itemFormExpiryDate = $0 ? Date() : nil }
                    ))

                    if let binding = Binding($viewModel.itemFormExpiryDate) {
                        DatePicker("소비기한", selection: binding, displayedComponents: .date)
                    }
                }

                if sections.count > 1 {
                    Section("구역") {
                        Picker("구역", selection: $viewModel.itemFormSectionId) {
                            ForEach(sections) { section in
                                Text(section.name).tag(Optional(section.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle(isEditing ? "품목 수정" : "품목 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task {
                            await viewModel.saveItem()
                        }
                    }
                    .disabled(viewModel.itemFormName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
