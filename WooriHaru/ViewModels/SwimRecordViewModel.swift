import Foundation
import SwiftUI

@MainActor
@Observable
final class SwimRecordViewModel {
    private(set) var workouts: [SwimWorkout] = []
    private(set) var isLoading = false
    /// 최초 로딩이 끝났는지. 로딩 중 빈 화면이 잠깐 스치는 걸 막는 용도.
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let service: SwimWorkoutFetching
    private let limit: Int

    init(service: SwimWorkoutFetching = HealthKitService(), limit: Int = 100) {
        self.service = service
        self.limit = limit
    }

    var isHealthDataAvailable: Bool { service.isHealthDataAvailable }

    /// 권한 거부와 데이터 없음은 HealthKit이 구분해 주지 않아 같은 빈 상태로 다룬다.
    var showsEmptyState: Bool { hasLoaded && workouts.isEmpty && errorMessage == nil }

    // MARK: - Summary

    var totalCount: Int { workouts.count }

    var totalDistanceText: String? {
        let total = workouts.compactMap(\.distanceMeters).reduce(0, +)
        guard total > 0 else { return nil }
        if total >= 1000 { return String(format: "%.1fkm", total / 1000) }
        return "\(Int(total.rounded()))m"
    }

    var totalDurationText: String {
        Int(workouts.reduce(0) { $0 + $1.duration }).durationText
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await service.requestAuthorization()
            workouts = try await service.fetchSwimWorkouts(limit: limit)
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
        isLoading = false
    }
}
