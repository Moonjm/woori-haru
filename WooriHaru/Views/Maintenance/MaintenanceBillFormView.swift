import SwiftUI

/// 검수(`.create`)와 편집(`.edit`)을 한 화면으로 다룬다. 갈리는 것은 제목·연월 편집
/// 가능 여부·저장 메서드뿐이고, 그 판단은 전부 뷰모델이 한다.
struct MaintenanceBillFormView: View {
    @State private var vm: MaintenanceBillFormViewModel
    @Environment(\.dismiss) private var dismiss
    /// 409 알럿. **버튼이 둘이다** — 「기존 내역 수정하기」와 「취소」.
    @State private var showingDuplicateAlert = false
    @State private var saveTask: Task<Void, Never>?

    var onSaved: () -> Void

    init(mode: MaintenanceBillFormViewModel.Mode, onSaved: @escaping () -> Void = {}) {
        // **`init`에서 세운다** — 뷰가 다시 그려질 때마다 뷰모델이 새로 생기면 사용자가
        // 친 값이 날아간다.
        _vm = State(initialValue: MaintenanceBillFormViewModel(mode: mode))
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                warningCard
                monthCard
                itemsCard
                sumCard
                usageCard
                amountCard
                if let message = vm.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .vehicleDarkTheme()
        .navigationTitle(vm.isYearMonthEditable ? "고지서 검수" : "관리비 수정")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { saveTask?.cancel() }
        .alert("이미 등록된 달입니다", isPresented: $showingDuplicateAlert) {
            Button("기존 내역 수정하기") {
                saveTask?.cancel()
                saveTask = Task {
                    // **화면을 닫지 않는다.** 서버 값으로 폼을 갈아 끼우고 그 자리에 머문다 —
                    // 방금 인식한 값으로 기존 달을 덮지 않으려는 것이다.
                    _ = await vm.loadForEdit(yearMonth: vm.yearMonth)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(MaintenanceFormat.monthTitle(vm.yearMonth)) 관리비가 이미 있습니다. 기존 내역을 불러와 고칠 수 있습니다.")
        }
    }

    /// **둘 중 하나만 있어도 뜬다.** `sumMatched == false`인데 서버가 `warnings`를 비워
    /// 보낼 수 있다 — `warnings`만 보면 검수 화면에서 가장 중요한 신호(합계 불일치)가
    /// 조용히 사라진다. `.edit`에서는 `sumMatched`가 늘 true이고 `warnings`가 늘
    /// 비어 있어 이 카드가 자연히 숨는다(스펙이 요구하는 「`.create`에서만」과 같다).
    @ViewBuilder private var warningCard: some View {
        if !vm.sumMatched || !vm.warnings.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("확인이 필요합니다", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.warning)
                    if !vm.sumMatched {
                        Text("항목 합계와 부과액이 맞지 않습니다")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(VehicleTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 서버 문구가 이미 사용자용 한국어다 — 앱이 다시 쓰지 않는다.
                    ForEach(vm.warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption)
                            .foregroundStyle(VehicleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var monthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("연월 · 세대")
                HStack(spacing: 10) {
                    Text("연월")
                        .font(.subheadline)
                        .foregroundStyle(VehicleTheme.textSecondary)
                        .frame(width: 56, alignment: .leading)
                    if vm.isYearMonthEditable {
                        TextField("2026-08", text: $vm.yearMonth)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .monospacedDigit()
                    } else {
                        // 편집 모드에서 연월은 키다. 바꾸는 것은 삭제 후 재등록이지 수정이 아니다.
                        Text(vm.yearMonth)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.textTertiary)
                        Spacer()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)

                HStack(spacing: 10) {
                    labeledField("동", text: $vm.dong, keyboard: .default)
                    labeledField("호", text: $vm.ho, keyboard: .default)
                    labeledField("면적", text: $vm.areaM2, keyboard: .decimalPad)
                }
            }
        }
    }

    private var itemsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("항목")
                    Spacer()
                    Button {
                        vm.addItem()
                    } label: {
                        Label("추가", systemImage: "plus")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VehicleTheme.accentBright)
                }
                ForEach($vm.items) { $item in
                    HStack(spacing: 8) {
                        MaintenanceItemRow(item: $item)
                        Button {
                            if let index = vm.items.firstIndex(where: { $0.id == item.id }) {
                                vm.removeItems(at: IndexSet(integer: index))
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(VehicleTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        // **행 이름을 넣는다.** 항목이 스무 줄 넘는 고지서에서 전부 「항목
                        // 삭제」만 읽히면 VoiceOver 사용자는 스무 번을 들어도 어느 줄인지
                        // 구분하지 못한다. 갓 추가한 빈 행은 이름이 없으니 그 자리를 말로 채운다.
                        .accessibilityLabel(
                            "\(item.name.isEmpty ? "새 항목" : item.name) 삭제"
                        )
                    }
                }
                if vm.items.isEmpty {
                    Text("항목이 하나도 없으면 저장할 수 없습니다")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.warning)
                }
            }
        }
    }

    /// 항목 합계와 부과액을 나란히 놓는다. **틀려도 막지 않는다** — 반올림·별도 조정이
    /// 실제로 있고 판단은 사람이 한다. 다만 차액은 눈에 띄게 적는다.
    private var sumCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("항목 합계")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer()
                    Text(MaintenanceFormat.won(vm.itemsTotal))
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(VehicleTheme.textPrimary)
                }
                if !vm.isSumMatched {
                    HStack {
                        Text("부과액과 차이")
                            .font(.caption)
                            .foregroundStyle(VehicleTheme.warning)
                        Spacer()
                        Text(MaintenanceFormat.signedWon(vm.sumGap))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.warning)
                    }
                }
            }
        }
    }

    private var usageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("사용량")
                MaintenanceUsageFields(vm: vm)
            }
        }
    }

    private var amountCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("금액")
                amountField("부과액", text: $vm.chargedAmount)
                amountField("할인 합계", text: $vm.discountTotal)
            }
        }
    }

    private var saveButton: some View {
        Button {
            saveTask?.cancel()
            saveTask = Task {
                switch await vm.save() {
                case .saved:
                    onSaved()
                    dismiss()
                case .duplicated:
                    showingDuplicateAlert = true
                case .failed:
                    break   // `vm.errorMessage`가 화면에 이미 뜬다
                }
            }
        } label: {
            if vm.isSaving {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("저장").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!vm.canSave)
        // 툴바가 아니라 맨 아래다 — 항목이 스무 줄이라 스크롤이 길고, 툴바 버튼은
        // 검수를 다 하기 전에 눌리기 쉽다.
        .padding(.top, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(VehicleTheme.textSecondary)
    }

    private func labeledField(_ label: String, text: Binding<String>,
                              keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textTertiary)
            TextField("", text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
        }
    }

    private func amountField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textSecondary)
                .frame(width: 72, alignment: .leading)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.subheadline)
                .foregroundStyle(VehicleTheme.textPrimary)
        }
    }
}
