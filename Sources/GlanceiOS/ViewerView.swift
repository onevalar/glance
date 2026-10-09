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
                        onZoomedIn: { Task { await loadOriginal() } }
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
