//
//  PhotoImageLoader.swift
//  Glance (iPhone / iPad)
//

import Photos
import UIKit

/// Async wrapper around `PHImageManager` that cancels the request when the calling task is cancelled
/// (e.g. a thumbnail scrolls off screen).
enum PhotoImageLoader {
    private final class RequestBox: @unchecked Sendable {
        var id: PHImageRequestID = PHInvalidImageRequestID
        var cancelled = false
    }

    /// - Parameter targetSize: size in pixels. Pass `PHImageManagerMaximumSize` for the original.
    static func image(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit
    ) async -> UIImage? {
        let box = RequestBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat   // a single callback
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true       // photos kept in iCloud

                box.id = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: contentMode,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }
        } onCancel: {
            box.cancelled = true
            if box.id != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(box.id)
            }
        }
    }
}
