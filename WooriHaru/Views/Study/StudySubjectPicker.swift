import SwiftUI

/// idle 상태의 과목 선택/관리 UI — 과목 칩 그리드, 추가 버튼, 길게 눌러 수정/삭제.
/// 추가/수정 입력 알럿은 vm 상태(showAddSubject/editingSubject)를 통해 부모 화면이 띄운다.
struct StudySubjectPicker: View {
    @Environment(StudyTimerViewModel.self) private var vm
    @Environment(SubjectStore.self) private var subjectStore

    var body: some View {
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
                .appGlassButton()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(subjectStore.subjects) { subject in
                        subjectChip(subject)
                    }
                    Button {
                        vm.showAddSubject = true
                    } label: {
                        Text(" ")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.slate400)
                            }
                            .background(Color.slate100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("과목 추가")
                    }
                }
            }
        }
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
}
