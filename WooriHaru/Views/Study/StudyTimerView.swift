import SwiftUI

/// 공부 타이머 화면 — 카드 UI는 StudyTimerCardView·StudyTodaySummaryCard·
/// StudyWeeklyGoalCard·StudyTodayTimelineView 컴포넌트가 담당하고,
/// 이 화면은 레이아웃, 초기 로드, 과목 추가/수정·오류 알럿, 포그라운드 동기화만 관리한다.
struct StudyTimerView: View {
    @Environment(StudyTimerViewModel.self) private var vm
    @Environment(SubjectStore.self) private var subjectStore
    @Environment(PauseTypeStore.self) private var pauseTypeStore
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isAlarmFieldFocused: Bool
    @State private var selectedSegmentKey: String?
    @State private var recordVM = StudyRecordViewModel()

    var body: some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(spacing: 20) {
                StudyTimerCardView(isAlarmFieldFocused: $isAlarmFieldFocused)
                StudyTodaySummaryCard()
                StudyWeeklyGoalCard()
                StudyTodayTimelineView(selectedSegmentKey: $selectedSegmentKey)
                WeeklyStudyRecordSection(vm: recordVM, showAllRecordsLink: true)
            }
            .padding(20)
        }
        .glassScreenBackground()
        .onTapGesture { isAlarmFieldFocused = false; selectedSegmentKey = nil }
        .navigationTitle("공부 타이머")
        .navigationBarTitleDisplayMode(.inline)
        .task { @MainActor in
            let vm = self.vm
            let recordVM = self.recordVM
            vm.configure(subjectStore: subjectStore, pauseTypeStore: pauseTypeStore)
            recordVM.configure(pauseTypeStore: pauseTypeStore)
            async let subjects: () = vm.loadSubjects()
            async let sessions: () = vm.loadTodaySessions()
            async let weekly: () = vm.loadWeeklySummary()
            async let pauseTypes: () = vm.loadPauseTypes()
            async let monthly: () = recordVM.loadRecentWeeks(count: 5)
            _ = await (subjects, sessions, weekly, pauseTypes, monthly)
            await vm.restoreActiveSession()
        }
        .onChange(of: vm.todaySessions.count) {
            recordVM.refreshRecentWeeks(count: 5)
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
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                vm.syncOnForeground()
            }
        }
    }
}
