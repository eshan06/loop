import SwiftUI
import ImageIO
import UIKit

/// Loads and caches images without third-party packages.
/// Memory: an NSCache of images already downsampled to the size they're shown at.
/// Disk: `URLCache.shared`, enlarged at launch, holds the raw bytes.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()
    private let memory = NSCache<NSString, UIImage>()

    init() {
        memory.countLimit = 300
    }

    static func configureURLCache() {
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    }

    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        memory.object(forKey: key(url, maxPixel))
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = key(url, maxPixel)
        if let hit = memory.object(forKey: key) { return hit }

        let image: UIImage?
        if url.scheme == "mock" {
            image = MockMedia.shared.image(for: url).map { Self.downsample($0, maxPixel: maxPixel) }
                ?? PlaceholderArt.image(for: url)
        } else {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            image = Self.downsample(data, maxPixel: maxPixel)
        }
        if let image { memory.setObject(image, forKey: key) }
        return image
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixel))" as NSString
    }

    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceShouldCacheImmediately: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func downsample(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxPixel else { return image }
        let scale = maxPixel / longest
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// A remote or local image that fills its frame (aspect fill, clipped by the caller).
@MainActor struct CachedImage: View {
    let url: URL?
    /// Longest side in pixels to decode at. Grid thumbnails use about 400.
    var maxPixel: CGFloat = 800

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageLoader.shared.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            let loaded = await ImageLoader.shared.image(for: url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// Placeholder art for mock photos without a real image: a soft tint with the category's symbol.
/// URLs look like `mock://media/<category>-<id>-<n>.jpg`.
enum PlaceholderArt {
    private static let tints: [UIColor] = [
        UIColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1), UIColor(red: 0.94, green: 0.90, blue: 0.86, alpha: 1),
        UIColor(red: 0.88, green: 0.93, blue: 0.89, alpha: 1), UIColor(red: 0.93, green: 0.89, blue: 0.92, alpha: 1),
        UIColor(red: 0.92, green: 0.92, blue: 0.88, alpha: 1), UIColor(red: 0.87, green: 0.90, blue: 0.93, alpha: 1),
    ]

    static func image(for url: URL) -> UIImage {
        let name = url.deletingPathExtension().lastPathComponent
        let category = ItemCategory(rawValue: String(name.split(separator: "-").first ?? ""))
        let symbol = category?.symbol ?? (name.hasPrefix("avatar") ? "person.fill" : "tshirt")
        let tint = tints[Int(UInt(bitPattern: name.hashValueStable) % UInt(tints.count))]
        let size = CGSize(width: 480, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            tint.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 150, weight: .ultraLight)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(UIColor.black.withAlphaComponent(0.28), renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2)
                glyph.draw(at: origin)
            }
        }
    }
}

private extension String {
    /// `hashValue` changes every launch; this doesn't, so placeholders keep their tint.
    var hashValueStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}

/// A faint inner edge so photos with white backgrounds don't dissolve into the page.
struct PhotoHairline: View {
    var radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
            .allowsHitTesting(false)
    }
}
