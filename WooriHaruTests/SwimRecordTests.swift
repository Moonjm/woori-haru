import Foundation
import Testing
@testable import WooriHaru

// MARK: - Fake

private final class FakeSwimFetcher: SwimWorkoutFetching {
    var isHealthDataAvailable: Bool
    /// 최신순으로 정렬된 전체 기록. 커서·limit에 맞춰 잘라서 돌려준다.
    var workouts: [SwimWorkout]
    var errorToThrow: Error?
    private(set) var calls: [(limit: Int, cursor: Date?)] = []

    init(isHealthDataAvailable: Bool = true, workouts: [SwimWorkout] = [], errorToThrow: Error? = nil) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.workouts = workouts
        self.errorToThrow = errorToThrow
    }

    func requestAuthorization() async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func fetchSwimWorkouts(limit: Int, before: Date?) async throws -> SwimWorkoutPage {
        calls.append((limit, before))
        if let errorToThrow { throw errorToThrow }

        let candidates = before.map { cursor in
            workouts.filter { $0.startDate < cursor }
        } ?? workouts
        let page = Array(candidates.prefix(limit))

        // 실제 구현과 같이 경계 시각의 기록을 통째로 채워 무리를 완성한다.
        guard page.count == limit, let boundary = page.last?.startDate else {
            return SwimWorkoutPage(workouts: page, mayHaveMore: page.count == limit)
        }
        let tied = candidates.filter { $0.startDate == boundary }
        let known = Set(page.map(\.id))
        return SwimWorkoutPage(
            workouts: page + tied.filter { !known.contains($0.id) },
            mayHaveMore: true
        )
    }

    var effortScore: Double?

    func fetchEffortScore(workoutID: UUID) async throws -> Double? {
        if let errorToThrow { throw errorToThrow }
        return effortScore
    }

    var heartRate: SwimHeartRate?
    private(set) var heartRateCalls: [UUID] = []

    func fetchHeartRate(workoutID: UUID) async throws -> SwimHeartRate? {
        heartRateCalls.append(workoutID)
        if let errorToThrow { throw errorToThrow }
        return heartRate
    }
}

/// 재시도할 값어치가 있는 일반 오류. 미지원 기기와 구분하려고 따로 둔다.
private struct RetryableError: LocalizedError {
    var errorDescription: String? { "일시적인 오류입니다." }
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

    /// 잘못 시작해 바로 끝낸 기록. 카드에 채울 것이 「1분 미만」과 「-」뿐이다.
    @Test func 짧으면서_거리가_없으면_감출_기록이다() {
        #expect(makeWorkout(duration: 55, distance: nil).isEmptyRecord == true)
        #expect(makeWorkout(duration: 55, distance: 0).isEmptyRecord == true)
        #expect(makeWorkout(duration: 3, distance: nil).isEmptyRecord == true)
    }

    /// 짧아도 헤엄친 거리가 있으면 남긴다 — 50m 스프린트 한 판이 사라지면 안 된다.
    @Test func 짧아도_거리가_있으면_남긴다() {
        #expect(makeWorkout(duration: 40, distance: 50).isEmptyRecord == false)
    }

    /// 거리를 못 잡은 개방 수역 기록이 통째로 사라지면 안 된다. 시간이 판정을 막는다.
    @Test func 거리가_없어도_1분_이상이면_남긴다() {
        #expect(makeWorkout(duration: 90, distance: 0).isEmptyRecord == false)
        #expect(makeWorkout(duration: 1800, distance: nil).isEmptyRecord == false)
    }

    /// 경계는 「미만」이다 — 정확히 60초는 남긴다.
    @Test func 정확히_1분이면_남긴다() {
        #expect(makeWorkout(duration: 60, distance: 0).isEmptyRecord == false)
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
    @Test func 로딩_성공시_목록이_채워진다() async {
        let fetcher = FakeSwimFetcher(workouts: [
            makeWorkout(duration: 1800, distance: 1200),
            makeWorkout(duration: 1200, distance: 800)
        ])
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 30)

        await vm.load()

        #expect(vm.workouts.count == 2)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.showsEmptyState == false)
        // 첫 페이지는 커서 없이 요청한다
        #expect(fetcher.calls.count == 1)
        #expect(fetcher.calls[0].limit == 30)
        #expect(fetcher.calls[0].cursor == nil)
        // 한 페이지를 못 채웠으니 더 없다고 본다
        #expect(vm.canLoadMore == false)
    }

    @Test func 결과가_없으면_빈_상태를_보여준다() async {
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(workouts: []))

        #expect(vm.showsEmptyState == false) // 로딩 전에는 빈 상태를 띄우지 않는다
        await vm.load()

        #expect(vm.workouts.isEmpty)
        #expect(vm.showsEmptyState == true)
    }

    @Test func 실패시_에러메시지가_설정되고_빈_상태는_뜨지_않는다() async {
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(errorToThrow: RetryableError()))

        await vm.load()

        #expect(vm.errorMessage == "일시적인 오류입니다.")
        #expect(vm.showsEmptyState == false)
        #expect(vm.showsFailureState == true)
        #expect(vm.isLoading == false)
    }

    @Test func 알림을_닫아도_실패가_기록없음으로_바뀌지_않는다() async {
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(errorToThrow: RetryableError()))

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
        #expect(fetcher.calls[1].cursor == all[2].startDate)
        #expect(fetcher.calls[1].limit == 3)
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

    @Test func 시작_시각이_같은_기록이_페이지_경계에_걸려도_빠지지_않는다() async {
        // t0 / t1 세 건 / t2 / t3 — 경계(3건)가 t1 무리 한가운데를 자른다
        let base = Date(timeIntervalSince1970: 1_753_400_000)
        let t1 = base.addingTimeInterval(-100)
        let all = [
            makeWorkout(start: base),
            makeWorkout(start: t1),
            makeWorkout(start: t1),
            makeWorkout(start: t1),
            makeWorkout(start: base.addingTimeInterval(-200)),
            makeWorkout(start: base.addingTimeInterval(-300))
        ]
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        // 첫 페이지에서 경계에 걸린 t1 무리가 통째로 채워져 3건이 아니라 4건이 온다
        await vm.load()
        #expect(vm.workouts.count == 4)
        #expect(vm.workouts.filter { $0.startDate == t1 }.count == 3)

        await vm.loadMoreIfNeeded(currentItem: vm.workouts[3])

        #expect(vm.workouts.count == 6)
        #expect(Set(vm.workouts.map(\.id)) == Set(all.map(\.id)))
        // 무리가 완성돼 있으므로 다음 커서는 그 시각을 통째로 건너뛴다
        #expect(fetcher.calls[1].cursor == t1)
    }

    @Test func 같은_시각_기록만_있어도_진행이_멈추지_않는다() async {
        // 모든 기록의 시작 시각이 같은 극단적인 경우
        let sameTime = Date(timeIntervalSince1970: 1_753_400_000)
        let all = (0..<7).map { _ in makeWorkout(start: sameTime) }
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        // 무리를 통째로 채우므로 첫 페이지에서 7건이 다 온다
        #expect(vm.workouts.count == 7)

        var guardCount = 0
        while vm.canLoadMore && guardCount < 10 {
            await vm.loadMoreIfNeeded(currentItem: vm.workouts[vm.workouts.count - 1])
            guardCount += 1
        }

        #expect(vm.workouts.count == 7)
        #expect(vm.canLoadMore == false)
        #expect(guardCount == 1) // 같은 페이지를 무한히 다시 받지 않는다
    }

    // MARK: - 내역 없는 기록

    /// 최신순 `count`건을 하루 간격으로. `emptyAt`에 든 인덱스만 감출 기록으로 만든다.
    private func makeMixedPage(count: Int, emptyAt: Set<Int>) -> [SwimWorkout] {
        let newest = Date(timeIntervalSince1970: 1_753_400_000)
        return (0..<count).map { index in
            let start = newest.addingTimeInterval(TimeInterval(-index) * 86_400)
            return emptyAt.contains(index)
                ? makeWorkout(start: start, duration: 5, distance: nil)
                : makeWorkout(start: start, duration: 1800, distance: 1200)
        }
    }

    @Test func 내역_없는_기록은_목록에서_빠진다() async {
        let all = makeMixedPage(count: 4, emptyAt: [1, 2])
        let vm = SwimRecordViewModel(service: FakeSwimFetcher(workouts: all), pageSize: 30)

        await vm.load()

        #expect(vm.workouts.map(\.id) == [all[0].id, all[3].id])
    }

    /// 커서가 화면에 남은 마지막 기록에서 나오면, 감춘 구간을 다음 페이지가 다시 실어 온다.
    @Test func 커서는_감춘_기록까지_지나간다() async {
        // 3건짜리 페이지의 끝 두 건이 감출 기록이다
        let all = makeMixedPage(count: 6, emptyAt: [1, 2])
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        #expect(vm.workouts.map(\.id) == [all[0].id])

        await vm.loadMoreIfNeeded(currentItem: all[0])

        // 살아남은 all[0]이 아니라 필터 전 마지막인 all[2]가 커서다
        #expect(fetcher.calls.count == 2)
        #expect(fetcher.calls[1].cursor == all[2].startDate)
        #expect(vm.workouts.map(\.id) == [all[0].id, all[3].id, all[4].id, all[5].id])
    }

    /// 스크롤 도중에 갱신되는 커서도 마찬가지다 — 두 번째 페이지 꼬리가 감춘 기록이면
    /// 세 번째 요청이 그 구간을 다시 실어 온다.
    @Test func 스크롤_중에도_커서가_감춘_기록까지_지나간다() async {
        // 두 번째 페이지(3·4·5)의 꼬리 두 건이 감출 기록이다
        let all = makeMixedPage(count: 9, emptyAt: [4, 5])
        let fetcher = FakeSwimFetcher(workouts: all)
        let vm = SwimRecordViewModel(service: fetcher, pageSize: 3)

        await vm.load()
        await vm.loadMoreIfNeeded(currentItem: all[2])
        #expect(vm.workouts.map(\.id) == [all[0].id, all[1].id, all[2].id, all[3].id])

        await vm.loadMoreIfNeeded(currentItem: all[3])

        // 살아남은 all[3]이 아니라 필터 전 마지막인 all[5]가 커서다
        #expect(fetcher.calls.count == 3)
        #expect(fetcher.calls.last?.cursor == all[5].startDate)
        #expect(vm.workouts.map(\.id) == [all[0].id, all[1].id, all[2].id,
                                          all[3].id, all[6].id, all[7].id, all[8].id])
    }

    @Test func 건강데이터_미지원이면_실패가_아니라_빈_상태다() async {
        let fetcher = FakeSwimFetcher(
            isHealthDataAvailable: false,
            errorToThrow: SwimWorkoutError.healthDataUnavailable
        )
        let vm = SwimRecordViewModel(service: fetcher)

        await vm.load()

        // 재시도해도 달라지지 않으므로 "다시 시도" 대신 전용 안내로 보낸다
        #expect(vm.showsFailureState == false)
        #expect(vm.showsEmptyState == true)
        #expect(vm.errorMessage == nil)
        #expect(vm.isHealthDataAvailable == false)
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

/// 심박수는 워크아웃 집계 통계에 없을 수 있어 상세 화면이 따로 읽어 메운다.
/// **운동 강도와는 무관하다** — 강도가 없어도 심박수만 있으면 보여야 한다.
@MainActor
struct SwimHeartRateTests {
    @Test func bpm은_반올림해_정수로_보여준다() {
        #expect(SwimWorkout.bpmText(132.4) == "132bpm")
        #expect(SwimWorkout.bpmText(132.5) == "133bpm")
    }

    /// 0은 「진짜 0」이 아니라 「없음」이다 — 심박이 0인 운동은 없다.
    @Test func bpm이_없거나_0이면_감춘다() {
        #expect(SwimWorkout.bpmText(nil) == nil)
        #expect(SwimWorkout.bpmText(0) == nil)
    }

    /// 목록 매핑이 채워 온 값이 있으면 그게 이긴다 — 따로 읽을 이유가 없다.
    @Test func 워크아웃에_이미_있으면_그_값을_쓴다() {
        let workout = makeWorkout(averageHeartRate: 140, maxHeartRate: 170)
        let fallback = SwimHeartRate(averageBpm: 99, maxBpm: 111)

        let texts = workout.heartRateTexts(fallback: fallback)

        #expect(texts.average == "140bpm")
        #expect(texts.maximum == "170bpm")
    }

    /// **이 자리가 실제로 나던 문제다** — `HKWorkout.statistics(for:)`가 심박수를 안 담고
    /// 오면 목록 매핑에서 nil이 되고, 상세 화면이 별도 질의로 메운다.
    @Test func 워크아웃에_없으면_따로_읽은_값으로_메운다() {
        let workout = makeWorkout(averageHeartRate: nil, maxHeartRate: nil)
        let fallback = SwimHeartRate(averageBpm: 138, maxBpm: 165)

        let texts = workout.heartRateTexts(fallback: fallback)

        #expect(texts.average == "138bpm")
        #expect(texts.maximum == "165bpm")
    }

    /// 둘 다 없으면 감춘다 — 빈 칸을 그리지 않는다.
    @Test func 양쪽_다_없으면_아무것도_보여주지_않는다() {
        let texts = makeWorkout(averageHeartRate: nil, maxHeartRate: nil)
            .heartRateTexts(fallback: nil)

        #expect(texts.average == nil)
        #expect(texts.maximum == nil)
    }

    /// 평균만 있고 최대가 없는 기록도 있다 — 있는 쪽만 보여준다.
    @Test func 한쪽만_있으면_그쪽만_보여준다() {
        let texts = makeWorkout(averageHeartRate: nil, maxHeartRate: nil)
            .heartRateTexts(fallback: SwimHeartRate(averageBpm: 138, maxBpm: nil))

        #expect(texts.average == "138bpm")
        #expect(texts.maximum == nil)
    }

    @Test func 둘_다_비었는지_알린다() {
        #expect(SwimHeartRate(averageBpm: nil, maxBpm: nil).isEmpty)
        #expect(!SwimHeartRate(averageBpm: 138, maxBpm: nil).isEmpty)
    }
}
