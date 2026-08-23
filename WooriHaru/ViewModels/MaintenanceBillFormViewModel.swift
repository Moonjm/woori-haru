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
    var unpaidAmount: String
    var unpaidLateFee: String
    var dueAmount: String
    var dueDate: String

    /// 서버가 붙인 경고. **이미 사용자용 한국어다** — 앱이 다시 쓰지 않는다. 편집 모드에선 비어 있다.
    private(set) var warnings: [String]
    private(set) var isSaving = false
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
            unpaidAmount = Self.text(recognition.unpaidAmount)
            unpaidLateFee = Self.text(recognition.unpaidLateFee)
            dueAmount = Self.text(recognition.dueAmount)
            dueDate = recognition.dueDate ?? ""
            warnings = recognition.warnings
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
            unpaidAmount = Self.text(bill.unpaidAmount)
            unpaidLateFee = Self.text(bill.unpaidLateFee)
            dueAmount = Self.text(bill.dueAmount)
            dueDate = bill.dueDate ?? ""
            warnings = []
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
        items.reduce(Decimal(0)) { $0 + (Self.decimal($1.amount) ?? 0) }
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
        guard !isSaving else { return false }
        guard MaintenanceTrendMath.isValidYearMonth(yearMonth) else { return false }
        guard !items.isEmpty else { return false }
        return items.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && Self.decimal($0.amount) != nil
        }
    }

    /// 저장할 수 없는 상태면 nil. 화면은 `canSave`로 이미 막고 있어 여기 오지 않는다.
    func makeRequest() -> MaintenanceBillSaveRequest? {
        guard canSave else { return nil }
        let drafts: [MaintenanceBillItemRequest] = items.compactMap { draft in
            guard let amount = Self.decimal(draft.amount) else { return nil }
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return MaintenanceBillItemRequest(name: name, amount: amount)
        }
        guard !drafts.isEmpty else { return nil }

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
            yearMonth: yearMonth.trimmingCharacters(in: .whitespaces),
            items: drafts,
            chargedAmount: Self.decimal(chargedAmount) ?? 0,
            dueAmount: Self.decimal(dueAmount) ?? 0,
            dong: Self.optionalText(dong),
            ho: Self.optionalText(ho),
            areaM2: Self.decimal(areaM2),
            usage: usage,
            discountTotal: Self.decimal(discountTotal) ?? 0,
            unpaidAmount: Self.decimal(unpaidAmount) ?? 0,
            unpaidLateFee: Self.decimal(unpaidLateFee) ?? 0,
            dueDate: Self.optionalText(dueDate)
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
        unpaidAmount = Self.text(bill.unpaidAmount)
        unpaidLateFee = Self.text(bill.unpaidLateFee)
        dueAmount = Self.text(bill.dueAmount)
        dueDate = bill.dueDate ?? ""
        // 인식 경고는 더 이상 이 화면의 것이 아니다 — 지금 편집하는 건 저장돼 있던 달이다.
        warnings = []
        errorMessage = nil
    }

    /// 서버에서 그 달을 받아 편집 모드로 갈아 끼운다. 실패하면 false.
    func loadForEdit(yearMonth: String) async -> Bool {
        do {
            switchToEdit(try await service.fetchBill(yearMonth: yearMonth))
            return true
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

    private static func decimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // `Decimal(string:)`은 로캘을 타지 않는 파서다. `NumberFormatter`를 쓰면 소수점이
        // 쉼표인 지역에서 `312.5`가 312가 된다.
        return Decimal(string: trimmed)
    }

    private static func optionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
