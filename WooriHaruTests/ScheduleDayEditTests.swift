import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct ScheduleDayEditViewModelTests {
    private func day(
        _ role: DispatchRole,
        working: Bool,
        slot: Int? = nil,
        slotCode: String? = nil,
        note: String? = nil
    ) -> DispatchShiftDay {
        DispatchShiftDay(date: "2026-08-15", role: role, working: working, slot: slot, slotCode: slotCode, note: note)
    }

    private func makeViewModel(
        days: [DispatchShiftDay],
        holidayNames: [String] = [],
        service: FakeScheduleService = FakeScheduleService(days: [])
    ) -> ScheduleDayEditViewModel {
        ScheduleDayEditViewModel(
            date: "2026-08-15",
            dayLabel: "8월 15일 (토)",
            days: days,
            holidayNames: holidayNames,
            service: service
        )
    }

    @Test func 공휴일_이름을_들고_있는다() {
        let vm = makeViewModel(days: [], holidayNames: ["광복절"])

        #expect(vm.holidayNames == ["광복절"])
    }

    @Test func 공휴일이_아니면_비어_있다() {
        let vm = makeViewModel(days: [])

        #expect(vm.holidayNames.isEmpty)
    }

    @Test func 미등록인_역할은_선택_없이_시작한다() {
        let vm = makeViewModel(days: [day(.mother, working: true)])

        #expect(vm.fatherWorking == nil)
        #expect(vm.motherWorking == .working)
    }

    @Test func 아무것도_건드리지_않으면_저장이_잠긴다() {
        let vm = makeViewModel(days: [])

        #expect(vm.canSave == false)
    }

    @Test func 한_역할만_고르면_저장이_열린다() {
        let vm = makeViewModel(days: [])

        vm.motherWorking = .off

        #expect(vm.canSave)
    }

    @Test func 건드린_역할만_요청에_실린다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        vm.motherSlotCode = "B"
        _ = await vm.save()

        #expect(service.editCalls.count == 1)
        #expect(service.editCalls.first?.date == "2026-08-15")
        #expect(service.editCalls.first?.request.father == nil)
        #expect(service.editCalls.first?.request.mother == DispatchRoleEdit(working: true, slot: nil, slotCode: "B"))
    }

    /// **저장된 값이 폼에 채워진 것과 사용자가 건드린 것은 다르다.** 손대지 않은 역할을
    /// 함께 보내면, 시트를 열 때 읽은 값으로 그 사이 다른 곳에서 바뀐 값을 덮어쓴다.
    @Test func 손대지_않은_역할은_요청에_실리지_않는다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 2)], service: service)

        vm.motherWorking = .off
        _ = await vm.save()

        #expect(service.editCalls.first?.request.father == nil)
        #expect(service.editCalls.first?.request.mother == DispatchRoleEdit(working: false, slot: nil, slotCode: nil))
    }

    @Test func 기존_레코드가_있어도_안_건드리면_저장이_잠긴다() {
        let vm = makeViewModel(days: [
            day(.father, working: true, slot: 2),
            day(.mother, working: true, slotCode: "A")
        ])

        #expect(vm.canSave == false)
    }

    /// 값을 같은 것으로 다시 골라도 「건드렸다」로 센다. 사용자가 그 역할을 확인하고
    /// 확정한 것이라, 보내지 않으면 아무 일도 안 일어나 고장으로 보인다.
    @Test func 같은_값을_다시_골라도_실린다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 2)], service: service)

        vm.fatherWorking = .working
        _ = await vm.save()

        #expect(service.editCalls.first?.request.father == DispatchRoleEdit(working: true, slot: 2, slotCode: nil))
    }

    @Test func 휴무를_고르면_순번이_비워진다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 1)], service: service)

        vm.fatherWorking = .off
        _ = await vm.save()

        #expect(service.editCalls.first?.request.father == DispatchRoleEdit(working: false, slot: nil, slotCode: nil))
    }

    @Test func 순번_선택지는_1과_2다() {
        let vm = makeViewModel(days: [])

        #expect(vm.fatherSlotOptions == [1, 2])
        #expect(vm.motherSlotCodeOptions == ["A", "B", "C"])
    }

    /// 사진 인식이 넣어 둔 값이 선택지에 없으면, 그 역할을 고칠 때 순번이 조용히 지워진다.
    @Test func 선택지에_없는_저장값도_선택지에_들어간다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 3)], service: service)

        #expect(vm.fatherSlotOptions == [1, 2, 3])
        #expect(vm.fatherSlot == 3)

        // 아빠의 근무 여부만 다시 확정한다 — 순번은 손대지 않았으니 3이 그대로 실려야 한다.
        vm.fatherWorking = .working
        _ = await vm.save()

        #expect(service.editCalls.first?.request.father?.slot == 3)
    }

    /// 서버는 204라 돌려주는 것이 없다. 화면에 그릴 값은 여기서 만든다.
    @Test func 저장에_성공하면_보낸_값으로_그날을_만든다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        vm.motherSlotCode = "A"
        let result = await vm.save()

        #expect(result == [day(.mother, working: true, slotCode: "A")])
        #expect(vm.errorMessage == nil)
    }

    /// **건드리지 않은 역할은 결과에도 없다.** 그 값까지 「방금 저장한 값」인 척 달력에
    /// 얹으면, 시트를 열 때 읽은 낡은 값이 그 뒤에 도착한 조회 결과를 덮는다.
    @Test func 건드리지_않은_역할은_결과에_없다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 2, note: "*97")], service: service)

        vm.motherWorking = .off
        let result = await vm.save()

        #expect(result == [day(.mother, working: false)])
    }

    /// `note`는 이 경로에서 읽지도 쓰지도 않는다. 화면 값에서도 지워지면 안 된다.
    @Test func 고친_역할의_메모도_남는다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [day(.father, working: true, slot: 1, note: "간담회")], service: service)

        vm.fatherSlot = 2
        let result = await vm.save()

        #expect(result == [day(.father, working: true, slot: 2, note: "간담회")])
    }

    /// 미등록인 채로 남은 역할은 레코드가 없다. 휴무로 만들어 두면 달력이 거짓말을 한다.
    @Test func 미등록으로_남은_역할은_결과에_없다() async {
        let service = FakeScheduleService(days: [])
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        let result = await vm.save()

        #expect(result?.contains { $0.role == .father } == false)
    }

    @Test func 저장에_실패하면_nil을_주고_메시지를_남긴다() async {
        let service = FakeScheduleService(days: [])
        service.editError = APIError.serverError(statusCode: 400, message: "엄마 순번은 slotCode입니다")
        let vm = makeViewModel(days: [], service: service)

        vm.motherWorking = .working
        let result = await vm.save()

        #expect(result == nil)
        #expect(vm.errorMessage == "엄마 순번은 slotCode입니다")
        #expect(vm.isSaving == false)
    }
}
