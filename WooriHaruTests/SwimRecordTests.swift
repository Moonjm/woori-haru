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

    var effortScore: Double?

    func fetchEffortScore(workoutID: UUID) async throws -> Double? {
        if let errorToThrow { throw errorToThrow }
        return effortScore
    }
}

private func makeWorkout(
    start: Date = Date(timeIntervalSince1970: 1_753_400_000),
    duration: TimeInterval = 1800,
    distance: Double? = 1200,
    energy: Double? = 320,
    strokes: Int? = 1240,
    location: SwimWorkout.Location = .pool,
    laneLength: Double? = 25,
    laps: [SwimLap] = [],
    averageHeartRate: Double? = nil,
    maxHeartRate: Double? = nil
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
        averageHeartRate: averageHeartRate,
        maxHeartRate: maxHeartRate,
        laneLengthMeters: laneLength,
        laps: laps
    )
}

/// 레인 길이 `laneLength`짜리 랩을 `durations` 개수만큼 만든다.
private func makeLaps(
    durations: [TimeInterval],
    laneLength: Double = 25,
    strokes: [SwimStrokeStyle]? = nil
) -> [SwimLap] {
    var start = Date(timeIntervalSince1970: 1_753_400_000)
    return durations.indices.map { index in
        let lap = SwimLap(
            id: index,
            startDate: start,
            duration: durations[index],
            distanceMeters: laneLength,
            strokeStyle: strokes?[index] ?? .freestyle
        )
        start = start.addingTimeInterval(durations[index])
        return lap
    }
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

// MARK: - Stroke Breakdown

struct StrokeBreakdownTests {
    @Test func 랩이_없으면_집계도_없다() {
        let workout = makeWorkout(laps: [])
        #expect(workout.hasLapData == false)
        #expect(workout.strokeBreakdown.isEmpty)
    }

    @Test func 영법별_거리를_많이_한_순서로_집계한다() {
        // 자유형 4랩(100m), 평영 2랩(50m)
        let workout = makeWorkout(laps: makeLaps(
            durations: [30, 30, 40, 40, 30, 30],
            strokes: [.breaststroke, .breaststroke, .freestyle, .freestyle, .freestyle, .freestyle]
        ))
        let breakdown = workout.strokeBreakdown

        #expect(breakdown.count == 2)
        #expect(breakdown[0].style == .freestyle)
        #expect(breakdown[0].metersText == "100m")
        #expect(breakdown[0].ratio == 1)
        #expect(breakdown[1].style == .breaststroke)
        #expect(breakdown[1].metersText == "50m")
        #expect(breakdown[1].ratio == 0.5)
    }

    @Test func 영법별_페이스는_100m_환산이다() {
        // 자유형 2랩 50m를 70초 → 100m 환산 2:20
        let workout = makeWorkout(laps: makeLaps(durations: [35, 35]))
        #expect(workout.strokeBreakdown[0].paceText == "2:20/100m")
    }

    @Test func 시간_표기는_1시간을_넘으면_시까지_쓴다() {
        #expect(TimeInterval(59).clockText == "0:59")
        #expect(TimeInterval(112).clockText == "1:52")
        #expect(TimeInterval(3723).clockText == "1:02:03")
    }

    @Test func 영법이_섞이면_혼영으로_묶인다() {
        let mixed = makeWorkout(laps: makeLaps(
            durations: [30, 30], strokes: [.freestyle, .breaststroke]
        ))
        #expect(mixed.sets[0].strokeStyle == .mixed)

        let single = makeWorkout(laps: makeLaps(
            durations: [30, 30], strokes: [.backstroke, .backstroke]
        ))
        #expect(single.sets[0].strokeStyle == .backstroke)
    }
}

// MARK: - Auto Sets

struct SwimSetTests {
    /// 2026-07-25 실제 워치 기록의 앞부분 12랩 (50m 레인).
    /// (워크아웃 시작 후 경과 초, 소요 초) — 진단 화면에서 그대로 옮겼다.
    private static let realLaps: [(offset: TimeInterval, duration: TimeInterval)] = [
        (44, 66), (113, 68), (188, 66), (258, 69),
        (466, 61), (533, 65),
        (761, 63), (830, 64),
        (1014, 62), (1077, 72),
        (1336, 57),
        (1470, 62)
    ]

    private func realWorkout() -> SwimWorkout {
        let start = Date(timeIntervalSince1970: 1_753_400_000)
        let laps = Self.realLaps.indices.map { index in
            SwimLap(
                id: index,
                startDate: start.addingTimeInterval(Self.realLaps[index].offset),
                duration: Self.realLaps[index].duration,
                distanceMeters: 50,
                strokeStyle: .freestyle
            )
        }
        return makeWorkout(start: start, laneLength: 50, laps: laps)
    }

    @Test func 실제_기록의_세트_구분이_피트니스와_같다() {
        let sets = realWorkout().sets

        #expect(sets.count == 6)
        #expect(sets.map(\.distanceText) == ["200m", "100m", "100m", "100m", "50m", "50m"])
    }

    @Test func 실제_기록의_휴식_시간이_피트니스와_일치한다() {
        let sets = realWorkout().sets

        // 피트니스 표시: 2:19 / 2:42 / 2:00 / 3:06 / 1:17 / (마지막 없음)
        #expect(sets.map(\.restText) == ["2:19", "2:43", "2:00", "3:07", "1:17", nil])
    }

    @Test func 세트_시간은_턴을_포함해_랩_합보다_길다() {
        let sets = realWorkout().sets

        // 세트2 = 랩 2개(61초 + 65초 = 2:06), 사이 턴 6초 → 2:12
        #expect(sets[1].durationText == "2:12")
        #expect(sets[1].paceText == "2:12/100m")

        // 세트5는 랩 1개라 턴이 없어 랩 시간 그대로
        #expect(sets[4].durationText == "0:57")
    }

    @Test func 마지막_세트는_휴식이_없다() {
        #expect(realWorkout().sets.last?.restDuration == nil)
    }

    @Test func 턴_정도의_짧은_공백은_세트를_나누지_않는다() {
        let start = Date(timeIntervalSince1970: 1_753_400_000)
        // 랩 사이 공백 5초 — 턴으로 본다
        let laps = [
            SwimLap(id: 0, startDate: start, duration: 60, distanceMeters: 50, strokeStyle: .freestyle),
            SwimLap(id: 1, startDate: start.addingTimeInterval(65), duration: 60, distanceMeters: 50, strokeStyle: .freestyle)
        ]
        let sets = makeWorkout(laneLength: 50, laps: laps).sets

        #expect(sets.count == 1)
        #expect(sets[0].distanceText == "100m")
    }

    @Test func 랩이_없으면_세트도_없다() {
        #expect(makeWorkout(laps: []).sets.isEmpty)
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
