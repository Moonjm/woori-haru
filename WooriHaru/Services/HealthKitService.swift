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

/// 수영 기록 조회 소스. 테스트에서 대체할 수 있도록 프로토콜로 분리한다.
protocol SwimWorkoutFetching {
    /// 기기가 건강 데이터를 지원하는지 (iPad 등 미지원 기기 대비)
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization() async throws
    /// 수영 워크아웃을 최신순으로 최대 `limit`건 반환.
    ///
    /// `startingAtOrBefore`를 주면 그 시각 **이하**에 시작한 기록만 가져온다.
    /// 경계를 포함하는 이유는, 시작 시각이 같은 기록이 페이지 경계에 걸렸을 때
    /// 뒤쪽 기록이 통째로 빠지는 걸 막기 위해서다. 이미 본 기록은 호출 쪽에서 거른다.
    func fetchSwimWorkouts(limit: Int, startingAtOrBefore: Date?) async throws -> [SwimWorkout]
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

    func fetchSwimWorkouts(limit: Int, startingAtOrBefore: Date?) async throws -> [SwimWorkout] {
        guard isHealthDataAvailable else { throw SwimWorkoutError.healthDataUnavailable }

        // 기간 상한을 두지 않아 건강 앱에 남아 있는 전체 이력이 대상이 된다.
        // 커서가 있으면 시작 시각이 그 이하인 기록만 남겨 다음 페이지를 만든다.
        var predicates = [HKQuery.predicateForWorkouts(with: .swimming)]
        if let startingAtOrBefore {
            predicates.append(NSPredicate(
                format: "%K <= %@", HKPredicateKeyPathStartDate, startingAtOrBefore as NSDate
            ))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let found = try await samples(
            type: .workoutType(),
            predicate: predicate,
            limit: limit,
            sortDescriptors: [sort]
        )

        return found.compactMap { $0 as? HKWorkout }.map(Self.makeSwimWorkout)
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
