import Foundation
import Testing
@testable import WooriHaru

/// **직렬로 돌린다.** 셋 다 같은 Keychain 항목 하나를 건드려서, 나란히 돌면 서로를 지운다.
@Suite(.serialized)
struct VisitorCarCredentialTests {

    /// 테스트끼리 부딪히지 않게 서비스 이름을 따로 쓴다.
    private func makeStore() -> VisitorCarKeychainStore {
        VisitorCarKeychainStore(service: "com.woori.haru.visitorcar.tests")
    }

    @Test func 저장하고_다시_읽는다() throws {
        let store = makeStore()
        defer { store.clear() }

        try store.save(VisitorCarCredentials(id: "10010101", password: "비밀"))

        #expect(store.load() == VisitorCarCredentials(id: "10010101", password: "비밀"))
    }

    /// 계정을 바꿔 다시 저장하면 **덮어써야** 한다 — 두 벌이 남으면 어느 쪽으로 붙을지 알 수 없다.
    @Test func 다시_저장하면_덮어쓴다() throws {
        let store = makeStore()
        defer { store.clear() }

        try store.save(VisitorCarCredentials(id: "10010101", password: "옛것"))
        try store.save(VisitorCarCredentials(id: "20020202", password: "새것"))

        #expect(store.load()?.id == "20020202")
        #expect(store.load()?.password == "새것")
    }

    /// 로그아웃하면 자국이 남지 않아야 한다.
    @Test func 지우면_사라진다() throws {
        let store = makeStore()

        try store.save(VisitorCarCredentials(id: "10010101", password: "비밀"))
        store.clear()

        #expect(store.load() == nil)
    }

    @Test func 저장한_적이_없으면_nil이다() {
        let store = VisitorCarKeychainStore(service: "com.woori.haru.visitorcar.tests.empty")
        store.clear()

        #expect(store.load() == nil)
    }
}
