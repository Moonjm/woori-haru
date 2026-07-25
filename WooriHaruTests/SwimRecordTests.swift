import Foundation
import Testing
@testable import WooriHaru

// MARK: - Fake

private final class FakeSwimFetcher: SwimWorkoutFetching {
    var isHealthDataAvailable: Bool
    var workouts: [SwimWorkout]
    var errorToThrow: Error?
    private(set) var requestedLimit: Int?

    init(isHealthDataAvailable: Bool = true, workouts: [SwimWorkout] = [], errorToThrow: Error? = nil) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.workouts = workouts
        self.errorToThrow = errorToThrow
    }

    func requestAuthorization() async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func fetchSwimWorkouts(limit: Int) async throws -> [SwimWorkout] {
        requestedLimit = limit
        if let errorToThrow { throw errorToThrow }
        return workouts
    }
}

private func makeWorkout(
    start: Date = Date(timeIntervalSince1970: 1_753_400_000),
    duration: TimeInterval = 1800,
    distance: Double? = 1200,
    energy: Double? = 320,
    strokes: Int? = 1240,
    location: SwimWorkout.Location = .pool,
    laneLength: Double? = 25
) -> SwimWorkout {
    SwimWorkout(
        id: UUID(),
        startDate: start,
        endDate: start.addingTimeInterval(duration),
        duration: duration,
        distanceMeters: distance,
        activeEnergyKcal: energy,
        strokeCount: strokes,
        location: location,
        laneLengthMeters: laneLength
    )
}

// MARK: - Model Formatting

struct SwimWorkoutFormatTests {
    @Test func 거리_1km_이상은_km로_미만은_m로() {
        #expect(makeWorkout(distance: 1200).distanceText == "1.20km")
        #expect(makeWorkout(distance: 800).distanceText == "800m")
        #expect(makeWorkout(distance: 1000).distanceText == "1.00km")
    }

    @Test func 값이_없거나_0이면_표기하지_않음() {
        #expect(makeWorkout(distance: nil).distanceText == nil)
        #expect(makeWorkout(distance: 0).distanceText == nil)
        #expect(makeWorkout(energy: nil).energyText == nil)
        #expect(makeWorkout(strokes: 0).strokeText == nil)
    }

    @Test func 운동시간_표기() {
        #expect(makeWorkout(duration: 1800).durationText == "30분")
        #expect(makeWorkout(duration: 3900).durationText == "1시간 5분")
        #expect(makeWorkout(duration: 30).durationText == "1분 미만")
    }

    @Test func 장소와_레인길이_합성() {
        #expect(makeWorkout(location: .pool, laneLength: 25).locationText == "수영장 · 25m 레인")
        #expect(makeWorkout(location: .openWater, laneLength: nil).locationText == "개방 수역")
        #expect(makeWorkout(location: .unknown, laneLength: nil).locationText == "수영")
    }

    @Test func 날짜에_연도가_포함된다() {
        // 실행 환경 타임존에 좌우되지 않도록 현재 달력으로 날짜를 만든다
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 9))!
        #expect(makeWorkout(start: date).dayText == "2026년 7월 25일 (토)")
    }

    @Test func 칼로리_스트로크_표기() {
        #expect(makeWorkout(energy: 320).energyText == "320kcal")
        #expect(makeWorkout(strokes: 1240).strokeText == "1,240회")
    }
}

// MARK: - ViewModel

@MainActor
struct SwimRecordViewModelTests {
    @Test func 로딩_성공시_목록과_요약이_채워진다() async {
        let fetcher = FakeSwimFetcher(workouts: [
            makeWorkout(duration: 1800, distance: 1200),
            makeWorkout(duration: 1200, distance: 800)
        ])
        let vm = SwimRecordViewModel(service: fetcher, limit: 100)

        await vm.load()

        #expect(vm.workouts.count == 2)
        #expect(vm.totalCount == 2)
        #expect(vm.totalDistanceText == "2.0km")
        #expect(vm.totalDurationText == "50분")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.showsEmptyState == false)
        #expect(fetcher.requestedLimit == 100)
    }

    @Test func 결과가_없으면_빈_상태를_보여준다() async {
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(workouts: []))

        #expect(vm.showsEmptyState == false) // 로딩 전에는 빈 상태를 띄우지 않는다
        await vm.load()

        #expect(vm.workouts.isEmpty)
        #expect(vm.showsEmptyState == true)
        #expect(vm.totalDistanceText == nil)
    }

    @Test func 실패시_에러메시지가_설정되고_빈_상태는_뜨지_않는다() async {
        let vm = SwimRecordViewModel(
            service: FakeSwimFetcher(errorToThrow: SwimWorkoutError.healthDataUnavailable)
        )

        await vm.load()

        #expect(vm.errorMessage == "이 기기에서는 건강 데이터를 사용할 수 없습니다.")
        #expect(vm.showsEmptyState == false)
        #expect(vm.isLoading == false)
    }

    @Test func 건강데이터_미지원_기기_여부를_그대로_전달한다() {
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(isHealthDataAvailable: false))
        #expect(vm.isHealthDataAvailable == false)
    }
}
