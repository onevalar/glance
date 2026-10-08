import Foundation

enum CropRatio: String, CaseIterable, Identifiable {
    case free = "自由比例", square = "1:1", fourThree = "4:3", sixteenNine = "16:9", twoThree = "2:3"
    var id: String { rawValue }
    var value: CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4 / 3
        case .sixteenNine: 16 / 9
        case .twoThree: 2 / 3
        }
    }
}

enum CropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    var direction: CGPoint {
        switch self {
        case .topLeft: CGPoint(x: -1, y: -1)
        case .top: CGPoint(x: 0, y: -1)
        case .topRight: CGPoint(x: 1, y: -1)
        case .right: CGPoint(x: 1, y: 0)
        case .bottomRight: CGPoint(x: 1, y: 1)
        case .bottom: CGPoint(x: 0, y: 1)
        case .bottomLeft: CGPoint(x: -1, y: 1)
        case .left: CGPoint(x: -1, y: 0)
        }
    }
    var isCorner: Bool { direction.x != 0 && direction.y != 0 }
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: direction.x < 0 ? rect.minX : direction.x > 0 ? rect.maxX : rect.midX,
                y: direction.y < 0 ? rect.minY : direction.y > 0 ? rect.maxY : rect.midY)
    }
}

/// A draft uses top-left coordinates relative to the original image, independent of the window.
/// Only the editor's Done action writes this value to metadata.
struct CropSession {
    static let fullImage = CGRect(x: 0, y: 0, width: 1, height: 1)
    private(set) var rect: CGRect
    private(set) var ratio: CropRatio = .free

    init(rect: CGRect?) { self.rect = CropGeometry.validated(rect) }

    mutating func reset() { rect = Self.fullImage; ratio = .free }

    mutating func selectRatio(_ ratio: CropRatio, imageSize: CGSize) {
        self.ratio = ratio
        guard let value = ratio.value, imageSize.width > 0, imageSize.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite else { return }
        // A square on screen is usually not a square in normalized image coordinates.
        let normalizedRatio = value * imageSize.height / imageSize.width
        rect = CropGeometry.applyingRatio(normalizedRatio, to: rect, in: Self.fullImage)
    }

    func displayRect(in imageFrame: CGRect) -> CGRect {
        CGRect(x: imageFrame.minX + rect.minX * imageFrame.width,
               y: imageFrame.minY + rect.minY * imageFrame.height,
               width: rect.width * imageFrame.width, height: rect.height * imageFrame.height)
    }

    mutating func update(displayRect: CGRect, imageFrame: CGRect) {
        guard CropGeometry.isUsable(imageFrame), CropGeometry.isUsable(displayRect) else { return }
        rect = CropGeometry.validated(CGRect(x: (displayRect.minX - imageFrame.minX) / imageFrame.width,
                                             y: (displayRect.minY - imageFrame.minY) / imageFrame.height,
                                             width: displayRect.width / imageFrame.width,
                                             height: displayRect.height / imageFrame.height))
    }
}

enum CropGeometry {
    static func isUsable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }

    static func validated(_ rect: CGRect?) -> CGRect {
        guard let rect, isUsable(rect) else { return CropSession.fullImage }
        let clipped = rect.intersection(CropSession.fullImage)
        return isUsable(clipped) ? clipped : CropSession.fullImage
    }

    static func imageFrame(imageSize: CGSize, viewport: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewport.width > 0, viewport.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite, viewport.width.isFinite, viewport.height.isFinite else { return .zero }
        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Keep the requested ratio and size; translate at the boundary instead of clipping the box.
    static func applyingRatio(_ ratio: CGFloat, to box: CGRect, in bounds: CGRect) -> CGRect {
        guard ratio.isFinite, ratio > 0, isUsable(box), isUsable(bounds) else { return box }
        let width = min(box.width, bounds.width, bounds.height * ratio)
        let height = width / ratio
        return CGRect(x: clamp(box.midX - width / 2, bounds.minX, bounds.maxX - width),
                      y: clamp(box.midY - height / 2, bounds.minY, bounds.maxY - height),
                      width: width, height: height)
    }

    static func moved(_ box: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        guard delta.width.isFinite, delta.height.isFinite else { return box }
        return CGRect(x: clamp(box.minX + delta.width, bounds.minX, bounds.maxX - box.width),
                      y: clamp(box.minY + delta.height, bounds.minY, bounds.maxY - box.height),
                      width: box.width, height: box.height)
    }

    /// Deltas use the fixed canvas coordinate space and the rectangle captured at gesture start.
    static func resized(_ box: CGRect, handle: CropHandle, by delta: CGSize, in bounds: CGRect,
                        ratio: CGFloat?, minimumSize: CGFloat = 40) -> CGRect {
        guard isUsable(box), isUsable(bounds), delta.width.isFinite, delta.height.isFinite else { return box }
        if delta == .zero { return box }
        let direction = handle.direction
        let corner = handle.point(in: box)
        let anchor = CGPoint(x: direction.x < 0 ? box.maxX : box.minX,
                             y: direction.y < 0 ? box.maxY : box.minY)
        let availableW = direction.x < 0 ? anchor.x - bounds.minX : bounds.maxX - anchor.x
        let availableH = direction.y < 0 ? anchor.y - bounds.minY : bounds.maxY - anchor.y
        var width = direction.x == 0 ? box.width : clamp(direction.x * (corner.x + delta.width - anchor.x), min(minimumSize, availableW), availableW)
        var height = direction.y == 0 ? box.height : clamp(direction.y * (corner.y + delta.height - anchor.y), min(minimumSize, availableH), availableH)
        if let ratio, ratio.isFinite, ratio > 0, handle.isCorner {
            // Project onto the ratio diagonal; either drag axis can change the size.
            let projectedW = (ratio * ratio * width + ratio * height) / (ratio * ratio + 1)
            let maximumW = min(availableW, availableH * ratio)
            let minimumW = min(maximumW, max(minimumSize, minimumSize * ratio))
            width = clamp(projectedW, minimumW, maximumW)
            height = width / ratio
        }
        return CGRect(x: direction.x < 0 ? anchor.x - width : box.minX,
                      y: direction.y < 0 ? anchor.y - height : box.minY, width: width, height: height)
    }

    private static func clamp(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        max(minimum, min(maximum, value))
    }
}
