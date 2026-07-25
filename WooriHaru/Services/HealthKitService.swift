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
    /// 전 기간의 수영 워크아웃을 최신순으로 최대 `limit`건 반환
    func fetchSwimWorkouts(limit: Int) async throws -> [SwimWorkout]
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
            HKQuantityType(.swimmingStrokeCount)
        ]
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw SwimWorkoutError.healthDataUnavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchSwimWorkouts(limit: Int) async throws -> [SwimWorkout] {
        guard isHealthDataAvailable else { throw SwimWorkoutError.healthDataUnavailable }

        // predicate에 기간을 두지 않아 건강 앱에 남아 있는 전체 이력을 최신순으로 가져온다.
        let predicate = HKQuery.predicateForWorkouts(with: .swimming)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }

        return samples.compactMap { $0 as? HKWorkout }.map(Self.makeSwimWorkout)
    }

    // MARK: - Mapping

    private static func makeSwimWorkout(_ workout: HKWorkout) -> SwimWorkout {
        SwimWorkout(
            id: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            distanceMeters: sum(workout, .distanceSwimming, unit: .meter()),
            activeEnergyKcal: sum(workout, .activeEnergyBurned, unit: .kilocalorie()),
            strokeCount: sum(workout, .swimmingStrokeCount, unit: .count()).map { Int($0.rounded()) },
            location: location(of: workout),
            laneLengthMeters: laneLength(of: workout)
        )
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
