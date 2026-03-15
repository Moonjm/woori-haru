import SwiftUI

struct StatsView: View {
    @Environment(PairStore.self) private var pairStore
    @State private var viewModel = StatsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("\(viewModel.periodLabel) · 총 \(viewModel.totalCount)건")
                        .font(.subheadline)
                        .foregroundStyle(Color.slate600)
                    Spacer()
                }

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

                if pairStore.isPaired {
                    HStack(spacing: 8) {
                        ForEach(RecordFilter.allCases, id: \.self) { filter in
                            Button {
                                viewModel.filterType = filter
                                viewModel.reloadStats()
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background {
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(viewModel.filterType == filter ? Color.blue50 : .white)
                                            .stroke(viewModel.filterType == filter ? Color.blue300 : Color.slate200, lineWidth: 1)
                                    }
                                    .foregroundStyle(viewModel.filterType == filter ? Color.blue700 : Color.slate500)
                            }
                        }
                        Spacer()
                    }
                }

                if viewModel.isLoading {
                    ProgressView().padding(.vertical, 40)
                } else if viewModel.stats.isEmpty {
                    Text("해당 기간에 기록이 없습니다")
                        .font(.subheadline)
                        .foregroundStyle(Color.slate400)
                        .padding(.vertical, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.stats) { stat in
                            StatBarView(stat: stat)
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error).font(.caption).foregroundStyle(Color.red500)
                }
            }
            .padding(16)
        }
        .navigationTitle("통계")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(pairStore: pairStore)
            await viewModel.loadStats()
        }
        .onChange(of: viewModel.selectedYear) { _, _ in viewModel.reloadStats() }
        .onChange(of: viewModel.selectedMonth) { _, _ in viewModel.reloadStats() }
    }
}

struct StatBarView: View {
    let stat: CategoryStat

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                EmojiIconView(emoji: stat.emoji, size: 17)
                Text(stat.name).font(.subheadline)
                Spacer()
                Text("\(stat.count)건").font(.subheadline).fontWeight(.medium)
                Text("\(Int(stat.ratio * 100))%").font(.caption).foregroundStyle(Color.slate500)
            }

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue400)
                    .frame(width: geo.size.width * stat.ratio, height: 8)
            }
            .frame(height: 8)
            .background { RoundedRectangle(cornerRadius: 4).fill(Color.slate100) }
        }
    }
}
