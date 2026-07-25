import Foundation
import Testing
@testable import WooriHaru

// MARK: - Fake

private final class FakeSwimFetcher: SwimWorkoutFetching {
    var isHealthDataAvailable: Bool
    /// 최신순으로 정렬된 전체 기록. 커서·limit에 맞춰 잘라서 돌려준다.
    var workouts: [SwimWorkout]
    var errorToThrow: Error?
    private(set) var calls: [(limit: Int, before: Date?)] = []

    init(isHealthDataAvailable: Bool = true, workouts: [SwimWorkout] = [], errorToThrow: Error? = nil) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.workouts = workouts
        self.errorToThrow = errorToThrow
    }

    func requestAuthorization() async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func fetchSwimWorkouts(limit: Int, before: Date?) async throws -> [SwimWorkout] {
        calls.append((limit, before))
        if let errorToThrow { throw errorToThrow }
        let candidates = before.map { cursor in
            workouts.filter { $0.startDate < cursor }
        } ?? workouts
        return Array(candidates.prefix(limit))
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

// MARK: - Lap Building

struct SwimLapBuildTests {
    private let start = Date(timeIntervalSince1970: 1_753_400_000)

    private func event(offset: TimeInterval, duration: TimeInterval) -> SwimLap.Event {
        SwimLap.Event(
            start: start.addingTimeInterval(offset),
            duration: duration,
            stroke: .freestyle
        )
    }

    @Test func 정상_랩은_그대로_만들어진다() {
        let laps = SwimLap.build(
            from: [event(offset: 0, duration: 60), event(offset: 65, duration: 62)],
            lapLength: 50
        )

        #expect(laps.count == 2)
        #expect(laps[0].duration == 60)
        #expect(laps[1].distanceMeters == 50)
    }

    /// 길이 0인 마커를 다음 마커까지로 메우면 랩 사이 공백이 0이 되어
    /// 세트가 전부 하나로 뭉개진다. 그래서 아예 만들지 않는다.
    @Test func 길이_0인_마커가_섞이면_랩을_만들지_않는다() {
        let laps = SwimLap.build(
            from: [event(offset: 0, duration: 60), event(offset: 200, duration: 0)],
            lapLength: 50
        )

        #expect(laps.isEmpty)
    }

    @Test func 레인_길이를_모르면_랩을_만들지_않는다() {
        #expect(SwimLap.build(from: [event(offset: 0, duration: 60)], lapLength: 0).isEmpty)
    }

    @Test func 이벤트가_없으면_빈_배열() {
        #expect(SwimLap.build(from: [], lapLength: 50).isEmpty)
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
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 30)

        await vm.load()

        #expect(vm.workouts.count == 2)
        #expect(vm.totalCount == 2)
        #expect(vm.totalDistanceText == "2.0km")
        #expect(vm.totalDurationText == "50분")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.showsEmptyState == false)
        // 첫 페이지는 커서 없이 요청한다
        #expect(fetcher.calls.count == 1)
        #expect(fetcher.calls[0].limit == 30)
        #expect(fetcher.calls[0].before == nil)
        // 한 페이지를 못 채웠으니 더 없다고 본다
        #expect(vm.canLoadMore == false)
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
        #expect(vm.showsFailureState == true)
        #expect(vm.isLoading == false)
    }

    @Test func 알림을_닫아도_실패가_기록없음으로_바뀌지_않는다() async {
        let vm = SwimRecordViewModel(
            service: FakeSwimFetcher(errorToThrow: SwimWorkoutError.healthDataUnavailable)
        )

        await vm.load()
        vm.errorMessage = nil // 사용자가 알림을 닫은 상황

        #expect(vm.showsEmptyState == false)
        #expect(vm.showsFailureState == true)
    }

    @Test func 재진입해도_목록을_다시_읽지_않는다() async {
        let fetcher = FakeSwimFetcher(workouts: makePage(count: 10))
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.loadIfNeeded()
        await vm.loadMoreIfNeeded(currentItem: vm.workouts[2])
        #expect(vm.workouts.count == 6)

        // 상세에서 돌아와 화면이 다시 나타난 상황
        await vm.loadIfNeeded()

        #expect(vm.workouts.count == 6) // 첫 페이지로 줄어들지 않는다
        #expect(fetcher.calls.count == 2)
    }

    // MARK: - Paging

    /// 최신순으로 `count`건. 하루 간격이라 커서로 자르기 쉽다.
    private func makePage(count: Int) -> [SwimWorkout] {
        let newest = Date(timeIntervalSince1970: 1_753_400_000)
        return (0..<count).map { index in
            makeWorkout(start: newest.addingTimeInterval(TimeInterval(-index) * 86_400))
        }
    }

    @Test func 첫_페이지가_꽉_차면_더_있다고_본다() async {
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(workouts: makePage(count: 10)), pageSize: 3)

        await vm.load()

        #expect(vm.workouts.count == 3)
        #expect(vm.canLoadMore == true)
    }

    @Test func 마지막_항목에_닿으면_다음_페이지를_잇는다() async {
        let all = makePage(count: 10)
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        await vm.loadMoreIfNeeded(currentItem: vm.workouts[2])

        #expect(vm.workouts.count == 6)
        #expect(vm.workouts.map(\.id) == all.prefix(6).map(\.id))
        // 두 번째 요청은 직전 마지막 기록의 시작 시각을 커서로 쓴다
        #expect(fetcher.calls.count == 2)
        #expect(fetcher.calls[1].before == all[2].startDate)
    }

    @Test func 마지막_항목이_아니면_불러오지_않는다() async {
        let fetcher = FakeSwimFetcher(workouts: makePage(count: 10))
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        await vm.loadMoreIfNeeded(currentItem: vm.workouts[0])

        #expect(vm.workouts.count == 3)
        #expect(fetcher.calls.count == 1)
    }

    @Test func 끝까지_읽으면_더_요청하지_않는다() async {
        let fetcher = FakeSwimFetcher(workouts: makePage(count: 5))
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        await vm.loadMoreIfNeeded(currentItem: vm.workouts[2])

        #expect(vm.workouts.count == 5)
        #expect(vm.canLoadMore == false)

        // 더 없다고 판단한 뒤에는 호출 자체를 하지 않는다
        await vm.loadMoreIfNeeded(currentItem: vm.workouts[4])
        #expect(fetcher.calls.count == 2)
    }

    @Test func 새로고침하면_처음부터_다시_읽는다() async {
        let fetcher = FakeSwimFetcher(workouts: makePage(count: 10))
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        await vm.loadMoreIfNeeded(currentItem: vm.workouts[2])
        #expect(vm.workouts.count == 6)

        await vm.load()

        #expect(vm.workouts.count == 3)
        #expect(vm.canLoadMore == true)
    }

    @Test func 건강데이터_미지원_기기_여부를_그대로_전달한다() {
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(isHealthDataAvailable: false))
        #expect(vm.isHealthDataAvailable == false)
    }
}
