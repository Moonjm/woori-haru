import ImageIO
import UIKit
import UniformTypeIdentifiers

extension UIImage {
    /// 업로드 전에 장변을 `maxDimension`으로 줄인 JPEG 데이터.
    ///
    /// `UIImage(data:)`로 통째로 디코드하지 않고 ImageIO 썸네일로 만든다 — PhotosPicker 원본은
    /// 12MP급이라 5장을 동시에 들고 있으면 메모리가 튄다. 서버(라즈베리파이)가 재인코딩하지
    /// 않도록 앱에서 줄이는 것이고, 장변 1024px에서 음식 인식 정확도 손실은 사실상 없다.
    ///
    /// 원본이 상한보다 작으면 `kCGImageSourceCreateThumbnailFromImageAlways`가 확대하지 않도록
    /// 상한을 원본 장변으로 낮춘다.
    static func downsampledJPEG(from data: Data, maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let originalMax = max(
            (properties[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0,
            (properties[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        )
        guard originalMax > 0 else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxDimension, originalMax)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}
