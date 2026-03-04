import SwiftUI

struct PairEventsView: View {
    @State private var viewModel = PairEventsViewModel()
    @State private var deleteTarget: PairEvent?

    var body: some View {
        VStack(spacing: 0) {
            // 생성 폼
            VStack(spacing: 12) {
                Text("새 기념일")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    TextField("😀", text: $viewModel.newEmoji)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.newEmoji) { _, newValue in
                            if newValue.count > 1 { viewModel.newEmoji = String(newValue.prefix(1)) }
                        }

                    TextField("제목", text: $viewModel.newTitle)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.newTitle) { _, newValue in
                            if newValue.count > 30 { viewModel.newTitle = String(newValue.prefix(30)) }
                        }
                }

                HStack {
                    DatePicker("날짜", selection: $viewModel.newDate, displayedComponents: .date)
                        .labelsHidden()

                    Toggle("매년 반복", isOn: $viewModel.newRecurring)
                        .font(.caption)
                }

                Button {
                    Task { await viewModel.createEvent() }
                } label: {
                    Text("추가")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
            .font(.subheadline)

            Divider()

            // Messages
            if let success = viewModel.successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(Color.green700)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red500)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Event list
            List {
                ForEach(viewModel.events) { event in
                    HStack(spacing: 10) {
                        Text(event.emoji).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline)
                            Text(event.eventDate)
                                .font(.caption)
                                .foregroundStyle(Color.slate500)
                        }
                        Spacer()
                        if event.recurring {
                            Text("🔄 매년")
                                .font(.caption2)
                                .foregroundStyle(Color.blue600)
                        }
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        deleteTarget = viewModel.events[index]
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("기념일 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadEvents() }
        .confirmationDialog(
            "기념일 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let target = deleteTarget {
                    Task { await viewModel.deleteEvent(target) }
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("\(target.emoji) \(target.title)을(를) 삭제할까요?")
            }
        }
    }
}
