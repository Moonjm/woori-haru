import SwiftUI

/// 사진 여러 장·항목 목록·끼니 점수·점수 근거·피드백. 항목 수정과 **끼니 삭제**가 여기 있다.
struct MealDetailView: View {
    let mealId: Int
    /// 항목 수정·삭제로 하루 집계가 달라졌을 때. 하루 화면이 다시 조회한다.
    var onChanged: () -> Void

    @State private var vm: MealDetailViewModel
    @State private var showDeleteAlert = false
    @State private var editingTarget: EditingTarget?
    @State private var showAddItem = false
    /// 전체화면으로 보고 있는 사진.
    @State private var viewingPhoto: StripPhoto?
    @Environment(\.dismiss) private var dismiss

    /// 교체 시트가 열릴 때 필요한 것 둘 — 어느 항목이고(`item`), 무엇으로 채워 열지(`current`).
    /// **둘을 함께 담아야** 대상을 못 찾는 순간에 내용 없는 빈 시트가 뜨는 일이 없다.
    private struct EditingTarget: Identifiable {
        let item: MealItem
        let current: MealItemRequest
        var id: Int { item.id }
    }

    init(mealId: Int, service: any DietServing = DietService(), onChanged: @escaping () -> Void) {
        self.mealId = mealId
        self.onChanged = onChanged
        _vm = State(initialValue: MealDetailViewModel(mealId: mealId, service: service))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                if vm.isStale { staleBanner }

                if let meal = vm.meal {
                    PhotoStrip(photos: meal.photos.map { StripPhoto(id: $0.fileId, url: $0.url) }) { photo in
                        viewingPhoto = photo
                    }
                    itemsCard(meal)
                    ScoreBasisCard(title: "끼니 점수", score: meal.score, basis: meal.scoreBasis)
                    feedbackCard(meal)
                    deleteButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle(vm.meal?.mealType.label ?? "끼니")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .overlay { if vm.isLoading && vm.meal == nil { ProgressView() } }
        .fullScreenCover(item: $viewingPhoto) { photo in
            // **하루 재조회(`onChanged`)를 걸지 않는다** — 사진이 줄어도 먹은 것은 그대로라
            // 서버가 점수·피드백·하루 집계를 다시 만들지 않는다.
            PhotoViewerSheet(
                url: photo.url,
                // 상세를 열어 둔 채 10분이 지나면 이 주소는 죽어 있다. 「다시 시도」가
                // 끼니를 다시 조회해 새 주소부터 받게 한다.
                refreshURL: { await vm.refreshedPhotoURL(fileId: photo.id) }
            ) {
                guard await vm.deletePhoto(fileId: photo.id) else {
                    // 이 화면이 상세를 덮고 있어 상세의 오류 알럿이 보이지 않는다 —
                    // 메시지를 여기로 넘기고, 뒤에 남아 알럿을 띄우지 않도록 지운다.
                    let message = vm.errorMessage ?? "사진을 지우지 못했어요."
                    vm.errorMessage = nil
                    return .failed(message)
                }
                return .deleted
            }
        }
        .sheet(item: $editingTarget) { target in
            // 이미 저장된 끼니를 고치는 자리라 **하나씩 확인하며 바꾸는 편이 안전하다.**
            // 다중 선택은 범위 밖이다(설계 문서 「범위 밖」 참조).
            MealItemEditView(mode: .replace(target.current)) { picked in
                if let replacement = picked.first {
                    Task {
                        // 성공했을 때만 하루 화면을 재조회시킨다 — 가드가 막았거나 서버가
                        // 거절하면 아무것도 안 바뀐 채로 화면만 깜빡인다.
                        if await vm.replaceItem(target.item, with: replacement) {
                            onChanged()
                        }
                    }
                }
                editingTarget = nil
            }
        }
        .sheet(isPresented: $showAddItem) {
            MealItemEditView(mode: .addOne) { picked in
                if let added = picked.first {
                    Task {
                        if await vm.replaceItems(vm.editableItems + [added]) {
                            onChanged()
                        }
                    }
                }
                showAddItem = false
            }
        }
        .alert("끼니를 삭제할까요?", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) {
                Task {
                    if await vm.deleteMeal() {
                        onChanged()
                        dismiss()
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제하면 되돌릴 수 없어요.")
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

    /// 재조회가 실패해 화면이 낡았을 때. **편집이 막혀 있으므로 다시 불러올 길을 줘야 한다** —
    /// 안 그러면 화면을 나갔다 들어오는 것 말고는 방법이 없다.
    private var staleBanner: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.orange400)
                Text("최신 상태를 불러오지 못했어요. 지금 보이는 내용이 서버와 다를 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(Color.slate700)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("다시 불러오기") {
                    Task { await vm.load() }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.blue500)
                .buttonStyle(.plain)
            }
        }
    }

    private func itemsCard(_ meal: Meal) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("먹은 것")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Spacer()
                    Text("\(Int(meal.totalKcal.rounded()))kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.slate900)
                }

                ForEach(meal.items) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.foodName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.slate700)

                                // 식품DB 매칭이 안 됐음을 알린다.
                                if item.source == .llmEstimated {
                                    Text("추정")
                                        .font(.caption2)
                                        .foregroundStyle(Color.orange400)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color.orange100, in: Capsule())
                                }
                            }
                            Text("\(Int(item.quantityG.rounded()))g · \(Int(item.kcal.rounded()))kcal")
                                .font(.caption2)
                                .foregroundStyle(Color.slate400)
                        }

                        Spacer()

                        Button {
                            if let current = vm.editableItem(matching: item) {
                                editingTarget = EditingTarget(item: item, current: current)
                            }
                        } label: {
                            Image(systemName: "pencil").foregroundStyle(Color.blue500)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isSaving)

                        Button {
                            Task {
                                if await vm.deleteItem(item) {
                                    onChanged()
                                }
                            }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(Color.red400)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isSaving)
                    }
                }

                Button {
                    showAddItem = true
                } label: {
                    Label("음식 추가", systemImage: "plus").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.blue500)
                .disabled(vm.isSaving)
            }
        }
    }

    /// 이 피드백은 **그 끼니의 균형에 대해서만** 말한다 — 하루 맥락 조언은 하루 요약 카드에 있다.
    @ViewBuilder
    private func feedbackCard(_ meal: Meal) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("피드백")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                if let feedback = meal.feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(Color.slate700)
                        .fixedSize(horizontal: false, vertical: true)
                } else if vm.isFeedbackPending {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("피드백을 만들고 있어요")
                            .font(.caption)
                            .foregroundStyle(Color.slate400)
                    }
                } else {
                    Text("피드백을 만들지 못했어요. 항목을 고치면 다시 만들어져요.")
                        .font(.caption)
                        .foregroundStyle(Color.slate400)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Text("끼니 삭제")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .appGlassButton()
        .foregroundStyle(Color.red500)
        .disabled(vm.isSaving)
    }
}
