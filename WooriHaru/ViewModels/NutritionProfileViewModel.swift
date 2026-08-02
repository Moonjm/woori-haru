import Foundation

/// 키·몸무게·활동량·목표 입력. **목표치는 서버가 계산해 돌려준다** — 앱은 표시만 한다.
/// 성별·생년월일은 기존 `User` 값을 쓰므로 여기서 입력하지 않는다.
@MainActor
@Observable
final class NutritionProfileViewModel {
    private(set) var profile: NutritionProfile?
    var heightText = ""
    var weightText = ""
    var activityLevel: ActivityLevel = .moderate
    var goal: DietGoal = .maintain

    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var didSave = false
    /// 서버가 성별·생년월일 결측으로 거절했을 때. 「내 정보」로 보내야 한다.
    private(set) var needsUserInfo = false
    var errorMessage: String?

    private let service: any DietServing

    init(service: any DietServing = DietService()) {
        self.service = service
    }

    /// **서버가 받아 주는 범위 안일 때만 저장을 연다.** 밖의 값을 보내면 400이 돌아오는데,
    /// 그때는 무엇이 잘못됐는지 알 길이 없다 — 여기서 막고 아래 힌트로 알려 준다.
    var canSave: Bool {
        guard let height = Double(heightText), let weight = Double(weightText) else { return false }
        return NutritionProfileLimits.heightCm.contains(height)
            && NutritionProfileLimits.weightKg.contains(weight)
            && !isSaving
    }

    /// 키가 범위 밖일 때 띄울 안내. **빈 칸에는 띄우지 않는다** — 아직 입력을 시작하지도
    /// 않은 자리에 경고를 다는 것은 재촉일 뿐이다(저장은 `canSave`가 따로 막는다).
    var heightRangeHint: String? {
        rangeHint(heightText, NutritionProfileLimits.heightCm, NutritionProfileLimits.heightHint)
    }

    var weightRangeHint: String? {
        rangeHint(weightText, NutritionProfileLimits.weightKg, NutritionProfileLimits.weightHint)
    }

    private func rangeHint(_ text: String, _ range: ClosedRange<Double>, _ hint: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let value = Double(text), range.contains(value) else { return hint }
        return nil
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await service.fetchProfile()
            profile = loaded
            if let loaded {
                heightText = loaded.heightCm.trimmedText
                weightText = loaded.weightKg.trimmedText
                activityLevel = loaded.activityLevel
                goal = loaded.goal
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        guard let height = Double(heightText), let weight = Double(weightText),
              height > 0, weight > 0, !isSaving else { return }
        isSaving = true
        didSave = false
        needsUserInfo = false
        defer { isSaving = false }

        do {
            try await service.saveProfile(NutritionProfileRequest(
                heightCm: height, weightKg: weight, activityLevel: activityLevel, goal: goal
            ))
            // 목표는 서버가 계산하므로 저장 뒤 다시 읽어야 화면에 새 목표가 보인다.
            profile = try await service.fetchProfile()
            didSave = true
        } catch is CancellationError {
            return
        } catch {
            // 성별·생년월일 중 하나라도 없으면 BMR을 계산할 수 없어 서버가 거절한다.
            if error.dietErrorCode == .invalidRequest {
                needsUserInfo = true
                errorMessage = "성별과 생년월일이 있어야 목표를 계산할 수 있습니다. 「내 정보」에서 먼저 입력해 주세요."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
