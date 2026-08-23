import Foundation
import Testing
@testable import WooriHaru

@Suite("가계부 금액 정렬")
struct LedgerSortTests {

    private func entry(_ id: Int,
                       _ amount: Decimal,
                       currency: String = "KRW",
                       at entryAt: String = "2026-08-21T13:00:00",
                       description: String? = nil,
                       type: EntryType = .expense) -> LedgerEntry {
        LedgerEntry(id: id, entryAt: entryAt, amount: amount, currency: currency,
                    type: type, merchant: "가맹점\(id)", description: description, source: .manual)
    }

    // MARK: - 정렬 키

    /// 통화가 섞인 목록에서 숫자를 그대로 비교하면 JPY 12,000이 KRW 94,300을 이긴다.
    /// 환율 메모의 환산액으로 바꿔야 「이 달에 제일 크게 쓴 건」이 실제로 위에 온다.
    @Test func 외화는_환율_메모의_원화_환산액으로_비교한다() {
        let yen = entry(1, 12_000, currency: "JPY",
                        description: "환율 1 JPY ≈ 9.0원 (약 108,000원)")
        #expect(LedgerViewModel.sortAmount(yen) == 108_000)
    }

    @Test func 환율_메모가_없는_외화는_원_금액을_그대로_쓴다() {
        let yen = entry(1, 12_000, currency: "JPY")
        #expect(LedgerViewModel.sortAmount(yen) == 12_000)
    }

    @Test func 원화는_금액을_그대로_쓴다() {
        #expect(LedgerViewModel.sortAmount(entry(1, 94_300)) == 94_300)
    }

    /// 환율 메모의 환산액은 절대값으로 적혀 있다. 부호를 잃으면 취소 건이
    /// 「12만원 쓴 건」으로 둔갑해 목록 맨 위로 올라온다.
    @Test func 외화_취소_건은_환산액에_음수_부호가_붙는다() {
        let cancel = entry(1, -12_000, currency: "JPY",
                           description: "환율 1 JPY ≈ 9.0원 (약 108,000원)")
        #expect(LedgerViewModel.sortAmount(cancel) == -108_000)
    }

    // MARK: - 정렬 순서

    @Test func 금액_큰순은_환산액_내림차순이다() {
        let list = [
            entry(1, 94_300),
            entry(2, 12_000, currency: "JPY", description: "환율 1 JPY ≈ 9.0원 (약 108,000원)"),
            entry(3, 6_500),
        ]
        #expect(LedgerViewModel.sortedByAmount(list).map(\.id) == [2, 1, 3])
    }

    @Test func 취소_건은_맨_아래로_간다() {
        let list = [
            entry(1, -50_000),
            entry(2, 6_500),
            entry(3, 650_000),
        ]
        #expect(LedgerViewModel.sortedByAmount(list).map(\.id) == [3, 2, 1])
    }

    /// 금액이 같으면 순서가 매번 흔들리지 않게 최근 건을 먼저 둔다.
    @Test func 금액이_같으면_최근_건이_먼저_온다() {
        let list = [
            entry(1, 10_000, at: "2026-08-01T09:00:00"),
            entry(2, 10_000, at: "2026-08-20T09:00:00"),
        ]
        #expect(LedgerViewModel.sortedByAmount(list).map(\.id) == [2, 1])
    }

    @Test func 수입도_같은_목록에서_금액순으로_줄_선다() {
        let list = [
            entry(1, 30_000),
            entry(2, 500_000, type: .income),
        ]
        #expect(LedgerViewModel.sortedByAmount(list).map(\.id) == [2, 1])
    }

    @Test func 빈_목록도_그대로_비어_있다() {
        #expect(LedgerViewModel.sortedByAmount([]).isEmpty)
    }

    // MARK: - 뷰모델 상태

    @MainActor
    @Test func 기본_정렬은_날짜순이다() {
        #expect(LedgerViewModel().sortMode == .date)
    }

    /// 정렬 모드는 화면 상태일 뿐이라 달을 옮겨도 그대로 남아야 한다.
    @MainActor
    @Test func 달을_옮겨도_정렬_모드는_유지된다() async {
        let mock = MockAPIClient()
        mock.stubGet("/entries", result: DataResponse<[LedgerEntry]>(data: []))
        let viewModel = LedgerViewModel(ledgerService: LedgerService(api: mock))
        viewModel.sortMode = .amount
        await viewModel.shiftMonth(-1)
        #expect(viewModel.sortMode == .amount)
    }

    @MainActor
    @Test func 금액순_목록은_날짜_섹션을_거치지_않고_한_덩어리로_나온다() async {
        let mock = MockAPIClient()
        let list = [
            entry(1, 6_500, at: "2026-08-21T13:00:00"),
            entry(2, 650_000, at: "2026-08-03T09:00:00"),
        ]
        mock.stubGet("/entries", result: DataResponse<[LedgerEntry]>(data: list))
        let viewModel = LedgerViewModel(ledgerService: LedgerService(api: mock))
        await viewModel.load()
        #expect(viewModel.sections.count == 2) // 날짜순은 하루씩 나뉜 그대로
        #expect(viewModel.amountSortedEntries.map(\.id) == [2, 1])
    }
}
