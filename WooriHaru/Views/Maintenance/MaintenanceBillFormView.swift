import SwiftUI

/// 검수(`.create`)와 편집(`.edit`)을 한 화면으로 다룬다. 갈리는 것은 제목·연월 편집
/// 가능 여부·저장 메서드뿐이고, 그 판단은 전부 뷰모델이 한다.
struct MaintenanceBillFormView: View {
    @State private var vm: MaintenanceBillFormViewModel
    /// 409 알럿. **버튼이 둘이다** — 「기존 내역 수정하기」와 「취소」.
    @State private var showingDuplicateAlert = false
    @State private var saveTask: Task<Void, Never>?

    /// 저장이 끝났다. **물러나는 일은 이 클로저를 넘긴 쪽이 한다** — 이 화면은
    /// 스스로 `dismiss()`하지 않는다. 부르는 두 곳 모두 이 화면 너머까지 물러나야 해서
    /// (등록은 업로드 화면째, 수정은 상세 화면째) 여기서 한 번 더 물러나면 화면이
    /// 두 겹 빠진다. 새 호출부를 붙일 때도 이 클로저 안에서 물러나야 한다.
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
                // **왜 잠겼는지 말해 준다.** 사용량·면적·할인 중 하나가 숫자로 안 읽히면
                // 저장 버튼이 꺼지는데, 그 칸들은 스크롤 아래쪽에 흩어져 있어 어디가
                // 문제인지 모르면 버튼이 고장 난 줄 안다.
                if vm.hasInvalidOptionalNumber {
                    Text("숫자로 읽을 수 없는 칸이 있습니다. 비우거나 숫자만 남겨 주세요")
                        .font(.footnote)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        // 스크롤로도 내려간다 — `LedgerEntryFormView`가 쓰는 것과 같은 방식이다.
        .scrollDismissesKeyboard(.interactively)
        // **아무 데나 탭해도 내려간다.** 이 화면은 칸이 열댓 개라 키보드가 화면 절반을
        // 덮는데, 그 상태로는 아래쪽 칸도 저장 버튼도 안 보인다.
        //
        // `onTapGesture`가 아니라 `simultaneousGesture`다 — 앞엣것은 안쪽 버튼·입력칸의
        // 탭을 가로채, 항목 삭제나 다른 칸으로 옮기는 탭이 한 번에 안 먹는다.
        .simultaneousGesture(TapGesture().onEnded { Self.dismissKeyboard() })
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
        if !vm.isSumMatched || !vm.sumMatched || !vm.warnings.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("확인이 필요합니다", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.warning)
                    // **둘은 배타적이다.** 앞은 지금 상태(`isSumMatched`), 뒤는 인식 시점의
                    // 판정(`sumMatched`)이다. 예전에는 뒤엣것만 보고 배너를 띄워서, 사용자가
                    // 금액을 고쳐 합계를 맞춘 뒤에도 배너는 「안 맞는다」고 하고 바로 아래
                    // 대조 카드는 「맞는다」고 하는 **모순된 화면**이 됐다.
                    if !vm.isSumMatched {
                        Text("항목 합계와 부과액이 맞지 않습니다")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(VehicleTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !vm.sumMatched {
                        // 지금은 맞지만 인식할 때는 어긋나 있었다. 사람이 고쳐서 맞은 게
                        // 아니라 **잘못 읽힌 값끼리 우연히 맞아떨어졌을 수도** 있어 남긴다.
                        Text("인식할 때 합계가 어긋나 있었습니다. 값을 한 번 더 확인해 주세요")
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
                // **왜 잠겼는지 말해 준다.** 이름이 겹치면 저장 버튼이 꺼지는데, 스무 줄짜리
                // 화면에서 어느 두 줄이 문제인지 모르면 사용자는 버튼이 고장 난 줄 안다.
                if vm.hasDuplicateItemNames {
                    Text("같은 이름의 항목이 둘 있습니다. 이름을 다르게 해 주세요")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
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
                    // **여기서 `dismiss()`를 부르지 않는다.** 물러나는 일은 `onSaved`를
                    // 넘긴 쪽이 한다 — 부르는 두 곳 모두 이 화면 **너머까지** 물러나기
                    // 때문이다(등록은 `showingUpload = false`로 업로드 화면째, 수정은
                    // 상세 화면의 `dismiss()`로 상세째). 거기에 이 화면이 한 번 더
                    // 물러나면 **`MaintenanceView`까지 `path`에서 빠져 앱 첫 화면으로
                    // 튕긴다.**
                    onSaved()
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

    /// **`@FocusState`를 쓰지 않는다.** 이 화면의 입력칸은 열댓 개이고 그중 다섯은
    /// 별도 뷰(`MaintenanceUsageFields`·`MaintenanceItemRow`)에 있어, 포커스를 하나로
    /// 묶으려면 그 뷰들에 바인딩을 뚫어야 한다. 내리기만 하면 되는 일에 그만한 배선을
    /// 깔 이유가 없다.
    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
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
