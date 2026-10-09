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
            // Measured by hand from the touch itself: `translation` is only updated inside `super`, which may
            // already start the gesture on a fast first move.
            let dx = point.x - startPoint.x, dy = point.y - startPoint.y
            if abs(dx) > 12 || abs(dy) > 12 {
                // Decide once: only a movement that is clearly vertical (within about 25° of straight up/down)
                // starts a rating drag. Everything else belongs to paging and zooming, so a sideways swipe
                // with a little vertical drift can never rate or discard by accident.
                if abs(dy) < abs(dx) * 2.2 { state = .failed; return }
            }
        }
        super.touchesMoved(touches, with: event)
    }
}

/// Pinch to zoom, drag to pan, double-tap to toggle zoom. Built on `UIScrollView`,
/// which gives the native feel (inertia, rubber-banding) that a SwiftUI gesture can't match.
///
/// While the photo is fitted (not zoomed), dragging it up or down is the rating gesture. The photo is moved by
/// hand (not by scroll-view bounce): pulled down it shrinks into a rounded card that can be dropped in the
/// trash; pulled up it recedes while the stars appear. Releasing past the threshold commits.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    var pixelSize: CGSize = .zero { didSet { if oldValue != pixelSize { needsFit = true } } }
    var onZoomChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?
    var onZoomedIn: (() -> Void)?

    /// Rating by vertical drag while the photo is fitted: `offset` > 0 is dragged up (stars),
    /// < 0 dragged down (trash); `xFraction` is where the finger is across the screen (0…1), which picks the star.
    var ratingGesturesEnabled = true
    /// Window position of the trash opening; the discarded photo flies there.
    var trashTarget: (() -> CGPoint?)?
    var onVerticalDrag: ((_ offset: CGFloat, _ xFraction: CGFloat, _ yFraction: CGFloat) -> Void)?
    /// `direction` -1 = released far enough down (trash), +1 = released after pulling up (stars): the receiver
    /// decides from the finger position whether a star was chosen.
    var onVerticalCommit: ((_ direction: Int, _ xFraction: CGFloat, _ yFraction: CGFloat) -> Void)?

    var syncHub: CompareSyncHub? { didSet { syncHub?.register(self, id: syncID) } }
    var syncID = ""

    /// Movement that is ignored before anything reacts, so a small drift never shows the stars or the trash.
    private static let deadZone: CGFloat = 26
    private static let commitDistance: CGFloat = 130
    private let ratingPan = VerticalPanGestureRecognizer()

    /// Opacity the photo returns to after an animation (dimmed while it is in the discard pile).
    var restingAlpha: CGFloat = 1
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
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        isDirectionalLockEnabled = true

        ratingPan.addTarget(self, action: #selector(handleRatingPan(_:)))
        ratingPan.maximumNumberOfTouches = 1
        ratingPan.delegate = self
        addGestureRecognizer(ratingPan)

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
        layer.removeAllAnimations()
        layer.sublayerTransform = CATransform3DIdentity
        imageView.layer.removeAllAnimations()
        imageView.layer.cornerRadius = 0
        imageView.alpha = 1
        imageView.image = nil
        imageView.transform = .identity
        zoomScale = 1
        contentOffset = .zero
        didReportZoomedIn = false
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
        broadcastTransform()
    }

    // MARK: - Rating drag (up = stars, down = trash)

    /// Never make the page-turning scroll view of the pager wait for (or be blocked by) the vertical rating pan.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === ratingPan
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === ratingPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        return ratingGesturesEnabled && isFitted
    }

    /// Horizontal finger position across the window, 0…1.
    private func fingerFraction(_ gesture: UIGestureRecognizer) -> CGPoint {
        let size = window?.bounds.size ?? bounds.size
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let point = gesture.location(in: nil)
        return CGPoint(x: (point.x / size.width).clamped(to: 0...1), y: (point.y / size.height).clamped(to: 0...1))
    }

    @objc private func handleRatingPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let finger = fingerFraction(gesture)
        switch gesture.state {
        case .began, .changed:
            layer.removeAnimation(forKey: "dragTransform")
            imageView.layer.removeAnimation(forKey: "dragCorner")
            // Nothing moves or shows until the finger has travelled past the dead zone.
            let beyond = max(0, abs(translation.y) - Self.deadZone) * (translation.y < 0 ? -1 : 1)
            applyDragVisuals(pull: beyond)
            onVerticalDrag?(-beyond, finger.x, finger.y)
        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: self).y
            let down = translation.y
            let up = -translation.y
            var direction = 0
            if gesture.state == .ended {
                if down > Self.commitDistance || (velocity > 1400 && down > 80) { direction = -1 }
                else if up > Self.deadZone + 40 { direction = 1 }
            }
            if direction != -1 { onVerticalDrag?(0, finger.x, finger.y) }
            switch direction {
            case -1:
                // The trash stays on screen until the photo has gone into it.
                dropIntoTrash { [weak self] in
                    self?.onVerticalCommit?(-1, finger.x, finger.y)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        guard let self, self.ratingPan.state == .possible else { return }
                        self.onVerticalDrag?(0, finger.x, finger.y)
                    }
                }
            case 1:
                springBack()
                onVerticalCommit?(1, finger.x, finger.y)
            default:
                springBack()
            }
        default:
            break
        }
    }

    /// `pull` > 0 drags the photo down (it shrinks into a rounded card), < 0 drags it up (it recedes a little).
    private func applyDragVisuals(pull: CGFloat) {
        let progress = min(abs(pull) / (Self.commitDistance - Self.deadZone), 1)
        let scale: CGFloat
        let translationY: CGFloat
        if pull >= 0 {
            scale = 1 - 0.40 * progress
            translationY = pull * 0.92
        } else {
            scale = 1 - 0.06 * progress
            translationY = pull * 0.55
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = CATransform3DScale(CATransform3DMakeTranslation(0, translationY, 0), scale, scale, 1)
        imageView.layer.cornerRadius = pull > 0 ? 24 * progress : 0
        imageView.layer.masksToBounds = pull > 0
        CATransaction.commit()
    }

    private func springBack() {
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        let spring = CASpringAnimation(keyPath: "sublayerTransform")
        spring.fromValue = from
        spring.toValue = CATransform3DIdentity
        spring.damping = 15
        spring.stiffness = 260
        spring.mass = 1
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        layer.sublayerTransform = CATransform3DIdentity
        layer.add(spring, forKey: "dragTransform")

        let corner = CABasicAnimation(keyPath: "cornerRadius")
        corner.fromValue = imageView.layer.presentation()?.cornerRadius ?? imageView.layer.cornerRadius
        corner.toValue = 0
        corner.duration = 0.25
        imageView.layer.cornerRadius = 0
        imageView.layer.add(corner, forKey: "dragCorner")
    }

    /// The photo, already a small card, drops toward the trash that has risen at the bottom and disappears.
    private func dropIntoTrash(completion: @escaping () -> Void) {
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        var dx: CGFloat = 0, dy = bounds.height * 0.40
        if window != nil, let point = trashTarget?() {
            let local = convert(point, from: nil)
            dx = local.x - bounds.midX
            dy = local.y - bounds.midY
        }
        var target = CATransform3DMakeTranslation(dx, dy, 0)
        target = CATransform3DRotate(target, 0.18, 0, 0, 1)
        target = CATransform3DScale(target, 0.10, 0.10, 1)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            completion()
            // Show the photo again (it may stay on screen with its "discarded" badge) after a beat.
            self?.imageView.alpha = 0
            self?.layer.removeAnimation(forKey: "dragTransform")
            self?.layer.sublayerTransform = CATransform3DIdentity
            self?.imageView.layer.cornerRadius = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                UIView.animate(withDuration: 0.25) { self?.imageView.alpha = self?.restingAlpha ?? 1 }
            }
        }
        let move = CABasicAnimation(keyPath: "sublayerTransform")
        move.fromValue = from
        move.toValue = target
        move.duration = 0.32
        move.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.sublayerTransform = target
        layer.add(move, forKey: "dragTransform")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.16
        fade.beginTime = CACurrentMediaTime() + 0.16      // stays visible until it is small, then vanishes into the opening
        fade.fillMode = .both
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        imageView.layer.opacity = 0
        imageView.layer.add(fade, forKey: "dropFade")
        CATransaction.commit()
        // Layer opacity is restored through `alpha` above; keep the model value in step.
        imageView.layer.opacity = 1
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
    var onVerticalDrag: (CGFloat, CGFloat, CGFloat) -> Void = { _, _, _ in }
    var onVerticalCommit: (Int, CGFloat, CGFloat) -> Void = { _, _, _ in }

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

        view.ratingGesturesEnabled = ratingGesturesEnabled
        view.pixelSize = pixelSize
        if view.imageView.image !== image {
            view.imageView.image = image
        }
    }
}
