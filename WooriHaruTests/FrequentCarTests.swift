import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct FrequentCarTests {

    /// 테스트마다 고유한 임시 디렉터리를 쓴다 — 실제 Application Support를 절대 건드리지 않는다.
    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("frequentcar.tests.\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    private func makeStore(directory: URL? = nil) -> (FrequentCarStore, URL) {
        let dir = directory ?? makeTempDirectory()
        return (FrequentCarStore(directory: dir), dir)
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func 처음에는_비어_있다() {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        #expect(store.cars.isEmpty)
    }

    @Test func 추가하면_목록에_들어온다() {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        #expect(store.add(nickname: "아빠차", carNo: "12가3456") == nil)

        #expect(store.cars.count == 1)
        #expect(store.cars[0].nickname == "아빠차")
        #expect(store.cars[0].carNo == "12가3456")
    }

    /// 차량번호 규칙은 등록 화면과 같은 것을 쓴다 — 저장해 놓고 등록할 때 튕기면 늦다.
    @Test func 잘못된_차량번호는_거절한다() {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        #expect(store.add(nickname: "아빠차", carNo: "12가 3456") == "차량번호에 공백을 넣을 수 없습니다.")
        #expect(store.cars.isEmpty)
    }

    @Test func 별칭이_비면_거절한다() {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        #expect(store.add(nickname: "  ", carNo: "12가3456") == "별칭을 입력해 주세요.")
        #expect(store.cars.isEmpty)
    }

    /// 같은 번호를 두 번 담으면 고를 때 어느 쪽인지 알 수 없다.
    @Test func 같은_차량번호는_한_번만_담는다() {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        #expect(store.add(nickname: "아빠차", carNo: "12가3456") == nil)
        #expect(store.add(nickname: "엄마차", carNo: "12가3456") == "이미 저장된 차량번호입니다.")
        #expect(store.cars.count == 1)
    }

    @Test func 지우면_사라진다() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        _ = store.add(nickname: "아빠차", carNo: "12가3456")
        let id = try #require(store.cars.first?.id)

        store.remove(id: id)

        #expect(store.cars.isEmpty)
    }

    /// **서버로 보내지 않는다** — 이 기기에만 남는다. 앱을 다시 띄워도 살아 있어야 한다.
    @Test func 다시_띄워도_남아_있다() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        _ = FrequentCarStore(directory: dir).add(nickname: "아빠차", carNo: "12가3456")

        #expect(FrequentCarStore(directory: dir).cars.count == 1)
    }

    /// **이 변경의 핵심.** 백업 제외 플래그가 실제로 파일에 세워지지 않으면
    /// 설정 화면의 "기기를 바꾸면 사라집니다" 문구는 다시 거짓말이 된다.
    @Test func 저장한_파일은_백업에서_제외된다() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        _ = store.add(nickname: "아빠차", carNo: "12가3456")

        let fileURL = dir.appendingPathComponent("frequent-cars.json")
        let values = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])

        #expect(values.isExcludedFromBackup == true)
    }

    @Test func 깨진_파일은_빈_목록으로_시작한다() throws {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("frequent-cars.json")
        try Data("이건 JSON이 아니다".utf8).write(to: fileURL)

        #expect(FrequentCarStore(directory: dir).cars.isEmpty)
    }
}
