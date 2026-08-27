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
///
/// **`UserDefaults`가 아니라 Application Support의 JSON 파일에 담고, 백업에서 뺀다.**
/// `UserDefaults.standard`는 iCloud/iTunes 백업에 포함돼서 "기기를 바꾸면 사라진다"는
/// 설정 화면 문구가 거짓이 됐다 — 여기 담기는 건 방문객·배달원 등 **남의** 차량번호라
/// 백업을 타고 새 기기로 옮겨 갈 이유가 없다. 같은 이유로 `VisitorCarCredentialStore`도
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`를 쓴다.
@MainActor @Observable
final class FrequentCarStore {
    static let shared = FrequentCarStore()

    private let directory: URL
    private let fileURL: URL

    private(set) var cars: [FrequentCar] = []

    init(directory: URL = FrequentCarStore.defaultDirectory) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("frequent-cars.json")

        ensureDirectoryExcludedFromBackup()
        cars = Self.load(from: fileURL)
    }

    nonisolated private static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VisitorCar", isDirectory: true)
    }

    /// 파일이 없거나 깨졌으면 빈 목록으로 시작한다 — 여기서 던지면 화면이 못 뜬다.
    private static func load(from url: URL) -> [FrequentCar] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FrequentCar].self, from: data)
        else { return [] }
        return decoded
    }

    // **마이그레이션 없음.** 이 기능은 아직 출시된 적이 없어서 `UserDefaults`에 읽어 올
    // 기존 사용자 데이터가 없다 — 새로 만들 필요가 없는 코드를 미리 만들지 않는다.

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

    /// 쓰기가 실패해도 메모리 상의 목록은 그대로 둔다 — 사용자 눈에는 이미 반영된 상태다.
    private func persist() {
        guard let data = try? JSONEncoder().encode(cars) else { return }
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return }
        excludeFromBackup(fileURL)
    }

    /// 디렉터리를 만들면서(혹은 처음 손대면서) 백업 제외 플래그를 세운다.
    private func ensureDirectoryExcludedFromBackup() {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        excludeFromBackup(directory)
    }

    /// 플래그는 아이노드에 붙는다 — `write(to:)`로 파일을 다시 만들 때마다 새로 세워야
    /// 이전에 세운 플래그가 새 아이노드로 이어지지 않고 사라지는 일을 막는다.
    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
