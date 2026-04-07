import SwiftUI

struct ItemCategoryPickerView: View {
    @Binding var selection: ItemCategory
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredGroups: [(group: ItemGroup, categories: [ItemCategory])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return ItemGroup.allCases.compactMap { group in
            let cats: [ItemCategory]
            if query.isEmpty {
                cats = group.categories
            } else {
                cats = group.categories.filter {
                    $0.label.lowercased().contains(query) || group.label.lowercased().contains(query)
                }
            }
            return cats.isEmpty ? nil : (group: group, categories: cats)
        }
    }

    var body: some View {
        List {
            ForEach(filteredGroups, id: \.group.id) { entry in
                Section(entry.group.label) {
                    ForEach(entry.categories) { cat in
                        Button {
                            selection = cat
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Text(cat.emoji)
                                    .font(.title3)
                                    .frame(width: 32)

                                Text(cat.label)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.slate700)

                                Spacer()

                                if cat == selection {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.purple500)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if filteredGroups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "카테고리 검색")
        .navigationTitle("카테고리 선택")
        .navigationBarTitleDisplayMode(.inline)
    }
}
