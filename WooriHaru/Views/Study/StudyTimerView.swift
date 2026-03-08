import SwiftUI

struct StudyTimerView: View {
    @State private var vm = StudyTimerViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                timerSection
                subjectSection
                todaySessionsSection
            }
            .padding(20)
        }
        .background(Color.slate50)
        .navigationTitle("공부 타이머")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadSubjects()
            await vm.loadTodaySessions()
        }
        .alert("과목 추가", isPresented: $vm.showAddSubject) {
            TextField("과목명", text: $vm.newSubjectName)
            Button("추가") { Task { await vm.addSubject() } }
            Button("취소", role: .cancel) { vm.newSubjectName = "" }
        }
        .alert("과목 수정", isPresented: .init(
            get: { vm.editingSubject != nil },
            set: { if !$0 { vm.editingSubject = nil } }
        )) {
            TextField("과목명", text: $vm.editSubjectName)
            Button("수정") { Task { await vm.updateSubject() } }
            Button("취소", role: .cancel) { vm.editingSubject = nil }
        }
    }

    // MARK: - Timer Section

    private var timerSection: some View {
        VStack(spacing: 16) {
            if let subject = vm.selectedSubject, vm.timerState != .idle {
                Text(subject.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.slate500)
            }

            Text(vm.elapsedFormatted)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(Color.slate900)

            Text("오늘 총 \(vm.todayTotalFormatted)")
                .font(.caption)
                .foregroundStyle(Color.slate400)

            timerButtons
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var timerButtons: some View {
        switch vm.timerState {
        case .idle:
            Button {
                Task { await vm.start() }
            } label: {
                Label("시작", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(vm.selectedSubject != nil ? Color.blue500 : Color.slate200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(vm.selectedSubject == nil)

        case .running:
            HStack(spacing: 12) {
                Button {
                    Task { await vm.pause() }
                } label: {
                    Label("일시정지", systemImage: "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.orange700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Task { await vm.end() }
                } label: {
                    Label("종료", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red400.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

        case .paused:
            HStack(spacing: 12) {
                Button {
                    Task { await vm.resume() }
                } label: {
                    Label("재개", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.green700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green100)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Task { await vm.end() }
                } label: {
                    Label("종료", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red400.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Subject Section

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("과목")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Spacer()
                Button {
                    vm.showAddSubject = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.blue500)
                }
                .disabled(vm.timerState != .idle)
            }

            if vm.subjects.isEmpty {
                Text("과목을 추가해 주세요")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(vm.subjects) { subject in
                        subjectChip(subject)
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func subjectChip(_ subject: StudySubject) -> some View {
        let isSelected = vm.selectedSubject?.id == subject.id

        return Button {
            if vm.timerState == .idle {
                vm.selectedSubject = isSelected ? nil : subject
            }
        } label: {
            Text(subject.name)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .white : Color.slate700)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.blue500 : Color.slate100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(vm.timerState != .idle)
        .contextMenu {
            if vm.timerState == .idle {
                Button {
                    vm.editingSubject = subject
                    vm.editSubjectName = subject.name
                } label: {
                    Label("수정", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task { await vm.deleteSubject(subject) }
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Today Sessions

    private var todaySessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘 기록")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)

            if vm.todaySessions.isEmpty && vm.timerState == .idle {
                Text("아직 기록이 없습니다")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(vm.todaySessions) { session in
                    sessionRow(session)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sessionRow(_ session: StudySession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.subject.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.slate900)
                Text(sessionTimeRange(session))
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
            Spacer()
            Text(formatSeconds(session.totalSeconds))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.blue600)
        }
        .padding(12)
        .background(Color.slate50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func sessionTimeRange(_ session: StudySession) -> String {
        let start = formatTime(session.startedAt)
        let end = session.endedAt.map { formatTime($0) } ?? "진행중"
        return "\(start) - \(end)"
    }

    private func formatTime(_ isoString: String) -> String {
        let parts = isoString.split(separator: "T")
        guard parts.count == 2 else { return isoString }
        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count >= 2 else { return String(parts[1]) }
        return "\(timeParts[0]):\(timeParts[1])"
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return String(format: "%d시간 %d분", h, m)
        }
        return String(format: "%d분", m)
    }
}
