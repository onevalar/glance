//
//  ImageRotator.swift
//  Glance
//

import CoreGraphics
import Foundation
import ImageIO

/// Rotates an image file in place while keeping its original format, EXIF and resolution (DPI).
enum ImageRotator {
    enum Direction {
        case clockwise
        case counterClockwise
    }

    enum RotationError: LocalizedError {
        case unreadable
        case animated
        case unsupportedFormat(String)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return String(localized: "无法读取这张图片")
            case .animated:
                return String(localized: "动图无法旋转，否则会丢失动画")
            case .unsupportedFormat(let ext):
                return String(localized: "暂不支持旋转 \(ext.uppercased()) 格式，原文件不会被改动")
            case .writeFailed:
                return String(localized: "保存失败，原文件没有被改动")
            }
        }
    }

    static func rotate(_ url: URL, direction: Direction) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else {
            throw RotationError.unreadable
        }
        guard CGImageSourceGetCount(source) == 1 else { throw RotationError.animated }

        // The destination must be able to write the very same format, otherwise we would
        // end up with e.g. PNG bytes inside a ".webp" file.
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard writable.contains(type as String) else {
            throw RotationError.unsupportedFormat(url.pathExtension)
        }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        guard let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw RotationError.unreadable
        }

        // Full-size decode with the EXIF orientation already applied to the pixels.
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
        ]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary),
              let rotated = rotated(upright, direction: direction) else {
            throw RotationError.unreadable
        }

        // The pixels are now upright, so the stored orientation tag and the old size fields must go.
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = nil
        properties[kCGImagePropertyPixelHeight] = nil
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = rotated.width
            exif[kCGImagePropertyExifPixelYDimension] = rotated.height
            properties[kCGImagePropertyExifDictionary] = exif
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            throw RotationError.writeFailed
        }
        CGImageDestinationAddImage(destination, rotated, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RotationError.writeFailed }

        // Atomic write: a crash halfway never leaves a truncated picture behind.
        do {
            try (data as Data).write(to: url, options: .atomic)
        } catch {
            throw RotationError.writeFailed
        }
    }

    /// Returns `image` turned by a quarter turn in the requested direction.
    static func rotated(_ image: CGImage, direction: Direction) -> CGImage? {
        let width = image.width
        let height = image.height

        let colorSpace: CGColorSpace
        if let own = image.colorSpace, own.model == .rgb {
            colorSpace = own
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        }

        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let bitmapInfo = hasAlpha
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: height,
            height: width,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // CoreGraphics has a bottom-left origin; the later call is applied to the point first.
        switch direction {
        case .clockwise:
            context.translateBy(x: 0, y: CGFloat(width))
            context.rotate(by: -.pi / 2)
        case .counterClockwise:
            context.translateBy(x: CGFloat(height), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
