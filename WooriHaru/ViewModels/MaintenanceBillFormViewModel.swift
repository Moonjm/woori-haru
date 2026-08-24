import Foundation

/// 편집 중인 항목 한 줄.
///
/// **`id`가 `UUID`인 이유.** `MaintenanceBillItem.id`는 이름인데, 편집 중에는 이름이 겹친다
/// (빈 행 둘만 더해도 바로 겹친다). 그러면 `ForEach`가 행 둘을 같은 뷰로 잡아 **타이핑이
/// 옆 행으로 튄다.**
///
/// **금액이 `String`인 이유.** `TextField`는 값을 지우는 중간 상태(`""`·`"12."`)를 지나간다.
/// `Decimal`에 바로 바인딩하면 그 상태가 0으로 튀어 사용자가 지운 값이 되살아난다.
struct MaintenanceItemDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var amount: String

    init(id: UUID = UUID(), name: String, amount: String) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

/// 검수(`.create`)와 편집(`.edit`)을 **한 화면으로** 다룬다.
///
/// 화면을 나누면 항목 편집·합계 검증·요청 조립이 두 벌이 되고, 한쪽만 고친 날 두 화면이
/// 다른 값을 저장한다. 갈리는 것은 저장 메서드(POST/PUT)와 연월 편집 가능 여부뿐이다.
@MainActor
@Observable
final class MaintenanceBillFormViewModel {
    enum Mode: Equatable {
        case create(MaintenanceRecognition)
        case edit(MaintenanceBill)
    }

    /// 409를 실패와 갈라 낸다 — 화면이 「기존 내역 수정하기」로 이어 붙일 수 있어야 한다.
    enum SaveOutcome: Equatable {
        case saved
        case duplicated
        case failed
    }

    private let service: any MaintenanceServing
    /// `.edit`이면 PUT, 아니면 POST. `switchToEdit`이 이 값을 바꾼다.
    private var editingYearMonth: String?

    var yearMonth: String
    var dong: String
    var ho: String
    var areaM2: String
    var items: [MaintenanceItemDraft]
    var electricityKwh: String
    var waterM3: String
    var hotWaterM3: String
    var heatingGcal: String
    var foodKg: String
    var chargedAmount: String
    var discountTotal: String

    /// 서버가 붙인 경고. **이미 사용자용 한국어다** — 앱이 다시 쓰지 않는다. 편집 모드에선 비어 있다.
    private(set) var warnings: [String]
    /// 인식 시점에 항목 합계와 부과액이 맞았는가. **`.edit`은 늘 true다** — 저장돼 있던
    /// 달은 서버가 이미 확정한 값이라 이 배너가 다시 뜰 이유가 없다. `switchToEdit`도
    /// 같은 이유로 true로 되돌린다. `warnings`가 비어 있어도 이 값이 false면 배너를
    /// 띄워야 한다 — 서버가 `sumMatched: false`만 보내고 `warnings`는 비울 수 있어서다.
    private(set) var sumMatched: Bool
    private(set) var isSaving = false
    /// 409에서 「기존 내역 수정하기」를 누른 뒤 `loadForEdit`이 도는 동안 true. `canSave`가
    /// 이것도 본다 — 안 그러면 이 fetch가 도는 사이 저장 버튼이 살아 있어, 조급하게 「저장」을
    /// 누르면 `saveTask?.cancel()`이 이 fetch를 취소하고 폼은 여전히 `.create`라 같은 POST가
    /// 다시 나가 또 409를 받는다.
    private(set) var isLoadingExisting = false
    private(set) var errorMessage: String?

    init(mode: Mode, service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
        switch mode {
        case .create(let recognition):
            editingYearMonth = nil
            yearMonth = recognition.yearMonth ?? ""
            dong = recognition.dong ?? ""
            ho = recognition.ho ?? ""
            areaM2 = Self.text(recognition.areaM2)
            items = recognition.items.map {
                MaintenanceItemDraft(name: $0.name, amount: Self.text($0.amount))
            }
            electricityKwh = Self.text(recognition.usage?.electricityKwh)
            waterM3 = Self.text(recognition.usage?.waterM3)
            hotWaterM3 = Self.text(recognition.usage?.hotWaterM3)
            heatingGcal = Self.text(recognition.usage?.heatingGcal)
            foodKg = Self.text(recognition.usage?.foodKg)
            chargedAmount = Self.text(recognition.chargedAmount)
            discountTotal = Self.text(recognition.discountTotal)
            warnings = recognition.warnings
            sumMatched = recognition.sumMatched
        case .edit(let bill):
            editingYearMonth = bill.yearMonth
            yearMonth = bill.yearMonth
            dong = bill.dong ?? ""
            ho = bill.ho ?? ""
            areaM2 = Self.text(bill.areaM2)
            items = bill.items.map {
                MaintenanceItemDraft(name: $0.name, amount: Self.text($0.amount))
            }
            electricityKwh = Self.text(bill.usage?.electricityKwh)
            waterM3 = Self.text(bill.usage?.waterM3)
            hotWaterM3 = Self.text(bill.usage?.hotWaterM3)
            heatingGcal = Self.text(bill.usage?.heatingGcal)
            foodKg = Self.text(bill.usage?.foodKg)
            chargedAmount = Self.text(bill.chargedAmount)
            discountTotal = Self.text(bill.discountTotal)
            warnings = []
            sumMatched = true
        }
    }

    /// **연월은 편집 모드에서 키다.** 바꾸는 것은 삭제 후 재등록이지 수정이 아니다.
    var isYearMonthEditable: Bool { editingYearMonth == nil }

    // MARK: - 항목

    func addItem() {
        items.append(MaintenanceItemDraft(name: "", amount: ""))
    }

    func removeItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    // MARK: - 합계 대조

    /// **앱이 실시간으로 다시 계산한다.** 서버의 `sumMatched`는 인식 시점 판정이라 사람이
    /// 금액을 고치면 낡는다.
    var itemsTotal: Decimal {
        items.reduce(Decimal(0)) { $0 + (Self.decimal($1.amount, allowsNegative: true) ?? 0) }
    }

    /// 항목 합계 − 부과액. 음수면 항목이 모자라다는 뜻이다.
    var sumGap: Decimal {
        itemsTotal - (Self.decimal(chargedAmount) ?? 0)
    }

    var isSumMatched: Bool { sumGap == 0 }

    // MARK: - 저장

    /// **막는 것은 서버가 400을 낼 것들뿐이다.** 합계 불일치는 막지 않는다 — 고지서에
    /// 반올림·별도 조정이 실제로 있고, 판단은 사람이 한다.
    var canSave: Bool {
        guard !isSaving, !isLoadingExisting else { return false }
        guard MaintenanceTrendMath.isValidYearMonth(yearMonth) else { return false }
        // **부과액은 필수다.** 예전에는 여기서 안 보고 `makeRequest`가 `?? 0`으로 메웠는데,
        // 사용자가 고치려고 칸을 비운 순간이 정확히 그 상황이라 **실제 부과액이 0으로
        // 덮여** 저장됐다. 항목 합계 불일치는 사람 판단에 맡기지만(그건 막지 않는다),
        // 「값이 아예 없다」는 판단할 것이 없다.
        guard Self.decimal(chargedAmount) != nil else { return false }
        guard !items.isEmpty else { return false }
        guard !hasDuplicateItemNames else { return false }
        return items.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && Self.decimal($0.amount, allowsNegative: true) != nil
        }
    }

    /// 같은 이름을 가진 항목이 둘 이상인가.
    ///
    /// **저장 전에만 막는다.** 편집 중에는 겹쳐도 된다 — 이름을 고치는 도중에 잠깐
    /// 같아지는 건 정상이고, 그때마다 화면이 빨개지면 타이핑을 방해한다.
    ///
    /// **막아야 하는 이유는 저장 이후에 있다.** `MaintenanceBillItem.id`가 이름이라
    /// (한 달 안에서 유일하다는 고지서 표의 성질에 기댄 것이다) 같은 이름이 둘 저장되면
    /// 상세·통계의 `ForEach`가 같은 id를 둘 받는다 — 행이 뭉개지거나 엉뚱한 행이
    /// 재사용된다. 통계의 `itemNames`·`itemPoints`도 이름으로 항목을 찾으므로 한쪽만 잡힌다.
    var hasDuplicateItemNames: Bool {
        let names = items.map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Set(names).count != names.count
    }

    /// 저장할 수 없는 상태면 nil. 화면은 `canSave`로 이미 막고 있어 여기 오지 않는다.
    func makeRequest() -> MaintenanceBillSaveRequest? {
        guard canSave else { return nil }
        let drafts: [MaintenanceBillItemRequest] = items.compactMap { draft in
            guard let amount = Self.decimal(draft.amount, allowsNegative: true) else { return nil }
            var name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            // 서버 한도 50자. `MaintenanceItemRow`의 `onChange`가 타이핑 중에 이미 자르지만,
            // 그건 뷰 쪽 방어라 테스트가 닿지 않는다 — `makeRequest`가 실제로 검증되는
            // 경로이니 여기서도 자른다.
            if name.count > 50 { name = String(name.prefix(50)) }
            return MaintenanceBillItemRequest(name: name, amount: amount)
        }
        guard !drafts.isEmpty else { return nil }

        // **`?? 0`으로 메우지 않는다.** `canSave`가 이미 막고 있지만, 그 가드가 언젠가
        // 느슨해져도 여기서 0이 새어 나가면 안 된다 — 저장을 포기하는 편이 실제 부과액을
        // 0으로 덮는 것보다 낫다. 반대로 **할인은 아래에서 `?? 0`이 맞다**: 비운 할인은
        // 「할인이 없다」는 뜻이고, 0이 그 뜻 그대로다.
        guard let charged = Self.decimal(chargedAmount) else { return nil }

        // **빈 칸은 nil이지 0이 아니다.** 0으로 보내면 서버에 「0을 썼다」가 저장돼
        // 통계에서 「못 읽은 달」이 「안 쓴 달」로 바뀐다.
        let usage = MaintenanceUsage(
            electricityKwh: Self.decimal(electricityKwh),
            waterM3: Self.decimal(waterM3),
            hotWaterM3: Self.decimal(hotWaterM3),
            heatingGcal: Self.decimal(heatingGcal),
            foodKg: Self.decimal(foodKg)
        )

        return MaintenanceBillSaveRequest(
            // **여기서 다시 다듬지 않는다.** `canSave`가 이미 `isValidYearMonth`로 막고
            // 있어(`Int(" 2026")`이 nil이라 앞뒤 공백이 있으면 애초에 여기 못 온다) 이
            // 자리의 `.trimmingCharacters`는 아무 값도 바꾸지 못하면서 「뭔가 다듬고
            // 있다」는 인상만 준다.
            yearMonth: yearMonth,
            items: drafts,
            chargedAmount: charged,
            dong: Self.optionalText(dong),
            ho: Self.optionalText(ho),
            areaM2: Self.decimal(areaM2),
            usage: usage,
            discountTotal: Self.decimal(discountTotal) ?? 0
        )
    }

    func save() async -> SaveOutcome {
        // **`makeRequest`가 `canSave`를 보므로 `isSaving`을 세우기 전에 부른다.**
        // 순서를 뒤집으면 `canSave`가 false가 되어 자기 저장이 자기를 막는다.
        guard let request = makeRequest() else { return .failed }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let editingYearMonth {
                try await service.updateBill(yearMonth: editingYearMonth, request)
            } else {
                try await service.saveBill(request)
            }
            return .saved
        } catch let error as APIError {
            // 409는 실패가 아니라 갈림길이다 — 화면이 「기존 내역 수정하기」를 띄운다.
            if case .serverError(409, _) = error { return .duplicated }
            errorMessage = error.serverMessage ?? error.localizedDescription
            return .failed
        } catch is CancellationError {
            // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return .failed
        } catch {
            errorMessage = error.serverMessage ?? error.localizedDescription
            return .failed
        }
    }

    /// 409에서 「기존 내역 수정하기」를 눌렀을 때. **화면 값을 버리고 서버 값으로 다시 채운다** —
    /// 방금 인식한 값으로 기존 달을 통째로 덮는 것은 사용자가 의도한 적 없는 파괴다.
    func switchToEdit(_ bill: MaintenanceBill) {
        editingYearMonth = bill.yearMonth
        yearMonth = bill.yearMonth
        dong = bill.dong ?? ""
        ho = bill.ho ?? ""
        areaM2 = Self.text(bill.areaM2)
        items = bill.items.map { MaintenanceItemDraft(name: $0.name, amount: Self.text($0.amount)) }
        electricityKwh = Self.text(bill.usage?.electricityKwh)
        waterM3 = Self.text(bill.usage?.waterM3)
        hotWaterM3 = Self.text(bill.usage?.hotWaterM3)
        heatingGcal = Self.text(bill.usage?.heatingGcal)
        foodKg = Self.text(bill.usage?.foodKg)
        chargedAmount = Self.text(bill.chargedAmount)
        discountTotal = Self.text(bill.discountTotal)
        // 인식 경고는 더 이상 이 화면의 것이 아니다 — 지금 편집하는 건 저장돼 있던 달이다.
        warnings = []
        sumMatched = true
        errorMessage = nil
    }

    /// 서버에서 그 달을 받아 편집 모드로 갈아 끼운다. 실패하면 false.
    ///
    /// **도는 동안 저장을 잠근다.** 잠그지 않으면 409 알럿에서 「기존 내역 수정하기」를
    /// 누른 뒤 조급하게 「저장」을 또 누를 수 있다 — 그러면 `saveTask?.cancel()`이 이
    /// fetch를 취소하는데, 폼은 아직 `.create`라 취소된 채로 같은 POST가 다시 나가
    /// 곧장 또 409를 받는다.
    func loadForEdit(yearMonth: String) async -> Bool {
        isLoadingExisting = true
        defer { isLoadingExisting = false }
        do {
            switchToEdit(try await service.fetchBill(yearMonth: yearMonth))
            return true
        } catch is CancellationError {
            // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return false
        } catch {
            errorMessage = error.serverMessage ?? error.localizedDescription
            return false
        }
    }

    // MARK: - 변환

    /// **못 읽은 값은 빈 칸이다** — 0을 적어 두면 사람이 지우지 않는 한 0이 저장된다.
    private static func text(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    /// `ChargeModels.ChargeFormat.parseCost`와 같은 규칙이다 — 저장소에 이미 있는 해법을
    /// 다시 만들지 않는다.
    ///
    /// **쉼표를 지운다.** `.decimalPad`로는 쉼표를 못 치지만, 고지서 금액을 복사해
    /// 붙여넣으면(예: 「168,620」) 들어온다. `Decimal(string:)`은 쉼표에서 파싱을 멈춰
    /// 「168」만 읽고 나머지를 버린다 — 화면엔 「168,620」이 그대로 보이는데 저장은
    /// 168원으로 나가는, 알아채기 어려운 손실이다.
    ///
    /// **로캘을 POSIX로 고정한다.** `locale`을 안 주면 기기 로캘을 따라가는데, 소수점을
    /// 쉼표로 쓰는 지역에서는 "." 하나로 파싱이 실패한다 — 반대로 사용자가 넣은 쉼표
    /// 자리구분과 그 지역의 소수 구분이 뒤섞이면 값이 조용히 달라진다.
    /// **`allowsNegative`의 기본값이 `false`인 이유.** 음수가 뜻을 갖는 자리는 차감 항목
    /// 하나뿐이다 — 사용량(`-30kWh를 썼다`)과 면적에 붙은 마이너스는 값이 아니라 오타이고,
    /// 한 달 부과액도 마찬가지다. 새 칸이 생겼을 때 아무 생각 없이 쓰면 엄한 쪽으로
    /// 걸리도록 기본값을 잡았다.
    private static func decimal(_ text: String, allowsNegative: Bool = false) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        // **`Decimal(string:)`은 관대해서 그대로 기대면 안 된다.** `"."`을 0으로 읽고
        // `"12abc"`를 12로 읽는다. 사용자가 고치려고 지우다 만 칸이 그 길로 조용히 0이
        // 되어 실제 부과액을 덮었다. 칠 수 있는 모양만 받고, 숫자가 한 자도 없으면 거른다
        // — 붙여넣기는 키보드를 우회한다.
        let isDigit: (Character) -> Bool = { ("0"..."9").contains($0) }
        let body = allowsNegative && cleaned.hasPrefix("-") ? String(cleaned.dropFirst()) : cleaned
        // 마이너스는 **하나, 맨 앞에서만** 뜻이 있다. `dropFirst` 뒤에도 남아 있으면
        // `--5`·`5-`·`1-2` 같은 모양이라 숫자가 아니다.
        guard body.contains(where: isDigit),
              body.allSatisfy({ isDigit($0) || $0 == "." }),
              body.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: cleaned, locale: posixLocale)
        else { return nil }
        return value
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static func optionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
