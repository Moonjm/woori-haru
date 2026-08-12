import SwiftUI

/// 날짜 하나의 근무를 고치는 시트. **엄마가 위, 아빠가 아래** — 달력 칸의 밴드 순서와 같다.
/// 화면마다 순서가 뒤집히면 어느 밴드를 고치고 있는지 헷갈린다.
struct ScheduleDayEditSheet: View {
    @State var vm: ScheduleDayEditViewModel
    /// 저장에 성공했다. 서버는 204라 돌려주는 것이 없어, 인자는 **뷰모델이 만든** 그날의
    /// 최종 상태다(보낸 값 + 손대지 않은 역할의 원본).
    let onSaved: ([DispatchShiftDay]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                roleSection(title: "엄마", color: .pink500, working: $vm.motherWorking) {
                    Picker("순번", selection: $vm.motherSlotCode) {
                        Text("없음").tag(String?.none)
                        ForEach(vm.motherSlotCodeOptions, id: \.self) { code in
                            Text(code).tag(String?.some(code))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                roleSection(title: "아빠", color: .blue500, working: $vm.fatherWorking) {
                    Picker("순번", selection: $vm.fatherSlot) {
                        Text("없음").tag(Int?.none)
                        ForEach(vm.fatherSlotOptions, id: \.self) { slot in
                            Text("\(slot)").tag(Int?.some(slot))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let message = vm.errorMessage {
                    Section {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(vm.dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("저장") { save() }.disabled(!vm.canSave)
                    }
                }
            }
        }
        .onDisappear { saveTask?.cancel() }
    }

    /// 근무/휴무는 **아직 고르지 않음**을 포함한 세 상태다. 미등록인 역할은 아무것도
    /// 선택되지 않은 채로 뜨고, 그대로 저장하면 그 역할은 요청에 실리지 않는다.
    @ViewBuilder
    private func roleSection(
        title: String,
        color: Color,
        working: Binding<ScheduleDayEditViewModel.Working?>,
        @ViewBuilder slotPicker: () -> some View
    ) -> some View {
        Section {
            Picker("근무", selection: working) {
                Text("근무").tag(ScheduleDayEditViewModel.Working?.some(.working))
                Text("휴무").tag(ScheduleDayEditViewModel.Working?.some(.off))
            }
            .pickerStyle(.segmented)

            // 휴무면 순번이 없다. **잠그기만 하고 감추지 않는다** — 자리가 들고 나면
            // 근무/휴무를 오갈 때마다 아래 항목이 위아래로 튄다.
            slotPicker()
                .disabled(working.wrappedValue != .working)
        } header: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
                Text(title)
            }
        }
    }

    /// **실패하면 시트를 닫지 않는다.** 닫고 나서 알리면 어떤 값이 안 들어갔는지 다시 열어
    /// 확인해야 한다. 고치던 값이 그대로 남아 있는 자리에서 알리는 편이 짧다.
    private func save() {
        saveTask?.cancel()
        saveTask = Task {
            guard let days = await vm.save() else { return }
            onSaved(days)
            dismiss()
        }
    }
}
