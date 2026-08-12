import Foundation
import Testing
@testable import WooriHaru

/// 조회 전용 화면이다. 여기서 근무를 고치지 않는다 — 수정은 사진 → 검수 경로로만 한다.
@MainActor
struct ScheduleViewModelTests {
    private func makeViewModel(
        mock: MockAPIClient,
        service: FakeScheduleService
    ) -> ScheduleViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return ScheduleViewModel(
            service: service,
            holidayService: HolidayService(api: mock),
            now: calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!,
            calendar: calendar
        )
    }

    @Test func 진입하면_이번_달을_조회한다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        #expect(vm.yearMonth == "2026-08")
        #expect(vm.monthLabel == "2026년 8월")
        #expect(service.requestedYearMonths == ["2026-08"])
        #expect(vm.badges(on: "2026-08-15") == [ScheduleViewModel.Badge(role: .father, slot: 1)])
    }

    @Test func 휴무는_밴드를_만들지_않는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: false, slot: nil, note: "휴")
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 휴무와 미등록을 구분하지 않는다. 아빠는 그 달 전체를 한 번에 등록하므로
        // 미등록이면 달 전체가 비어 한눈에 보인다.
        #expect(vm.badges(on: "2026-08-15").isEmpty)
    }

    @Test func 순번_없는_근무도_밴드를_만든다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: true, slot: nil, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 엄마는 순번을 넣지 않는다. 색만 칠한다.
        #expect(vm.badges(on: "2026-08-15") == [ScheduleViewModel.Badge(role: .mother, slot: nil)])
    }

    @Test func 아빠와_엄마가_같은_날에_함께_온다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .mother, working: true, slot: nil, note: nil),
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 2, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 순서를 역할로 고정한다 — 응답 순서대로 그리면 날마다 위아래가 바뀐다.
        #expect(vm.badges(on: "2026-08-15") == [
            ScheduleViewModel.Badge(role: .father, slot: 2),
            ScheduleViewModel.Badge(role: .mother, slot: nil)
        ])
    }

    @Test func 달을_옮기면_그_달을_조회한다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()

        await vm.move(by: 1)
        #expect(vm.yearMonth == "2026-09")

        await vm.move(by: -2)
        #expect(vm.yearMonth == "2026-07")
        #expect(service.requestedYearMonths == ["2026-08", "2026-09", "2026-07"])
    }

    @Test func 해를_넘어도_이동한다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let vm = makeViewModel(mock: mock, service: FakeScheduleService(days: []))
        await vm.load()

        await vm.move(by: 5)

        #expect(vm.yearMonth == "2027-01")
        #expect(vm.monthLabel == "2027년 1월")
    }

    @Test func 공휴일은_달을_오가도_남는다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: ["2026-08-15": ["광복절"]]))
        let vm = makeViewModel(mock: mock, service: FakeScheduleService(days: []))

        await vm.load()
        await vm.move(by: 1)
        await vm.move(by: -1)

        // 받은 값을 연 단위로 들고 있어야 한다. 화면 상태 안에만 두고 「이미 받았다」는
        // 표시를 따로 두면 둘이 어긋나 공휴일이 통째로 사라진다(#70).
        #expect(vm.holidayNames(on: "2026-08-15") == ["광복절"])
        #expect(mock.getCalls.filter { $0.path == "/holidays" }.count == 1)
    }

    @Test func 공휴일_조회가_실패해도_근무는_보인다() async {
        let mock = MockAPIClient()
        mock.setError(APIError.serverError(statusCode: 500, message: "nope"), for: "GET /holidays")
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        // 근무가 주 정보고 공휴일은 부가다. 부가 때문에 화면이 비면 안 된다.
        #expect(vm.badges(on: "2026-08-15").isEmpty == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func 근무_조회가_실패하면_알린다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [])
        service.error = APIError.serverError(statusCode: 500, message: """
        {"status":500,"message":"조회에 실패했습니다.","code":"500","error":"INTERNAL"}
        """)
        let vm = makeViewModel(mock: mock, service: service)

        await vm.load()

        #expect(vm.errorMessage == "조회에 실패했습니다.")
    }

    @Test func 연월_문자열로_그_달을_띄운다() async {
        // 저장을 마치고 검수 화면에서 돌아올 때 이 경로를 탄다. 배차표는 다음 달치를
        // 등록하는 게 정상이라, 보고 있던 달이 아니라 저장한 달을 띄워야 한다.
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-09-05", role: .father, working: true, slot: 2, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()

        await vm.show(yearMonth: "2026-09")

        #expect(vm.yearMonth == "2026-09")
        #expect(vm.monthLabel == "2026년 9월")
        #expect(service.requestedYearMonths == ["2026-08", "2026-09"])
        #expect(vm.badges(on: "2026-09-05") == [ScheduleViewModel.Badge(role: .father, slot: 2)])
    }

    @Test func 형식이_틀린_연월은_보고_있던_달을_유지한다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(mock: mock, service: service)
        await vm.load()

        await vm.show(yearMonth: "2026-9")
        await vm.show(yearMonth: "")
        await vm.show(yearMonth: "not-a-date")

        // 엉뚱한 달로 튀는 것보다, 보고 있던 달을 그대로 유지하는 편이 낫다.
        #expect(vm.yearMonth == "2026-08")
        #expect(service.requestedYearMonths == ["2026-08"])
    }

    @Test func 늦게_온_이전_달_응답을_버린다() async {
        let mock = MockAPIClient()
        mock.stubGet("/holidays", result: DataResponse<[String: [String]]>(data: [:]))
        let service = FakeScheduleService(days: [
            DispatchShiftDay(date: "2026-08-15", role: .father, working: true, slot: 1, note: nil)
        ])
        let vm = makeViewModel(mock: mock, service: service)
        service.duringFetch = { [vm] in
            // 한 번만 끼어든다. 그대로 두면 move가 부른 load에서 또 걸려 무한히 돈다.
            service.duringFetch = nil
            await vm.move(by: 1)
        }

        await vm.load()

        // 8월 응답이 9월 화면에 그려지면 사용자는 9월에 그 근무가 있다고 믿는다.
        #expect(vm.yearMonth == "2026-09")
        #expect(vm.badges(on: "2026-08-15").isEmpty)
    }
}

/// 조회만 하는 대역. 요청한 연월을 기록한다.
final class FakeScheduleService: DispatchServing, @unchecked Sendable {
    var days: [DispatchShiftDay]
    var error: Error?
    /// 조회가 진행 중인 순간에 끼어들 자리.
    var duringFetch: (@Sendable () async -> Void)?
    private(set) var requestedYearMonths: [String] = []

    init(days: [DispatchShiftDay]) {
        self.days = days
    }

    func findShifts(yearMonth: String) async throws -> [DispatchShiftDay] {
        requestedYearMonths.append(yearMonth)
        await duringFetch?()
        if let error { throw error }
        // 서버는 그 달의 날짜만 돌려준다. 대역도 같아야 「늦게 온 8월 응답을 버리는가」를
        // 실제로 검증할 수 있다.
        return days.filter { $0.date.hasPrefix(yearMonth) }
    }

    func recognize(imageData: Data) async throws -> DispatchRecognition {
        fatalError("이 화면은 인식하지 않는다")
    }

    func saveShifts(_ request: DispatchShiftSaveRequest) async throws {
        fatalError("이 화면은 저장하지 않는다")
    }
}
