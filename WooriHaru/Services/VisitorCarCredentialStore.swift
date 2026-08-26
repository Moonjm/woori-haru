import Foundation
import Security

struct VisitorCarCredentials: Codable, Sendable, Equatable {
    let id: String
    let password: String
}

/// 자격증명 보관. **테스트는 이 자리를 메모리 대역으로 바꾼다** —
/// 서비스 테스트가 Keychain에 붙을 이유가 없다.
protocol VisitorCarCredentialStoring: Sendable {
    func load() -> VisitorCarCredentials?
    func save(_ credentials: VisitorCarCredentials) throws
    func clear()
}

/// Keychain 한 항목에 아이디·비밀번호를 JSON으로 담는다.
///
/// **항목을 하나만 쓴다.** 계정을 여러 벌 다루지 않기로 했고(스펙 비목표),
/// 아이디를 `kSecAttrAccount`로 쪼개면 「어느 아이디로 저장했는지」를 어딘가 또 적어 둬야 한다.
struct VisitorCarKeychainStore: VisitorCarCredentialStoring {
    private let service: String
    private let account = "credentials"

    init(service: String = "com.woori.haru.visitorcar") {
        self.service = service
    }

    func load() -> VisitorCarCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return try? JSONDecoder().decode(VisitorCarCredentials.self, from: data)
    }

    func save(_ credentials: VisitorCarCredentials) throws {
        let data = try JSONEncoder().encode(credentials)

        // **먼저 지우고 넣는다.** `SecItemUpdate`로 갈래를 나누면 「없을 때 추가」
        // 경로가 따로 생기고, 둘 중 하나만 틀려도 항목이 두 벌 남는다.
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        // 잠긴 기기에서 백그라운드로 붙을 일이 없다 — 화면을 열어야 쓰는 기능이다.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw VisitorCarError.keychain(Int(status)) }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
