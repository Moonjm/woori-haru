import SwiftUI

struct StudySessionLogView: View {
    @State private var vm = StudySessionLogViewModel()
    @State private var hasScrolledToToday = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 과거 로딩 트리거
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await vm.loadPastIfNeeded() }
                        }

                    ForEach(vm.dayEntries) { entry in
                        dayRow(entry)
                            .id(entry.id)
                    }

                    // 미래 로딩 트리거
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await vm.loadFutureIfNeeded() }
                        }
                }
                .padding(.vertical, 8)
            }
            .background(Color.white)
            .task {
                await vm.loadInitial()
                scrollToToday(proxy: proxy)
            }
            .onChange(of: vm.dayEntries.count) {
                if !hasScrolledToToday {
                    scrollToToday(proxy: proxy)
                }
            }
        }
        .navigationTitle("공부 기록")
        .navigationBarTitleDisplayMode(.inline)
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Day Row

    private func dayRow(_ entry: DayEntry) -> some View {
        let isToday = entry.date.isToday

        return HStack(alignment: .top, spacing: 0) {
            // 왼쪽: 날짜 + 요일
            VStack(spacing: 2) {
                Text("\(entry.date.day)")
                    .font(.title3.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.blue500 : Color.slate900)
                Text(weekdayShort(entry.date))
                    .font(.caption2)
                    .foregroundStyle(isToday ? Color.blue500 : Color.slate400)
            }
            .frame(width: 44)
            .padding(.top, 4)

            // 구분선
            Rectangle()
                .fill(Color.slate100)
                .frame(width: 1)
                .padding(.vertical, 4)

            // 오른쪽: 세션 블록들
            VStack(spacing: 6) {
                if entry.sessions.isEmpty {
                    Color.clear.frame(height: 32)
                } else {
                    ForEach(entry.sessions) { session in
                        sessionBlock(session)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Session Block

    private func sessionBlock(_ session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.subject.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text(sessionTimeRange(session))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue500)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func weekdayShort(_ date: Date) -> String {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return symbols[date.weekday - 1]
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "a h:mm"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    private func sessionTimeRange(_ session: StudySession) -> String {
        let start = Date.fromISO(session.startedAt).map { Self.timeFormatter.string(from: $0) } ?? "??:??"
        let end = session.endedAt.flatMap { Date.fromISO($0) }.map { Self.timeFormatter.string(from: $0) } ?? "진행중"
        return "\(start) - \(end)"
    }

    private func scrollToToday(proxy: ScrollViewProxy) {
        if let index = vm.todayEntryIndex() {
            let id = vm.dayEntries[index].id
            proxy.scrollTo(id, anchor: .center)
            hasScrolledToToday = true
        }
    }
}
