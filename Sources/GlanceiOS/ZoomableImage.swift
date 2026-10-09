//
//  ZoomableImage.swift
//  Glance (iPhone / iPad)
//

import SwiftUI
import UIKit

/// Keeps several zooming photos aligned on the same spot (comparison screen).
/// Views register themselves; a change in one is applied directly to the others.
final class CompareSyncHub {
    private struct Entry { weak var view: ZoomingScrollView?; let id: String }
    private var entries: [Entry] = []
    var isEnabled = true
    /// Latest shared state, applied to photos that scroll into view later (long comparisons).
    private(set) var last: (zoom: CGFloat, center: CGPoint)?

    func register(_ view: ZoomingScrollView, id: String) {
        entries.removeAll { $0.view == nil || $0.id == id }
        entries.append(Entry(view: view, id: id))
    }

    func broadcast(from id: String, zoom: CGFloat, center: CGPoint) {
        guard isEnabled else { return }
        last = (zoom, center)
        for entry in entries where entry.id != id {
            entry.view?.applySync(zoom: zoom, center: center)
        }
    }
}

/// A pan that only starts for vertical movement, so horizontal swipes still turn the page.
final class VerticalPanGestureRecognizer: UIPanGestureRecognizer {
    private var startPoint: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        startPoint = touches.first?.location(in: view) ?? .zero
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let point = touches.first?.location(in: view) {
            // Measured by hand from the touch itself, and nothing is passed on to the pan until the direction is
            // known: otherwise a slow drag can start the pan after a few points, before it is clear it is sideways.
            let dx = point.x - startPoint.x, dy = point.y - startPoint.y
            guard abs(dx) > 12 || abs(dy) > 12 else { return }
            // Decide once: only a movement that is clearly vertical (within about 25° of straight up/down)
            // starts a pull. Everything else belongs to paging and zooming, so a sideways swipe with a little
            // vertical drift can never rate or discard by accident.
            if abs(dy) < abs(dx) * 2.2 { state = .failed; return }
        }
        super.touchesMoved(touches, with: event)
    }
}

/// Pinch to zoom, drag to pan, double-tap to toggle zoom. Built on `UIScrollView`,
/// which gives the native feel (inertia, rubber-banding) that a SwiftUI gesture can't match.
///
/// The view covers the whole screen. At rest the photo is fitted inside `fitInsets` (clear of the bars); zooming
/// in lets it use the whole screen, so there is never an invisible edge in the way.
///
/// While the photo is fitted, a clearly vertical drag is handed to `onPull` (rating / discarding).
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    var pixelSize: CGSize = .zero { didSet { if oldValue != pixelSize { needsFit = true; setNeedsLayout() } } }
    var onZoomChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?
    var onZoomedIn: (() -> Void)?

    /// Space kept free around the photo when it is not zoomed (the bars), in this view's coordinates.
    var fitInsets: UIEdgeInsets = .zero {
        didSet { if oldValue != fitInsets { updateMinimumZoom(animated: window != nil) } }
    }

    var ratingGesturesEnabled = true
    /// A vertical drag on the fitted photo (state, location and velocity are read from the recognizer).
    var onPull: ((UIPanGestureRecognizer) -> Void)?

    var syncHub: CompareSyncHub? { didSet { syncHub?.register(self, id: syncID) } }
    var syncID = ""

    private let pullPan = VerticalPanGestureRecognizer()

    /// Opacity the photo returns to after an animation (dimmed while it is in the discard pile).
    var restingAlpha: CGFloat = 1
    private var needsFit = true
    private var lastBoundsSize: CGSize = .zero
    private var didReportZoomedIn = false
    private var applyingSync = false
    /// The fit is being changed by the app (bars shown / hidden), not by the user: not a zoom.
    private var fitAdjustments = 0
    private var adjustingFit: Bool { fitAdjustments > 0 }
    private var reportedZoomed = false

    /// Not zoomed in: the photo is at its resting size.
    var isFitted: Bool { zoomScale <= minimumZoomScale + 0.01 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        decelerationRate = .fast
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        isDirectionalLockEnabled = true

        pullPan.addTarget(self, action: #selector(handlePull(_:)))
        pullPan.maximumNumberOfTouches = 1
        pullPan.delegate = self
        addGestureRecognizer(pullPan)

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Called when a pager cell is recycled for another photo.
    func resetForReuse() {
        // Resetting the scale is not the user zooming.
        fitAdjustments += 1
        defer { fitAdjustments -= 1 }
        layer.removeAllAnimations()
        imageView.layer.removeAllAnimations()
        imageView.alpha = 1
        imageView.isHidden = false
        imageView.image = nil
        transform = .identity
        minimumZoomScale = 1
        zoomScale = 1
        contentOffset = .zero
        didReportZoomedIn = false
        if reportedZoomed { onZoomChange?(false) }
        reportedZoomed = false
        needsFit = true
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if needsFit || bounds.size != lastBoundsSize {
            fitImage()
        }
        centerImage()
    }

    /// Zoom scale 1 is the photo fitted to the whole view; the resting (minimum) scale fits it inside `fitInsets`.
    private func fitImage() {
        needsFit = false
        lastBoundsSize = bounds.size
        guard bounds.width > 0, bounds.height > 0, pixelSize.width > 0, pixelSize.height > 0 else { return }
        fitAdjustments += 1
        defer { fitAdjustments -= 1 }

        minimumZoomScale = 1
        zoomScale = 1
        let ratio = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let fitted = CGSize(width: pixelSize.width * ratio, height: pixelSize.height * ratio)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted

        // Allow zooming in to at least 100% of the original pixels (focus / detail checks).
        let screenScale = traitCollection.displayScale
        let actualPixels = pixelSize.width / (fitted.width * screenScale)
        maximumZoomScale = min(max(actualPixels, 4), 20)
        let resting = restingScale()
        minimumZoomScale = resting
        zoomScale = resting
        didReportZoomedIn = false
        report(zoomed: false)
        if let last = syncHub?.last, syncHub?.isEnabled == true { applySync(zoom: last.zoom, center: last.center) }
    }

    /// The scale (relative to the full-view fit) at which the photo fits inside `fitInsets`.
    private func restingScale() -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        let available = bounds.inset(by: fitInsets)
        guard available.width > 60, available.height > 60 else { return 1 }
        let full = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let inset = min(available.width / pixelSize.width, available.height / pixelSize.height)
        return min(inset / full, 1)
    }

    /// The bars appeared or went away: a resting photo smoothly takes the new room; a zoomed one stays as it is.
    private func updateMinimumZoom(animated: Bool) {
        guard !needsFit, pixelSize.width > 0, bounds.width > 0 else { setNeedsLayout(); return }
        let wasFitted = isFitted
        let resting = restingScale()
        guard abs(resting - minimumZoomScale) > 0.0001 else { centerImage(); return }
        fitAdjustments += 1
        let apply = {
            self.minimumZoomScale = resting
            if wasFitted || self.zoomScale < resting { self.zoomScale = resting }
            self.centerImage()
        }
        if animated {
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: apply) { _ in
                self.fitAdjustments -= 1
            }
        } else {
            apply()
            fitAdjustments -= 1
        }
    }

    /// Centres the photo inside the free area between the bars while it is small enough, inside the whole view
    /// as it grows, and lets it scroll edge to edge once it is larger than the screen.
    private func centerImage() {
        var frame = imageView.frame
        frame.origin.x = Self.leading(content: frame.width, length: bounds.width, lead: fitInsets.left, trail: fitInsets.right)
        frame.origin.y = Self.leading(content: frame.height, length: bounds.height, lead: fitInsets.top, trail: fitInsets.bottom)
        imageView.frame = frame
    }

    private static func leading(content: CGFloat, length: CGFloat, lead: CGFloat, trail: CGFloat) -> CGFloat {
        guard content < length else { return 0 }
        let free = length - content
        if free >= lead + trail { return lead + (free - lead - trail) / 2 }
        let total = lead + trail
        return total > 0 ? free * lead / total : free / 2
    }

    private func report(zoomed: Bool) {
        guard zoomed != reportedZoomed else { return }
        reportedZoomed = zoomed
        onZoomChange?(zoomed)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        if !adjustingFit { report(zoomed: !isFitted) }
        if zoomScale > 1.3, !didReportZoomedIn {
            didReportZoomedIn = true
            onZoomedIn?()
        }
        broadcastTransform()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if !adjustingFit { report(zoomed: !isFitted) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        broadcastTransform()
    }

    // MARK: - Pulling up / down

    /// Never make the page-turning scroll view of the pager wait for (or be blocked by) the vertical pull.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pullPan
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pullPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        return ratingGesturesEnabled && onPull != nil && isFitted && imageView.image != nil
    }

    @objc private func handlePull(_ gesture: UIPanGestureRecognizer) {
        onPull?(gesture)
    }

    /// Hides the photo while its lifted copy is on the stage.
    func setLifted(_ lifted: Bool) {
        imageView.isHidden = lifted
    }

    /// Brings the photo back after it was lifted: instantly (it was put back in place) or fading in.
    func showAgain(animated: Bool) {
        imageView.isHidden = false
        guard animated else { imageView.alpha = restingAlpha; return }
        imageView.alpha = 0
        transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            self.imageView.alpha = self.restingAlpha
            self.transform = .identity
        }
    }

    // MARK: - Comparison sync

    private func currentCenterFraction() -> CGPoint {
        let frame = imageView.frame
        guard frame.width > 0, frame.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: (contentOffset.x + bounds.width / 2 - frame.minX) / frame.width,
            y: (contentOffset.y + bounds.height / 2 - frame.minY) / frame.height
        )
    }

    private func broadcastTransform() {
        guard !applyingSync, let syncHub else { return }
        syncHub.broadcast(from: syncID, zoom: zoomScale, center: currentCenterFraction())
    }

    /// Follows another photo's zoom and focus point without echoing it back.
    func applySync(zoom: CGFloat, center: CGPoint) {
        applyingSync = true
        defer { applyingSync = false }
        let target = zoom.clamped(to: minimumZoomScale...maximumZoomScale)
        if abs(zoomScale - target) > 0.001 { setZoomScale(target, animated: false) }
        centerImage()
        let frame = imageView.frame
        var offset = CGPoint(
            x: frame.minX + center.x * frame.width - bounds.width / 2,
            y: frame.minY + center.y * frame.height - bounds.height / 2
        )
        offset.x = contentSize.width <= bounds.width ? 0 : offset.x.clamped(to: 0...(contentSize.width - bounds.width))
        offset.y = contentSize.height <= bounds.height ? 0 : offset.y.clamped(to: 0...(contentSize.height - bounds.height))
        setContentOffset(offset, animated: false)
    }

    // MARK: - Gestures

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if !isFitted {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let target = min(max(minimumZoomScale * 2.5, 2), maximumZoomScale)
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            zoom(to: rect, animated: true)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    /// Pixel size of the original; the layout is based on it so a sharper image can be swapped in later.
    let pixelSize: CGSize
    var ratingGesturesEnabled = true
    var syncHub: CompareSyncHub?
    var syncID = ""
    var onZoomChange: (Bool) -> Void
    var onSingleTap: () -> Void
    var onZoomedIn: () -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.syncID = syncID
        view.syncHub = syncHub
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.onZoomChange = onZoomChange
        view.onSingleTap = onSingleTap
        view.onZoomedIn = onZoomedIn

        view.ratingGesturesEnabled = ratingGesturesEnabled
        view.pixelSize = pixelSize
        if view.imageView.image !== image {
            view.imageView.image = image
        }
    }
}
