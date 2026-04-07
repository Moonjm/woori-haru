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

                    HStack {
                        Text("수량")
                        Spacer()
                        HStack(spacing: 12) {
                            Button {
                                if viewModel.itemFormQuantity > 1 {
                                    viewModel.itemFormQuantity -= 1
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(viewModel.itemFormQuantity <= 1 ? Color.slate300 : Color.orange300)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.itemFormQuantity <= 1)

                            TextField("", value: Binding(
                                get: { viewModel.itemFormQuantity },
                                set: { viewModel.itemFormQuantity = max(1, min(999, $0)) }
                            ), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 50)
                                .padding(.vertical, 4)
                                .background(Color.slate100)
                                .cornerRadius(6)

                            Button {
                                if viewModel.itemFormQuantity < 999 {
                                    viewModel.itemFormQuantity += 1
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(viewModel.itemFormQuantity >= 999 ? Color.slate300 : Color.orange300)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.itemFormQuantity >= 999)
                        }
                    }

                    Toggle("소비기한 설정", isOn: Binding(
                        get: { viewModel.itemFormExpiryDate != nil },
                        set: { viewModel.itemFormExpiryDate = $0 ? Date() : nil }
                    ))

                    if let binding = Binding($viewModel.itemFormExpiryDate) {
                        DatePicker("소비기한", selection: binding, displayedComponents: .date)
                    }
                }

                Section("카테고리") {
                    NavigationLink {
                        ItemCategoryPickerView(selection: $viewModel.itemFormCategory)
                    } label: {
                        HStack {
                            Text("카테고리")
                            Spacer()
                            Text("\(viewModel.itemFormCategory.emoji) \(viewModel.itemFormCategory.label)")
                                .foregroundStyle(Color.slate500)
                        }
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
