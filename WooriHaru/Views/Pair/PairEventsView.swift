import SwiftUI

struct PairEventsView: View {
    @State private var viewModel = PairEventsViewModel()
    @State private var deleteTarget: PairEvent?

    var body: some View {
        VStack(spacing: 0) {
            // 생성 폼
            GlassCard {
                VStack(spacing: 12) {
                    Text("새 기념일")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        TextField("😀", text: $viewModel.newEmoji)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 10)
                            .frame(width: 50)
                            .glassInputField()
                            .onChange(of: viewModel.newEmoji) { _, newValue in
                                if newValue.count > 1 { viewModel.newEmoji = String(newValue.prefix(1)) }
                            }

                        TextField("제목", text: $viewModel.newTitle)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassInputField()
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .appGlassProminentButton()
                }
                .font(.subheadline)
            }
            .padding(16)

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
                        Button {
                            Task { await viewModel.toggleBadge(for: event) }
                        } label: {
                            Image(systemName: viewModel.badgeEventId == event.id
                                  ? "app.badge.checkmark.fill" : "app.badge")
                                .font(.body)
                                .foregroundStyle(viewModel.badgeEventId == event.id
                                                 ? Color.blue600 : Color.slate500)
                        }
                        .buttonStyle(.plain)
                        if event.recurring {
                            Text("🔄 매년")
                                .font(.caption2)
                                .foregroundStyle(Color.blue600)
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        deleteTarget = viewModel.events[index]
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .glassScreenBackground()
        .navigationTitle("기념일 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadEvents() }
        .alert(
            "기념일 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("취소", role: .cancel) { deleteTarget = nil }
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
        .alert("알림 권한 필요", isPresented: $viewModel.showBadgePermissionAlert) {
            Button("설정으로 이동") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("D-Day 뱃지를 표시하려면 설정에서 알림과 배지를 허용해주세요.")
        }
    }
}
