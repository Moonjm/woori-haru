import SwiftUI

/// 항목 고르기 — 자주 드셨어요 · 검색결과 · 직접 등록 세 탭.
///
/// **담기는 두 속도다.** ⊕는 기본 수량으로 즉시 담고, 행을 누르면 상세 시트가 열려 수량·단위를
/// 조정한다. **1인분을 모르는 항목은 ⊕도 상세 시트를 연다** — 채워 넣을 기본 수량이 없다.
///
/// 다중 선택은 **새 끼니를 만들 때(`.addMany`)만**이다. 끼니 상세의 추가·교체는 항목 하나마다
/// 서버 왕복이라 모아 보낼 이유가 없다.
struct MealItemEditView: View {
    /// **항상 배열이다.** 한 개 모드에서는 원소가 하나라 호출부가 두 모양을 구분하지 않아도 된다.
    var onCommit: ([MealItemRequest]) -> Void

    @State private var vm: MealItemPickViewModel
    @State private var detailSource: FoodPickSource?
    @Environment(\.dismiss) private var dismiss

    init(
        mode: MealItemPickMode,
        service: any DietServing = DietService(),
        onCommit: @escaping ([MealItemRequest]) -> Void
    ) {
        self.onCommit = onCommit
        _vm = State(initialValue: MealItemPickViewModel(mode: mode, service: service))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .safeAreaInset(edge: .bottom) {
                // 여러 개 모드에서만 뜬다. **끼니 종류 피커는 두지 않는다** — 바로 뒤
                // `MealConfirmView`가 그 피커를 이미 갖고 있어 둘 다 두면 같은 값을 만지는
                // 컨트롤이 한 화면에 둘 생긴다.
                if vm.showsBottomBar { bottomBar }
            }
            .glassScreenBackground()
            .navigationTitle(vm.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .task { await vm.load() }
            .sheet(item: $detailSource) { source in
                FoodDetailSheet(source: source, targetKcal: vm.targetKcal) { item in
                    detailSource = nil
                    handle(vm.accept(item, from: source))
                }
            }
            .alert("오류", isPresented: .init(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    /// ⊕·상세 시트의 결과를 화면 동작으로 옮긴다.
    private func handle(_ outcome: MealItemPickViewModel.PickOutcome, fallback: FoodPickSource? = nil) {
        switch outcome {
        case .needsDetail:
            detailSource = fallback
        case let .commit(items):
            onCommit(items)
            dismiss()
        case .collected:
            break
        }
    }

    // MARK: - 상단 (검색창 · 탭 · 필터 칩)

    private var header: some View {
        VStack(spacing: 10) {
            if let replacing = vm.mode.replacingText {
                Text(replacing)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // **검색창은 탭 위에 둔다** — 어느 탭에서든 바로 검색으로 들어갈 수 있어야 한다.
            HStack {
                TextField("음식 검색", text: $vm.query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { Task { await vm.search() } }
                if vm.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassInputField()

            Picker("탭", selection: $vm.tab) {
                ForEach(MealItemPickViewModel.Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if vm.tab == .search { filterChips }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// 가공식품 30만 건과 원재료 523건이 섞여 나오므로 「조리 음식만」으로 좁힐 길이 필요하다.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MealItemPickViewModel.DatasetFilter.allCases) { option in
                    let isOn = vm.filter == option
                    Button {
                        // **칩이 곧 쿼리다** — 서버가 거르므로 다시 검색해야 목록이 바뀐다.
                        Task { await vm.selectFilter(option) }
                    } label: {
                        Text(option.label)
                            .font(.caption)
                            .foregroundStyle(isOn ? .white : Color.slate500)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isOn ? Color.blue500 : Color.slate100, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 본문

    @ViewBuilder
    private var content: some View {
        switch vm.tab {
        case .frequent:
            pickList(vm.frequentSources, emptyText: "아직 자주 드신 음식이 없어요.")
        case .search:
            pickList(vm.searchSources, emptyText: vm.searchEmptyText ?? "")
        case .manual:
            manualForm
        }
    }

    private func pickList(_ sources: [FoodPickSource], emptyText: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if sources.isEmpty {
                    Text(emptyText)
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                        .padding(.vertical, 40)
                } else {
                    ForEach(sources) { source in
                        FoodPickRow(
                            source: source,
                            pickedCount: vm.pickedCount(for: source),
                            onTapRow: { detailSource = source },
                            onQuickAdd: { handle(vm.quickAdd(source), fallback: source) }
                        )
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// 포장지 영양성분표를 보고 채우는 자리. **당류·나트륨·식이섬유 칸이 반드시 있어야 한다** —
    /// 넷만 채워 보내면 서버가 나머지를 0.0으로 받아 말없이 저장한다.
    private var manualForm: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("음식 이름", text: $vm.manualName)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .glassInputField()

                    HStack(spacing: 8) {
                        numberField("수량", unit: "g", text: $vm.manualQuantity)
                        numberField("칼로리", unit: "kcal", text: $vm.manualKcal)
                    }
                    HStack(spacing: 8) {
                        numberField("탄수화물", unit: "g", text: $vm.manualCarbs)
                        numberField("단백질", unit: "g", text: $vm.manualProtein)
                        numberField("지방", unit: "g", text: $vm.manualFat)
                    }
                    HStack(spacing: 8) {
                        numberField("당류", unit: "g", text: $vm.manualSugar)
                        numberField("나트륨", unit: "mg", text: $vm.manualSodium)
                        numberField("식이섬유", unit: "g", text: $vm.manualFiber)
                    }

                    Button {
                        guard let outcome = vm.acceptManual() else { return }
                        handle(outcome)
                    } label: {
                        Text("추가하기").frame(maxWidth: .infinity)
                    }
                    .appGlassProminentButton()
                    .disabled(vm.buildManualItem() == nil)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }

    private func numberField(_ label: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label)(\(unit))")
                .font(.caption2)
                .foregroundStyle(Color.slate400)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .glassInputField(cornerRadius: 8)
        }
    }

    private var bottomBar: some View {
        Button {
            onCommit(vm.commitPicked())
            dismiss()
        } label: {
            Text(vm.bottomBarText).frame(maxWidth: .infinity)
        }
        .appGlassProminentButton()
        .disabled(!vm.canCommitPicked)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
