import Foundation
import Observation

struct FrequentCar: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var nickname: String
    var carNo: String

    init(id: UUID = UUID(), nickname: String, carNo: String) {
        self.id = id
        self.nickname = nickname
        self.carNo = carNo
    }
}

/// 자주 등록하는 차량번호를 **이 기기에만** 담아 둔다.
///
/// **서버로 보내지 않는다.** 방문차량 사이트에 그럴 자리가 없고, 우리 서버에 올리면
/// 남의 차량번호를 우리가 보관하는 일이 된다. 화면에도 그 사실을 적어 둔다.
@MainActor @Observable
final class FrequentCarStore {
    static let shared = FrequentCarStore()

    private let defaults: UserDefaults
    private let key = "visitorCar.frequentCars"

    private(set) var cars: [FrequentCar] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FrequentCar].self, from: data) {
            cars = decoded
        }
    }

    /// - Returns: 문제가 있으면 사용자에게 보여줄 문구, 없으면 `nil`.
    @discardableResult
    func add(nickname: String, carNo: String) -> String? {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCarNo = carNo.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedNickname.isEmpty { return "별칭을 입력해 주세요." }
        // **등록 화면과 같은 규칙을 쓴다** — 저장해 놓고 등록할 때 튕기면 늦다.
        if let error = VisitorCarValidation.carNoError(trimmedCarNo) { return error }
        if cars.contains(where: { $0.carNo == trimmedCarNo }) { return "이미 저장된 차량번호입니다." }

        cars.append(FrequentCar(nickname: trimmedNickname, carNo: trimmedCarNo))
        persist()
        return nil
    }

    func remove(id: UUID) {
        cars.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cars) else { return }
        defaults.set(data, forKey: key)
    }
}
