//
//  ViewerView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// One page of the pager: shows the photo fitted to the screen and loads the original once the user zooms in.
struct PhotoPage: View {
    let asset: PHAsset
    var onZoomChange: (Bool) -> Void
    var onSingleTap: () -> Void

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
                        onZoomChange: onZoomChange,
                        onSingleTap: onSingleTap,
                        onZoomedIn: { Task { await loadOriginal() } }
                    )
                } else {
                    ProgressView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
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

/// Horizontal paging through the visible photos.
struct ViewerPager: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isZoomed = false
    var onSingleTap: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(store.visible, id: \.localIdentifier) { asset in
                    PhotoPage(
                        asset: asset,
                        onZoomChange: { zoomed in
                            if asset.localIdentifier == store.currentID { isZoomed = zoomed }
                        },
                        onSingleTap: onSingleTap
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
        .scrollDisabled(isZoomed)
        .clipped()
        .onChange(of: store.currentID) { _, _ in isZoomed = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前照片")
        .accessibilityValue("\((store.currentIndex ?? 0) + 1) / \(store.visible.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: store.next()
            case .decrement: store.previous()
            @unknown default: break
            }
        }
    }
}
