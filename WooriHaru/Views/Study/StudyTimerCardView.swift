import SwiftUI

/// 타이머 카드 — 상태 배지, 경과 시간, 과목 선택(idle), 알림 간격, 시작/일시정지/재개/종료 버튼.
/// 1분 미만 조기 일시정지/종료 확인 알럿은 이 카드가 자체 처리한다.
struct StudyTimerCardView: View {
    @Environment(StudyTimerViewModel.self) private var vm
    @Environment(SubjectStore.self) private var subjectStore
    @Environment(PauseTypeStore.self) private var pauseTypeStore
    /// 알림 간격 입력 포커스 — 화면 어디를 탭해도 해제되도록 부모가 소유한다.
    @FocusState.Binding var isAlarmFieldFocused: Bool
    @State private var showEarlyPauseConfirm = false
    @State private var showEarlyEndConfirm = false

    var body: some View {
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
                StudySubjectPicker()
            }

            // 알림 설정
            alarmIntervalSection

            // 액션 버튼
            timerButtons
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .appGlassProminentButton()
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
                }
                .appGlassButton()
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
                }
                .appGlassButton()
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
        }
        .appGlassButton()
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
        .padding(.vertical, 4)
    }
}
