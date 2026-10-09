//
//  ViewerView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// One photo: fitted to the available space, sharper original loaded once the user zooms in.
struct PhotoPage: View {
    let asset: PHAsset
    var ratingGesturesEnabled = true
    var syncHub: CompareSyncHub?
    var onZoomChange: (Bool) -> Void = { _ in }
    var onSingleTap: () -> Void = {}
    var onVerticalDrag: (CGFloat, CGFloat) -> Void = { _, _ in }
    var onVerticalCommit: (Int, CGFloat) -> Void = { _, _ in }

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedOriginal = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    ZoomableImage(
                        image: image,
                        pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                        ratingGesturesEnabled: ratingGesturesEnabled,
                        syncHub: syncHub,
                        syncID: asset.localIdentifier,
                        onZoomChange: onZoomChange,
                        onSingleTap: onSingleTap,
                        onZoomedIn: { Task { await loadOriginal() } },
                        onVerticalDrag: onVerticalDrag,
                        onVerticalCommit: onVerticalCommit
                    )
                } else {
                    ProgressView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: asset.localIdentifier) {
                loadedOriginal = false
                let target = CGSize(
                    width: max(proxy.size.width, 1) * displayScale,
                    height: max(proxy.size.height, 1) * displayScale
                )
                image = await PhotoImageLoader.image(for: asset, targetSize: target)
            }
        }
    }

    private func loadOriginal() async {
        guard !loadedOriginal else { return }
        loadedOriginal = true
        if let sharp = await PhotoImageLoader.image(for: asset, targetSize: PHImageManagerMaximumSize) {
            image = sharp
        }
    }
}

/// Horizontal paging through the visible photos, edge to edge.
struct ViewerPager: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isZoomed = false
    /// True while a photo is being pulled up / down: the finger also moves sideways to choose a star,
    /// and that must not turn the page.
    @State private var isRatingDrag = false

    var onSingleTap: () -> Void
    /// Vertical drag of the current photo: offset (> 0 up, < 0 down) and finger x across the screen (0…1).
    var onVerticalDrag: (CGFloat, CGFloat) -> Void
    /// Released past the threshold: +1 = up (stars), -1 = down (trash).
    var onVerticalCommit: (Int, CGFloat) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(store.visible, id: \.localIdentifier) { asset in
                    PhotoPage(
                        asset: asset,
                        onZoomChange: { zoomed in
                            if asset.localIdentifier == store.currentID { isZoomed = zoomed }
                        },
                        onSingleTap: onSingleTap,
                        onVerticalDrag: { offset, x in
                            guard asset.localIdentifier == store.currentID else { return }
                            isRatingDrag = offset != 0
                            onVerticalDrag(offset, x)
                        },
                        onVerticalCommit: { direction, x in
                            if asset.localIdentifier == store.currentID { onVerticalCommit(direction, x) }
                        }
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(asset.localIdentifier)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $store.currentID)
        .scrollIndicators(.hidden)
        // While zoomed in, dragging pans the photo instead of turning the page.
        .scrollDisabled(isZoomed || isRatingDrag)
        .onChange(of: store.currentID) { _, _ in isZoomed = false }
        .accessibilityIdentifier("viewer.pager")
    }
}
