import Foundation
import Testing
@testable import WooriHaru

/// 인식 호출을 기록하고 늦게 돌려줄 수 있는 대역.
final class RecognizeStubService: MaintenanceServing, @unchecked Sendable {
    var result: MaintenanceRecognition?
    var error: Error?
    private(set) var callCount = 0
    /// 이 값을 채우면 `recognize`가 그동안 대기한다 — 「도는 중에 사진 교체」를 만든다.
    var gate: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation)?

    func fetchBills() async throws -> [MaintenanceBill] { [] }
    func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil)
    }
    func recognize(imageData: Data) async throws -> MaintenanceRecognition {
        callCount += 1
        if let gate {
            var iterator = gate.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
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
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        service.gate = (stream, continuation)
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))

        async let first: Void = vm.recognize()
        // 첫 호출이 게이트에 걸린 사이 두 번째를 시도한다.
        await vm.recognize()
        continuation.yield()
        continuation.finish()
        await first

        #expect(service.callCount == 1)
    }

    /// 사진을 바꾸면 **늦게 돌아온 이전 결과를 버린다.** 안 그러면 이전 사진의 인식 결과와
    /// 새 사진의 미리보기가 섞인 검수 화면이 열린다.
    @Test func 사진을_바꾸면_늦은_결과를_버린다() async {
        let service = RecognizeStubService()
        service.result = makeRecognition(yearMonth: "2026-07")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        service.gate = (stream, continuation)
        let vm = MaintenanceUploadViewModel(service: service)
        vm.setImage(Data([0xFF, 0xD8]))

        async let running: Void = vm.recognize()
        vm.setImage(Data([0xFF, 0xD9]))   // 사진 교체
        continuation.yield()
        continuation.finish()
        await running

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
