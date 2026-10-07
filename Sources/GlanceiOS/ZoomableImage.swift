//
//  ZoomableImage.swift
//  Glance (iPhone / iPad)
//

import SwiftUI
import UIKit

/// Pinch to zoom, drag to pan, double-tap to toggle zoom. Built on `UIScrollView`,
/// which gives the native feel (inertia, rubber-banding) that a SwiftUI gesture can't match.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var pixelSize: CGSize = .zero { didSet { if oldValue != pixelSize { needsFit = true } } }
    var onZoomChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?
    var onZoomedIn: (() -> Void)?

    private var needsFit = true
    private var lastBoundsSize: CGSize = .zero
    private var didReportZoomedIn = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        decelerationRate = .fast

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

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    /// Pixel size of the original; the layout is based on it so a sharper image can be swapped in later.
    let pixelSize: CGSize
    var onZoomChange: (Bool) -> Void
    var onSingleTap: () -> Void
    var onZoomedIn: () -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.onZoomChange = onZoomChange
        view.onSingleTap = onSingleTap
        view.onZoomedIn = onZoomedIn
        view.pixelSize = pixelSize
        if view.imageView.image !== image {
            view.imageView.image = image
        }
    }
}
