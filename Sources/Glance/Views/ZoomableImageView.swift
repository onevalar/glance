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
        didSet { resetFit() }
    }
    var isCropEditing = false {
        didSet { resetFit() }
    }

    var magnification: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }
    var offset: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    /// Compare mode: reports (zoom relative to this view's own fit, pan as a fraction of the zoomed picture),
    /// so pictures of different sizes stay aligned on the same relative spot.
    var onTransformChanged: ((CGFloat, CGPoint) -> Void)?
    var isShared = false
    private var sharedState: (zoom: CGFloat, pan: CGPoint) = (1, .zero)
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
                self?.performInitialFitIfNeeded()
            }
        }
    }

    override func layout() {
        super.layout()
        performInitialFitIfNeeded()
    }

    private func performInitialFitIfNeeded() {
        guard !hasPerformedInitialFit, bounds.width > 0, bounds.height > 0 else { return }
        if isShared {
            // Compare mode owns the zoom: follow the shared state instead of resetting it.
            hasPerformedInitialFit = true
            applyShared(zoom: sharedState.zoom, pan: sharedState.pan)
        } else {
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
        // The crop frame is laid out for the fitted picture, so the view must stay put while cropping.
        guard !isCropEditing, event.modifierFlags.contains(.command) else {
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
        notifyTransform()
    }

    // MARK: - Magnify Gesture (trackpad pinch-to-zoom)

    override func magnify(with event: NSEvent) {
        guard !isCropEditing else { return }
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
        notifyTransform()
    }

    // MARK: - Mouse Drag (pan)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStartPoint = point
        dragStartOffset = offset
        isPotentialClick = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isCropEditing else { return }
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
        notifyTransform()
    }

    override func mouseUp(with event: NSEvent) {
        if isPotentialClick {
            onClick?()
        }
        isPotentialClick = false
    }

    // MARK: - Fit to Window

    /// Schedules a fit-to-window on the next layout pass.
    func resetFit() {
        hasPerformedInitialFit = false
        needsLayout = true
        needsDisplay = true
    }

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
        notifyTransform()
    }

    // MARK: - Compare mode

    /// Size of the picture region that is actually shown (respects the crop).
    private var targetSize: NSSize? {
        guard let image else { return nil }
        if let crop = cropRect, !isCropEditing {
            return NSSize(width: crop.width * image.size.width, height: crop.height * image.size.height)
        }
        return image.size
    }

    private var fitScale: CGFloat? {
        guard let size = targetSize, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }
        return min(bounds.width / size.width, bounds.height / size.height)
    }

    /// Follows the shared compare state without reporting back (avoids feedback loops).
    func applyShared(zoom: CGFloat, pan: CGPoint) {
        sharedState = (zoom, pan)
        guard let size = targetSize, let fit = fitScale else { return }
        let mag = (fit * zoom).clamped(to: minMag...maxMag)
        let scaleChanged = mag != magnification
        magnification = mag
        offset = CGPoint(x: pan.x * size.width * mag, y: pan.y * size.height * mag)
        if scaleChanged { onStateChanged?(magnification) }
    }

    private func notifyTransform() {
        guard let onTransformChanged else { return }
        if isShared {
            guard let size = targetSize, let fit = fitScale, magnification > 0 else { return }
            let pan = CGPoint(
                x: offset.x / (size.width * magnification),
                y: offset.y / (size.height * magnification)
            )
            sharedState = (magnification / fit, pan)
            onTransformChanged(magnification / fit, pan)
        } else {
            onTransformChanged(magnification, offset)
        }
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
        notifyTransform()
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
    var sharedZoom: Binding<CGFloat>? = nil
    var sharedPan: Binding<CGPoint>? = nil
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
        
        if isShared, let sharedZoom, let sharedPan {
            view.isShared = true
            view.onTransformChanged = Self.sharedUpdater(zoom: sharedZoom, pan: sharedPan)
        }
        
        DispatchQueue.main.async {
            onViewCreated?(view)
        }
        return view
    }

    func updateNSView(_ nsView: GlanceImageView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
            // Single-image mode: a new picture starts fitted to the window instead of
            // inheriting the previous picture's zoom and pan. Compare mode rebuilds its
            // NSImage instances on every render, so it must keep its shared transform.
            if !isShared {
                nsView.resetFit()
            }
        }
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
        
        if isShared, let sharedZoom, let sharedPan {
            nsView.isShared = true
            nsView.onTransformChanged = Self.sharedUpdater(zoom: sharedZoom, pan: sharedPan)
            nsView.applyShared(zoom: sharedZoom.wrappedValue, pan: sharedPan.wrappedValue)
        }
    }

    private static func sharedUpdater(zoom: Binding<CGFloat>, pan: Binding<CGPoint>) -> (CGFloat, CGPoint) -> Void {
        { newZoom, newPan in
            DispatchQueue.main.async {
                if zoom.wrappedValue != newZoom { zoom.wrappedValue = newZoom }
                if pan.wrappedValue != newPan { pan.wrappedValue = newPan }
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
    var sharedZoom: Binding<CGFloat>? = nil
    var sharedPan: Binding<CGPoint>? = nil
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
            sharedZoom: sharedZoom,
            sharedPan: sharedPan,
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
