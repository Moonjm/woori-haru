import Foundation

/// 인식 결과를 확인·수정하고 확정한다. **저장하기 전에는 `Meal`이 만들어지지 않는다.**
///
/// `analysis`가 `nil`이면 **사진 없는 기록**이다 — 검색·직접 입력으로 만든 항목만 저장한다.
@MainActor
@Observable
final class MealConfirmViewModel {
    /// 사진 하나에서 나온 항목 묶음. 사진 없는 기록에서는 `fileId`가 nil인 그룹 하나뿐이다.
    struct PhotoGroup: Identifiable {
        let id: Int
        let fileId: Int?
        let url: String?
        let failed: Bool
        var items: [MealItemRequest]
    }

    let date: Date
    var mealType: MealType
    private(set) var groups: [PhotoGroup]
    private(set) var isSaving = false
    private(set) var savedMealID: Int?
    /// 확정을 서버가 `PROFILE_NOT_FOUND`로 거절했다 — 프로필 화면으로 보내야 한다.
    private(set) var needsProfile = false
    /// 인식 원본에서 하나라도 달라졌는지. 저장 없이 나갈 때 알럿을 띄울지 판단한다.
    private(set) var hasChanges = false
    var errorMessage: String?

    private let analysisId: Int?
    private let service: any DietServing

    init(
        date: Date,
        mealType: MealType,
        analysis: MealAnalysis?,
        service: any DietServing = DietService()
    ) {
        self.date = date
        self.mealType = mealType
        self.analysisId = analysis?.id
        self.service = service

        if let analysis {
            self.groups = analysis.photos.enumerated().map { index, photo in
                PhotoGroup(
                    id: index,
                    fileId: photo.fileId,
                    url: photo.url,
                    failed: photo.failed,
                    items: photo.items.map(NutritionMath.request(from:))
                )
            }
        } else {
            // 사진 없는 기록 — 담을 자리 하나만 둔다.
            self.groups = [PhotoGroup(id: 0, fileId: nil, url: nil, failed: false, items: [])]
        }
    }

    /// 그날 이미 기록해 둔 끼니 종류. **안내 한 줄에만 쓴다** — 저장 동작에는 영향이 없다.
    private(set) var existingMealTypes: Set<MealType> = []

    /// 저장 버튼을 누르기 전에 무슨 일이 일어날지 알려 준다. 서버가 같은 날 같은 끼니를
    /// 하나로 묶으므로(간식 제외), 새 카드가 생기는 줄 알았다가 합쳐지면 당황한다.
    var mergeNoticeText: String? {
        guard mealType.mergesWithinDay, existingMealTypes.contains(mealType) else { return nil }
        return "이미 기록한 \(mealType.label)에 합쳐져요."
    }

    /// **실패해도 조용히 넘어간다** — 안내 한 줄이 없을 뿐이고, 여기까지 오는 데 이미 LLM
    /// 비용과 대기시간이 들었다. 이 조회 때문에 확인 화면이 막히면 안 된다.
    func loadExistingMeals() async {
        guard let day = try? await service.fetchDay(date: date.dateString) else { return }
        existingMealTypes = Set(day.meals.map(\.mealType))
    }

    var hasPhotos: Bool { groups.contains { $0.fileId != nil } }
    var photoURLs: [String] { groups.compactMap(\.url) }
    var failedFileIds: Set<Int> { Set(groups.filter(\.failed).compactMap(\.fileId)) }

    var allItems: [MealItemRequest] { groups.flatMap(\.items) }

    var totalKcal: Double { allItems.reduce(0) { $0 + $1.kcal } }
    var totalCarbsG: Double { allItems.reduce(0) { $0 + $1.carbsG } }
    var totalProteinG: Double { allItems.reduce(0) { $0 + $1.proteinG } }
    var totalFatG: Double { allItems.reduce(0) { $0 + $1.fatG } }

    /// 서버가 빈 배열을 거절한다.
    var canSave: Bool { !allItems.isEmpty && !isSaving }

    // MARK: - 편집

    func removeItem(_ item: MealItemRequest, in groupId: Int) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].items.removeAll { $0.id == item.id }
        hasChanges = true
    }

    /// 수량을 바꾸면 영양소 7개가 함께 비례한다 — 서버와 같은 환산이 `NutritionMath`에 있다.
    ///
    /// **0 이하는 여기서 막는다.** `NutritionMath.rescaled`는 현재 수량이 0이면 0으로 나누지
    /// 않으려고 수량만 바꾸고 영양소는 그대로 둔다 — 그 자체는 맞는 방어지만, 호출부가 0을
    /// 들여보내면 이후로는 수량을 아무리 늘려도 영양소가 영원히 0에 묶인다("50g의 아무것도
    /// 아닌 것"). 행을 지우는 건 삭제 버튼의 몫이니, 수량 불변식은 뷰모델이 이 경계에서 지킨다.
    func updateQuantity(_ quantityG: Double, of item: MealItemRequest, in groupId: Int) {
        guard quantityG > 0 else { return }
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              let itemIndex = groups[groupIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
        groups[groupIndex].items[itemIndex] = NutritionMath.rescaled(item, to: quantityG)
        hasChanges = true
    }

    /// 식품 검색으로 교체.
    func replaceItem(_ item: MealItemRequest, with replacement: MealItemRequest, in groupId: Int) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              let itemIndex = groups[groupIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
        groups[groupIndex].items[itemIndex] = replacement
        hasChanges = true
    }

    /// 인식이 놓친 음식 추가.
    func addItem(_ item: MealItemRequest, to groupId: Int) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].items.append(item)
        hasChanges = true
    }

    /// 실패한 사진의 재시도 결과를 병합한다. **이전에 실패했다가 이번에 성공한 그룹만** 새
    /// 항목으로 바꾼다 — 사용자가 다른 그룹에서 이미 고치고 있던 수량·삭제·추가는 그대로
    /// 둔다. `fileId`로 맞춘다 — 배열 순서가 밀려도 엉뚱한 사진에 항목이 옮겨붙지 않는다.
    func applyRetriedAnalysis(_ analysis: MealAnalysis) {
        // **끝난 결과만 병합한다.** 폴링은 진행 중(`.pending`) 응답도 그대로 내보낸다. 그걸
        // 병합하면 아직 인식이 안 끝난 사진을 「성공했는데 항목 0개」로 확정해 버리고, 그다음
        // 진짜 결과는 아래 가드(`groups[index].failed`)에 걸려 **영영 무시된다.**
        // 지금 서버는 재인식을 한 번에 써서 그 상태가 안 나오지만, 그걸 막는 것이 아래 가드
        // 하나뿐이라 여기서 잠근다.
        guard analysis.status == .completed else { return }

        for photo in analysis.photos {
            guard let index = groups.firstIndex(where: { $0.fileId == photo.fileId }),
                  groups[index].failed, !photo.failed else { continue }
            groups[index] = PhotoGroup(
                id: groups[index].id,
                fileId: photo.fileId,
                url: photo.url,
                failed: false,
                items: photo.items.map(NutritionMath.request(from:))
            )
        }
    }

    // MARK: - 저장

    func save() async {
        guard canSave else { return }
        isSaving = true
        needsProfile = false
        errorMessage = nil
        defer { isSaving = false }

        do {
            // **인식 원본이 아니라 사용자가 고친 최종본을 보낸다.** 서버는 대조하지 않고 그대로 신뢰한다.
            savedMealID = try await service.confirmMeal(MealConfirmRequest(
                date: date.dateString,
                mealType: mealType,
                analysisId: analysisId,
                items: allItems
            ))
        } catch is CancellationError {
            return
        } catch {
            switch error.dietErrorCode {
            case .profileNotFound:
                needsProfile = true
            case .analysisNotConfirmable:
                errorMessage = "인식이 아직 끝나지 않았습니다. 잠시 후 다시 시도해 주세요."
            default:
                errorMessage = error.localizedDescription
            }
        }
    }
}
