import SwiftUI

struct StudyTimerView: View {
    @Environment(StudyTimerViewModel.self) private var vm
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isAlarmFieldFocused: Bool

    var body: some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(spacing: 24) {
                timerSection
                dailyGoalSection
                subjectSection
                todaySessionsSection
            }
            .padding(20)
        }
        .background(Color.slate50)
        .onTapGesture { isAlarmFieldFocused = false }
        .navigationTitle("공부 타이머")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadSubjects()
            await vm.loadTodaySessions()
            await vm.loadDailyGoal()
            await vm.restoreActiveSession()
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
        .alert("목표 시간 설정", isPresented: $vm.showGoalEdit) {
            TextField("시간", text: $vm.dailyGoalText)
                .keyboardType(.decimalPad)
            Button("저장") { Task { await vm.saveDailyGoal() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("오늘 목표 공부 시간을 입력해 주세요")
        }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                vm.syncOnForeground()
            }
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

            alarmIntervalSection

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
                isAlarmFieldFocused = false
                vm.saveAlarmInterval()
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
                endButton
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
                endButton
            }
        }
    }

    private var endButton: some View {
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

    // MARK: - Alarm Interval

    private var alarmIntervalSection: some View {
        @Bindable var vm = vm
        return HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .foregroundStyle(Color.blue500)
                .font(.caption)

            TextField("분", text: $vm.alarmIntervalText)
                .keyboardType(.numberPad)
                .focused($isAlarmFieldFocused)
                .font(.caption)
                .frame(width: 40)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.slate200, lineWidth: 1))
                .onChange(of: isAlarmFieldFocused) {
                    if !isAlarmFieldFocused {
                        vm.saveAlarmInterval()
                    }
                }
                .disabled(vm.timerState != .idle)

            Text("분마다 알림")
                .font(.caption)
                .foregroundStyle(Color.slate500)
        }
        .padding(12)
        .background(Color.slate50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Daily Goal Section

    private var dailyGoalSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("오늘 목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Spacer()
                if vm.dailyGoalMinutes > 0 {
                    Text(vm.goalPercentText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(vm.goalProgress >= 1.0 ? Color.green700 : Color.blue500)
                }
                Button {
                    vm.dailyGoalText = vm.dailyGoalMinutes > 0
                        ? vm.goalMinutesToHoursText(vm.dailyGoalMinutes) : ""
                    vm.showGoalEdit = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(Color.blue500)
                }
            }

            if vm.dailyGoalMinutes > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.slate100)
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(vm.goalProgress >= 1.0 ? Color.green300 : Color.blue500)
                                .frame(width: geo.size.width * vm.goalProgressClamped, height: 12)
                                .animation(.easeInOut(duration: 0.3), value: vm.goalProgressClamped)
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text(vm.todayTotalFormatted)
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                        Spacer()
                        let h = vm.dailyGoalMinutes / 60
                        let m = vm.dailyGoalMinutes % 60
                        Text(h > 0 ? (m > 0 ? "\(h)시간 \(m)분" : "\(h)시간") : "\(m)분")
                            .font(.caption)
                            .foregroundStyle(Color.slate400)
                    }
                }
            } else {
                Text("목표 시간을 설정해 주세요")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
            HStack {
                Text("오늘 기록")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Spacer()
                NavigationLink(value: AppDestination.studySessionLog) {
                    HStack(spacing: 4) {
                        Text("전체 기록")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.blue500)
                }
            }

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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formatTime(_ isoString: String) -> String {
        if let date = Date.fromISO(isoString) {
            return Self.timeFormatter.string(from: date)
        }
        return "??:??"
    }

    private func formatSeconds(_ seconds: Int) -> String {
        seconds.durationText
    }
}
