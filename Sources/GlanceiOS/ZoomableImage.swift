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

/// Pinch to zoom, drag to pan, double-tap to toggle zoom. Built on `UIScrollView`,
/// which gives the native feel (inertia, rubber-banding) that a SwiftUI gesture can't match.
///
/// While the photo is fitted (not zoomed), dragging it up or down is a rating gesture:
/// the photo follows the finger with a rubber band and a release past the threshold commits.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var pixelSize: CGSize = .zero { didSet { if oldValue != pixelSize { needsFit = true } } }
    var onZoomChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?
    var onZoomedIn: (() -> Void)?

    /// Rating by vertical drag while the photo is fitted: `offset` > 0 is dragged up (stars),
    /// < 0 dragged down (trash); `xFraction` is where the finger is across the screen (0…1), which picks the star.
    var ratingGesturesEnabled = true
    var onVerticalDrag: ((_ offset: CGFloat, _ xFraction: CGFloat) -> Void)?
    var onVerticalCommit: ((_ direction: Int, _ xFraction: CGFloat) -> Void)?

    var syncHub: CompareSyncHub? { didSet { syncHub?.register(self, id: syncID) } }
    var syncID = ""

    private static let commitDistance: CGFloat = 70

    private var needsFit = true
    private var lastBoundsSize: CGSize = .zero
    private var didReportZoomedIn = false
    private var applyingSync = false

    private var isFitted: Bool { zoomScale <= 1.01 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        decelerationRate = .fast
        // Vertical rubber band is the rating gesture; horizontal drags fall through to the pager.
        alwaysBounceVertical = true
        alwaysBounceHorizontal = false
        isDirectionalLockEnabled = true

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

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if needsFit || bounds.size != lastBoundsSize {
            fitImage()
        }
        centerImage()
    }

    /// Lays the picture out at "fit to screen" size, which is zoom scale 1.
    private func fitImage() {
        needsFit = false
        lastBoundsSize = bounds.size
        guard bounds.width > 0, bounds.height > 0, pixelSize.width > 0, pixelSize.height > 0 else { return }

        zoomScale = 1
        let ratio = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let fitted = CGSize(width: pixelSize.width * ratio, height: pixelSize.height * ratio)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted

        // Allow zooming in to at least 100% of the original pixels (focus / detail checks).
        let screenScale = traitCollection.displayScale
        let actualPixels = pixelSize.width / (fitted.width * screenScale)
        minimumZoomScale = 1
        maximumZoomScale = min(max(actualPixels, 4), 20)
        didReportZoomedIn = false
        onZoomChange?(false)
        if let last = syncHub?.last, syncHub?.isEnabled == true { applySync(zoom: last.zoom, center: last.center) }
    }

    private func centerImage() {
        var frame = imageView.frame
        frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
        imageView.frame = frame
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        onZoomChange?(zoomScale > 1.01)
        if zoomScale > 1.3, !didReportZoomedIn {
            didReportZoomedIn = true
            onZoomedIn?()
        }
        broadcastTransform()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if ratingGesturesEnabled, isFitted, isDragging || isDecelerating {
            onVerticalDrag?(contentOffset.y, fingerFraction())
        }
        broadcastTransform()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard ratingGesturesEnabled, isFitted else { return }
        let offset = contentOffset.y
        let fraction = fingerFraction()
        let flickedUp = velocity.y > 0.9 && offset > 20
        let flickedDown = velocity.y < -0.9 && offset < -20
        if offset > Self.commitDistance || flickedUp {
            onVerticalCommit?(1, fraction)
        } else if offset < -Self.commitDistance || flickedDown {
            onVerticalCommit?(-1, fraction)
        }
        onVerticalDrag?(0, fraction)
    }

    /// Horizontal finger position across the window, 0…1.
    private func fingerFraction() -> CGFloat {
        let width = window?.bounds.width ?? bounds.width
        guard width > 0 else { return 0.5 }
        return (panGestureRecognizer.location(in: nil).x / width).clamped(to: 0...1)
    }

    /// The photo drops away (into the trash that rises from the bottom) before it is replaced.
    func playDiscardFall() {
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            self.transform = CGAffineTransform(translationX: 0, y: self.bounds.height * 0.32).scaledBy(x: 0.22, y: 0.22)
            self.alpha = 0
        } completion: { _ in
            // Ready again in case the same page stays on screen.
            UIView.performWithoutAnimation {
                self.transform = .identity
                self.alpha = 1
            }
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
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            let target = min(3, maximumZoomScale)
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
    var onVerticalDrag: (CGFloat, CGFloat) -> Void = { _, _ in }
    var onVerticalCommit: (Int, CGFloat) -> Void = { _, _ in }
    /// Bumped to run the discard "fall" animation on this photo.
    var discardFallToken = 0

    final class Coordinator { var lastFallToken = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

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
        view.onVerticalDrag = onVerticalDrag
        view.onVerticalCommit = onVerticalCommit
        if context.coordinator.lastFallToken != discardFallToken {
            context.coordinator.lastFallToken = discardFallToken
            if discardFallToken > 0 { view.playDiscardFall() }
        }
        view.ratingGesturesEnabled = ratingGesturesEnabled
        view.pixelSize = pixelSize
        if view.imageView.image !== image {
            view.imageView.image = image
        }
    }
}
