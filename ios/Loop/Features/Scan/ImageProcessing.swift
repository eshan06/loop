import UIKit

enum ImageProcessing {
    /// Resize so the longest side is at most 1600 px, then JPEG at quality 0.8 (docs/API.md, POST /photos).
    /// Also converts HEIC and PNG to JPEG, which the server requires.
    static func jpeg(_ image: UIImage, maxPixel: CGFloat = 1600, quality: CGFloat = 0.8) -> Data {
        let resized = ImageLoader.downsample(image.normalizedOrientation(), maxPixel: maxPixel)
        return resized.jpegData(compressionQuality: quality) ?? Data()
    }
}

extension UIImage {
    /// Redraws the image upright so EXIF orientation doesn't matter downstream.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
