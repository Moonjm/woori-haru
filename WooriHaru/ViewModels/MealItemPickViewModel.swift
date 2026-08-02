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

    /// **받아 온 페이지를 앱에서 거른다** — 서버에 `dataset` 파라미터가 없다. 그래서 상위
    /// 결과가 전부 가공식품이면 「음식」 칩이 빈 목록을 보여준다. `size`를 50(서버 상한)으로
    /// 올려 완화했고, 근본 해법은 서버 필터라 별도 작업이다.
    var filteredSearchSources: [FoodPickSource] {
        let filtered = filter.dataset.map { dataset in
            searchResults.filter { $0.dataset == dataset }
        } ?? searchResults
        return filtered.map(FoodPickSource.food)
    }

    /// 검색결과 탭이 비었을 때 무엇을 보여줄지. **셋을 갈라야 한다** — 스펙이 예고한 대로
    /// 필터가 받아 온 페이지를 전부 걸러내는 경우가 실제로 자주 생기는데(서버에 `dataset`
    /// 파라미터가 없어 앱에서 거른다), 그때 「검색해 주세요」를 띄우면 원인이 필터라는 걸
    /// 알 길이 없다.
    var searchEmptyText: String? {
        guard filteredSearchSources.isEmpty else { return nil }
        if searchResults.isEmpty {
            return query.trimmingCharacters(in: .whitespaces).isEmpty
                ? "찾을 음식을 검색해 주세요."
                : "검색 결과가 없어요. 다른 이름으로 찾아 보세요."
        }
        return "이 검색 결과에는 「\(filter.label)」이 없어요. 「전체」로 보거나 검색어를 좁혀 보세요."
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
        guard !name.isEmpty, let quantity = Double(manualQuantity), quantity > 0 else { return nil }
        return NutritionMath.manualItem(
            name: name,
            quantityG: quantity,
            kcal: Double(manualKcal) ?? 0,
            carbsG: Double(manualCarbs) ?? 0,
            proteinG: Double(manualProtein) ?? 0,
            fatG: Double(manualFat) ?? 0,
            sugarG: Double(manualSugar) ?? 0,
            sodiumMg: Double(manualSodium) ?? 0,
            fiberG: Double(manualFiber) ?? 0
        )
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
