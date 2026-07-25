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
    /// 마지막 조회가 실패했는지. 알림을 닫아도 남아 있어야 "기록 없음"으로 오인되지 않는다.
    private(set) var loadFailed = false
    var errorMessage: String?

    /// 진행 중인 조회를 무효화하는 표식. 새로고침이 끼어들면 값을 올려
    /// 뒤늦게 돌아온 이전 결과를 버린다.
    private var generation = 0

    /// 상세 화면이 강도를 따로 조회할 수 있도록 노출한다.
    let service: SwimWorkoutFetching
    private let pageSize: Int

    init(service: SwimWorkoutFetching = HealthKitService(), pageSize: Int = 30) {
        self.service = service
        self.pageSize = pageSize
    }

    var isHealthDataAvailable: Bool { service.isHealthDataAvailable }

    /// 권한 거부와 데이터 없음은 HealthKit이 구분해 주지 않아 같은 빈 상태로 다룬다.
    /// 조회가 실패한 경우는 여기서 빼야 알림을 닫았을 때 "기록 없음"으로 잘못 보이지 않는다.
    var showsEmptyState: Bool { hasLoaded && workouts.isEmpty && !loadFailed }

    /// 한 건도 못 불러온 채 실패한 상태. 다시 시도 안내를 띄운다.
    var showsFailureState: Bool { loadFailed && workouts.isEmpty }

    // MARK: - Load

    /// 화면 진입용. 상세에서 돌아올 때마다 다시 읽으면 목록이 첫 페이지로 줄어들어
    /// 스크롤 위치가 콘텐츠 밖을 가리키게 되므로, 최초 한 번만 읽는다.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// 처음부터 다시 읽는다. 당겨서 새로고침에 쓴다.
    func load() async {
        guard !isLoading else { return }
        generation += 1
        let token = generation
        isLoading = true
        // 진행 중이던 페이지 로딩은 토큰이 어긋나 결과가 버려진다.
        isLoadingMore = false
        errorMessage = nil
        loadFailed = false

        do {
            try await service.requestAuthorization()
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: nil)
            guard token == generation else { return }
            workouts = page.workouts
            canLoadMore = page.mayHaveMore
        } catch SwimWorkoutError.healthDataUnavailable {
            // 재시도해도 달라지지 않는 조건이라 실패로 두지 않는다.
            // 빈 상태로 보내야 "건강 데이터를 쓸 수 없는 기기입니다" 안내가 뜬다.
            guard token == generation else { return }
            workouts = []
            canLoadMore = false
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            loadFailed = true
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

        // 서비스가 경계 시각의 기록을 통째로 채워 주므로, 이미 읽은 마지막 시각은
        // 배제하고 넘어가면 된다. 동점 무리가 쪼개질 일이 없어 순서에 기대지 않는다.
        let token = generation
        isLoadingMore = true
        do {
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: cursor)
            // 기다리는 사이 새로고침이 끼어들었으면 이 결과는 이미 낡았다.
            guard token == generation else { return }
            let known = Set(workouts.map(\.id))
            workouts.append(contentsOf: page.workouts.filter { !known.contains($0.id) })
            canLoadMore = page.mayHaveMore
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
        guard token == generation else { return }
        isLoadingMore = false
    }
}
