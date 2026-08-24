import Foundation

/// 고지서 사진 한 장을 골라 인식을 요청한다. 연월은 고지서에 적혀 있어 서버가 읽어 주므로
/// 여기서 묻지 않는다 — 검수 화면에서 확인·수정한다.
///
/// **사진을 축소하지 않는다.** 고지서는 항목이 스무 줄 넘고 금액이 여섯 자리라, 줄이면
/// 서버가 잘라 확대해도 정보가 이미 없어 모델이 빈 칸을 숫자로 메운다. 서버 multipart 한도는 10MB다.
@MainActor
@Observable
final class MaintenanceUploadViewModel {
    enum Phase: Equatable {
        case idle
        case recognizing
        case completed
        case failed
    }

    private let service: any MaintenanceServing

    private(set) var imageData: Data?
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var recognition: MaintenanceRecognition?

    /// 사진이 바뀔 때마다 올린다. 인식이 도는 중에 사진을 바꾸면 이전 요청이 뒤늦게 돌아와
    /// 완료를 세우는데, 그러면 **이전 사진의 인식 결과와 새 사진의 미리보기가 섞인** 검수
    /// 화면이 열리고 그대로 저장하면 다른 고지서가 들어간다.
    private var generation = 0

    init(service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
    }

    var canRecognize: Bool {
        imageData != nil && phase != .recognizing
    }

    func setImage(_ data: Data) {
        generation += 1
        imageData = data
        phase = .idle
        errorMessage = nil
        recognition = nil
    }

    /// 새 사진을 고른 순간 이전 사진은 무효다. **비워 두지 않으면** 새 사진이 아직 로딩
    /// 중인데도 「인식하기」가 살아 있어 **이전 사진이 그대로 나간다.**
    func clearImage() {
        generation += 1
        imageData = nil
        phase = .idle
        errorMessage = nil
        recognition = nil
    }

    /// 해상도를 줄이지 않고는 전송 한도를 못 맞춘다.
    ///
    /// **줄여서 보내지 않는다.** 고지서는 항목이 스무 줄에 금액이 여섯 자리라 줄이면
    /// 인식이 망가지는데, 그건 조용히 나빠지는 실패다 — 사용자는 유료 인식이 왜 엉망인지
    /// 알 수 없다. 차라리 여기서 막고 이유를 말한다.
    func setImageTooLarge() {
        generation += 1
        imageData = nil
        phase = .idle
        recognition = nil
        errorMessage = "사진이 너무 커서 보낼 수 없습니다. 고지서 표만 담기게 잘라서 다시 찍어 주세요."
    }

    /// 앨범에서 읽거나 JPEG로 굽는 데 실패했다. 조용히 넘기면 사진 자리가 빈 채로 남아
    /// 사용자가 「사진이 안 들어갔다」는 것조차 모른다.
    func setImageLoadFailed() {
        generation += 1
        imageData = nil
        phase = .idle
        recognition = nil
        errorMessage = "사진을 읽지 못했습니다. 다른 사진으로 다시 시도해 주세요."
    }

    func recognize() async {
        // 연타나 화면 복귀로 두 번 들어오면 유료 인식이 두 번 나간다.
        guard phase != .recognizing else { return }
        guard let imageData else { return }
        phase = .recognizing
        errorMessage = nil
        let token = generation
        do {
            let result = try await service.recognize(imageData: imageData)
            // 사진이 바뀌었다. 이 결과는 화면에 보이는 사진의 것이 아니다.
            // **여기서 phase를 건드리지 않는다** — 새 인식이 이미 시작됐을 수 있고,
            // 그 스피너를 꺼 버리면 유료 요청이 두 번 나간다. `setImage`가 이미 `.idle`로 돌려놨다.
            guard token == generation else { return }
            recognition = result
            phase = .completed
        } catch is CancellationError {
            // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return
        } catch {
            // 바뀌기 전 사진의 실패다. 새 사진으로 다시 인식하려는 참인데 오류만 떠 있으면
            // 사용자는 방금 고른 사진이 실패한 줄 안다.
            guard token == generation else { return }
            // 서버 메시지가 이미 사용자용 한국어다. 봉투 JSON째 보여주지 않으려고 `message`만 꺼낸다.
            errorMessage = error.serverMessage ?? error.localizedDescription
            phase = .failed
        }
    }
}
