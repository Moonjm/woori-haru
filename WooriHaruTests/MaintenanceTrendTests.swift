import Foundation
import Testing
@testable import WooriHaru

struct MaintenanceMonthMathTests {
    @Test func 앞_달을_만든다() {
        #expect(MaintenanceTrendMath.previousMonth(of: "2026-08") == "2026-07")
    }

    /// 연 넘김. `Calendar`를 쓰지 않는 이유가 여기 있다 — 문자열 산술이라 기기 달력 설정을 타지 않는다.
    @Test func 일월의_앞_달은_작년_십이월이다() {
        #expect(MaintenanceTrendMath.previousMonth(of: "2026-01") == "2025-12")
    }

    @Test func 형식이_틀리면_nil이다() {
        #expect(MaintenanceTrendMath.previousMonth(of: "2026") == nil)
        #expect(MaintenanceTrendMath.previousMonth(of: "abcd-ef") == nil)
    }
}

struct MaintenanceDeltaTests {
    private func bill(_ yearMonth: String, due: Decimal) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil,
                        chargedAmount: due, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: due, dueDate: nil)
    }

    @Test func 바로_앞_달과_견준다() throws {
        let bills = [bill("2026-08", due: 168_620), bill("2026-07", due: 156_320)]
        let delta = try #require(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0))

        #expect(delta.amount == Decimal(12_300))
        // 12300 / 156320 ≈ 0.0787
        let ratio = try #require(delta.ratio)
        #expect(ratio > Decimal(string: "0.078")! && ratio < Decimal(string: "0.079")!)
    }

    /// **연속하지 않은 달은 견주지 않는다.** 8월과 6월을 놓고 「전월 대비」라고 적으면 거짓이다.
    @Test func 달이_건너뛰면_델타가_없다() {
        let bills = [bill("2026-08", due: 100), bill("2026-06", due: 50)]
        #expect(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0) == nil)
    }

    @Test func 마지막_달은_델타가_없다() {
        let bills = [bill("2026-08", due: 100)]
        #expect(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0) == nil)
    }

    /// 앞 달이 0이면 비율이 나오지 않는다 — 0으로 나누지 않는다. 금액 차이만 남는다.
    @Test func 앞_달이_0이면_비율은_nil이다() throws {
        let bills = [bill("2026-08", due: 100), bill("2026-07", due: 0)]
        let delta = try #require(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0))

        #expect(delta.amount == Decimal(100))
        #expect(delta.ratio == nil)
    }
}

@MainActor
struct MaintenanceBillsViewModelTests {
    private func bill(_ yearMonth: String) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil,
                        chargedAmount: 0, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: 0, dueDate: nil)
    }

    /// 목록·삭제 호출을 기록하는 대역. 서비스가 프로토콜이라 `MockAPIClient` 없이도 선다.
    final class FakeService: MaintenanceServing, @unchecked Sendable {
        var bills: [MaintenanceBill] = []
        var listError: Error?
        var deleteError: Error?
        private(set) var deletedYearMonths: [String] = []
        private(set) var listCallCount = 0

        func fetchBills() async throws -> [MaintenanceBill] {
            listCallCount += 1
            if let listError { throw listError }
            return bills
        }
        func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
            MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                            items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
                            unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil)
        }
        func recognize(imageData: Data) async throws -> MaintenanceRecognition {
            fatalError("이 스위트는 인식을 부르지 않는다")
        }
        func saveBill(_ request: MaintenanceBillSaveRequest) async throws {}
        func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {}
        func deleteBill(yearMonth: String) async throws {
            deletedYearMonths.append(yearMonth)
            if let deleteError { throw deleteError }
        }
        func fetchTrends(months: Int) async throws -> [MaintenanceTrendMonth] { [] }
    }

    @Test func 목록을_받아_담는다() async {
        let service = FakeService()
        service.bills = [bill("2026-08"), bill("2026-07")]
        let vm = MaintenanceBillsViewModel(service: service)

        await vm.load()

        #expect(vm.bills.map(\.yearMonth) == ["2026-08", "2026-07"])
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func 실패하면_메시지를_남기고_목록을_비우지_않는다() async {
        let service = FakeService()
        service.bills = [bill("2026-08")]
        let vm = MaintenanceBillsViewModel(service: service)
        await vm.load()

        service.listError = APIError.serverError(statusCode: 500, message: nil)
        await vm.load()

        #expect(vm.errorMessage != nil)
        // 이미 받아 둔 목록을 지우지 않는다 — 새로고침 한 번 실패했다고 화면이 비면 안 된다.
        #expect(vm.bills.map(\.yearMonth) == ["2026-08"])
    }

    @Test func 삭제에_성공하면_목록에서_빠진다() async {
        let service = FakeService()
        service.bills = [bill("2026-08"), bill("2026-07")]
        let vm = MaintenanceBillsViewModel(service: service)
        await vm.load()

        let ok = await vm.delete(yearMonth: "2026-08")

        #expect(ok == true)
        #expect(service.deletedYearMonths == ["2026-08"])
        #expect(vm.bills.map(\.yearMonth) == ["2026-07"])
    }

    /// **실패하면 false다.** 화면이 이 값을 보고 물러날지 정한다 — 실패했는데 물러나면
    /// 사용자는 지워진 줄 안다.
    @Test func 삭제에_실패하면_false고_목록이_그대로다() async {
        let service = FakeService()
        service.bills = [bill("2026-08")]
        let vm = MaintenanceBillsViewModel(service: service)
        await vm.load()
        service.deleteError = APIError.serverError(statusCode: 500, message: nil)

        let ok = await vm.delete(yearMonth: "2026-08")

        #expect(ok == false)
        #expect(vm.bills.map(\.yearMonth) == ["2026-08"])
        #expect(vm.errorMessage != nil)
    }
}
