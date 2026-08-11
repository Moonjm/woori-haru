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
    /// **고르기 전에는 nil이다.** 기본값을 박아 두면 그대로 저장돼, 나중에 고치는 일이
    /// 반복된다. 「골랐는지」를 별도 플래그로 들지 않는 이유는 그때 값이 여전히 남아 있어
    /// 검사를 한 군데만 빠뜨려도 고르지 않은 끼니가 서버로 나가기 때문이다.
    var mealType: MealType?
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
        mealType: MealType?,
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

    /// 그날 이미 기록해 둔 끼니 종류. **안내와 확인에만 쓴다** — 저장 동작 자체는 서버가
    /// 정한다(같은 날 같은 끼니를 합치는 것은 서버 규칙이고 앱이 고를 수 있는 게 아니다).
    private(set) var existingMealTypes: Set<MealType> = []

    /// 저장하면 기존 끼니에 합쳐지는 상태인가. 간식은 본래 여러 번이라 묶지 않는다.
    var mergesIntoExisting: Bool {
        guard let mealType else { return false }
        return mealType.mergesWithinDay && existingMealTypes.contains(mealType)
    }

    /// 저장 버튼을 누르기 전에 무슨 일이 일어날지 알려 준다. 서버가 같은 날 같은 끼니를
    /// 하나로 묶으므로(간식 제외), 새 카드가 생기는 줄 알았다가 합쳐지면 당황한다.
    var mergeNoticeText: String? {
        guard mergesIntoExisting, let mealType else { return nil }
        return "이미 기록한 \(mealType.label)에 합쳐져요."
    }

    /// 그날 조회가 실패했다. **「합쳐질 끼니가 없다」와 구분해야 한다** — 앞은 안심해도 되는
    /// 상태이고 이것은 아무것도 모르는 상태다.
    private(set) var existingLookupFailed = false
    /// 저장을 누르고 조회를 기다리는 중. 버튼이 멈춘 것처럼 보이지 않게 한다.
    private(set) var isResolvingSave = false

    /// 진행 중인 그날 조회. **저장 판단이 이 결과에 걸려 있으므로 손에 쥐고 있어야 한다** —
    /// 화면이 열리자마자 시작하고, 저장을 누른 시점에 아직 안 끝났으면 기다린다.
    private var existingLookup: Task<Void, Never>?

    /// 저장 버튼을 눌렀을 때 할 일.
    enum SaveAction: Equatable {
        /// 알럿을 띄운다. 문구를 여기서 정한다 — 「합쳐진다」와 「모르겠다」가 다른 말이다.
        case confirm(title: String, message: String)
        case save
    }

    /// 화면이 열릴 때 시작한다. **`await`로 붙잡지 않는다** — 여기까지 오는 데 이미 LLM
    /// 비용과 대기시간이 들었으므로 이 조회가 화면을 막으면 안 된다.
    func loadExistingMeals() async {
        startExistingLookup()
        await existingLookup?.value
    }

    private func startExistingLookup() {
        guard existingLookup == nil else { return }
        existingLookup = Task { [weak self] in
            guard let self else { return }
            do {
                let day = try await service.fetchDay(date: date.dateString)
                existingMealTypes = Set(day.meals.map(\.mealType))
                existingLookupFailed = false
            } catch {
                existingLookupFailed = true
            }
        }
    }

    /// 저장을 눌렀다. **조회를 기다린 뒤에 정한다.**
    ///
    /// 기다리지 않으면 조회가 느릴 때 `existingMealTypes`가 빈 채로 남아, 빠르게 누른
    /// 사용자가 확인 없이 저장한다 — **보호 장치가 없어지는 쪽으로 조용히 실패한다.**
    /// 되돌릴 수 없는 병합이라 그 방향의 실패가 특히 나쁘다.
    ///
    /// 조회 자체가 실패했으면 **모르는 채로 넘어가지 않고 물어본다.** 「없다」와 「모른다」를
    /// 같게 다루면 접속이 잠깐 끊긴 것만으로 이 기능이 통째로 없는 것과 같아진다.
    func resolveSaveAction() async -> SaveAction {
        startExistingLookup()
        isResolvingSave = true
        defer { isResolvingSave = false }
        await existingLookup?.value

        // 끼니를 안 골랐으면 물어볼 것이 없다 — 저장 자체가 `canSave`에서 막힌다.
        guard let mealType else { return .save }

        if mergesIntoExisting {
            return .confirm(
                title: "이미 기록한 \(mealType.label)이 있어요",
                message: "저장하면 이미 기록한 \(mealType.label)에 합쳐져요. 따로 남기려면 취소하고 다른 끼니를 골라 주세요."
            )
        }
        if existingLookupFailed, mealType.mergesWithinDay {
            return .confirm(
                title: "이미 기록한 \(mealType.label)이 있는지 확인하지 못했어요",
                message: "있다면 저장할 때 합쳐지고, 합쳐진 뒤에는 되돌릴 수 없어요."
            )
        }
        return .save
    }

    var hasPhotos: Bool { groups.contains { $0.fileId != nil } }
    var photoURLs: [String] { groups.compactMap(\.url) }
    var failedFileIds: Set<Int> { Set(groups.filter(\.failed).compactMap(\.fileId)) }

    var allItems: [MealItemRequest] { groups.flatMap(\.items) }

    var totalKcal: Double { allItems.reduce(0) { $0 + $1.kcal } }
    var totalCarbsG: Double { allItems.reduce(0) { $0 + $1.carbsG } }
    var totalProteinG: Double { allItems.reduce(0) { $0 + $1.proteinG } }
    var totalFatG: Double { allItems.reduce(0) { $0 + $1.fatG } }

    /// 서버가 빈 배열을 거절한다. 조회를 기다리는 동안에도 잠근다 — 연타로 두 번 눌리면
    /// 알럿이 두 번 뜬다. **끼니를 고르기 전에도 잠근다** — 기본값으로 저장되는 것을 막는
    /// 게이트가 여기 하나다(사진 경로와 직접 추가 경로가 둘 다 이 화면을 거친다).
    var canSave: Bool { mealType != nil && !allItems.isEmpty && !isSaving && !isResolvingSave }

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

    /// 스테퍼 ⊕⊖. **격자는 `GramStepper`가 정한다** — 검색 상세·끼니 항목 수정과 같은
    /// 폭으로 움직여야 한다. 이 화면이 오래 ±50g·하한 10g을 따로 들고 있었고, 그래서
    /// 스테퍼를 25g으로 바꿨을 때 여기만 안 따라왔다.
    ///
    /// **뷰가 아니라 여기서 계산한다** — 뷰에 있으면 격자가 맞는지 테스트가 못 닿는다.
    func increaseQuantity(of item: MealItemRequest, in groupId: Int) {
        updateQuantity(item.quantityG + GramStepper.step, of: item, in: groupId)
    }

    /// 바닥은 0이 아니다 — 0으로 내려가면 영양소가 전부 0으로 굳고 되돌릴 수 없다.
    /// 하한에서도 값이 하한으로 맞춰져서 버튼이 「먹히긴 했다」는 것이 보인다.
    func decreaseQuantity(of item: MealItemRequest, in groupId: Int) {
        updateQuantity(max(GramStepper.minimum, item.quantityG - GramStepper.step), of: item, in: groupId)
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
            // **직접 넣은 항목을 지우지 않는다.** 인식이 실패한 그룹에도 「음식 추가」가
            // 열려 있어서, 사용자가 포기하고 손으로 넣은 뒤 재시도를 누르는 경로가 있다.
            // 그룹을 통째로 갈아 끼우면 그 입력이 소리 없이 사라진다.
            //
            // 겹쳐서 담길 수는 있다(손으로 넣은 것과 인식한 것이 같은 음식일 때). 하지만
            // **겹친 것은 눈에 보이고 지울 수 있는 반면, 사라진 것은 알 길이 없다.**
            let editedByUser = groups[index].items
            groups[index] = PhotoGroup(
                id: groups[index].id,
                fileId: photo.fileId,
                url: photo.url,
                failed: false,
                items: photo.items.map(NutritionMath.request(from:)) + editedByUser
            )
        }
    }

    // MARK: - 저장

    func save() async {
        // `canSave`가 이미 nil을 막지만 강제 언래핑하지 않는다 — 나중에 `canSave`의 조건이
        // 하나 바뀌면 그 크래시는 사용자 기기에서 처음 발견된다.
        guard canSave, let mealType else { return }
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
