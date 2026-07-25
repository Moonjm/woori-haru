import Foundation
import SwiftUI

@MainActor
@Observable
final class SwimRecordViewModel {
    private(set) var workouts: [SwimWorkout] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    /// 최초 로딩이 끝났는지. 로딩 중 빈 화면이 잠깐 스치는 걸 막는 용도.
    private(set) var hasLoaded = false
    /// 마지막 페이지가 꽉 차서 왔으면 더 있을 수 있다고 본다.
    private(set) var canLoadMore = true
    var errorMessage: String?

    /// 상세 화면이 강도를 따로 조회할 수 있도록 노출한다.
    let service: SwimWorkoutFetching
    private let pageSize: Int

    init(service: SwimWorkoutFetching = HealthKitService(), pageSize: Int = 30) {
        self.service = service
        self.pageSize = pageSize
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

    /// 처음부터 다시 읽는다. 화면 진입과 당겨서 새로고침에 쓴다.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await service.requestAuthorization()
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: nil)
            workouts = page
            canLoadMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
        hasLoaded = true
        isLoading = false
    }

    /// 목록 끝에 도달했을 때 다음 페이지를 잇는다.
    func loadMoreIfNeeded(currentItem: SwimWorkout) async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard currentItem.id == workouts.last?.id else { return }
        guard let cursor = workouts.last?.startDate else { return }

        isLoadingMore = true
        do {
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: cursor)
            // 커서와 시작 시각이 같은 기록이 끼어들어도 중복으로 쌓이지 않게 거른다.
            let known = Set(workouts.map(\.id))
            workouts.append(contentsOf: page.filter { !known.contains($0.id) })
            canLoadMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
        isLoadingMore = false
    }
}
