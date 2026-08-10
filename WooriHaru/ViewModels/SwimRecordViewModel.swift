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

    /// 다음 페이지의 경계. **필터 전** 마지막 기록의 시작 시각이다 — 감춘 기록에서
    /// 커서를 다시 잡으면 그 구간을 다음 페이지가 통째로 다시 실어 온다.
    private var nextCursor: Date?

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
            // 처음부터 다시 읽으므로 커서를 비운다. `workouts`는 새 페이지가 올 때까지
            // 그대로 둔다 — 여기서 비우면 당겨서 새로고침 중에 목록이 한 번 사라진다.
            nextCursor = nil
            canLoadMore = true
            let fresh = try await fetchVisiblePages(token: token, excluding: [])
            guard token == generation else { return }
            workouts = fresh
        } catch SwimWorkoutError.healthDataUnavailable {
            // 재시도해도 달라지지 않는 조건이라 실패로 두지 않는다.
            // 빈 상태로 보내야 "건강 데이터를 쓸 수 없는 기기입니다" 안내가 뜬다.
            guard token == generation else { return }
            workouts = []
            nextCursor = nil
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
        // 첫 로드가 끝나야 커서가 생긴다 — 그 전에는 이어읽기를 하지 않는다.
        guard nextCursor != nil else { return }

        let token = generation
        isLoadingMore = true
        do {
            let fresh = try await fetchVisiblePages(
                token: token, excluding: Set(workouts.map(\.id))
            )
            // 기다리는 사이 새로고침이 끼어들었으면 이 결과는 이미 낡았다.
            guard token == generation else { return }
            workouts.append(contentsOf: fresh)
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
        guard token == generation else { return }
        isLoadingMore = false
    }

    /// `nextCursor`부터 페이지를 읽어 **보여줄 기록만** 모아 돌려준다. 커서와
    /// `canLoadMore`는 여기서 갱신한다.
    ///
    /// **한 건이라도 건질 때까지 이어 읽는 것이 요점이다.** 한 페이지가 통째로 걸러지면
    /// 목록에 새 셀이 안 생겨 다음 페이지를 부를 `.task`가 영영 안 뜬다. 반복 상한을
    /// 두지 않는 이유도 같다 — 상한에 걸려 멈춰도 목록이 안 늘어난 채라 같은 교착이 된다.
    /// 대신 매 회차 토큰을 확인해 새로고침이 끼어들면 그 자리에서 멈춘다.
    private func fetchVisiblePages(
        token: Int, excluding known: Set<UUID>
    ) async throws -> [SwimWorkout] {
        var seen = known
        var collected: [SwimWorkout] = []

        while true {
            let page = try await service.fetchSwimWorkouts(limit: pageSize, before: nextCursor)
            guard token == generation else { return collected }

            guard let boundary = page.workouts.last?.startDate,
                  nextCursor.map({ boundary < $0 }) ?? true else {
                // 빈 페이지거나 커서가 안 움직인 페이지는 더 읽을 것이 없다는 뜻이다.
                // 커서가 제자리면 mayHaveMore를 믿고 계속 돌 때 같은 요청을 무한히 반복한다.
                canLoadMore = false
                return collected
            }
            // 서비스가 경계 시각의 기록을 통째로 채워 주므로, 이미 읽은 마지막 시각은
            // 배제하고 넘어가면 된다. 동점 무리가 쪼개질 일이 없어 순서에 기대지 않는다.
            nextCursor = boundary
            canLoadMore = page.mayHaveMore

            for workout in page.workouts where seen.insert(workout.id).inserted {
                if !workout.isEmptyRecord { collected.append(workout) }
            }

            if !collected.isEmpty || !canLoadMore { return collected }
        }
    }
}
