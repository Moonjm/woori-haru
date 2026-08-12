import Foundation

/// 사진 한 장과 연월을 골라 인식을 요청한다.
///
/// **사진을 축소하지 않는다.** 식단은 `UIImage.downsampledJPEG(maxDimension: 1024)`로 줄여
/// 올리지만, 배차표는 표가 가로로 길어 한 칸이 몇 픽셀밖에 안 된다. 줄이면 서버가 잘라
/// 확대해도 정보가 이미 없어 모델이 빈 칸을 숫자로 메운다 — 실측에서 전처리 해상도가
/// 정확도 0%와 100%를 갈랐다. 서버 multipart 한도는 10MB이고 원본은 ~600KB다.
@MainActor
@Observable
final class DispatchUploadViewModel {
    enum Phase: Equatable {
        case idle
        case recognizing
        case completed
        case failed
    }

    private let service: DispatchServing

    var imageData: Data?
    var yearMonth: String
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var recognition: DispatchRecognition?

    /// 사진이 바뀔 때마다 올린다. 인식이 도는 중에 사진을 바꾸면 이전 요청이 뒤늦게 돌아와
    /// 완료를 세우는데, 그러면 **이전 사진의 인식 결과와 새 사진의 미리보기가 섞인** 검수
    /// 화면이 열리고 그대로 저장하면 다른 사진의 근무가 들어간다.
    /// (`DietDayViewModel.generation`과 같은 장치다.)
    private var generation = 0

    init(
        service: DispatchServing = DispatchService(),
        now: Date = Date(),
        calendar: Calendar = .dispatchGregorian
    ) {
        self.service = service
        self.yearMonth = Self.defaultYearMonth(now: now, calendar: calendar)
    }

    var canRecognize: Bool {
        imageData != nil && phase != .recognizing && isYearMonthValid
    }

    /// 화면이 형식 오류를 알리는 데 쓴다.
    var isYearMonthValid: Bool {
        Self.isValidYearMonth(yearMonth)
    }

    func setImage(_ data: Data) {
        generation += 1
        imageData = data
        phase = .idle
        errorMessage = nil
        recognition = nil
    }

    /// 앨범에서 읽거나 JPEG로 굽는 데 실패했다. 조용히 넘기면 사진 섹션이 빈 채로 남아
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
            let result = try await service.recognize(imageData: imageData, yearMonth: yearMonth)
            // 인식이 도는 동안 사진이 바뀌었다. 이 결과는 화면에 보이는 사진의 것이 아니다.
            // 사진을 바꿀 때 `setImage`가 이미 `phase`를 `.idle`로 돌려놨으므로 그대로 버린다.
            guard token == generation else { return }
            recognition = result
            phase = .completed
        } catch is CancellationError {
            // 사용자가 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return
        } catch {
            // 바뀌기 전 사진의 실패다. 새 사진으로 다시 인식하려는 참인데 오류만 떠 있으면
            // 사용자는 방금 고른 사진이 실패한 줄 안다.
            guard token == generation else { return }
            // 서버 메시지가 이미 사용자용 한국어다(`TARGET_NOT_FOUND` 등). 앱이 다시 쓰지 않는다.
            // 다만 봉투 JSON째 보여주면 안 되므로 `message`만 꺼낸다.
            errorMessage = error.serverMessage ?? error.localizedDescription
            phase = .failed
        }
    }

    /// `^\d{4}-(0[1-9]|1[0-2])$`. **월에 0을 채워야 한다** — `2026-3`·`2026-13`은
    /// 서버의 `YearMonth` 파싱이 400을 낸다.
    static func isValidYearMonth(_ value: String) -> Bool {
        value.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil
    }

    /// `2026-08` 형식. **월에 0을 채워야 한다** — `2026-3`은 서버의 `YearMonth` 파싱이 400을 낸다.
    static func defaultYearMonth(now: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: now)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }
}
