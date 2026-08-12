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

    init(
        service: DispatchServing = DispatchService(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.service = service
        self.yearMonth = Self.defaultYearMonth(now: now, calendar: calendar)
    }

    var canRecognize: Bool {
        imageData != nil && phase != .recognizing
    }

    func setImage(_ data: Data) {
        imageData = data
        phase = .idle
        errorMessage = nil
        recognition = nil
    }

    func recognize() async {
        guard let imageData else { return }
        phase = .recognizing
        errorMessage = nil
        do {
            recognition = try await service.recognize(imageData: imageData, yearMonth: yearMonth)
            phase = .completed
        } catch {
            // 서버 메시지가 이미 사용자용 한국어다(`TARGET_NOT_FOUND` 등). 앱이 다시 쓰지 않는다.
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    /// `2026-08` 형식. **월에 0을 채워야 한다** — `2026-3`은 서버의 `YearMonth` 파싱이 400을 낸다.
    static func defaultYearMonth(now: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: now)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }
}
