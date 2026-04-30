import SwiftUI

private let narrowProgressThreshold = 0.11
private let progressBarHeight: CGFloat = 28
private let progressBarCornerRadius: CGFloat = 12

struct StudyTimerView: View {
    @Environment(StudyTimerViewModel.self) private var vm
    @Environment(SubjectStore.self) private var subjectStore
    @Environment(PauseTypeStore.self) private var pauseTypeStore
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isAlarmFieldFocused: Bool
    @State private var selectedSegmentKey: String?
    @State private var showEarlyPauseConfirm = false
    @State private var showEarlyEndConfirm = false

    var body: some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(spacing: 20) {
                timerCard
                todaySummaryCard
                weeklyGoalCard
                todayTimelineSection
                todaySessionsSection
            }
            .padding(20)
        }
        .background(Color.slate50)
        .onTapGesture { isAlarmFieldFocused = false; selectedSegmentKey = nil }
        .navigationTitle("공부 타이머")
        .navigationBarTitleDisplayMode(.inline)
        .task { @MainActor in
            let vm = self.vm
            vm.configure(subjectStore: subjectStore, pauseTypeStore: pauseTypeStore)
            async let subjects: () = vm.loadSubjects()
            async let sessions: () = vm.loadTodaySessions()
            async let weekly: () = vm.loadWeeklySummary()
            async let pauseTypes: () = vm.loadPauseTypes()
            _ = await (subjects, sessions, weekly, pauseTypes)
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
            Button("수정") {
                let subject = vm.editingSubject
                let name = vm.editSubjectName
                Task {
                    guard let subject else { return }
                    await vm.updateSubjectById(subject.id, name: name)
                }
            }
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
        .alert("확인", isPresented: $showEarlyPauseConfirm) {
            Button("일시정지", role: .destructive) { Task { await vm.pause() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("아직 1분이 지나지 않았습니다.\n정말 일시정지하시겠습니까?")
        }
        .alert("확인", isPresented: $showEarlyEndConfirm) {
            Button("종료", role: .destructive) { Task { await vm.end() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("아직 1분이 지나지 않았습니다.\n정말 종료하시겠습니까?")
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
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var timerStatusBadge: some View {
        switch vm.timerState {
        case .idle:
            EmptyView()
        case .running, .paused:
            let isRunning = vm.timerState == .running
            HStack(spacing: 6) {
                Circle()
                    .fill(isRunning ? Color.green300 : Color.orange300)
                    .frame(width: 8, height: 8)
                Text(isRunning ? "공부 중" : "일시정지됨")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRunning ? Color.green700 : Color.orange700)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isRunning ? Color.green100 : Color.orange200)
            .clipShape(Capsule())
        }
    }

    private var subjectSelectionInTimer: some View {
        VStack(spacing: 10) {
            if subjectStore.subjects.isEmpty {
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
                    ForEach(subjectStore.subjects) { subject in
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

    @ViewBuilder
    private var timerButtons: some View {
        switch vm.timerState {
        case .idle:
            Button {
                isAlarmFieldFocused = false
                vm.notificationScheduler.saveAlarmInterval()
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
                    if vm.isWithinEarlyConfirm {
                        showEarlyPauseConfirm = true
                    } else {
                        Task { await vm.pause() }
                    }
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
            if !pauseTypeStore.pauseTypes.isEmpty {
                HStack(spacing: 8) {
                    ForEach(pauseTypeStore.pauseTypes) { type in
                        pauseTypeChip(type)
                    }
                }
            }

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
            if vm.timerState == .running && vm.isWithinEarlyConfirm {
                showEarlyEndConfirm = true
            } else {
                Task { await vm.end() }
            }
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

    private func pauseTypeChip(_ type: PauseType) -> some View {
        let isSelected = vm.selectedPauseType == type.value
        return Button {
            vm.selectPauseType(type.value)
        } label: {
            Text(type.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : Color.slate600)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue500 : Color.slate100)
                .clipShape(Capsule())
        }
    }

    // MARK: - Alarm Interval

    private var alarmIntervalSection: some View {
        @Bindable var scheduler = vm.notificationScheduler
        return HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .foregroundStyle(Color.blue500)
                .font(.caption)

            TextField("분", text: $scheduler.alarmIntervalText)
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
                        vm.notificationScheduler.saveAlarmInterval()
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

    // MARK: - Weekly Goal Card

    private var weeklyGoalCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("이번 주 목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Text(vm.weeklyGoalFormatted)
                    .font(.subheadline)
                    .foregroundStyle(Color.slate400)
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
                Text(vm.weeklyRemainingFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
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
                Rectangle().fill(Color.slate100)
                if barWidth > 0 {
                    Rectangle()
                        .fill(progress >= 1.0 ? Color.green300 : Color.blue400)
                        .frame(width: barWidth)
                        .overlay {
                            if !isNarrow {
                                Text(percentText)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: progressClamped)
                }
                if isNarrow {
                    Text(percentText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.slate400)
                        .offset(x: barWidth + 8)
                }
            }
            .frame(height: progressBarHeight)
            .clipShape(RoundedRectangle(cornerRadius: progressBarCornerRadius))
        }
        .frame(height: progressBarHeight)
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

        return HStack(spacing: 8) {
            Text(startText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.slate400)
                .frame(width: 38, alignment: .trailing)

            timelineSegments(session)
                .frame(height: 10)
        }
    }

    private func timelineSegments(_ session: StudySession) -> some View {
        let segments = buildTimelineSegments(session)
        let totalDuration = segments.reduce(0.0) { $0 + $1.duration }

        return GeometryReader { geo in
            if totalDuration > 0 {
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(segments.indices, id: \.self) { i in
                            let seg = segments[i]
                            let width = geo.size.width * (seg.duration / totalDuration)
                            let key = "\(session.id)-\(i)"
                            let isSelected = selectedSegmentKey == key

                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.isStudy ? Color.blue400 : Color.slate200)
                                .frame(width: max(width, 1))
                                .overlay(alignment: .top) {
                                    if isSelected {
                                        segmentTooltip(seg)
                                            .offset(y: -28)
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedSegmentKey = isSelected ? nil : key
                                    }
                                }
                        }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue400)
            }
        }
    }

    private func segmentTooltip(_ segment: TimelineSegment) -> some View {
        let seconds = Int(segment.duration)
        let label = segment.isStudy ? "공부" : pauseTypeLabel(segment.typeValue)
        return VStack(spacing: 0) {
            Text("\(label) \(seconds.durationText)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.slate700)
                .clipShape(Capsule())
            Triangle()
                .fill(Color.slate700)
                .frame(width: 8, height: 5)
        }
        .fixedSize()
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.closeSubpath()
            }
        }
    }

    /// 차트에서 무시할 최소 세그먼트 길이(초) — 타이밍 오차로 생긴 미세 구간 필터링
    private let minimumSegmentDuration: TimeInterval = 5

    private struct TimelineSegment {
        let isStudy: Bool
        let duration: Double
        let typeValue: String
    }

    private func buildTimelineSegments(_ session: StudySession) -> [TimelineSegment] {
        guard let start = Date.fromISO(session.startedAt) else { return [] }
        let end = session.effectiveEndDate
        let sortedPauses = session.pauses
            .compactMap { pause -> (start: Date, end: Date, type: String)? in
                guard let ps = Date.fromISO(pause.pausedAt) else { return nil }
                let pe = pause.resumedAt.flatMap { Date.fromISO($0) } ?? end
                return (ps, pe, pause.type ?? "REST")
            }
            .sorted { $0.start < $1.start }

        guard !sortedPauses.isEmpty else {
            return [TimelineSegment(isStudy: true, duration: end.timeIntervalSince(start), typeValue: "")]
        }

        var segments: [TimelineSegment] = []
        var cursor = start
        for pause in sortedPauses {
            if cursor < pause.start {
                segments.append(TimelineSegment(isStudy: true, duration: pause.start.timeIntervalSince(cursor), typeValue: ""))
            }
            if pause.start < pause.end {
                segments.append(TimelineSegment(isStudy: false, duration: pause.end.timeIntervalSince(pause.start), typeValue: pause.type))
            }
            cursor = pause.end
        }
        if cursor < end {
            segments.append(TimelineSegment(isStudy: true, duration: end.timeIntervalSince(cursor), typeValue: ""))
        }
        return segments.filter { $0.duration >= minimumSegmentDuration }
    }

    private func pauseTypeLabel(_ value: String) -> String {
        pauseTypeStore.pauseTypes.first(where: { $0.value == value })?.label ?? value
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
            VStack(alignment: .trailing, spacing: 2) {
                Text("공부 \(session.totalSeconds.durationText)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.blue600)
                if session.pauseSeconds > 0 {
                    Text("휴식 \(session.pauseSeconds.durationText)")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }
            }
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
