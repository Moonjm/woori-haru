import SwiftUI

/// 키·몸무게·활동량·목표를 입력하고 서버가 계산한 목표 섭취량을 확인한다.
/// 체중은 수동 입력이다 — HealthKit에서 자동으로 가져오지 않는다.
struct NutritionProfileView: View {
    @State private var vm = NutritionProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    /// 저장이 끝났을 때 호출. 하루 화면이 목표를 다시 읽는 데 쓴다.
    var onSaved: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                inputCard
                activityCard
                goalCard
                if let profile = vm.profile { targetCard(profile) }
                if vm.needsUserInfo { needsUserInfoNotice }
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle("식단 프로필")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var inputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("몸")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                HStack(spacing: 12) {
                    labeledField("키", unit: "cm", text: $vm.heightText)
                    labeledField("몸무게", unit: "kg", text: $vm.weightText)
                }

                // 서버가 거절할 값을 보내기 전에 그 자리에서 알려 준다 — 400을 받고 나면
                // 무엇이 잘못됐는지 알 길이 없다.
                ForEach([vm.heightRangeHint, vm.weightRangeHint].compactMap(\.self), id: \.self) { hint in
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Color.orange400)
                }

                Text("성별·생년월일은 「내 정보」 값을 씁니다.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private func labeledField(_ label: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            HStack(spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.body.weight(.medium))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassInputField()
        }
    }

    private var activityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("활동량")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                ForEach(ActivityLevel.allCases) { level in
                    Button {
                        vm.activityLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.label)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.slate700)
                                Text(level.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Color.slate400)
                            }
                            Spacer()
                            if vm.activityLevel == level {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.blue500)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var goalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                Picker("목표", selection: $vm.goal) {
                    ForEach(DietGoal.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func targetCard(_ profile: NutritionProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("하루 목표")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                targetRow("칼로리", "\(profile.targetKcal)kcal")
                targetRow("탄수화물", "\(profile.targetCarbsG)g")
                targetRow("단백질", "\(profile.targetProteinG)g")
                targetRow("지방", "\(profile.targetFatG)g")

                Divider()

                targetRow("당류", "\(profile.targetSugarG)g 이하")
                targetRow("나트륨", "\(profile.targetSodiumMg)mg 이하")
                targetRow("식이섬유", "\(profile.targetFiberG)g 이상")

                Text("2025 한국인 영양소 섭취기준(KDRIs)을 바탕으로 서버가 계산합니다.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    /// 오류 알림은 「확인」을 누르면 사라지므로, 안내가 계속 남아 있도록 화면에 고정 표시한다.
    private var needsUserInfoNotice: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange400)
                Text("성별과 생년월일이 있어야 목표를 계산할 수 있습니다. 「내 정보」에서 먼저 입력해 주세요.")
                    .font(.caption)
                    .foregroundStyle(Color.slate700)
            }
        }
    }

    private func targetRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate700)
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                await vm.save()
                if vm.didSave {
                    onSaved?()
                    dismiss()
                }
            }
        } label: {
            HStack {
                if vm.isSaving { ProgressView().tint(.white) }
                Text("저장")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .appGlassProminentButton()
        .disabled(!vm.canSave)
    }
}
