import Foundation
import HealthKit

enum SwimWorkoutError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable: "이 기기에서는 건강 데이터를 사용할 수 없습니다."
        }
    }
}

/// 페이지 하나. 마지막 기록과 시작 시각이 같은 기록은 모두 포함된 상태로 온다.
struct SwimWorkoutPage {
    let workouts: [SwimWorkout]
    /// 조회가 limit을 채웠는지. 다음 페이지가 더 있을 수 있다는 뜻.
    let mayHaveMore: Bool

    static let empty = SwimWorkoutPage(workouts: [], mayHaveMore: false)
}

/// 수영 기록 조회 소스. 테스트에서 대체할 수 있도록 프로토콜로 분리한다.
protocol SwimWorkoutFetching {
    /// 기기가 건강 데이터를 지원하는지 (iPad 등 미지원 기기 대비)
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization() async throws
    /// 수영 워크아웃을 최신순으로 `limit`건쯤 반환. `before`를 주면 그 시각보다
    /// **먼저 시작한** 기록만 대상으로 한다.
    ///
    /// limit이 시작 시각이 같은 무리 한가운데를 자르면, 그 시각의 기록을 전부 채워
    /// 넣어 무리가 쪼개지지 않게 한다. 그래서 결과가 limit보다 길 수 있다.
    func fetchSwimWorkouts(limit: Int, before: Date?) async throws -> SwimWorkoutPage
    /// 운동 강도(1~10). 목록 로딩을 무겁게 하지 않으려고 상세 화면에서 따로 조회한다.
    func fetchEffortScore(workoutID: UUID) async throws -> Double?
}

/// 건강 앱에 동기화된 애플워치 수영 기록을 읽어온다. 읽기 전용 — 쓰기 권한은 요청하지 않는다.
final class HealthKitService: SwimWorkoutFetching {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.swimmingStrokeCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.workoutEffortScore),
            HKQuantityType(.estimatedWorkoutEffortScore)
        ]
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw SwimWorkoutError.healthDataUnavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchSwimWorkouts(limit: Int, before: Date?) async throws -> SwimWorkoutPage {
        guard isHealthDataAvailable else { throw SwimWorkoutError.healthDataUnavailable }

        // 기간 상한을 두지 않아 건강 앱에 남아 있는 전체 이력이 대상이 된다.
        var predicates = [HKQuery.predicateForWorkouts(with: .swimming)]
        if let before {
            predicates.append(NSPredicate(
                format: "%K < %@", HKPredicateKeyPathStartDate, before as NSDate
            ))
        }
        let page = try await workouts(
            matching: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
            limit: limit
        )

        // HealthKit은 시작 시각이 같은 샘플들의 순서를 보장하지 않는다. 경계가 그 무리
        // 한가운데를 자르면 요청할 때마다 다른 일부가 와서, 기록이 빠지거나 이미 본
        // 것만 반복해 받을 수 있다. 경계 시각의 기록을 통째로 채워 무리를 완성해 두면
        // 다음 커서가 그 시각을 통째로 건너뛰므로 순서에 기댈 일이 없어진다.
        guard page.count == limit, let boundary = page.last?.startDate else {
            return SwimWorkoutPage(
                workouts: page.map(Self.makeSwimWorkout),
                mayHaveMore: page.count == limit
            )
        }

        let tied = try await workouts(
            matching: NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForWorkouts(with: .swimming),
                NSPredicate(format: "%K == %@", HKPredicateKeyPathStartDate, boundary as NSDate)
            ]),
            limit: HKObjectQueryNoLimit
        )

        var merged: [UUID: HKWorkout] = [:]
        for workout in page + tied { merged[workout.uuid] = workout }
        return SwimWorkoutPage(
            workouts: merged.values
                .sorted { $0.startDate > $1.startDate }
                .map(Self.makeSwimWorkout),
            mayHaveMore: true
        )
    }

    private func workouts(matching predicate: NSPredicate, limit: Int) async throws -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let found = try await samples(
            type: .workoutType(),
            predicate: predicate,
            limit: limit,
            sortDescriptors: [sort]
        )
        return found.compactMap { $0 as? HKWorkout }
    }

    func fetchEffortScore(workoutID: UUID) async throws -> Double? {
        guard isHealthDataAvailable else { throw SwimWorkoutError.healthDataUnavailable }

        let found = try await samples(
            type: .workoutType(),
            predicate: HKQuery.predicateForObject(with: workoutID),
            limit: 1
        )
        guard let workout = found.first as? HKWorkout else { return nil }

        // 사용자가 직접 매긴 강도가 있으면 그걸 쓰고, 없으면 워치 추정값으로 넘어간다.
        let related = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
        for identifier in [HKQuantityTypeIdentifier.workoutEffortScore, .estimatedWorkoutEffortScore] {
            let scores = try await samples(
                type: HKQuantityType(identifier),
                predicate: related,
                limit: 1
            )
            if let quantity = (scores.first as? HKQuantitySample)?.quantity {
                return quantity.doubleValue(for: .appleEffortScore())
            }
        }
        return nil
    }

    // MARK: - Query

    private func samples(
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int,
        sortDescriptors: [NSSortDescriptor]? = nil
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Mapping

    private static func makeSwimWorkout(_ workout: HKWorkout) -> SwimWorkout {
        let lapLength = laneLength(of: workout)
        return SwimWorkout(
            id: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            distanceMeters: sum(workout, .distanceSwimming, unit: .meter()),
            activeEnergyKcal: sum(workout, .activeEnergyBurned, unit: .kilocalorie()),
            strokeCount: sum(workout, .swimmingStrokeCount, unit: .count()).map { Int($0.rounded()) },
            location: location(of: workout),
            averageHeartRate: heartRate(workout) { $0.averageQuantity() },
            maxHeartRate: heartRate(workout) { $0.maximumQuantity() },
            laneLengthMeters: lapLength,
            laps: laps(of: workout, lapLength: lapLength)
        )
    }

    private static func heartRate(
        _ workout: HKWorkout,
        _ pick: (HKStatistics) -> HKQuantity?
    ) -> Double? {
        guard let stats = workout.statistics(for: HKQuantityType(.heartRate)),
              let quantity = pick(stats) else { return nil }
        return quantity.doubleValue(for: .count().unitDivided(by: .minute()))
    }

    /// 수영장 기록의 lap 이벤트를 SwimLap으로 옮긴다.
    /// 레인 길이를 모르면 구간 거리를 계산할 수 없어 랩을 만들지 않는다.
    private static func laps(of workout: HKWorkout, lapLength: Double?) -> [SwimLap] {
        guard let lapLength else { return [] }
        let events = (workout.workoutEvents ?? [])
            .filter { $0.type == .lap }
            .map { event in
                SwimLap.Event(
                    start: event.dateInterval.start,
                    duration: event.dateInterval.duration,
                    stroke: strokeStyle(of: event)
                )
            }
        return SwimLap.build(from: events, lapLength: lapLength)
    }

    private static func strokeStyle(of event: HKWorkoutEvent) -> SwimStrokeStyle {
        guard let raw = event.metadata?[HKMetadataKeySwimmingStrokeStyle] as? NSNumber,
              let style = SwimStrokeStyle(rawValue: raw.intValue) else {
            return .unknown
        }
        return style
    }

    /// iOS 18에서 `totalDistance`·`totalEnergyBurned`가 deprecated 되어 statistics로 합계를 읽는다.
    private static func sum(
        _ workout: HKWorkout,
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) -> Double? {
        workout.statistics(for: HKQuantityType(identifier))?
            .sumQuantity()?
            .doubleValue(for: unit)
    }

    private static func location(of workout: HKWorkout) -> SwimWorkout.Location {
        guard let raw = workout.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber,
              let type = HKWorkoutSwimmingLocationType(rawValue: raw.intValue) else {
            return .unknown
        }
        switch type {
        case .pool: return .pool
        case .openWater: return .openWater
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    private static func laneLength(of workout: HKWorkout) -> Double? {
        (workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity)?.doubleValue(for: .meter())
    }
}
