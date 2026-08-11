import Foundation
import Testing
@testable import WooriHaru

/// 사진 앱 저장 대역. 실제 `PHPhotoLibrary`는 권한 창을 띄우므로 테스트에서 쓸 수 없다.
private final class FakePhotoLibrarySaver: PhotoLibrarySaving, @unchecked Sendable {
    private let lock = NSLock()
    var errorToThrow: Error?
    private(set) var savedByteCounts: [Int] = []

    func save(_ imageData: Data) async throws {
        lock.lock(); savedByteCounts.append(imageData.count); lock.unlock()
        if let errorToThrow { throw errorToThrow }
    }
}

private struct DownloadFailed: LocalizedError {
    var errorDescription: String? { "사진을 받지 못했습니다." }
}

struct PhotoDownloadTests {
    private let url = URL(string: "https://example.com/1.jpg")!

    /// **`URLSession.data(from:)`은 404·403에도 성공으로 돌아온다.** 걸러 내지 않으면
    /// 서버가 뱉은 오류 문서를 사진으로 알고 화면에 빈 자리를 그리고, 저장까지 하게 된다.
    /// presigned URL이 10분 만료라 실제로 자주 닿는 자리다.
    @Test func 응답이_2xx가_아니면_던진다() {
        for status in [400, 403, 404, 500] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            #expect(throws: (any Error).self) { try PhotoDownload.validate(response) }
        }
    }

    @Test func 응답이_2xx면_통과시킨다() throws {
        for status in [200, 206, 299] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            try PhotoDownload.validate(response)
        }
    }

    /// HTTP가 아닌 응답(파일 URL 등)은 상태 코드가 없다 — 막지 않는다.
    @Test func HTTP가_아니면_통과시킨다() throws {
        try PhotoDownload.validate(URLResponse(
            url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
        ))
    }
}

@MainActor
struct PhotoViewerViewModelTests {
    private let bytes = Data(repeating: 7, count: 32)

    private func makeVM(
        url: String? = "https://example.com/1.jpg",
        saver: FakePhotoLibrarySaver = .init(),
        isImage: @escaping @Sendable (Data) -> Bool = { _ in true },
        refreshURL: (@MainActor () async -> String?)? = nil,
        download: @escaping @Sendable (URL) async throws -> Data
    ) -> PhotoViewerViewModel {
        PhotoViewerViewModel(
            url: url, saver: saver, download: download, isImage: isImage, refreshURL: refreshURL
        )
    }

    @Test func 사진을_받아_두었다가_그대로_저장한다() async {
        let saver = FakePhotoLibrarySaver()
        let vm = makeVM(saver: saver) { _ in self.bytes }

        await vm.load()
        #expect(vm.imageData == bytes)
        #expect(vm.canSave)

        await vm.save()

        // **받아 온 원본 바이트를 그대로 넘긴다** — 다시 내려받으면 만료된 URL에서 실패한다.
        #expect(saver.savedByteCounts == [32])
        #expect(vm.saveState == .saved)
    }

    /// 받기 전에는 저장할 것이 없다.
    @Test func 받기_전에는_저장할_수_없다() async {
        let saver = FakePhotoLibrarySaver()
        let vm = makeVM(saver: saver) { _ in self.bytes }

        #expect(!vm.canSave)
        await vm.save()

        #expect(saver.savedByteCounts.isEmpty)
        #expect(vm.saveState == .idle)
    }

    /// presigned URL은 10분 만료라 열었을 때 이미 죽어 있을 수 있다.
    @Test func 받기에_실패하면_다시_시도할_수_있게_남긴다() async {
        let vm = makeVM { _ in throw DownloadFailed() }

        await vm.load()

        #expect(vm.loadFailed)
        #expect(vm.imageData == nil)
        #expect(!vm.canSave)
        #expect(!vm.isLoading)
    }

    @Test func 주소가_없으면_받으려_하지_않는다() async {
        let vm = makeVM(url: nil) { _ in
            Issue.record("주소가 없는데 받으려 했다")
            return Data()
        }

        await vm.load()

        #expect(vm.loadFailed)
    }

    /// 저장 실패는 알려 줘야 한다 — 조용히 넘어가면 저장된 줄 안다.
    @Test func 저장에_실패하면_이유를_알린다() async {
        let saver = FakePhotoLibrarySaver()
        saver.errorToThrow = PhotoLibraryError.permissionDenied
        let vm = makeVM(saver: saver) { _ in self.bytes }
        await vm.load()

        await vm.save()

        guard case let .failed(message) = vm.saveState else {
            Issue.record("실패 상태여야 한다: \(vm.saveState)")
            return
        }
        #expect(!message.isEmpty)

        // 알림을 닫으면 표시가 지워진다 — 「저장 실패」가 화면에 눌어붙지 않는다.
        vm.clearSaveState()
        #expect(vm.saveState == .idle)
    }

    /// **2xx라고 이미지인 것은 아니다** — 중간 프록시의 안내 페이지가 200으로 온다.
    /// 그 바이트를 들고 있으면 화면은 「다시 시도」를 띄우는데 `imageData != nil`이라
    /// `load()`가 곧바로 되돌아가, **눌러도 아무 일이 없는 버튼**이 된다.
    @Test func 이미지가_아닌_바이트는_들고_있지_않아_다시_받을_수_있다() async {
        let counter = DownloadCounter()
        let good = Data(repeating: 7, count: 32)
        let bad = Data("<html>error</html>".utf8)
        let saver = FakePhotoLibrarySaver()
        let vm = makeVM(saver: saver, isImage: { $0 == good }) { _ in
            await counter.next() == 1 ? bad : good
        }

        await vm.load()

        #expect(vm.loadFailed)
        #expect(vm.imageData == nil)
        // 이미지가 아닌 바이트를 사진 앱에 넣으려 들면 안 된다.
        #expect(!vm.canSave)

        // 화면이 띄운 「다시 시도」다. 실제로 다시 내려받아야 한다.
        await vm.load()

        #expect(vm.imageData == good)
        #expect(!vm.loadFailed)
        #expect(await counter.count == 2)

        await vm.save()
        #expect(saver.savedByteCounts == [32])
    }

    /// **presigned URL은 10분 만료다.** 상세를 열어 둔 채 시간이 지나면 주소부터 죽어 있는데,
    /// 같은 주소로 다시 받으면 몇 번을 눌러도 같은 실패가 돌아온다 — 「다시 시도」가 눌러지기만
    /// 하고 아무것도 못 고치는 거짓 버튼이 된다.
    @Test func 다시_시도는_주소부터_다시_받는다() async {
        let good = Data(repeating: 7, count: 32)
        let requested = URLRecorder()
        let vm = makeVM(
            url: "https://example.com/expired.jpg",
            refreshURL: { "https://example.com/fresh.jpg" }
        ) { url in
            await requested.record(url.absoluteString)
            // 만료된 주소는 계속 실패한다 — 서버가 403을 준다.
            guard url.absoluteString.contains("fresh") else { throw DownloadFailed() }
            return good
        }

        await vm.load()
        #expect(vm.loadFailed)

        await vm.retry()

        #expect(vm.imageData == good)
        #expect(!vm.loadFailed)
        #expect(await requested.urls == [
            "https://example.com/expired.jpg", "https://example.com/fresh.jpg"
        ])
    }

    /// 주소를 못 받아 왔다고 손 놓지 않는다 — 그 사이 접속이 돌아왔을 수도 있다.
    @Test func 주소를_다시_받지_못해도_시도는_한다() async {
        let counter = DownloadCounter()
        let vm = makeVM(refreshURL: { nil }) { _ in
            _ = await counter.next()
            throw DownloadFailed()
        }

        await vm.load()
        await vm.retry()

        #expect(await counter.count == 2)
        #expect(vm.loadFailed)
    }

    /// 이미 받아 둔 사진을 다시 받지 않는다 — 만료된 URL로 두 번째 요청을 내면 실패한다.
    @Test func 이미_받았으면_다시_받지_않는다() async {
        let counter = DownloadCounter()
        let vm = makeVM { _ in
            await counter.increment()
            return self.bytes
        }

        await vm.load()
        await vm.load()

        #expect(await counter.count == 1)
    }
}

/// 어떤 주소로 내려받으려 했는지 순서대로 남긴다 — 재시도가 **새 주소로** 갔는지 본다.
private actor URLRecorder {
    private(set) var urls: [String] = []
    func record(_ url: String) { urls.append(url) }
}

private actor DownloadCounter {
    private(set) var count = 0
    func increment() { count += 1 }

    /// 몇 번째 호출인지 돌려준다 — 첫 요청과 재시도에 서로 다른 응답을 주는 데 쓴다.
    func next() -> Int {
        count += 1
        return count
    }
}

// MARK: - 아래로 끌어 닫기

struct PhotoDragDismissTests {
    @Test func 아래로_충분히_끌면_닫는다() {
        #expect(PhotoDragDismiss.shouldDismiss(translationY: 150, velocityY: 0))
    }

    @Test func 조금만_끌면_안_닫는다() {
        #expect(!PhotoDragDismiss.shouldDismiss(translationY: 40, velocityY: 0))
    }

    /// **부호를 잘못 보면 위로 끌 때 닫힌다.** 위는 무시하기로 한 방향이다.
    @Test func 위로는_아무리_끌어도_안_닫는다() {
        #expect(!PhotoDragDismiss.shouldDismiss(translationY: -400, velocityY: -3000))
        // **위로 끌다 아래로 튕겨도 안 닫는다.** 속도만 보면 여기서 새어 나간다 — 손을 떼는
        // 순간의 방향이 아래일 뿐 사용자가 끈 방향은 위다.
        #expect(!PhotoDragDismiss.shouldDismiss(translationY: -50, velocityY: 1500))
    }

    /// **거리만 보면 이 경우가 조용히 빠진다.** 휙 튕기는 동작이 「안 닫히는 버그」로 느껴진다.
    @Test func 빠르게_튕기면_거리가_짧아도_닫는다() {
        #expect(PhotoDragDismiss.shouldDismiss(translationY: 40, velocityY: 1500))
    }

    /// **완전 투명까지 가면 안 된다** — fullScreenCover 뒤의 시스템 배경색이 드러나
    /// 라이트 모드에서 흰색이 튀어나온다.
    @Test func 배경은_하한_아래로_안_내려간다() {
        #expect(PhotoDragDismiss.backgroundOpacity(translationY: 5000) == PhotoDragDismiss.minimumBackgroundOpacity)
        #expect(PhotoDragDismiss.backgroundOpacity(translationY: 0) == 1)
    }

    /// 위로 끌면 화면이 따라 움직이지 않는다 — 따라오게 해 놓고 안 닫는 것이 가장 나쁘다.
    @Test func 위로_끌면_화면이_안_움직인다() {
        #expect(PhotoDragDismiss.offsetY(translationY: -200) == 0)
        #expect(PhotoDragDismiss.offsetY(translationY: 80) == 80)
    }
}
