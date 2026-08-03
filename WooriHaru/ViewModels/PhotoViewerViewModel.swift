import UIKit

/// 사진 내려받기의 응답 검사. **`URLSession.data(from:)`은 404·403에도 성공으로 돌아온다** —
/// 그때 본문은 이미지가 아니라 서버가 뱉은 오류 문서다. 걸러 내지 않으면 그 바이트를 사진으로
/// 알고 화면에 빈 자리를 그리고, 사진 앱에 저장까지 하게 된다.
/// **`@Sendable`은 뷰모델이 이 함수들을 값으로 받기 때문에 붙인다.** `PhotoViewerViewModel`의
/// 기본 인자가 `@Sendable` 함수 타입인데, 이름만 적어 넘기는 참조(`PhotoDownload.fetch`)는
/// 앱 타깃의 Swift 5 모드에서 `@Sendable`로 추론되지 않아 「data races」 경고가 난다
/// (SE-0418 `InferSendableFromCaptures`가 꺼져 있다 — 위젯 타깃만 켜져 있다).
///
/// 붙여도 되는 이유는 **둘 다 상태가 없기 때문이다** — 인자만 보고 답을 낸다.
enum PhotoDownload {
    /// 상태 코드가 2xx여도 본문이 이미지라는 보장은 없다 — 중간 프록시가 끼워 넣은 안내
    /// 페이지가 200으로 온다. **받은 바이트를 실제로 열어 봐야 안다.**
    @Sendable static func isImage(_ data: Data) -> Bool {
        UIImage(data: data) != nil
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    @Sendable static func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        return data
    }
}

/// 사진 한 장 전체화면 보기 + 사진 앱 저장.
///
/// **이미지를 직접 내려받는다.** `AsyncImage`에 맡기면 화면에 그릴 수는 있어도 저장할
/// 바이트를 손에 쥘 수 없어 같은 URL을 두 번 받게 된다. presigned URL은 10분 만료라
/// 두 번째 요청이 실패할 수도 있다.
@MainActor
@Observable
final class PhotoViewerViewModel {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private(set) var imageData: Data?
    private(set) var isLoading = false
    /// 내려받기 실패. 만료된 presigned URL이 가장 흔한 원인이다.
    private(set) var loadFailed = false
    private(set) var saveState: SaveState = .idle

    /// **바뀔 수 있다.** presigned URL은 10분 만료라, 다시 시도할 때 새 주소로 갈아 끼운다.
    private var url: String?
    private let download: @Sendable (URL) async throws -> Data
    private let isImage: @Sendable (Data) -> Bool
    /// 새 presigned URL을 얻어 온다. 없으면 주소를 갱신할 길이 없다는 뜻이다.
    private let refreshURL: (@MainActor () async -> String?)?
    private let saver: any PhotoLibrarySaving

    init(
        url: String?,
        saver: any PhotoLibrarySaving = PhotoLibrarySaver(),
        download: @escaping @Sendable (URL) async throws -> Data = PhotoDownload.fetch,
        isImage: @escaping @Sendable (Data) -> Bool = PhotoDownload.isImage,
        refreshURL: (@MainActor () async -> String?)? = nil
    ) {
        self.url = url
        self.saver = saver
        self.download = download
        self.isImage = isImage
        self.refreshURL = refreshURL
    }

    /// 저장 버튼은 **받아 온 뒤에만** 눌린다 — 없는 바이트를 저장할 수는 없다.
    var canSave: Bool {
        imageData != nil && saveState != .saving
    }

    /// 「다시 시도」. **주소부터 다시 받는다** — 실패의 가장 흔한 원인이 만료된 주소 자체라,
    /// 같은 주소로 다시 내려받으면 몇 번을 눌러도 같은 실패가 돌아온다. 그런 버튼은 없느니만
    /// 못하다 — 사용자는 눌러지니까 제 인터넷 탓이라 여기고 계속 누른다.
    func retry() async {
        await load(refreshingURL: true)
    }

    func load(refreshingURL: Bool = false) async {
        guard imageData == nil, !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        // 새 주소를 못 받아 와도 **예전 주소로라도 시도한다** — 그 사이 접속이 돌아왔을 수 있다.
        if refreshingURL, let refreshURL, let refreshed = await refreshURL() {
            url = refreshed
        }

        guard let url, let parsed = URL(string: url) else {
            loadFailed = true
            return
        }

        do {
            let data = try await download(parsed)
            // **이미지가 아니면 들고 있지 않는다.** 여기서 넣어 두면 `imageData != nil`이라
            // 다음 `load()`가 위 가드에서 곧바로 되돌아가, 화면이 띄운 「다시 시도」가 눌러도
            // 아무 일이 없는 버튼이 된다. 저장 버튼도 그 바이트를 사진 앱에 넣으려 든다.
            guard isImage(data) else {
                loadFailed = true
                return
            }
            imageData = data
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }

    func save() async {
        guard let imageData, saveState != .saving else { return }
        saveState = .saving
        do {
            try await saver.save(imageData)
            saveState = .saved
        } catch is CancellationError {
            saveState = .idle
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    /// 저장 결과 표시를 지운다 — 「저장됨」이 화면에 눌어붙지 않게 한다.
    func clearSaveState() {
        saveState = .idle
    }
}
