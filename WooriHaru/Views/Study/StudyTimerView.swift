import SwiftUI

private let narrowProgressThreshold = 0.11

struct StudyTimerView: View {
    @Environment(StudyTimerViewModel.self) private var vm
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isAlarmFieldFocused: Bool
    @FocusState private var isGoalFieldFocused: Bool

    var body: some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(spacing: 20) {
                timerCard
                todaySummaryCard
                dailyGoalCard
                weeklyGoalCard
                todayTimelineSection
                todaySessionsSection
            }
            .padding(20)
        }
        .background(Color.slate50)
        .onTapGesture { isAlarmFieldFocused = false; isGoalFieldFocused = false }
        .navigationTitle("공부 타이머")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let subjects: () = vm.loadSubjects()
            async let sessions: () = vm.loadTodaySessions()
            async let goal: () = vm.loadDailyGoal()
            async let weekly: () = vm.loadWeeklySummary()
            _ = await (subjects, sessions, goal, weekly)
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

    // MARK: - Timer Card

    private var timerCard: some View {
        VStack(spacing: 16) {
            // 상태 표시
            timerStatusBadge

            // 진행 중이면 과목명만, idle이면 과목 선택 UI
            if vm.timerState != .idle {
                if let subject = vm.selectedSubject {
                    Text(subject.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.slate900)
                }
            }

            // 타이머 숫자
            Text(vm.elapsedFormatted)
                .font(.system(size: 60, weight: .light, design: .monospaced))
                .foregroundStyle(timerNumberColor)
                .contentTransition(.numericText())

            // idle 상태에서 과목 선택
            if vm.timerState == .idle {
                subjectSelectionInTimer
            }

            // 알림 설정
            alarmIntervalSection

            // 액션 버튼
            timerButtons
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(timerCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var timerStatusBadge: some View {
        switch vm.timerState {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green300)
                    .frame(width: 8, height: 8)
                Text("공부 중")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.green700)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green100)
            .clipShape(Capsule())
        case .paused:
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange300)
                    .frame(width: 8, height: 8)
                Text("일시정지됨")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange700)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange200)
            .clipShape(Capsule())
        }
    }

    private var subjectSelectionInTimer: some View {
        VStack(spacing: 10) {
            if vm.subjects.isEmpty {
                Button {
                    vm.showAddSubject = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("과목 추가")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.blue500)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(vm.subjects) { subject in
                        subjectChip(subject)
                    }
                    Button {
                        vm.showAddSubject = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                            .foregroundStyle(Color.slate400)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.slate50)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var timerNumberColor: Color {
        switch vm.timerState {
        case .idle: return Color.slate900
        case .running: return Color.blue600
        case .paused: return Color.slate400
        }
    }

    private var timerCardBackground: Color {
        .white
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
                Label("공부 시작", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(vm.selectedSubject != nil ? Color.blue500 : Color.slate200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(vm.selectedSubject == nil || vm.isLoading)

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
                .disabled(vm.isLoading)
                endButton
            }

        case .paused:
            HStack(spacing: 12) {
                Button {
                    Task { await vm.resume() }
                } label: {
                    Label("다시 시작", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.green700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green100)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(vm.isLoading)
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
        .disabled(vm.isLoading)
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
        .padding(10)
        .background(Color.slate50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Today Summary Card

    private var todaySummaryCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("오늘 공부")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.slate400)
                Text(vm.todayTotalFormatted)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.slate900)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 4) {
                Text("세션")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.slate400)
                Text("\(vm.todaySessionCount)회")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.slate900)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Daily Goal Card

    private var dailyGoalCard: some View {
        @Bindable var vm = vm
        return VStack(spacing: 10) {
            HStack {
                Text("오늘 목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Spacer()
                HStack(spacing: 6) {
                    TextField("0", text: $vm.dailyGoalText)
                        .keyboardType(.numberPad)
                        .focused($isGoalFieldFocused)
                        .font(.caption)
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.slate200, lineWidth: 1))
                    Text("시간")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                    Button {
                        isGoalFieldFocused = false
                        Task { await vm.saveDailyGoal() }
                    } label: {
                        Text("저장")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue500)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            goalProgressBar(
                progress: vm.goalProgress,
                progressClamped: vm.goalProgressClamped,
                percentText: vm.goalPercentText
            )

            HStack {
                Text(vm.todayTotalFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                if let goalText = vm.dailyGoalFormatted {
                    Text(goalText)
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Weekly Goal Card

    private var weeklyGoalCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("이번 주 목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Spacer()
            }

            goalProgressBar(
                progress: vm.weeklyGoalProgress,
                progressClamped: vm.weeklyGoalProgressClamped,
                percentText: vm.weeklyGoalPercentText
            )

            HStack {
                Text(vm.weeklyTotalActualFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                if let goalText = vm.weeklyGoalFormatted {
                    Text(goalText)
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Shared Progress Bar

    private func goalProgressBar(progress: Double, progressClamped: Double, percentText: String) -> some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * progressClamped
            let isNarrow = progressClamped < narrowProgressThreshold
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.slate100)
                    .frame(height: 28)
                RoundedRectangle(cornerRadius: 12)
                    .fill(progress >= 1.0 ? Color.green300 : Color.blue400)
                    .frame(width: barWidth, height: 28)
                    .overlay {
                        if !isNarrow {
                            Text(percentText)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: progressClamped)
                if isNarrow {
                    Text(percentText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.slate400)
                        .offset(x: barWidth + 8)
                }
            }
        }
        .frame(height: 28)
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

    // MARK: - Today Timeline

    private var todayTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘 공부 흐름")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)

            if vm.todaySessions.isEmpty && vm.timerState == .idle {
                Text("아직 기록이 없습니다")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(vm.todaySessions) { session in
                        timelineBar(session)
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func timelineBar(_ session: StudySession) -> some View {
        let startText = formatTime(session.startedAt)
        let endText = session.endedAt.map { formatTime($0) } ?? "진행중"
        let durationText = session.totalSeconds.durationText

        return HStack(spacing: 10) {
            Text("\(startText)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.slate400)
                .frame(width: 38, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.blue400)
                .frame(height: 8)

            Text("\(endText)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.slate400)
                .frame(width: 38, alignment: .leading)

            Spacer()

            Text(durationText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.blue600)
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
                NavigationLink(value: AppDestination.studyRecord) {
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
            Text(session.totalSeconds.durationText)
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
}
