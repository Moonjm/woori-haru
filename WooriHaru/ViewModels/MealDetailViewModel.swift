import Foundation

/// 타입을 골랐을 때 화면이 할 일. **문구를 뷰모델에서 정한다** — 「합쳐진다」와 「모르겠다」가
/// 다른 말이라, 뷰가 하나의 문구로 뭉뚱그리면 사용자가 무엇을 승인하는지 모른다
/// (`MealConfirmViewModel.SaveAction`과 같은 모양이고 같은 이유다).
enum MealTypeChangeAction: Equatable {
    case confirm(title: String, message: String)
    case change
}

/// 타입을 바꾼 결과.
enum MealTypeChangeOutcome: Equatable {
    /// 화면에 남는다 — 제목만 바뀐다.
    case changed
    /// **보던 끼니가 사라졌다.** 상세를 닫고 하루로 돌아간다.
    case merged
    case failed
}

/// 끼니 상세 — 항목 수정·항목 삭제·**끼니 삭제**, 그리고 끼니 피드백 폴링.
///
/// **피드백 폴링은 화면을 붙잡지 않는다.** 확정 응답 시점에 점수·항목은 이미 확정돼 있다.
@MainActor
@Observable
final class MealDetailViewModel {
    let mealId: Int

    private(set) var meal: Meal?
    private(set) var isLoading = false
    private(set) var isFeedbackPending = false
    private(set) var isFeedbackDelayed = false
    /// 끼니가 삭제됐다. 화면은 이 신호로 하루 요약을 다시 조회하고 뒤로 나간다.
    private(set) var didDelete = false
    /// 항목 수정·삭제·추가 요청이 진행 중이다. **이 동안은 두 번째 변경을 아예 보내지 않는다** —
    /// 항목 편집 하나하나가 각자 네트워크 왕복이라, 두 번의 빠른 조작(A 수정, B 삭제)이 같은
    /// `meal.items` 스냅샷 위에서 각각 요청을 보내면 나중에 끝난 쪽이 먼저 끝난 쪽을 덮어써
    /// 사용자가 방금 한 변경 하나가 소리 없이 사라진다.
    private(set) var isSaving = false
    /// 화면에 보이는 끼니가 서버 상태와 다를 수 있다. **저장은 성공했는데 그 뒤 재조회가
    /// 실패한 경우**가 여기 걸린다 — 그 상태에서 또 편집하면 낡은 `editableItems` 위에서
    /// 만든 목록이 방금 성공한 변경을 덮어쓴다(항목 전체 교체 방식이라 그렇다).
    /// 다시 읽어 오기 전까지 편집을 받지 않고, 화면은 다시 불러올 길을 띄운다.
    private(set) var isStale = false
    /// 마지막 조회가 실패했다. **`isStale`보다 넓다** — 첫 조회가 실패하면 `meal`이 nil이라
    /// `isStale`은 false로 남는데, 그때가 오히려 사용자가 빈 화면에 갇히는 경우다.
    private(set) var loadFailed = false
    /// 끼니 타입 변경 **판정**이 진행 중이다(`fetchDay` 왕복).
    ///
    /// **`isSaving`으로는 부족하다.** 그것은 실제 전송이 시작돼야 켜지는데, 판정은 그 전에
    /// 네트워크 한 번을 왕복한다. 그 사이 메뉴가 열려 있으면 두 판정이 겹치고, **먼저 끝난
    /// 쪽이 저장을 잡아 나중에 고른 것이 `isSaving` 가드에 막혀 조용히 사라진다** —
    /// 사용자가 마지막에 고른 것이 말없이 뒤집힌다.
    ///
    /// `MealConfirmViewModel.isResolvingSave`와 같은 이유로 둔다.
    private(set) var isResolvingTypeChange = false
    var errorMessage: String?

    /// 다시 불러오기 배너에 쓸 문구. **끼니가 있느냐 없느냐로 말이 달라진다** — 앞은 「보이는
    /// 게 낡았을 수 있다」이고 뒤는 「아무것도 못 받았다」다.
    var loadFailureText: String? {
        guard loadFailed else { return nil }
        return meal == nil
            ? "끼니를 불러오지 못했어요."
            : "최신 상태를 불러오지 못했어요. 지금 보이는 내용이 서버와 다를 수 있어요."
    }

    private var generation = 0
    private var feedbackTask: Task<Void, Never>?

    private let service: any DietServing
    private let pollInterval: Duration
    private let pollTimeout: Duration

    init(
        mealId: Int,
        service: any DietServing = DietService(),
        pollInterval: Duration = DietPolicy.pollInterval,
        pollTimeout: Duration = DietPolicy.pollTimeout
    ) {
        self.mealId = mealId
        self.service = service
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    /// 편집 화면으로 넘길 현재 항목들.
    var editableItems: [MealItemRequest] {
        (meal?.items ?? []).map { item in
            MealItemRequest(
                foodName: item.foodName, foodCode: item.foodCode, quantityG: item.quantityG,
                kcal: item.kcal, carbsG: item.carbsG, proteinG: item.proteinG, fatG: item.fatG,
                sugarG: item.sugarG, sodiumMg: item.sodiumMg, fiberG: item.fiberG, source: item.source
            )
        }
    }

    /// 교체 시트에 넘길 대상. **id로 자리를 찾는다** — 이름·수량으로 거르면 같은 음식을
    /// 두 번 담은 끼니에서 엉뚱한 쪽을 집는다. 목록에 없으면 nil.
    func editableItem(matching item: MealItem) -> MealItemRequest? {
        guard let items = meal?.items, let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return editableItems[index]
    }

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        feedbackTask?.cancel()
        isFeedbackDelayed = false
        // 폴링 중이던 이전 로드가 실패로 끝나면 "만드는 중" 표시가 방치된다 — 취소한
        // 자리에서 같이 꺼야 화면이 무한 로딩으로 남지 않는다.
        isFeedbackPending = false
        defer { isLoading = false }

        do {
            // presigned URL은 10분 만료라 화면을 다시 열 때 조회한다 —
            // 사진이 여러 장이어도 만료 시각이 같으니 한 번에 다시 받는다.
            let loaded = try await service.fetchMeal(id: mealId)
            guard token == generation else { return }
            meal = loaded
            isStale = false
            loadFailed = false
            startFeedbackPollingIfNeeded(token: token)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            errorMessage = error.dietErrorCode == .resourceNotFound
                ? "찾을 수 없습니다."
                : error.localizedDescription
            loadFailed = true
            // 화면에 끼니가 남아 있는데 조회에 실패했다 — 보이는 것이 서버 상태와 같다고
            // 보장할 수 없다. 특히 저장 직후 재조회가 실패한 경우가 위험하다(아래 참조).
            //
            // **끼니가 아예 없는 경우는 여기 안 걸린다.** 그래서 화면이 `isStale`만 보면
            // 첫 조회 실패는 아무 길도 안 남긴다 — `loadFailed`를 따로 세우는 이유다.
            isStale = meal != nil
        }
    }

    private func startFeedbackPollingIfNeeded(token: Int) {
        guard meal?.status == .pending else {
            isFeedbackPending = false
            return
        }
        isFeedbackPending = true
        feedbackTask = Task { [weak self] in
            await self?.pollFeedback(token: token)
        }
    }

    private func pollFeedback(token: Int) async {
        let deadline = ContinuousClock.now + pollTimeout

        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
                let refreshed = try await service.fetchMeal(id: mealId)
                guard token == generation else { return }

                if refreshed.status != .pending {
                    meal = refreshed
                    isFeedbackPending = false
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }

        guard token == generation else { return }
        isFeedbackPending = false
        isFeedbackDelayed = true
    }

    func waitForFeedbackPolling() async {
        await feedbackTask?.value
    }

    /// 항목 전체 교체 → 서버가 영양소·점수·피드백을 재계산한다.
    /// **성공했을 때만 `true`를 돌려준다** — 화면은 이 값으로만 하루 화면 재조회(`onChanged`)를
    /// 트리거해야 한다. 가드가 막았거나 서버가 거절했을 때 재조회하면 바뀐 것도 없이 깜빡인다.
    @discardableResult
    func replaceItems(_ items: [MealItemRequest]) async -> Bool {
        // 이미 진행 중인 변경이 있으면 새 변경을 아예 받지 않는다 — 받아 주면 두 요청이 같은
        // 이전 스냅샷 위에서 출발해 나중에 끝난 쪽이 먼저 것을 덮어쓴다.
        guard !isSaving else { return false }

        // 재조회에 실패해 화면이 낡았을 수 있다. 같은 이유로 받지 않는다 — 낡은
        // `editableItems`에서 만든 목록을 보내면 **앞서 성공한 변경이 사라진다.**
        guard !isStale else {
            errorMessage = "최신 상태를 불러오지 못했어요. 다시 불러온 뒤 수정해 주세요."
            return false
        }

        guard !items.isEmpty else {
            // 서버가 빈 배열을 거절한다 — 다 지우고 싶으면 끼니를 삭제해야 한다.
            errorMessage = "항목을 모두 지우려면 끼니를 삭제해 주세요."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await service.updateMealItems(id: mealId, items: items)
            await load()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// **id로 자리를 찾는다.** 이름·수량으로 거르면 같은 음식을 두 번 담은 끼니에서 둘 다 지워진다.
    @discardableResult
    func deleteItem(_ item: MealItem) async -> Bool {
        guard let items = meal?.items, let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        var remaining = editableItems
        remaining.remove(at: index)
        return await replaceItems(remaining)
    }

    /// 항목 하나를 교체한다. `editableItems`가 `meal.items`와 같은 순서라 인덱스를 그대로 쓴다.
    @discardableResult
    func replaceItem(_ item: MealItem, with replacement: MealItemRequest) async -> Bool {
        guard let items = meal?.items, let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        var changed = editableItems
        changed[index] = replacement
        return await replaceItems(changed)
    }

    /// 타입을 고른 뒤 **보내기 전에** 부른다. nil이면 아무것도 하지 않는다(같은 타입).
    ///
    /// **그날을 조회해 합쳐질지 먼저 본다.** 판단은 확정 저장과 같다
    /// (`MealConfirmViewModel.resolveSaveAction`) — 조회가 실패했으면 **모르는 채로 넘어가지
    /// 않고 물어본다.** 「없다」와 「모른다」를 같게 다루면 접속이 잠깐 끊긴 것만으로 보호
    /// 장치가 사라진다.
    func resolveTypeChange(to newType: MealType) async -> MealTypeChangeAction? {
        guard let meal, meal.mealType != newType else { return nil }
        // **겹쳐 고른 것은 무시한다 — 먼저 고른 것이 이긴다.** 화면이 메뉴를 잠그지만
        // (`isResolvingTypeChange`), 여기서도 막아야 계약이 화면에 기대지 않는다.
        guard !isResolvingTypeChange else { return nil }
        // 간식은 본래 여러 번이라 합쳐지지 않는다 — 물어볼 것이 없다.
        guard newType.mergesWithinDay else { return .change }

        isResolvingTypeChange = true
        defer { isResolvingTypeChange = false }

        do {
            let day = try await service.fetchDay(date: meal.date)
            // **자기 자신은 뺀다** — 그날 목록에는 지금 보고 있는 끼니도 들어 있다.
            guard day.meals.contains(where: { $0.mealType == newType && $0.id != meal.id }) else {
                return .change
            }
            return .confirm(
                title: "이미 기록한 \(newType.label)이 있어요",
                message: "이미 기록한 \(newType.label)에 합쳐져요. 사진도 함께 옮겨져요. 합쳐진 뒤에는 되돌릴 수 없어요."
            )
        } catch {
            return .confirm(
                title: "이미 기록한 \(newType.label)이 있는지 확인하지 못했어요",
                message: "있다면 합쳐지고, 합쳐진 뒤에는 되돌릴 수 없어요."
            )
        }
    }

    /// 실제로 보낸다. **`resolveTypeChange`가 `.change`를 줬거나 사용자가 확인을 누른 뒤**에만
    /// 부른다.
    ///
    /// **돌려받은 id가 원래와 다르면 합쳐진 것이다** — 항목·사진이 대상 끼니로 옮겨지고 이
    /// 끼니는 서버에서 사라졌다. 그 자리에서 다시 조회하면 404라 `load()`를 부르지 않는다.
    ///
    /// **`isStale`을 검사하지 않는다.** 항목 편집은 낡은 목록을 통째로 보내서 막지만, 여기는
    /// **항목을 아예 안 보낸다** — 덮어쓸 목록이 없다.
    func changeMealType(to newType: MealType) async -> MealTypeChangeOutcome {
        guard let meal, meal.mealType != newType, !isSaving else { return .failed }

        isSaving = true
        defer { isSaving = false }

        do {
            let survivorId = try await service.changeMealType(id: meal.id, to: newType)
            guard survivorId == meal.id else { return .merged }
            await load()
            return .changed
        } catch is CancellationError {
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    /// 수량 시트용 저장. **결과에 이유를 담아 돌려준다** — 시트가 상세 화면을 덮고 있어
    /// 상세가 띄우는 오류 알럿이 화면에 나타나지 않는다(사진 뷰어에서 같은 것을 겪었다).
    func saveQuantity(_ item: MealItem, with replacement: MealItemRequest) async -> QuantitySaveOutcome {
        guard await replaceItem(item, with: replacement) else {
            // **상세 쪽 값을 지운다** — 안 지우면 시트를 닫은 뒤 같은 오류가 한 번 더 뜬다.
            let message = errorMessage ?? "저장하지 못했어요."
            errorMessage = nil
            return .failed(message)
        }
        return .saved
    }

    /// 사진 주소를 다시 받는다. **presigned URL은 10분 만료다** — 상세를 열어 둔 채 시간이
    /// 지나면 전체화면 보기가 실패하는데, 같은 주소로 다시 내려받아 봐야 같은 실패다.
    /// 끼니를 다시 조회해 그 사진의 새 주소를 돌려준다. 그 사이 사라진 사진이면 nil.
    func refreshedPhotoURL(fileId: Int) async -> String? {
        await load()
        return meal?.photos.first { $0.fileId == fileId }?.url
    }

    /// 사진 한 장 삭제. 되돌릴 수 없다.
    ///
    /// **끼니 점수·피드백은 그대로다.** 점수는 항목에서만 나오고 피드백 프롬프트에도 사진이
    /// 안 들어간다 — 사진이 줄어도 먹은 것은 그대로라 서버가 재계산하지 않는다. 하루 집계도
    /// 안 바뀌므로 **화면은 이 성공으로 하루 재조회(`onChanged`)를 걸 이유가 없다.**
    @discardableResult
    func deletePhoto(fileId: Int) async -> Bool {
        // 항목 편집과 같은 가드다. 사진 삭제 두 번이 겹치면 두 번째가 이미 사라진 `fileId`를
        // 한 번 더 보내고, 항목 변경과 겹치면 뒤에 끝난 재조회가 앞의 결과를 덮어쓴다.
        guard !isSaving else { return false }

        // 화면이 낡았으면 지금 보이는 사진이 서버의 그 사진이라고 보장할 수 없다 —
        // 엉뚱한 장을 지우게 된다.
        guard !isStale else {
            errorMessage = "최신 상태를 불러오지 못했어요. 다시 불러온 뒤 지워 주세요."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await service.deleteMealPhoto(mealId: mealId, fileId: fileId)
            // presigned URL이 남은 사진마다 다시 필요하다 — 통째로 다시 읽는다.
            await load()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.dietErrorCode == .resourceNotFound
                ? "이미 지워진 사진입니다."
                : error.localizedDescription
            return false
        }
    }

    /// 되돌릴 수 없다. 서버는 사진을 `TEMP`로 되돌리고 그날 하루 피드백 캐시를 지운다 —
    /// **그래서 삭제 뒤에는 하루 요약을 다시 조회해야 한다.**
    @discardableResult
    func deleteMeal() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.deleteMeal(id: mealId)
            didDelete = true
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
