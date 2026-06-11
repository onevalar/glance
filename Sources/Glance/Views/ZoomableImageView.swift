import AppKit
import SwiftUI

// MARK: - NSView: Image display with zoom & pan

final class GlanceImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var onStateChanged: ((CGFloat) -> Void)?
    var onClick: (() -> Void)?
    var isDarkMode = false
    
    var cropRect: CGRect? {
        didSet {
            hasPerformedInitialFit = false
            needsDisplay = true
        }
    }
    var isCropEditing = false {
        didSet {
            hasPerformedInitialFit = false
            needsDisplay = true
        }
    }

    var magnification: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }
    var offset: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    var onTransformChanged: ((CGFloat, CGPoint) -> Void)?
    private var hasPerformedInitialFit = false

    private let minMag: CGFloat = 0.1
    private let maxMag: CGFloat = 16.0

    // Pan state
    private var dragStartPoint: CGPoint = .zero
    private var dragStartOffset: CGPoint = .zero
    private var isPotentialClick = false

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, !hasPerformedInitialFit {
            DispatchQueue.main.async { [weak self] in
                self?.fitToWindow()
            }
        }
    }

    override func layout() {
        super.layout()
        if !hasPerformedInitialFit, bounds.width > 0, bounds.height > 0 {
            fitToWindow()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let fillColor: NSColor = isDarkMode
            ? NSColor(white: 0.15, alpha: 1.0)
            : NSColor(white: 0.9, alpha: 1.0)
        fillColor.setFill()
        bounds.fill()

        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()

        // Get sizes to draw
        let srcRect: NSRect
        let dstRect: NSRect
        
        if let crop = cropRect, !isCropEditing {
            let fromX = crop.origin.x * image.size.width
            let fromY = (1.0 - crop.origin.y - crop.height) * image.size.height
            let fromW = crop.width * image.size.width
            let fromH = crop.height * image.size.height
            
            srcRect = NSRect(x: fromX, y: fromY, width: fromW, height: fromH)
            dstRect = NSRect(x: -fromW / 2, y: -fromH / 2, width: fromW, height: fromH)
        } else {
            srcRect = NSRect(origin: .zero, size: image.size)
            dstRect = NSRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height)
        }

        // Transform: center in view → apply pan offset → scale
        let cx = bounds.width / 2 + offset.x
        let cy = bounds.height / 2 + offset.y
        context.translateBy(x: cx, y: cy)
        context.scaleBy(x: magnification, y: magnification)

        // Draw image section
        image.draw(in: dstRect, from: srcRect, operation: .sourceOver, fraction: 1.0)

        context.restoreGState()
    }

    // MARK: - Scroll Wheel (Command + scroll = zoom)

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }

        let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.1 : 0.9
        let newMag = (magnification * factor).clamped(to: minMag...maxMag)
        guard newMag != magnification else { return }

        let scaleRatio = newMag / magnification

        // Mouse position in this view's coordinate system (bottom-left origin)
        let mouseInView = convert(event.locationInWindow, from: nil)

        // Convert to center-relative coordinates
        let mouseCenteredX = mouseInView.x - bounds.width / 2
        let mouseCenteredY = mouseInView.y - bounds.height / 2

        // Compute new offset such that the pixel under the mouse stays fixed
        let newOffsetX = (offset.x - mouseCenteredX) * scaleRatio + mouseCenteredX
        let newOffsetY = (offset.y - mouseCenteredY) * scaleRatio + mouseCenteredY

        magnification = newMag
        offset = CGPoint(x: newOffsetX, y: newOffsetY)

        needsDisplay = true
        onStateChanged?(magnification)
        onTransformChanged?(magnification, offset)
    }

    // MARK: - Magnify Gesture (trackpad pinch-to-zoom)

    override func magnify(with event: NSEvent) {
        // magnification is the delta since the last event, apply directly
        let factor = 1 + event.magnification
        let newMag = (magnification * factor).clamped(to: minMag...maxMag)
        guard newMag != magnification else { return }

        let scaleRatio = newMag / magnification

        let mouseInView = convert(event.locationInWindow, from: nil)
        let mouseCenteredX = mouseInView.x - bounds.width / 2
        let mouseCenteredY = mouseInView.y - bounds.height / 2

        let newOffsetX = (offset.x - mouseCenteredX) * scaleRatio + mouseCenteredX
        let newOffsetY = (offset.y - mouseCenteredY) * scaleRatio + mouseCenteredY

        magnification = newMag
        offset = CGPoint(x: newOffsetX, y: newOffsetY)
        needsDisplay = true
        onStateChanged?(magnification)
        onTransformChanged?(magnification, offset)
    }

    // MARK: - Mouse Drag (pan)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStartPoint = point
        dragStartOffset = offset
        isPotentialClick = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - dragStartPoint.x
        let dy = point.y - dragStartPoint.y

        if abs(dx) > 3 || abs(dy) > 3 {
            isPotentialClick = false
        }

        let newOffsetX = dragStartOffset.x + dx
        let newOffsetY = dragStartOffset.y + dy

        guard newOffsetX.isFinite, newOffsetY.isFinite else { return }

        offset = CGPoint(x: newOffsetX, y: newOffsetY)
        needsDisplay = true
        onTransformChanged?(magnification, offset)
    }

    override func mouseUp(with event: NSEvent) {
        if isPotentialClick {
            onClick?()
        }
        isPotentialClick = false
    }

    // MARK: - Fit to Window

    func fitToWindow() {
        guard let image else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        let targetSize: NSSize
        if let crop = cropRect, !isCropEditing {
            targetSize = NSSize(width: crop.width * image.size.width, height: crop.height * image.size.height)
        } else {
            targetSize = image.size
        }

        let fitMag = min(
            bounds.width / targetSize.width,
            bounds.height / targetSize.height
        )
        magnification = fitMag
        offset = .zero
        hasPerformedInitialFit = true
        needsDisplay = true

        onStateChanged?(magnification)
        onTransformChanged?(magnification, offset)
    }

    // MARK: - Toolbar Zoom Actions

    func zoomIn() {
        zoomAtCenter(factor: 1.25)
    }

    func zoomOut() {
        zoomAtCenter(factor: 0.8)
    }

    private func zoomAtCenter(factor: CGFloat) {
        let newMag = (magnification * factor).clamped(to: minMag...maxMag)
        guard newMag != magnification else { return }

        let scaleRatio = newMag / magnification
        magnification = newMag
        offset.x = offset.x * scaleRatio
        offset.y = offset.y * scaleRatio
        needsDisplay = true
        onStateChanged?(magnification)
        onTransformChanged?(magnification, offset)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - NSViewRepresentable bridge

struct GlanceImageRepresentable: NSViewRepresentable {
    let image: NSImage?
    let isDarkMode: Bool
    
    // Crop state properties
    var cropRect: CGRect? = nil
    var isCropEditing: Bool = false
    
    // Sharing binding state
    var sharedMagnification: Binding<CGFloat>? = nil
    var sharedOffset: Binding<CGPoint>? = nil
    var isShared: Bool = false
    
    var onStateChanged: ((CGFloat) -> Void)?
    var onViewCreated: ((GlanceImageView) -> Void)?
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> GlanceImageView {
        let view = GlanceImageView()
        view.image = image
        view.isDarkMode = isDarkMode
        view.cropRect = cropRect
        view.isCropEditing = isCropEditing
        view.onStateChanged = onStateChanged
        view.onClick = onClick
        
        if isShared, let sharedMag = sharedMagnification, let sharedOff = sharedOffset {
            view.magnification = sharedMag.wrappedValue
            view.offset = sharedOff.wrappedValue
            view.onTransformChanged = { mag, off in
                DispatchQueue.main.async {
                    if sharedMag.wrappedValue != mag { sharedMag.wrappedValue = mag }
                    if sharedOff.wrappedValue != off { sharedOff.wrappedValue = off }
                }
            }
        }
        
        DispatchQueue.main.async {
            onViewCreated?(view)
        }
        return view
    }

    func updateNSView(_ nsView: GlanceImageView, context: Context) {
        nsView.image = image
        nsView.isDarkMode = isDarkMode
        
        // Update crop properties first, so if they change it triggers redraw/re-layout
        if nsView.isCropEditing != isCropEditing {
            nsView.isCropEditing = isCropEditing
        }
        if nsView.cropRect != cropRect {
            nsView.cropRect = cropRect
        }
        
        nsView.onStateChanged = onStateChanged
        nsView.onClick = onClick
        
        if isShared, let sharedMag = sharedMagnification, let sharedOff = sharedOffset {
            if nsView.magnification != sharedMag.wrappedValue {
                nsView.magnification = sharedMag.wrappedValue
            }
            if nsView.offset != sharedOff.wrappedValue {
                nsView.offset = sharedOff.wrappedValue
            }
            nsView.onTransformChanged = { mag, off in
                DispatchQueue.main.async {
                    if sharedMag.wrappedValue != mag { sharedMag.wrappedValue = mag }
                    if sharedOff.wrappedValue != off { sharedOff.wrappedValue = off }
                }
            }
        }
    }
}

// MARK: - SwiftUI Wrapper

struct ZoomableImageView: View {
    @Environment(\.colorScheme) private var colorScheme

    let image: NSImage?
    
    // Crop state properties
    var cropRect: CGRect? = nil
    var isCropEditing: Bool = false
    
    // Sharing binding state
    var sharedMagnification: Binding<CGFloat>? = nil
    var sharedOffset: Binding<CGPoint>? = nil
    var isShared: Bool = false

    var onScaleChanged: ((CGFloat) -> Void)?
    var onViewCreated: ((GlanceImageView) -> Void)?
    var onClick: (() -> Void)?

    var body: some View {
        GlanceImageRepresentable(
            image: image,
            isDarkMode: colorScheme == .dark,
            cropRect: cropRect,
            isCropEditing: isCropEditing,
            sharedMagnification: sharedMagnification,
            sharedOffset: sharedOffset,
            isShared: isShared,
            onStateChanged: onScaleChanged,
            onViewCreated: onViewCreated,
            onClick: onClick
        )
    }
}

#Preview {
    ZoomableImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil))
        .background(Color.gray)
}
