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

    @Test func 연월_형식을_검사한다() {
        #expect(MaintenanceTrendMath.isValidYearMonth("2026-08") == true)
        #expect(MaintenanceTrendMath.isValidYearMonth("2026-13") == false)
        #expect(MaintenanceTrendMath.isValidYearMonth("") == false)
    }

    /// **자릿수까지 본다.** 파싱만 하면 `2026-8`도 숫자로는 읽히지만, 이 문자열이 그대로
    /// 고지서의 키가 되어 `PUT`/`DELETE` 경로에 실린다 — 서버 계약은 `YYYY-MM`이라
    /// 같은 달이 `2026-8`과 `2026-08` 둘로 갈리거나 요청이 거부된다.
    @Test func 자릿수가_어긋난_연월은_받지_않는다() {
        #expect(MaintenanceTrendMath.isValidYearMonth("2026-8") == false)
        #expect(MaintenanceTrendMath.isValidYearMonth("2026-008") == false)
        #expect(MaintenanceTrendMath.isValidYearMonth("26-08") == false)
        #expect(MaintenanceTrendMath.isValidYearMonth("2026/08") == false)
        #expect(MaintenanceTrendMath.isValidYearMonth("2026-08 ") == false)
        #expect(MaintenanceTrendMath.isValidYearMonth("2026-00") == false)
    }
}

struct MaintenanceDeltaTests {
    private func bill(_ yearMonth: String, charged: Decimal) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil,
                        chargedAmount: charged, discountTotal: 0)
    }

    @Test func 바로_앞_달과_견준다() throws {
        let bills = [bill("2026-08", charged: 168_620), bill("2026-07", charged: 156_320)]
        let delta = try #require(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0))

        #expect(delta.amount == Decimal(12_300))
        // 12300 / 156320 ≈ 0.0787
        let ratio = try #require(delta.ratio)
        #expect(ratio > Decimal(string: "0.078")! && ratio < Decimal(string: "0.079")!)
    }

    /// **연속하지 않은 달은 견주지 않는다.** 8월과 6월을 놓고 「전월 대비」라고 적으면 거짓이다.
    @Test func 달이_건너뛰면_델타가_없다() {
        let bills = [bill("2026-08", charged: 100), bill("2026-06", charged: 50)]
        #expect(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0) == nil)
    }

    @Test func 마지막_달은_델타가_없다() {
        let bills = [bill("2026-08", charged: 100)]
        #expect(MaintenanceTrendMath.monthOverMonth(bills: bills, at: 0) == nil)
    }

    /// 앞 달이 0이면 비율이 나오지 않는다 — 0으로 나누지 않는다. 금액 차이만 남는다.
    @Test func 앞_달이_0이면_비율은_nil이다() throws {
        let bills = [bill("2026-08", charged: 100), bill("2026-07", charged: 0)]
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
                        chargedAmount: 0, discountTotal: 0)
    }

    /// 목록·삭제 호출을 기록하는 대역. 서비스가 프로토콜이라 `MockAPIClient` 없이도 선다.
    final class FakeService: MaintenanceServing, @unchecked Sendable {
        var bills: [MaintenanceBill] = []
        var listError: Error?
        var deleteError: Error?
        private(set) var deletedYearMonths: [String] = []

        func fetchBills() async throws -> [MaintenanceBill] {
            if let listError { throw listError }
            return bills
        }
        func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
            MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                            items: [], usage: nil, chargedAmount: 0, discountTotal: 0)
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

struct MaintenanceFormatTests {
    @Test func 원화를_천단위로_끊는다() {
        #expect(MaintenanceFormat.won(Decimal(168_620)) == "168,620원")
        #expect(MaintenanceFormat.won(Decimal(0)) == "0원")
    }

    /// 증감은 **부호를 반드시 붙인다** — 「12,300원」만 적으면 오른 건지 내린 건지 모른다.
    @Test func 증감에는_부호가_붙는다() {
        #expect(MaintenanceFormat.signedWon(Decimal(12_300)) == "+12,300원")
        #expect(MaintenanceFormat.signedWon(Decimal(-4_500)) == "-4,500원")
        #expect(MaintenanceFormat.signedWon(Decimal(0)) == "+0원")
    }

    @Test func 비율은_소수_한_자리에_부호를_붙인다() {
        #expect(MaintenanceFormat.percent(Decimal(string: "0.0787")!) == "+7.9%")
        #expect(MaintenanceFormat.percent(Decimal(string: "-0.031")!) == "-3.1%")
    }

    @Test func 연월을_한국어로_적는다() {
        #expect(MaintenanceFormat.monthTitle("2026-08") == "2026년 8월")
        // 형식이 틀리면 원문 그대로 — 화면이 비는 것보다 낫다.
        #expect(MaintenanceFormat.monthTitle("bogus") == "bogus")
    }
}

struct MaintenanceTrendMathTests {
    private func month(
        _ yearMonth: String,
        charged: Decimal = 0,
        items: [MaintenanceBillItem] = [],
        usage: MaintenanceUsage? = nil
    ) -> MaintenanceTrendMonth {
        MaintenanceTrendMonth(yearMonth: yearMonth, chargedAmount: charged,
                              items: items, usage: usage)
    }

    /// **응답 순서를 믿지 않는다.** 차트 다섯 장이 전부 시간축이라 뒤집히면 전부 거짓이 된다.
    @Test func 연월_오름차순으로_정렬한다() {
        let months = [month("2026-08"), month("2025-12"), month("2026-01")]
        #expect(MaintenanceTrendMath.sorted(months).map(\.yearMonth)
                == ["2025-12", "2026-01", "2026-08"])
    }

    @Test func 부과액_점을_만든다() {
        let points = MaintenanceTrendMath.chargedPoints(
            [month("2026-07", charged: 150_000), month("2026-08", charged: 168_000)]
        )
        #expect(points.map(\.id) == ["2026-07", "2026-08"])
        #expect(points.map(\.label) == ["7", "8"])
        #expect(points.map(\.value) == [Decimal(150_000), Decimal(168_000)])
    }

    /// **13개월 전체에서 모은다.** 최근 달에만 있는 이름을 빼면 피커에서 사라진다.
    @Test func 항목_이름을_전체에서_모은다() {
        let months = [
            month("2026-07", items: [MaintenanceBillItem(name: "난방비", amount: 50_000)]),
            month("2026-08", items: [MaintenanceBillItem(name: "일반관리비", amount: 120_000),
                                     MaintenanceBillItem(name: "난방비", amount: 1_000)]),
        ]
        // 금액 합이 큰 순 — 일반관리비 120,000 > 난방비 51,000
        #expect(MaintenanceTrendMath.itemNames(months) == ["일반관리비", "난방비"])
    }

    /// **그 이름이 없는 달은 nil이다.** 0으로 채우면 「안 나왔다」가 「0원이었다」가 된다.
    @Test func 없는_달의_항목은_nil이다() {
        let months = [
            month("2026-07", items: []),
            month("2026-08", items: [MaintenanceBillItem(name: "난방비", amount: 51_000)]),
        ]
        let points = MaintenanceTrendMath.itemPoints(months, name: "난방비")

        #expect(points.map(\.value) == [nil, Decimal(51_000)])
    }

    @Test func 사용량_점을_만든다() {
        let months = [
            month("2026-07", usage: MaintenanceUsage(electricityKwh: Decimal(300), waterM3: nil,
                                                     hotWaterM3: nil, heatingGcal: nil, foodKg: nil)),
            month("2026-08", usage: nil),
        ]
        let points = MaintenanceTrendMath.usagePoints(months, kind: .electricity)

        #expect(points.map(\.value) == [Decimal(300), nil])
        #expect(MaintenanceTrendMath.UsageKind.electricity.unit == "kWh")
    }

    /// 전년 동월과 항목별로 견준다. **증감 절댓값이 큰 순 상위 N개**만 남긴다.
    @Test func 전년_동월_대비_증감을_낸다() throws {
        let months = [
            month("2025-08", items: [MaintenanceBillItem(name: "난방비", amount: 10_000),
                                     MaintenanceBillItem(name: "일반관리비", amount: 100_000)]),
            month("2026-08", items: [MaintenanceBillItem(name: "난방비", amount: 40_000),
                                     MaintenanceBillItem(name: "일반관리비", amount: 105_000)]),
        ]
        let deltas = try #require(MaintenanceTrendMath.yearOverYearDeltas(months))

        #expect(deltas.map(\.name) == ["난방비", "일반관리비"])
        #expect(deltas[0].delta == Decimal(30_000))
        #expect(deltas[1].delta == Decimal(5_000))
    }

    /// 작년에 없던 항목은 이번 달 금액 전부가 증가분이다.
    @Test func 작년에_없던_항목은_전액_증가다() throws {
        let months = [
            month("2025-08", items: []),
            month("2026-08", items: [MaintenanceBillItem(name: "승강기유지비", amount: 7_000)]),
        ]
        let deltas = try #require(MaintenanceTrendMath.yearOverYearDeltas(months))
        #expect(deltas == [MaintenanceItemDelta(name: "승강기유지비", delta: Decimal(7_000))])
    }

    /// **전년 동월이 범위에 없으면 nil이다.** 0으로 채우면 모든 항목이 「신설」로 보인다.
    @Test func 전년_동월이_없으면_nil이다() {
        let months = [
            month("2026-07", items: [MaintenanceBillItem(name: "난방비", amount: 1)]),
            month("2026-08", items: [MaintenanceBillItem(name: "난방비", amount: 2)]),
        ]
        #expect(MaintenanceTrendMath.yearOverYearDeltas(months) == nil)
    }

    @Test func 증감_상위_개수를_자른다() throws {
        let old = (1...10).map { MaintenanceBillItem(name: "항목\($0)", amount: Decimal(0)) }
        let new = (1...10).map { MaintenanceBillItem(name: "항목\($0)", amount: Decimal($0 * 1000)) }
        let months = [month("2025-08", items: old), month("2026-08", items: new)]

        let deltas = try #require(MaintenanceTrendMath.yearOverYearDeltas(months, topCount: 3))

        #expect(deltas.map(\.name) == ["항목10", "항목9", "항목8"])
    }

    /// 작년엔 있었는데 올해 사라진 항목도 증감이다 — **전액 감소로 남긴다.**
    /// 빠뜨리면 「없어져서 덜 냈다」가 통계에서 사라져 작년 대비가 실제보다 나빠 보인다.
    @Test func 올해_사라진_항목은_전액_감소다() throws {
        let months = [
            month("2025-08", items: [MaintenanceBillItem(name: "승강기유지비", amount: 7_000)]),
            month("2026-08", items: []),
        ]
        let deltas = try #require(MaintenanceTrendMath.yearOverYearDeltas(months))
        #expect(deltas == [MaintenanceItemDelta(name: "승강기유지비", delta: Decimal(-7_000))])
    }

    /// **다섯 종이 각자 제 필드를 읽는지 전부 확인한다.** 수도와 온수는 단위가 같아
    /// 서로 바뀌어도 화면만 봐서는 모른다 — 차트 한 장이 통째로 거짓이 된다.
    @Test func 사용량_다섯_종이_제_필드를_읽는다() throws {
        let usage = MaintenanceUsage(
            electricityKwh: Decimal(311),
            waterM3: Decimal(12),
            hotWaterM3: Decimal(5),
            heatingGcal: Decimal(2),
            foodKg: Decimal(9)
        )
        let months = [month("2026-08", usage: usage)]
        let expected: [(MaintenanceTrendMath.UsageKind, Decimal, String, String)] = [
            (.electricity, 311, "전기", "kWh"),
            (.water, 12, "수도", "m³"),
            (.hotWater, 5, "온수", "m³"),
            (.heating, 2, "난방", "Gcal"),
            (.food, 9, "음식물", "kg"),
        ]
        for (kind, value, label, unit) in expected {
            #expect(MaintenanceTrendMath.usagePoints(months, kind: kind).first?.value == value)
            #expect(kind.label == label)
            #expect(kind.unit == unit)
        }
    }
}

struct DivergingRankGeometryTests {
    /// 가장 크게 움직인 행이 트랙 절반을 꽉 채운다.
    @Test func 최대값이_절반을_채운다() {
        let width = DivergingRankGeometry.halfWidth(Decimal(30_000), maxAbs: Decimal(30_000),
                                                    trackWidth: 200)
        #expect(width == 100)
    }

    /// **부호는 폭에 담지 않는다** — 방향은 그리는 쪽이 정렬로 정한다. 여기선 크기만 낸다.
    @Test func 음수도_같은_크기를_낸다() {
        let up = DivergingRankGeometry.halfWidth(Decimal(15_000), maxAbs: Decimal(30_000),
                                                 trackWidth: 200)
        let down = DivergingRankGeometry.halfWidth(Decimal(-15_000), maxAbs: Decimal(30_000),
                                                   trackWidth: 200)
        #expect(up == down)
        #expect(up == 50)
    }

    /// 0으로 나누지 않는다.
    @Test func 최대가_0이면_폭이_0이다() {
        #expect(DivergingRankGeometry.halfWidth(Decimal(0), maxAbs: Decimal(0), trackWidth: 200) == 0)
    }

    /// 0이 아닌데 너무 작아 안 보이는 막대는 최소 폭을 준다 — 「0이다」와 갈려야 한다.
    @Test func 아주_작은_값도_보인다() {
        let width = DivergingRankGeometry.halfWidth(Decimal(1), maxAbs: Decimal(1_000_000),
                                                    trackWidth: 200)
        #expect(width == 2)
    }

    /// 양수는 기준선에서 오른쪽으로 자란다 — 시작점이 곧 기준선이다.
    @Test func 양수는_기준선에서_시작한다() {
        #expect(DivergingRankGeometry.barStart(Decimal(15_000), maxAbs: Decimal(30_000),
                                               trackWidth: 200) == 100)
    }

    /// 음수는 기준선에서 **왼쪽으로** 자라므로 시작점이 기준선보다 막대 길이만큼 앞이다.
    /// 이 단언이 「막대가 트랙 바깥 가장자리에 붙는」 예전 배치를 걸러낸다.
    @Test func 음수는_기준선_왼쪽에서_시작한다() {
        #expect(DivergingRankGeometry.barStart(Decimal(-15_000), maxAbs: Decimal(30_000),
                                               trackWidth: 200) == 50)
    }
}

@MainActor
struct MaintenanceTrendsViewModelTests {
    final class TrendStubService: MaintenanceServing, @unchecked Sendable {
        var months: [MaintenanceTrendMonth] = []
        var error: Error?
        private(set) var callCount = 0
        private(set) var requestedMonths: [Int] = []

        func fetchBills() async throws -> [MaintenanceBill] { [] }
        func fetchBill(yearMonth: String) async throws -> MaintenanceBill {
            MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                            items: [], usage: nil, chargedAmount: 0, discountTotal: 0)
        }
        func recognize(imageData: Data) async throws -> MaintenanceRecognition {
            fatalError("이 스위트는 인식을 부르지 않는다")
        }
        func saveBill(_ request: MaintenanceBillSaveRequest) async throws {}
        func updateBill(yearMonth: String, _ request: MaintenanceBillSaveRequest) async throws {}
        func deleteBill(yearMonth: String) async throws {}
        func fetchTrends(months monthCount: Int) async throws -> [MaintenanceTrendMonth] {
            callCount += 1
            requestedMonths.append(monthCount)
            if let error { throw error }
            return months
        }
    }

    private func month(_ yearMonth: String, charged: Decimal,
                       items: [MaintenanceBillItem] = []) -> MaintenanceTrendMonth {
        MaintenanceTrendMonth(yearMonth: yearMonth, chargedAmount: charged, items: items, usage: nil)
    }

    private func point(_ yearMonth: String, _ value: Decimal?) -> ChartPoint {
        ChartPoint(id: yearMonth, label: MonthLabel.axis(yearMonth), value: value)
    }

    /// **13을 보낸다** — 전년 동월이 범위에 들어오게 하려는 것이다.
    @Test func 열세_달을_받아_오름차순으로_담는다() async {
        let service = TrendStubService()
        service.months = [month("2026-08", charged: 2), month("2025-08", charged: 1)]
        let vm = MaintenanceTrendsViewModel(service: service)

        await vm.load()

        #expect(service.requestedMonths == [13])
        #expect(vm.months.map(\.yearMonth) == ["2025-08", "2026-08"])
    }

    /// **탭을 오갈 때마다 다시 받지 않는다.**
    @Test func 이미_받았으면_다시_받지_않는다() async {
        let service = TrendStubService()
        let vm = MaintenanceTrendsViewModel(service: service)

        await vm.load()
        await vm.load()

        #expect(service.callCount == 1)
    }

    /// 저장·수정 뒤에는 낡은 값을 버리고 다시 받는다.
    @Test func reload는_다시_받는다() async {
        let service = TrendStubService()
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()

        await vm.reload()

        #expect(service.callCount == 2)
    }

    @Test func 실패하면_메시지가_남는다() async {
        let service = TrendStubService()
        service.error = APIError.serverError(statusCode: 500, message: nil)
        let vm = MaintenanceTrendsViewModel(service: service)

        await vm.load()

        #expect(vm.errorMessage != nil)
        // 실패한 로딩은 `hasLoaded`를 세우지 않는다 — 다시 열면 재시도해야 한다.
        #expect(vm.hasLoaded == false)
    }

    /// 최근 달 항목 순위. 금액 큰 순이다.
    @Test func 최근_달_항목을_금액순으로_낸다() async {
        let service = TrendStubService()
        service.months = [
            month("2026-08", charged: 170_000,
                  items: [MaintenanceBillItem(name: "세대전기료", amount: 48_000),
                          MaintenanceBillItem(name: "일반관리비", amount: 121_000)])
        ]
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()

        #expect(vm.latestItemRows.map(\.label) == ["일반관리비", "세대전기료"])
    }

    /// **차감 항목이 있어도 비율이 100%를 안 넘는다.** 분모를 부호 있는 합(90,000)으로
    /// 잡으면 100,000짜리 항목이 111%가 되고 차감은 −11%가 된다 — 구성비 카드가
    /// 거짓을 말한다. 분모는 양수 항목의 합(100,000)이어야 한다.
    @Test func 차감_항목이_있어도_비율이_100퍼센트를_안_넘는다() async {
        let service = TrendStubService()
        service.months = [
            month("2026-08", charged: 90_000,
                  items: [MaintenanceBillItem(name: "일반관리비", amount: 100_000),
                          MaintenanceBillItem(name: "관리비차감", amount: -10_000)])
        ]
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()

        let rows = vm.latestItemRows
        #expect(rows.map(\.label) == ["일반관리비", "관리비차감"])
        #expect(rows[0].secondary == "100.0%")
        // 차감 행에는 비율을 안 적는다 — 「구성비 -10%」는 뜻이 없다.
        #expect(rows[1].secondary == "차감")
    }

    /// **고른 항목이 사라지면 첫 항목으로 돌아간다.** 수정·삭제로 그 항목이 없어진 뒤
    /// 추이를 다시 받으면, 예전에는 피커가 지워진 이름을 계속 보여주고 차트는 전부 nil인
    /// 빈 그림이 됐다.
    @Test func 고른_항목이_사라지면_첫_항목으로_돌아간다() async {
        let service = TrendStubService()
        service.months = [
            month("2026-08", charged: 100,
                  items: [MaintenanceBillItem(name: "난방비", amount: 60),
                          MaintenanceBillItem(name: "일반관리비", amount: 40)])
        ]
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()
        vm.selectedItemName = "난방비"
        #expect(vm.effectiveItemName == "난방비")

        // 그 달을 고쳐 난방비 행이 없어졌다.
        service.months = [
            month("2026-08", charged: 40,
                  items: [MaintenanceBillItem(name: "일반관리비", amount: 40)])
        ]
        await vm.reload()

        #expect(vm.effectiveItemName == "일반관리비")
        #expect(vm.itemPoints.contains { $0.value != nil })
    }

    /// 전년 동월이 없으면 #3의 행이 nil이다 — 화면이 사유를 적는다.
    @Test func 전년_동월이_없으면_증감_행이_nil이다() async {
        let service = TrendStubService()
        service.months = [month("2026-07", charged: 1), month("2026-08", charged: 2)]
        let vm = MaintenanceTrendsViewModel(service: service)
        await vm.load()

        #expect(vm.yearOverYearRows == nil)
    }

    // MARK: - callout(for:selectedID:suffix:)

    /// **#1·#4·#5 콜아웃이 전부 이 함수 하나로 나온다.** 여기서 놓치면 세 카드가 조용히
    /// 같은 방식으로 틀린다 — 실제로 강조와 콜아웃이 다른 달을 가리키는 버그가 여기서 났다.

    @Test func 고른_점을_읽는다() {
        let vm = MaintenanceTrendsViewModel(service: TrendStubService())
        let points = [point("2026-07", 150_000), point("2026-08", 168_620)]

        let text = vm.callout(for: points, selectedID: "2026-07", suffix: "")

        #expect(text == "2026년 7월 150,000원")
    }

    /// **고른 것이 없으면 값이 있는 마지막 점이다.** 그냥 `points.last`를 쓰면 계절
    /// 토글에서 마지막 달이 `nil`인 채 걸린다.
    @Test func 아무것도_안_골랐으면_마지막_점이다() {
        let vm = MaintenanceTrendsViewModel(service: TrendStubService())
        let points = [point("2026-07", 150_000), point("2026-08", 168_620)]

        let text = vm.callout(for: points, selectedID: nil, suffix: "")

        #expect(text == "2026년 8월 168,620원")
    }

    /// 여름에 「난방」을 고르면 최근 달의 값이 `nil`일 수 있다 — 그 달을 건너뛰고
    /// 값이 있는 마지막 점을 고른다. `points.last`였다면 「기록 없음」을 잘못 냈을 자리다.
    @Test func nil인_점은_건너뛰고_값_있는_마지막_점을_고른다() {
        let vm = MaintenanceTrendsViewModel(service: TrendStubService())
        let points = [point("2026-06", 150_000), point("2026-07", nil), point("2026-08", nil)]

        let text = vm.callout(for: points, selectedID: nil, suffix: "")

        #expect(text == "2026년 6월 150,000원")
    }

    /// 골랐는데 그 달의 값이 `nil`이면 「기록 없음」이다 — 값이 있는 다른 달로 조용히
    /// 넘어가지 않는다. 고른 것은 존중한다.
    @Test func 고른_점이_nil이면_기록_없음이다() {
        let vm = MaintenanceTrendsViewModel(service: TrendStubService())
        let points = [point("2026-07", 150_000), point("2026-08", nil)]

        let text = vm.callout(for: points, selectedID: "2026-08", suffix: "")

        #expect(text == "2026년 8월 기록 없음")
    }

    @Test func suffix가_있으면_단위를_붙인다() {
        let vm = MaintenanceTrendsViewModel(service: TrendStubService())
        let points = [point("2026-08", Decimal(string: "312.5"))]

        let text = vm.callout(for: points, selectedID: "2026-08", suffix: "kWh")

        #expect(text == "2026년 8월 312.5 kWh")
    }

    /// **연도가 이제 갈린다.** 예전엔 `point.label`(월만, 「8」)을 썼어서 13개월 창의
    /// 양 끝인 2025-08과 2026-08이 콜아웃에서 똑같이 보였다 — 13개월을 고른 이유가
    /// 정확히 전년 동월 비교인데, 그 둘이 안 갈리면 창을 고른 뜻이 없다.
    @Test func 전년_동월과_올해가_콜아웃에서_갈린다() {
        let vm = MaintenanceTrendsViewModel(service: TrendStubService())
        let points = [point("2025-08", 150_000), point("2026-08", 168_620)]

        let thisYear = vm.callout(for: points, selectedID: "2026-08", suffix: "")
        let lastYear = vm.callout(for: points, selectedID: "2025-08", suffix: "")

        #expect(thisYear != lastYear)
        #expect(thisYear == "2026년 8월 168,620원")
        #expect(lastYear == "2025년 8월 150,000원")
    }

    /// 점이 하나도 없으면 콜아웃도 없다 — 빈 카드에 「기록 없음」을 억지로 그리지 않는다.
    @Test func 점이_없으면_nil이다() {
        let vm = MaintenanceTrendsViewModel(service: TrendStubService())

        #expect(vm.callout(for: [], selectedID: nil, suffix: "") == nil)
    }
}
