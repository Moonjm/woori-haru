import SwiftUI

/// 수량 저장 결과. **`Bool`로는 부족하다** — 시트가 상세 화면을 덮고 있어 상세가 띄우는 오류
/// 알럿이 화면에 나타나지 않는다. 이유를 시트까지 들고 와서 여기서 띄워야 한다
/// (`PhotoDeleteOutcome`과 같은 모양이고 같은 이유다).
enum QuantitySaveOutcome: Equatable {
    case saved
    case failed(String)
}

/// 저장된 끼니 항목의 **그램수만** 고친다.
///
/// **g 전용이다** — `MealItem`에 1인분 정보가 없어 검색 상세 시트의 「인분」이 여기엔 없다.
/// 음식 자체를 바꾸려면 「다른 음식으로 교체」로 넘어간다.
struct MealItemQuantitySheet: View {
    /// **저장을 화면이 하지 않는다** — 결과를 만드는 자리를 뷰에 두면 실패 경로가 테스트에
    /// 안 닿는다(`MealDetailViewModel.saveQuantity`).
    var onSave: (@MainActor (MealItemRequest) async -> QuantitySaveOutcome)
    /// 「다른 음식으로 교체 ›」. 화면이 이 시트를 교체 시트로 **갈아 끼운다** — 닫는 도중에
    /// 새 시트를 띄우면 SwiftUI가 조용히 삼킨다.
    var onReplace: () -> Void

    @State private var vm: MealItemQuantityViewModel
    @State private var isSaving = false
    /// 저장 실패 이유. 상세 화면의 알럿은 이 시트에 가려 보이지 않으므로 여기서 띄운다.
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    init(
        item: MealItem,
        original: MealItemRequest,
        onSave: @escaping (@MainActor (MealItemRequest) async -> QuantitySaveOutcome),
        onReplace: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onReplace = onReplace
        _vm = State(initialValue: MealItemQuantityViewModel(item: item, original: original))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassTokens.cardSpacing) {
                    quantityCard
                    nutritionCard
                    replaceButton
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    Text("완료").frame(maxWidth: .infinity)
                }
                .appGlassProminentButton()
                // 값이 그대로면 잠근다 — 저장 한 번에 LLM 호출 한 번이 나간다.
                .disabled(!vm.canSave || isSaving)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassScreenBackground()
            .navigationTitle(vm.item.foodName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("닫기")
                    .disabled(isSaving)
                }
            }
            .overlay { if isSaving { ProgressView() } }
            .alert("수량 수정", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let edited = vm.edited else { return }
        Task {
            isSaving = true
            let outcome = await onSave(edited)
            isSaving = false
            switch outcome {
            case .saved: dismiss()
            case let .failed(message): saveError = message
            }
        }
    }

    // MARK: - 수량

    private var quantityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                stepper
                quickGramChips
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: 10) {
            Button {
                vm.decrease()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
            .accessibilityLabel("수량 줄이기")

            HStack(spacing: 2) {
                TextField("0", text: $vm.gramText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 56)
                Text("g").foregroundStyle(Color.slate400)
            }

            Button {
                vm.increase()
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

    /// 검색 상세와 **같은 격자**를 쓴다(`GramStepper.quickGrams`).
    private var quickGramChips: some View {
        HStack(spacing: 6) {
            ForEach(GramStepper.quickGrams, id: \.self) { gram in
                Button {
                    vm.selectQuick(gram)
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
                Text(vm.kcalText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.slate700)

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

    /// 음식 자체가 틀렸을 때. **바꾸던 그램수는 버린다** — 다른 음식이면 이어받을 값이 아니다.
    private var replaceButton: some View {
        Button {
            onReplace()
        } label: {
            HStack {
                Text("다른 음식으로 교체")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.blue500)
        .glassInputField()
        .disabled(isSaving)
    }
}
