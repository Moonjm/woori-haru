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

    /// 바이트 상한에 맞춘 JPEG. **해상도를 마지막에 포기한다.**
    ///
    /// 배차표는 표 한 칸이 몇 픽셀이라 크기를 줄이면 인식이 무너진다(실측에서 전처리
    /// 해상도가 정확도 0%와 100%를 갈랐다). 그래서 품질부터 단계적으로 낮춰 보고, 그래도
    /// 넘칠 때만 장변을 줄인다. 4,800만 화소 사진을 원본 크기 그대로 품질 0.95로 구우면
    /// 서버 multipart 한도(10MB)를 넘겨 인식에 들어가 보지도 못하고 실패한다.
    ///
    /// 어느 단계도 상한에 못 들어가면 가장 작게 나온 것을 준다 — 여기서 `nil`을 주면 화면이
    /// 「사진을 읽지 못했습니다」를 띄우는데, 읽기는 멀쩡히 됐으므로 틀린 안내다.
    ///
    /// **디코딩과 인코딩이 무겁다.** 메인 액터에서 부르지 마라.
    static func jpegWithinByteLimit(
        from data: Data,
        byteLimit: Int = 9 * 1024 * 1024,
        qualities: [CGFloat] = [0.95, 0.8, 0.65, 0.5],
        dimensions: [CGFloat] = [.greatestFiniteMagnitude, 4000, 3000, 2400]
    ) -> Data? {
        var smallest: Data?
        for dimension in dimensions {
            for quality in qualities {
                guard let encoded = downsampledJPEG(from: data, maxDimension: dimension, quality: quality) else {
                    // 첫 시도부터 실패했다면 이미지가 아니다. 그 뒤 단계도 마찬가지다.
                    return smallest
                }
                if encoded.count <= byteLimit { return encoded }
                if smallest == nil || encoded.count < smallest!.count { smallest = encoded }
            }
        }
        return smallest
    }
}
