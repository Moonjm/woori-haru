import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct FrequentCarTests {

    private func makeStore() -> FrequentCarStore {
        FrequentCarStore(defaults: UserDefaults(suiteName: "frequentcar.tests.\(UUID().uuidString)")!)
    }

    @Test func 처음에는_비어_있다() {
        #expect(makeStore().cars.isEmpty)
    }

    @Test func 추가하면_목록에_들어온다() {
        let store = makeStore()

        #expect(store.add(nickname: "아빠차", carNo: "12가3456") == nil)

        #expect(store.cars.count == 1)
        #expect(store.cars[0].nickname == "아빠차")
        #expect(store.cars[0].carNo == "12가3456")
    }

    /// 차량번호 규칙은 등록 화면과 같은 것을 쓴다 — 저장해 놓고 등록할 때 튕기면 늦다.
    @Test func 잘못된_차량번호는_거절한다() {
        let store = makeStore()

        #expect(store.add(nickname: "아빠차", carNo: "12가 3456") == "차량번호에 공백을 넣을 수 없습니다.")
        #expect(store.cars.isEmpty)
    }

    @Test func 별칭이_비면_거절한다() {
        let store = makeStore()

        #expect(store.add(nickname: "  ", carNo: "12가3456") == "별칭을 입력해 주세요.")
        #expect(store.cars.isEmpty)
    }

    /// 같은 번호를 두 번 담으면 고를 때 어느 쪽인지 알 수 없다.
    @Test func 같은_차량번호는_한_번만_담는다() {
        let store = makeStore()

        #expect(store.add(nickname: "아빠차", carNo: "12가3456") == nil)
        #expect(store.add(nickname: "엄마차", carNo: "12가3456") == "이미 저장된 차량번호입니다.")
        #expect(store.cars.count == 1)
    }

    @Test func 지우면_사라진다() throws {
        let store = makeStore()
        _ = store.add(nickname: "아빠차", carNo: "12가3456")
        let id = try #require(store.cars.first?.id)

        store.remove(id: id)

        #expect(store.cars.isEmpty)
    }

    /// **서버로 보내지 않는다** — 이 기기에만 남는다. 앱을 다시 띄워도 살아 있어야 한다.
    @Test func 다시_띄워도_남아_있다() {
        let suite = "frequentcar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        _ = FrequentCarStore(defaults: defaults).add(nickname: "아빠차", carNo: "12가3456")

        #expect(FrequentCarStore(defaults: defaults).cars.count == 1)
    }
}
