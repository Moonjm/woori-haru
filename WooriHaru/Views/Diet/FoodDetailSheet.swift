import SwiftUI

/// 상세 시트 — 수량·단위를 조절하고 「추가하기」로 담는다.
///
/// **1인분을 모르는 항목이 여기로 온다.** 목록의 ⊕가 조용히 담지 못하는 경우가 곧 이 화면이
/// 필요한 경우다(검색 결과의 상당수가 여기 해당한다).
struct FoodDetailSheet: View {
    var onAdd: (MealItemRequest) -> Void

    @State private var vm: FoodDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        source: FoodPickSource,
        targetKcal: Int? = nil,
        onAdd: @escaping (MealItemRequest) -> Void
    ) {
        self.onAdd = onAdd
        _vm = State(initialValue: FoodDetailViewModel(source: source, targetKcal: targetKcal))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassTokens.cardSpacing) {
                    quantityCard
                    nutritionCard
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let item = vm.item else { return }
                    onAdd(item)
                } label: {
                    Text("추가하기").frame(maxWidth: .infinity)
                }
                .appGlassProminentButton()
                .disabled(!vm.canAdd)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassScreenBackground()
            .navigationTitle(vm.source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("닫기")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 수량

    private var quantityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if let servingSize = vm.servingSizeText {
                    Text(servingSize)
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                }

                HStack(spacing: 12) {
                    stepper
                    if vm.showsUnitPicker { unitPicker }
                }

                // g 모드에서만 보인다 — 1인분을 아는 항목의 화면을 어지럽히지 않는다.
                if vm.showsQuickGramChips { quickGramChips }

                if let hint = vm.servingSizeUnknownHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Color.orange400)
                }
            }
        }
    }

    @ViewBuilder
    private var stepper: some View {
        HStack(spacing: 10) {
            Button {
                if vm.unit == .serving { vm.decreaseServings() } else { vm.decreaseGram() }
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
            .accessibilityLabel("수량 줄이기")

            if vm.unit == .serving {
                Text(vm.servingsText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                    .frame(minWidth: 72)
            } else {
                HStack(spacing: 2) {
                    TextField("0", text: $vm.gramText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 56)
                    Text("g").foregroundStyle(Color.slate400)
                }
            }

            Button {
                if vm.unit == .serving { vm.increaseServings() } else { vm.increaseGram() }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
            .accessibilityLabel("수량 늘리기")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassInputField()
    }

    private var unitPicker: some View {
        Picker("단위", selection: Binding(
            get: { vm.unit },
            set: { vm.setUnit($0) }
        )) {
            ForEach(FoodDetailViewModel.Unit.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
    }

    private var quickGramChips: some View {
        HStack(spacing: 6) {
            ForEach(FoodDetailViewModel.quickGrams, id: \.self) { gram in
                Button {
                    vm.selectQuickGram(gram)
                } label: {
                    Text("\(gram.trimmedText)g")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.slate100, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 영양소

    private var nutritionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(vm.kcalText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.slate700)

                    // 목표가 없으면 비율에 의미가 없다 — 프로필이 없으면 감춘다.
                    if let goal = vm.dailyGoalPercentText {
                        Text(goal)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.blue500)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.slate100, in: Capsule())
                    }
                }

                ForEach(vm.nutrientRows) { row in
                    Divider()
                    HStack {
                        Text(row.isSub ? "↳ \(row.name)" : row.name)
                            .font(.caption)
                            .foregroundStyle(row.isSub ? Color.slate400 : Color.slate500)
                            .padding(.leading, row.isSub ? 10 : 0)
                        Spacer()
                        Text(row.valueText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.slate700)
                    }
                }
            }
        }
    }
}
