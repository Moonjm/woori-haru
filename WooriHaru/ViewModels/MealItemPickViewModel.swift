import Foundation

/// 시트가 열린 자리마다 다중 선택 여부가 다르다.
enum MealItemPickMode: Equatable {
    /// 교체 — 대상이 하나로 정해져 있다.
    case replace(MealItemRequest)
    /// 한 개 담기 — 이미 저장된 끼니를 고치는 자리라 **하나씩 확인하며 바꾸는 편이 안전하다.**
    case addOne
    /// 여러 개 담기 — 아직 저장 전이라 모아서 담아도 왕복이 없다.
    case addMany

    var allowsMultiple: Bool { self == .addMany }

    var title: String {
        switch self {
        case .replace: "음식 교체"
        case .addOne, .addMany: "음식 추가"
        }
    }

    /// 「「제육볶음」을 교체합니다」 — 교체 모드에서만 보인다.
    var replacingText: String? {
        guard case let .replace(item) = self else { return nil }
        return "「\(item.foodName)」을 교체합니다"
    }
}

/// 항목 고르기 — 자주 드셨어요 · 검색결과 · 직접 등록 세 탭과 (여러 개 모드의) 바구니.
@MainActor
@Observable
final class MealItemPickViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case frequent, search, manual

        var id: String { rawValue }
        var label: String {
            switch self {
            case .frequent: "자주 드셨어요"
            case .search: "검색결과"
            case .manual: "직접 등록"
            }
        }
    }

    /// 검색결과 탭에서만 보인다. **가공식품 30만 건과 원재료 523건이 섞여 나오므로
    /// 구분이 실제로 필요하다.**
    enum DatasetFilter: String, CaseIterable, Identifiable {
        case all, dish, raw, processed

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "전체"
            case .dish: "음식"
            case .raw: "원재료"
            case .processed: "가공식품"
            }
        }
        var dataset: FoodDataset? {
            switch self {
            case .all: nil
            case .dish: .dish
            case .raw: .raw
            case .processed: .processed
            }
        }
    }

    /// 고르기 한 번의 결과. 화면은 이 값만 보고 움직인다.
    enum PickOutcome: Equatable {
        /// 담을 기본 수량이 없다 — 상세 시트를 연다.
        case needsDetail
        /// 한 개 모드 — 이 항목을 넘기고 시트를 닫는다.
        case commit([MealItemRequest])
        /// 여러 개 모드 — 바구니에 담았다. 시트는 열려 있다.
        case collected
    }

    /// 바구니 한 칸. 같은 음식을 두 번 담을 수 있으므로 항목의 UUID가 키다.
    struct PickedItem: Identifiable, Hashable {
        let sourceId: String
        let item: MealItemRequest

        var id: UUID { item.id }
    }

    let mode: MealItemPickMode

    var tab: Tab = .frequent
    var filter: DatasetFilter = .all
    var query = ""

    private(set) var frequentItems: [FrequentItem] = []
    private(set) var searchResults: [Food] = []
    private(set) var isSearching = false
    /// 마지막 검색이 실패했다. **결과 0건과 구분해야 한다** — 알럿은 닫히고 나면 사라지는데
    /// 목록은 남아, 그때 「검색 결과가 없어요」를 띄우면 원인을 잘못 짚게 된다.
    private(set) var searchFailed = false
    private(set) var profile: NutritionProfile?
    /// 여러 개 모드에서 모아 둔 항목. 한 개 모드에서는 항상 비어 있다.
    private(set) var picked: [PickedItem] = []

    // 직접 등록 — 포장지 영양성분표를 보고 채운다. **당류·나트륨·식이섬유 칸이 반드시
    // 있어야 한다** — 넷만 채워 보내면 서버가 나머지를 0.0으로 받아 말없이 저장한다.
    var manualName = ""
    var manualQuantity = ""
    var manualKcal = ""
    var manualCarbs = ""
    var manualProtein = ""
    var manualFat = ""
    var manualSugar = ""
    var manualSodium = ""
    var manualFiber = ""

    var errorMessage: String?

    /// 늦게 돌아온 옛 검색 응답을 버리는 표식. 새 검색이 시작될 때마다 올린다.
    private var searchGeneration = 0

    private let service: any DietServing

    init(mode: MealItemPickMode, service: any DietServing = DietService()) {
        self.mode = mode
        self.service = service
    }

    // MARK: - 목록

    var frequentSources: [FoodPickSource] { frequentItems.map(FoodPickSource.frequent) }

    /// 검색결과 탭 목록. **서버가 이미 `dataset`으로 거른 결과다** — 여기서 또 거르지 않는다.
    /// 두 곳에서 거르면 기준이 어긋나는 날 「검색은 됐는데 목록이 빈」 상태가 다시 생긴다.
    var searchSources: [FoodPickSource] { searchResults.map(FoodPickSource.food) }

    /// 검색결과 탭이 비었을 때 무엇을 보여줄지. **셋을 가른다** — 아직 검색 전인지, 정말
    /// 없는지, 칩 때문인지가 사용자에게 다른 다음 행동을 뜻한다.
    ///
    /// **기준이 「칩이 걸려 있나」다.** 예전에는 「받아 온 것과 거른 것이 다른가」로 갈랐는데,
    /// 서버가 거르는 지금은 그 둘이 항상 같아 세 번째 가지가 영영 안 밟힌다.
    var searchEmptyText: String? {
        guard searchSources.isEmpty else { return nil }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "찾을 음식을 검색해 주세요."
        }
        // **「없다」와 「못 받았다」를 구분한다.** 실패한 뒤에도 「검색 결과가 없어요」를 띄우면
        // 사용자가 그 음식이 식품DB에 없다고 믿고 직접 등록으로 간다.
        guard !searchFailed else {
            return "검색에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
        guard filter == .all else {
            return "「\(filter.label)」에는 검색 결과가 없어요. 「전체」로 보거나 검색어를 바꿔 보세요."
        }
        return "검색 결과가 없어요. 다른 이름으로 찾아 보세요."
    }

    /// 상세 시트의 「일일목표 %」 분모. 프로필이 없으면 nil이라 배지가 감춰진다.
    var targetKcal: Int? { profile?.targetKcal }

    // MARK: - 조회

    func load() async {
        do {
            frequentItems = try await service.fetchFrequentItems()
        } catch is CancellationError {
            return
        } catch {
            // 자주 드셨어요가 비어도 검색은 되어야 한다 — 화면을 막지 않는다.
            frequentItems = []
        }

        do {
            profile = try await service.fetchProfile()
        } catch {
            // 「일일목표 %」 배지만 못 보여준다. 담는 것 자체는 프로필과 무관하다.
            profile = nil
        }
    }

    /// 칩을 고른다. **칩이 곧 쿼리라 다시 검색해야 한다** — 서버가 `dataset`으로 거르므로
    /// 이미 받아 둔 결과를 다시 쓸 수 없다.
    ///
    /// `search()`가 `searchGeneration`을 올리므로 **먼저 나간 칩의 응답이 늦게 돌아와
    /// 덮어쓰는 일은 그쪽에서 막힌다** — 칩을 빠르게 두 번 누르는 경로가 이번에 새로 생긴다.
    func selectFilter(_ newFilter: DatasetFilter) async {
        guard newFilter != filter else { return }
        filter = newFilter
        await search()
    }

    /// 검색어를 확정하면 **검색결과 탭으로 자동 전환한다** — 결과가 다른 탭 뒤에 숨으면 안 된다.
    func search() async {
        // 앞선 검색이 아직 안 끝났는데 새 검색어를 넣을 수 있다. 토큰이 다르면 늦게 돌아온
        // 옛 응답이라 버린다 — 안 버리면 **나중에 끝난 쪽이 이기므로** 지금 검색어와 다른
        // 결과가 화면에 남는다(`DietDayViewModel`의 `generation`과 같은 처리).
        //
        // **검색어를 지운 경우에도 올려야 한다.** 안 올리면 진행 중이던 옛 검색이 아직
        // 유효한 토큰을 들고 돌아와, 빈 검색어 아래에 지운 결과를 도로 채운다.
        searchGeneration += 1
        let token = searchGeneration

        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        tab = .search
        isSearching = true
        // 새 조회를 시작할 때 지난 오류를 지운다 — 안 지우면 실패 뒤 성공한 검색에서
        // 정상 결과 위에 낡은 오류가 계속 떠 있는다(`DietDayViewModel.load()`와 같은 처리).
        errorMessage = nil
        searchFailed = false

        // **예전 결과를 여기서 버린다.** 안 버리면 이 요청이 도는 동안, 그리고 실패하면 영영,
        // 새 검색어·칩 라벨 아래에 이전 결과가 그대로 남는다 — 「원재료」를 눌렀는데 가공식품
        // 목록이 남아 있고 그걸 담을 수 있다. 서버가 거르게 된 뒤로 생긴 창이다(앱이 거를
        // 때는 칩과 목록이 어긋날 수 없었다).
        searchResults = []

        do {
            let results = try await service.searchFoods(query: keyword, dataset: filter.dataset)
            guard token == searchGeneration else { return }
            searchResults = results
        } catch is CancellationError {
            // 더 새로운 검색이 끼어들어 취소된 경우가 대부분이지만, 아니라면 스피너가
            // 영원히 남는다 — 내가 아직 최신일 때만 끈다.
            if token == searchGeneration { isSearching = false }
            return
        } catch {
            guard token == searchGeneration else { return }
            errorMessage = error.localizedDescription
            searchFailed = true
        }

        // **`defer`로 끄면 안 된다** — 먼저 나간 옛 검색이 돌아오면서 최신 검색이 아직
        // 도는 중인데도 스피너를 꺼 버린다. 여기까지 온 것은 토큰이 최신이라는 뜻이다.
        isSearching = false
    }

    // MARK: - 담기

    /// ⊕를 눌렀다. **담을 기본 수량이 없으면 담지 않고 상세 시트를 열라고 알린다.**
    @discardableResult
    func quickAdd(_ source: FoodPickSource) -> PickOutcome {
        guard let item = source.quickAddItem else { return .needsDetail }
        return accept(item, from: source)
    }

    /// 상세 시트에서 「추가하기」를 눌렀다.
    @discardableResult
    func accept(_ item: MealItemRequest, from source: FoodPickSource) -> PickOutcome {
        guard mode.allowsMultiple else { return .commit([item]) }
        picked.append(PickedItem(sourceId: source.id, item: item))
        return .collected
    }

    /// 직접 등록 탭에서 담았다. 칸이 덜 찼으면 nil.
    @discardableResult
    func acceptManual() -> PickOutcome? {
        guard let item = buildManualItem() else { return nil }
        guard mode.allowsMultiple else { return .commit([item]) }
        picked.append(PickedItem(sourceId: "manual-\(item.id.uuidString)", item: item))
        // **다음 항목이 앞 항목의 영양소를 물려받으면 안 된다** — 이름만 바꿔 담으면
        // 전혀 다른 음식이 앞 항목의 나트륨·식이섬유를 달고 조용히 저장된다.
        clearManualInput()
        return .collected
    }

    /// 하단 바 「N개 담기」가 넘길 항목들.
    func commitPicked() -> [MealItemRequest] { picked.map(\.item) }

    /// 행에 붙는 「담김 N」 배지. **여러 개 모드에서만 센다.**
    func pickedCount(for source: FoodPickSource) -> Int {
        picked.filter { $0.sourceId == source.id }.count
    }

    var showsBottomBar: Bool { mode.allowsMultiple }
    var canCommitPicked: Bool { !picked.isEmpty }
    var bottomBarText: String { "\(picked.count)개 담기" }

    // MARK: - 직접 등록

    /// 탭을 옮겨도 칸을 지우지 않는다. 옛 화면은 검색과 직접 입력이 같은 자리를 번갈아 써서
    /// **안 보이는 값이 남아 다른 음식 이름을 달고 담기는** 결함이 있었지만, 탭에서는 직접
    /// 등록 화면에 있는 동안 모든 칸이 그대로 보이므로 남아 있는 편이 맞다.
    func buildManualItem() -> MealItemRequest? {
        let name = manualName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let quantity = manualQuantityG else { return nil }
        guard let kcal = manualNutrient(manualKcal),
              let carbs = manualNutrient(manualCarbs),
              let protein = manualNutrient(manualProtein),
              let fat = manualNutrient(manualFat),
              let sugar = manualNutrient(manualSugar),
              let sodium = manualNutrient(manualSodium),
              let fiber = manualNutrient(manualFiber) else { return nil }

        return NutritionMath.manualItem(
            name: name,
            quantityG: quantity,
            kcal: kcal, carbsG: carbs, proteinG: protein, fatG: fat,
            sugarG: sugar, sodiumMg: sodium, fiberG: fiber
        )
    }

    /// **`isFinite`까지 본다** — `Double("inf")`는 `> 0`을 통과하고, 그 값은 JSON 인코딩에서
    /// 터져 저장 자체가 실패한다.
    private var manualQuantityG: Double? {
        guard let value = Double(manualQuantity.trimmingCharacters(in: .whitespaces)),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    /// 영양소 칸 하나를 읽는다. **빈 칸은 0이다**(안 적은 것) — 하지만 **잘못 적힌 칸을 0으로
    /// 갈아 끼우지는 않는다.**
    ///
    /// 예전에는 `Double(text) ?? 0`이라 오타 하나가 「나트륨 0mg」으로 조용히 저장됐다.
    /// 사용자는 자기가 적은 값이 들어간 줄 안다 — 화면에는 적은 대로 남아 있으니까.
    /// 음수도 여기서 막는다. 서버가 거절하면 **그 항목이 아니라 끼니 전체가 저장되지 않는다.**
    private func manualNutrient(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// 「추가하기」가 안 눌리는 이유. **버튼만 잠그면 왜 안 되는지 알 수 없다** — 특히 영양소
    /// 칸은 아래쪽이라 화면 밖에 있을 수 있다.
    var manualHint: String? {
        guard buildManualItem() == nil else { return nil }
        guard !manualName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "음식 이름을 넣어 주세요."
        }
        guard manualQuantityG != nil else {
            return "수량을 0보다 큰 숫자로 넣어 주세요."
        }
        return "영양소는 0 이상 숫자로 넣어 주세요."
    }

    func clearManualInput() {
        manualName = ""
        manualQuantity = ""
        manualKcal = ""
        manualCarbs = ""
        manualProtein = ""
        manualFat = ""
        manualSugar = ""
        manualSodium = ""
        manualFiber = ""
    }
}
