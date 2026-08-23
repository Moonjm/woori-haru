import Foundation
import Testing
@testable import WooriHaru

/// 인식 호출을 기록하고 늦게 돌려줄 수 있는 대역.
final class RecognizeStubService: MaintenanceServing, @unchecked Sendable {
    var result: MaintenanceRecognition?
    var error: Error?
    private(set) var callCount = 0
    /// 인식이 진행 중인 순간에 끼어들 자리. 재진입 가드와 generation 토큰을 **결정적으로**
    /// 확인한다 — `async let`으로 두 번째 호출을 띄우면 자식 태스크가 언제 시작될지
    /// 보장되지 않아 교착하거나 검증 없이 통과한다. `DispatchTests`가 쓰는 패턴이다.
    var duringRecognize: (@Sendable () async -> Void)?

    func fetchBills() async throws -> [MaintenanceBill] { [] }
    func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil)
    }
    func recognize(imageData: Data) async throws -> MaintenanceRecognition {
        callCount += 1
        await duringRecognize?()
        if let error { throw error }
        guard let result else { throw APIError.serverError(statusCode: 500, message: nil) }
        return result
    }
    func saveBill(_ request: MaintenanceBillSaveRequest) async throws {}
    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {}
    func deleteBill(yearMonth: String) async throws {}
    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] { [] }
}

func makeRecognition(
    yearMonth: String? = "2026-08",
    items: [MaintenanceBillItem] = [MaintenanceBillItem(name: "일반관리비", amount: 100)],
    chargedAmount: Decimal = 100,
    dueAmount: Decimal = 100,
    usage: MaintenanceUsage? = nil,
    sumMatched: Bool = true,
    warnings: [String] = []
) -> MaintenanceRecognition {
    MaintenanceRecognition(
        yearMonth: yearMonth, dong: "101", ho: "1502", areaM2: Decimal(string: "84.97"),
        items: items, usage: usage, chargedAmount: chargedAmount,
        discountTotal: 0, unpaidAmount: 0, unpaidLateFee: 0,
        dueAmount: dueAmount, dueDate: nil,
        sumMatched: sumMatched, warnings: warnings
    )
}

@MainActor
struct MaintenanceUploadViewModelTests {
    @Test func 사진이_없으면_인식할_수_없다() {
        let vm = MaintenanceUploadViewModel(service: RecognizeStubService())
        #expect(vm.canRecognize == false)
    }

    @Test func 인식에_성공하면_결과와_완료가_남는다() async {
        let service = RecognizeStubService()
        service.result = makeRecognition()
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))

        await vm.recognize()

        #expect(vm.phase == .completed)
        #expect(vm.recognition?.yearMonth == "2026-08")
        #expect(vm.errorMessage == nil)
    }

    /// 서버 메시지가 이미 사용자용 한국어다. 앱이 다시 쓰지 않고 봉투에서 꺼내기만 한다.
    @Test func 실패하면_서버_메시지를_그대로_띄운다() async {
        let service = RecognizeStubService()
        service.error = APIError.serverError(
            statusCode: 400,
            message: #"{"status":400,"message":"고지서를 읽지 못했습니다","code":"400"}"#
        )
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))

        await vm.recognize()

        #expect(vm.phase == .failed)
        #expect(vm.errorMessage == "고지서를 읽지 못했습니다")
    }

    /// **연타로 유료 인식이 두 번 나가지 않는다.**
    @Test func 도는_중에는_다시_부르지_않는다() async {
        let service = RecognizeStubService()
        service.result = makeRecognition()
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))
        service.duringRecognize = { [vm] in
            // 이미 인식 중이다. 두 번째 호출은 그대로 돌아가야 한다.
            await vm.recognize()
        }

        await vm.recognize()

        #expect(service.callCount == 1)
        #expect(vm.phase == .completed)
    }

    /// 사진을 바꾸면 **늦게 돌아온 이전 결과를 버린다.** 안 그러면 이전 사진의 인식 결과와
    /// 새 사진의 미리보기가 섞인 검수 화면이 열린다.
    @Test func 사진을_바꾸면_늦은_결과를_버린다() async {
        let service = RecognizeStubService()
        service.result = makeRecognition(yearMonth: "2026-07")
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))
        service.duringRecognize = { [vm] in
            // 사진을 잘못 골라 곧바로 다시 고른 상황. 이전 인식이 아직 돌아오지 않았다.
            await MainActor.run { vm.setImage(Data([0xFF, 0xD9])) }
        }

        await vm.recognize()

        #expect(vm.recognition == nil)
        #expect(vm.phase == .idle)
    }

    @Test func 사진_읽기_실패는_안내로_남는다() {
        let vm = MaintenanceUploadViewModel(service: RecognizeStubService())
        vm.setImage(Data([0xFF, 0xD8]))

        vm.setImageLoadFailed()

        #expect(vm.imageData == nil)
        #expect(vm.canRecognize == false)
        #expect(vm.errorMessage == "사진을 읽지 못했습니다. 다른 사진으로 다시 시도해 주세요.")
    }
}

/// 저장·수정·조회를 기록하는 대역. 409를 흉내 낼 수 있다.
final class FormStubService: MaintenanceServing, @unchecked Sendable {
    var saveError: Error?
    var updateError: Error?
    var billToFetch: MaintenanceBill?
    private(set) var savedRequests: [MaintenanceBillSaveRequest] = []
    private(set) var updatedCalls: [(yearMonth: String, request: MaintenanceBillSaveRequest)] = []

    func fetchBills() async throws -> [MaintenanceBill] { [] }
    func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
        guard let billToFetch else {
            throw APIError.serverError(statusCode: 404, message: nil)
        }
        return billToFetch
    }
    func recognize(imageData: Data) async throws -> MaintenanceRecognition {
        fatalError("이 스위트는 인식을 부르지 않는다")
    }
    func saveBill(_ request: MaintenanceBillSaveRequest) async throws {
        savedRequests.append(request)
        if let saveError { throw saveError }
    }
    func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {
        updatedCalls.append((yearMonth, request))
        if let updateError { throw updateError }
    }
    func deleteBill(yearMonth: String) async throws {}
    func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] { [] }
}

@MainActor
struct MaintenanceFormViewModelTests {
    private func makeBill(
        yearMonth: String = "2026-08",
        items: [MaintenanceBillItem] = [MaintenanceBillItem(name: "일반관리비", amount: 121_500)],
        usage: MaintenanceUsage? = nil
    ) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: "101", ho: "1502",
                        areaM2: Decimal(string: "84.97"),
                        items: items, usage: usage,
                        chargedAmount: 121_500, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: 121_500, dueDate: "2026-08-31")
    }

    // MARK: - 초기화

    @Test func 인식_결과로_칸이_채워진다() {
        let recognition = makeRecognition(
            items: [MaintenanceBillItem(name: "일반관리비", amount: 121_500),
                    MaintenanceBillItem(name: "세대전기료", amount: 48_320)],
            chargedAmount: 169_820, dueAmount: 168_620,
            usage: MaintenanceUsage(electricityKwh: Decimal(string: "312.5"),
                                    waterM3: nil, hotWaterM3: nil,
                                    heatingGcal: nil, foodKg: nil),
            sumMatched: true
        )
        let vm = MaintenanceBillFormViewModel(mode: .create(recognition), service: FormStubService())

        #expect(vm.yearMonth == "2026-08")
        #expect(vm.items.map(\.name) == ["일반관리비", "세대전기료"])
        #expect(vm.items[1].amount == "48320")
        #expect(vm.electricityKwh == "312.5")
        // **못 읽은 사용량은 빈 칸이다** — 0을 적어 두면 사람이 지우지 않는 한 0이 저장된다.
        #expect(vm.waterM3 == "")
        #expect(vm.isYearMonthEditable == true)
    }

    /// 연월을 못 읽었으면 빈 칸이고, 그 상태로는 저장할 수 없다.
    @Test func 연월이_없으면_저장이_잠긴다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(yearMonth: nil)), service: FormStubService()
        )
        #expect(vm.yearMonth == "")
        #expect(vm.canSave == false)
    }

    /// **편집 모드에서 연월은 키다.** 바꾸는 것은 삭제 후 재등록이지 수정이 아니다.
    @Test func 편집_모드에서는_연월을_못_고친다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        #expect(vm.isYearMonthEditable == false)
        #expect(vm.yearMonth == "2026-08")
        #expect(vm.warnings.isEmpty)
    }

    // MARK: - 항목

    @Test func 항목을_더하고_지운다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.addItem()

        #expect(vm.items.count == 2)
        // 빈 행이 있으면 저장이 잠긴다 — 서버가 400을 낸다.
        #expect(vm.canSave == false)

        vm.removeItems(at: IndexSet(integer: 1))
        #expect(vm.items.count == 1)
        #expect(vm.canSave == true)
    }

    /// 빈 행 둘을 더해도 서로 다른 `id`를 갖는다 — 이름으로 식별하면 타이핑이 옆 행으로 튄다.
    @Test func 빈_행_둘의_id가_갈린다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.addItem()
        vm.addItem()

        #expect(Set(vm.items.map(\.id)).count == 3)
    }

    @Test func 항목이_하나도_없으면_저장이_잠긴다() {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.removeItems(at: IndexSet(integer: 0))
        #expect(vm.canSave == false)
    }

    // MARK: - 합계 대조

    @Test func 항목_합계와_부과액_차이를_낸다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(
                items: [MaintenanceBillItem(name: "일반관리비", amount: 100),
                        MaintenanceBillItem(name: "세대전기료", amount: 50)],
                chargedAmount: 160, dueAmount: 160
            )),
            service: FormStubService()
        )

        #expect(vm.itemsTotal == Decimal(150))
        #expect(vm.sumGap == Decimal(-10))   // 항목 합계 − 부과액
        #expect(vm.isSumMatched == false)
    }

    /// **금액을 고치면 판정이 따라온다.** 서버의 `sumMatched`는 인식 시점 값이라 낡는다.
    @Test func 금액을_고치면_합계_판정이_갱신된다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(
                items: [MaintenanceBillItem(name: "일반관리비", amount: 100)],
                chargedAmount: 150, dueAmount: 150, sumMatched: false
            )),
            service: FormStubService()
        )
        #expect(vm.isSumMatched == false)

        vm.items[0].amount = "150"

        #expect(vm.isSumMatched == true)
        #expect(vm.sumGap == 0)
    }

    /// **합계가 안 맞아도 저장은 막지 않는다** — 반올림·별도 조정이 실제로 있고 판단은 사람이 한다.
    @Test func 합계가_어긋나도_저장할_수_있다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(chargedAmount: 999, dueAmount: 999)),
            service: FormStubService()
        )
        #expect(vm.isSumMatched == false)
        #expect(vm.canSave == true)
    }

    // MARK: - 요청 조립

    @Test func 빈_사용량_칸은_nil로_나간다() throws {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.electricityKwh = "312.5"
        vm.waterM3 = ""

        let request = try #require(vm.makeRequest())

        #expect(request.usage?.electricityKwh == Decimal(string: "312.5"))
        #expect(request.usage?.waterM3 == nil)
    }

    /// 빈 문자열은 nil이지 0이 아니다 — 동·호·면적·납기일도 마찬가지다.
    @Test func 빈_세대_정보는_nil로_나간다() throws {
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: FormStubService())
        vm.dong = ""
        vm.ho = "  "
        vm.areaM2 = ""
        vm.dueDate = ""

        let request = try #require(vm.makeRequest())

        #expect(request.dong == nil)
        #expect(request.ho == nil)
        #expect(request.areaM2 == nil)
        #expect(request.dueDate == nil)
    }

    /// **`.create`와 `.edit`이 같은 값에서 같은 바디를 낸다.** 두 벌로 갈리면 한쪽만 고친 날
    /// 두 화면이 다른 값을 저장한다.
    @Test func 두_모드가_같은_바디를_낸다() throws {
        let bill = makeBill()
        let recognition = makeRecognition(
            items: bill.items, chargedAmount: bill.chargedAmount, dueAmount: bill.dueAmount
        )
        let fromCreate = MaintenanceBillFormViewModel(mode: .create(recognition), service: FormStubService())
        fromCreate.dueDate = "2026-08-31"
        let fromEdit = MaintenanceBillFormViewModel(mode: .edit(bill), service: FormStubService())

        #expect(try #require(fromCreate.makeRequest()) == (try #require(fromEdit.makeRequest())))
    }

    // MARK: - 저장

    @Test func 검수_저장은_POST로_나간다() async {
        let service = FormStubService()
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .saved)
        #expect(service.savedRequests.count == 1)
        #expect(service.updatedCalls.isEmpty)
    }

    @Test func 편집_저장은_PUT으로_나간다() async {
        let service = FormStubService()
        let vm = MaintenanceBillFormViewModel(mode: .edit(makeBill()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .saved)
        #expect(service.updatedCalls.map(\.yearMonth) == ["2026-08"])
        #expect(service.savedRequests.isEmpty)
    }

    /// **409는 실패와 다르다.** 화면이 「기존 내역 수정하기」를 띄울 수 있게 갈라 준다.
    @Test func 같은_달이_있으면_duplicated다() async {
        let service = FormStubService()
        service.saveError = APIError.serverError(statusCode: 409, message: nil)
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .duplicated)
    }

    @Test func 다른_실패는_failed고_메시지가_남는다() async {
        let service = FormStubService()
        service.saveError = APIError.serverError(
            statusCode: 400, message: #"{"status":400,"message":"항목이 비었습니다","code":"400"}"#
        )
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)

        let outcome = await vm.save()

        #expect(outcome == .failed)
        #expect(vm.errorMessage == "항목이 비었습니다")
    }

    /// **화면 값을 버리고 서버 값으로 다시 채운다** — 방금 인식한 값으로 기존 달을 덮는 것은
    /// 사용자가 의도한 적 없는 파괴다.
    @Test func 편집으로_바꾸면_서버_값으로_채워진다() {
        let vm = MaintenanceBillFormViewModel(
            mode: .create(makeRecognition(items: [MaintenanceBillItem(name: "잘못읽음", amount: 1)])),
            service: FormStubService()
        )

        vm.switchToEdit(makeBill(items: [MaintenanceBillItem(name: "일반관리비", amount: 121_500)]))

        #expect(vm.items.map(\.name) == ["일반관리비"])
        #expect(vm.isYearMonthEditable == false)
        #expect(vm.warnings.isEmpty)
    }

    /// 편집으로 바뀐 뒤 저장하면 PUT이다.
    @Test func 편집으로_바꾼_뒤_저장하면_PUT이다() async {
        let service = FormStubService()
        let vm = MaintenanceBillFormViewModel(mode: .create(makeRecognition()), service: service)
        vm.switchToEdit(makeBill())

        _ = await vm.save()

        #expect(service.updatedCalls.map(\.yearMonth) == ["2026-08"])
        #expect(service.savedRequests.isEmpty)
    }
}
