import SwiftUI

struct SearchView: View {
    @Environment(CategoryStore.self) private var categoryStore
    @State private var viewModel = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 필터 영역
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Picker("연도", selection: $viewModel.selectedYear) {
                        ForEach(2018...Calendar.current.component(.year, from: Date()) + 1, id: \.self) { year in
                            Text("\(String(year))년").tag(year)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("월", selection: $viewModel.selectedMonth) {
                        Text("전체").tag(0)
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)월").tag(month)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                HStack(spacing: 12) {
                    Menu {
                        Button("전체") { viewModel.selectedCategoryId = nil; viewModel.applyFilters() }
                        ForEach(categoryStore.categories) { cat in
                            Button("\(cat.emoji) \(cat.name)") {
                                viewModel.selectedCategoryId = cat.id
                                viewModel.applyFilters()
                            }
                        }
                    } label: {
                        HStack {
                            if let catId = viewModel.selectedCategoryId,
                               let cat = categoryStore.categories.first(where: { $0.id == catId }) {
                                Text("\(cat.emoji) \(cat.name)")
                            } else {
                                Text("전체 카테고리")
                            }
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.slate700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.slate200, lineWidth: 1)
                        }
                    }

                    TextField("키워드 검색", text: $viewModel.keyword)
                        .font(.subheadline)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.keyword) { _, _ in
                            viewModel.applyFilters()
                        }
                }
            }
            .padding(16)
            .background(.white)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView().padding(.vertical, 40)
                    } else if viewModel.results.isEmpty {
                        Text("검색 결과가 없습니다")
                            .font(.subheadline)
                            .foregroundStyle(Color.slate400)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(viewModel.results) { record in
                            SearchResultCard(record: record)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("검색")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(categoryStore: categoryStore)
            await viewModel.loadInitial()
        }
        .onChange(of: viewModel.selectedYear) { _, _ in viewModel.reloadSearch() }
        .onChange(of: viewModel.selectedMonth) { _, _ in viewModel.reloadSearch() }
    }
}

struct SearchResultCard: View {
    let record: DailyRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                if record.together {
                    Text("👫 같이")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue50)
                        .foregroundStyle(Color.blue600)
                        .cornerRadius(10)
                }
            }

            HStack(spacing: 6) {
                Text(record.category.emoji)
                Text(record.category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let memo = record.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .stroke(Color.slate200, lineWidth: 1)
        }
    }

    private var formattedDate: String {
        guard let date = Date.from(record.date) else { return record.date }
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let weekday = weekdays[date.weekday - 1]
        return "\(date.month)월 \(date.day)일 \(weekday)"
    }
}
