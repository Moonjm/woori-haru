import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct StudyTimerFormatTests {
    private func makeViewModel() -> StudyTimerViewModel {
        StudyTimerViewModel(service: StudyService(api: MockAPIClient()))
    }

    @Test func elapsedFormatted_시분초_자리맞춤() {
        let vm = makeViewModel()
        vm.elapsedSeconds = 0
        #expect(vm.elapsedFormatted == "00:00:00")
        vm.elapsedSeconds = 61
        #expect(vm.elapsedFormatted == "00:01:01")
        vm.elapsedSeconds = 3661
        #expect(vm.elapsedFormatted == "01:01:01")
        vm.elapsedSeconds = 10 * 3600 + 59 * 60 + 59
        #expect(vm.elapsedFormatted == "10:59:59")
    }

    @Test func 주간_목표_표기() {
        // weeklyGoalMinutes = 3000분 = 50시간 (분이 0이면 생략)
        #expect(makeViewModel().weeklyGoalFormatted == "50시간")
    }

    @Test func 시작_전에는_earlyConfirm_아님() {
        #expect(makeViewModel().isWithinEarlyConfirm == false)
    }
}
