import Foundation
import Photos
import UIKit

/// 사진을 기기 사진 앱에 저장한다. **쓰기 전용 권한(`.addOnly`)만 요청한다** —
/// 저장하려는 것뿐인데 사진첩 전체 읽기 권한을 묻는 것은 필요 이상이다.
protocol PhotoLibrarySaving: Sendable {
    func save(_ imageData: Data) async throws
}

enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "사진 접근 권한이 없어 저장하지 못했습니다. 설정에서 허용해 주세요."
        case .invalidImage: "사진을 저장할 수 없는 형식입니다."
        }
    }
}

struct PhotoLibrarySaver: PhotoLibrarySaving {
    func save(_ imageData: Data) async throws {
        guard UIImage(data: imageData) != nil else { throw PhotoLibraryError.invalidImage }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        // `.limited`는 읽기 범위를 제한한 상태지 쓰기가 막힌 것이 아니다 — 저장은 된다.
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            // **원본 바이트를 그대로 넣는다.** `UIImage`로 한 번 거치면 재인코딩되면서
            // 화질이 떨어지고 메타데이터가 사라진다.
            request.addResource(with: .photo, data: imageData, options: nil)
        }
    }
}
