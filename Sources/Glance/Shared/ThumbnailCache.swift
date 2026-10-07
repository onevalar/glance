//
//  ThumbnailCache.swift
//  Glance
//

import AppKit
import ImageIO

/// Decodes small previews off the main thread and remembers them, so scrolling the sidebar or
/// changing a rating never re-reads full-size photos.
enum ThumbnailCache {
    private final class Box: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 500
        return cache
    }()

    /// - Parameter maxPixelSize: longest edge in pixels (the sidebar shows 120×90 pt, so 360 stays sharp on Retina).
    static func thumbnail(for url: URL, maxPixelSize: Int = 360) async -> NSImage? {
        let box: Box? = await Task.detached(priority: .utility) {
            // The modification date is part of the key, so a rotated or edited file gets a fresh preview.
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
                .timeIntervalSinceReferenceDate ?? 0
            let key = "\(url.path)|\(modified)|\(maxPixelSize)" as NSString

            if let cached = cache.object(forKey: key) { return cached }

            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            let box = Box(cgImage)
            cache.setObject(box, forKey: key)
            return box
        }.value

        guard let image = box?.image else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
