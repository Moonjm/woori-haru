import SwiftUI

/// 인식 결과를 확인·수정하고 저장한다. 사진 없는 기록에서도 같은 화면을 쓴다 —
/// 항목 목록·합계·저장 버튼이 그대로 필요하고 `PhotoStrip`만 그릴 게 없다.
///
/// **저장 버튼이 1탭이어야 한다.** 확인 화면이 번거로우면 저장하지 않고 나가고, 그러면
/// LLM 비용은 나갔는데 기록은 남지 않는다. "검수 과업"이 아니라 "저장 전 미리보기"로 느껴져야 한다.
struct MealConfirmView: View {
    let date: Date
    let analysis: MealAnalysis?
    var onSaved: (Int) -> Void
    /// 실패한 사진만 다시 인식. 사진 없는 기록에서는 nil이다.
    var onRetryPhoto: (() async -> Void)?
    /// 재시도 진행 상태 표시용 — `MealCaptureViewModel`을 통째로 들고 있지 않고 화면이
    /// 필요한 값만 받는다. 사진 없는 기록에서는 기본값이 그대로 쓰이고(버튼 자체가 안 뜬다).
    var isRetrying: Bool = false
    var retryPhase: MealCaptureViewModel.Phase = .completed
    var retryErrorMessage: String?

    @State private var vm: MealConfirmViewModel
    @State private var showDiscardAlert = false
    /// 기존 끼니에 합쳐지는 저장인지 한 번 묻는다. **되돌릴 수 없다** — 합쳐진 뒤에는
    /// 어느 항목이 이번에 넣은 것이었는지 구분되지 않는다.
    ///
    /// 문구를 뷰모델이 정한다 — 「합쳐진다」와 「합쳐질지 확인하지 못했다」가 다른 말이다.
    @State private var mergeAlert: MergeAlert?

    private struct MergeAlert: Identifiable {
        let title: String
        let message: String
        var id: String { title }
    }
    @State private var editTarget: EditTarget?
    @State private var showProfile = false
    /// **화면과 함께 죽어야 한다.** 그냥 `Task { }`로 띄우면 저장 없이 나가도 재시도가
    /// 뒤에서 계속 돌다가 `phase`를 다시 `.completed`로 바꿔 이미 나간 화면을 되살려 낸다.
    @State private var retryTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// 어느 그룹에 무엇을 하려는지. 새 항목이면 `item`이 nil이다.
    /// `private`이 아니라 `internal`로 둔다 — 테스트(`@testable import`)에서 `pickMode`
    /// 매핑을 직접 검증하려면 파일 밖에서 보여야 한다.
    struct EditTarget: Identifiable {
        let groupId: Int
        let item: MealItemRequest?
        var id: String { "\(groupId)-\(item?.id.uuidString ?? "new")" }

        /// **「음식 추가」만 여러 개 모드다** — 아직 저장 전이라 모아서 담아도 왕복이 없다.
        /// 교체는 대상이 하나로 정해져 있다. 화면 밖으로 빼 두어야 이 매핑에 테스트가 붙는다.
        var pickMode: MealItemPickMode {
            item.map(MealItemPickMode.replace) ?? .addMany
        }
    }

    init(
        date: Date,
        mealType: MealType,
        analysis: MealAnalysis?,
        service: any DietServing = DietService(),
        isRetrying: Bool = false,
        retryPhase: MealCaptureViewModel.Phase = .completed,
        retryErrorMessage: String? = nil,
        onSaved: @escaping (Int) -> Void,
        onRetryPhoto: (() async -> Void)? = nil
    ) {
        self.date = date
        self.analysis = analysis
        self.onSaved = onSaved
        self.onRetryPhoto = onRetryPhoto
        self.isRetrying = isRetrying
        self.retryPhase = retryPhase
        self.retryErrorMessage = retryErrorMessage
        _vm = State(initialValue: MealConfirmViewModel(
            date: date, mealType: mealType, analysis: analysis, service: service
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                Picker("끼니", selection: $vm.mealType) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                // 피커 **바로 아래**여야 한다 — 끼니 종류를 바꿀 때마다 달라지는 안내라
                // 떨어져 있으면 무엇 때문에 나타났다 사라지는지 읽히지 않는다.
                if let notice = vm.mergeNoticeText {
                    Label(notice, systemImage: "arrow.triangle.merge")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if vm.hasPhotos {
                    PhotoStrip(
                        photos: vm.groups.compactMap { group in
                            group.fileId.map { StripPhoto(id: $0, url: group.url) }
                        },
                        failedIds: vm.failedFileIds
                    )

                    if !vm.failedFileIds.isEmpty, let onRetryPhoto {
                        retrySection(onRetryPhoto)
                    }
                }

                ForEach(vm.groups) { group in
                    groupCard(group)
                }

                totalCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle("확인")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") {
                    // 여기까지 오는 데 LLM 비용과 대기시간이 이미 들었다 — 실수로 이탈하지 않게 확인한다.
                    if vm.hasChanges || analysis != nil {
                        showDiscardAlert = true
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    // **합쳐지는 경우에만 한 번 묻는다.** 그 외에는 1탭을 지킨다 — 확인이
                    // 번거로우면 저장 없이 나가고, 그러면 LLM 비용은 나갔는데 기록이 없다.
                    //
                    // **그 판단을 뷰모델이 조회를 기다린 뒤에 내린다** — 여기서 바로 읽으면
                    // 조회가 느릴 때 빈 값을 보고 확인 없이 저장한다.
                    Task {
                        switch await vm.resolveSaveAction() {
                        case let .confirm(title, message):
                            mergeAlert = MergeAlert(title: title, message: message)
                        case .save:
                            await save()
                        }
                    }
                }
                // **재인식 중에는 잠근다.** 서버가 그 분석을 `PENDING`으로 되돌리고
                // 확정을 `ANALYSIS_NOT_CONFIRMABLE`로 거절한다 — 눌리기는 하는데 거절당하는
                // 버튼을 두지 않는다. `isRetrying`은 `MealCaptureViewModel.retry()`가 폴링까지
                // 끝낼 때까지 참이라(같은 함수 스코프의 `defer`) 서버가 `PENDING`인 구간과
                // 그대로 겹친다.
                .disabled(!vm.canSave || isRetrying)
            }
        }
        .sheet(item: $editTarget) { target in
            MealItemEditView(mode: target.pickMode) { picked in
                if let original = target.item {
                    if let edited = picked.first {
                        vm.replaceItem(original, with: edited, in: target.groupId)
                    }
                } else {
                    for item in picked {
                        vm.addItem(item, to: target.groupId)
                    }
                }
                editTarget = nil
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            NutritionProfileView()
        }
        .alert(item: $mergeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("합치기")) { Task { await save() } },
                secondaryButton: .cancel(Text("취소"))
            )
        }
        .alert("저장하지 않고 나갈까요?", isPresented: $showDiscardAlert) {
            Button("나가기", role: .destructive) { dismiss() }
            Button("계속 확인", role: .cancel) {}
        } message: {
            Text("저장하지 않으면 이 기록은 남지 않아요.")
        }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task {
            // 그날 이미 기록한 끼니를 읽어 「합쳐져요」 안내를 띄운다. 실패해도 조용히
            // 넘어가므로 화면을 막지 않는다.
            await vm.loadExistingMeals()
        }
        .onChange(of: vm.needsProfile) { _, needs in
            if needs { showProfile = true }
        }
        .onChange(of: analysis) { _, newValue in
            // 재시도 결과가 새로 도착하면 이미 떠 있는 이 화면의 뷰모델에 병합한다 — 화면을
            // 다시 만들지 않아야 사용자가 다른 사진에서 고치던 내용이 사라지지 않는다.
            //
            // 진행 중(`.pending`) 응답도 그대로 올라오는데, 걸러 내는 일은 뷰모델이 한다.
            if let newValue {
                vm.applyRetriedAnalysis(newValue)
            }
        }
        .onDisappear {
            // 화면이 나가면(저장했든 그냥 나갔든) 여기서 띄운 재시도는 더 볼 사람이 없다 —
            // 살려 두면 나중에 phase가 다시 `.completed`가 돼 이미 나간 화면을 되살려 낸다.
            retryTask?.cancel()
        }
    }

    private func save() async {
        await vm.save()
        if let mealId = vm.savedMealID { onSaved(mealId) }
    }

    /// 진행 중에는 스피너로 바꾸고, 지연·실패로 끝났을 때는 그 사실을 알린다 — 예전에는
    /// 버튼을 눌러도 화면이 60초 동안 아무것도 바뀌지 않는 것처럼 보였다.
    private func retrySection(_ onRetryPhoto: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                retryTask?.cancel()
                retryTask = Task { await onRetryPhoto() }
            } label: {
                if isRetrying {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("다시 인식하는 중")
                    }
                } else {
                    Text("실패한 사진 다시 인식")
                }
            }
            .appGlassButton()
            .font(.caption)
            .disabled(isRetrying)

            if !isRetrying, retryPhase == .delayed {
                Text("인식이 지연되고 있어요. 잠시 후 다시 시도해 주세요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            } else if !isRetrying, retryPhase == .failed, let retryErrorMessage {
                Text(retryErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(Color.red500)
            }
        }
    }

    /// **항목을 사진별로 묶어 보여주는 게 중요하다** — 같은 음식이 여러 사진에서 중복으로 잡힐 때
    /// 출처가 보여야 사용자가 같은 접시인지 진짜 2인분인지 판단할 수 있다.
    private func groupCard(_ group: MealConfirmViewModel.PhotoGroup) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if vm.hasPhotos {
                    HStack {
                        Text("사진 \(group.id + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.slate500)
                        if group.failed {
                            Text("인식 실패")
                                .font(.caption2)
                                .foregroundStyle(Color.red500)
                        }
                        Spacer()
                    }
                }

                ForEach(group.items) { item in
                    itemRow(item, in: group.id)
                }

                Button {
                    editTarget = EditTarget(groupId: group.id, item: nil)
                } label: {
                    Label("음식 추가", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.blue500)
            }
        }
    }

    private func itemRow(_ item: MealItemRequest, in groupId: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.foodName)
                        .font(.subheadline)
                        .foregroundStyle(Color.slate700)

                    // 확인 화면에서 특히 중요하다 — 어느 값을 우선 검토해야 하는지 알려준다.
                    if item.source == .llmEstimated {
                        Text("추정")
                            .font(.caption2)
                            .foregroundStyle(Color.orange400)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange100, in: Capsule())
                    }
                }
                Text("\(Int(item.quantityG.rounded()))g · \(Int(item.kcal.rounded()))kcal")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }

            Spacer()

            // 격자·하한은 `GramStepper`가 정한다 — 검색 상세·끼니 항목 수정과 같은 폭이다.
            Stepper("") {
                vm.increaseQuantity(of: item, in: groupId)
            } onDecrement: {
                vm.decreaseQuantity(of: item, in: groupId)
            }
            .labelsHidden()

            Button {
                editTarget = EditTarget(groupId: groupId, item: item)
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.blue500)
            }
            .buttonStyle(.plain)

            Button {
                vm.removeItem(item, in: groupId)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.red400)
            }
            .buttonStyle(.plain)
        }
    }

    private var totalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("합계")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Spacer()
                    Text("\(Int(vm.totalKcal.rounded()))kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.slate900)
                }
                HStack(spacing: 12) {
                    macroText("탄", vm.totalCarbsG)
                    macroText("단", vm.totalProteinG)
                    macroText("지", vm.totalFatG)
                }
            }
        }
    }

    private func macroText(_ label: String, _ grams: Double) -> some View {
        Text("\(label) \(Int(grams.rounded()))g")
            .font(.caption)
            .foregroundStyle(Color.slate500)
    }
}
