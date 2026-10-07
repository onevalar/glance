//
//  LibraryStore.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// Photo-library state for the culling flow: which photos are shown, which one is current,
/// and the keep / undecided / discard rating of each (stored by photo identifier).
@MainActor
final class LibraryStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    enum Access {
        case unknown
        case denied
        case ready
    }

    @AppLog(category: "LibraryStore")
    private var logger

    @Published private(set) var access: Access = .unknown
    /// Photos shown under the current filter, newest first.
    @Published private(set) var visible: [PHAsset] = []
    @Published var currentID: String?
    @Published var filter: PhotoFilter = .all {
        didSet { if filter != oldValue { rebuild(preferIndex: currentIndex) } }
    }
    @Published private(set) var totalCount = 0

    let metadata = MetadataManager.shared
    private var allAssets: [PHAsset] = []

    // MARK: - Derived

    var currentIndex: Int? {
        guard let currentID else { return nil }
        return visible.firstIndex { $0.localIdentifier == currentID }
    }

    var currentAsset: PHAsset? {
        currentIndex.map { visible[$0] }
    }

    var discardedAssets: [PHAsset] {
        allAssets.filter { status(of: $0) == .discard }
    }

    func status(of asset: PHAsset) -> ImageStatus {
        metadata.getMetadata(forKey: asset.localIdentifier).status
    }

    // MARK: - Permission & loading

    func start() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        refreshAccess()
    }

    func refreshAccess() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            if access != .ready {
                access = .ready
                PHPhotoLibrary.shared().register(self)
            }
            reload()
        case .notDetermined:
            access = .unknown
        default:
            access = .denied
        }
    }

    private func reload() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        allAssets = result.objects(at: IndexSet(integersIn: 0..<result.count))
        totalCount = allAssets.count
        rebuild(preferIndex: currentIndex)
    }

    /// Recomputes the visible list. Keeps the current photo if it is still shown,
    /// otherwise selects whatever slid into its position.
    private func rebuild(preferIndex: Int?) {
        let wanted = filter
        visible = allAssets.filter { asset in
            switch wanted {
            case .all: return true
            case .keep: return status(of: asset) == .keep
            case .undecided: return status(of: asset) == .undecided
            case .discard: return status(of: asset) == .discard
            }
        }

        if let currentID, visible.contains(where: { $0.localIdentifier == currentID }) { return }
        if visible.isEmpty {
            currentID = nil
        } else {
            currentID = visible[min(preferIndex ?? 0, visible.count - 1)].localIdentifier
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.reload() }
    }

    // MARK: - Navigation

    func select(_ asset: PHAsset) {
        currentID = asset.localIdentifier
    }

    func next() {
        guard let index = currentIndex, index + 1 < visible.count else { return }
        currentID = visible[index + 1].localIdentifier
    }

    func previous() {
        guard let index = currentIndex, index > 0 else { return }
        currentID = visible[index - 1].localIdentifier
    }

    // MARK: - Rating

    func rate(_ status: ImageStatus, advance: Bool) {
        guard let asset = currentAsset, let index = currentIndex else { return }
        metadata.updateMetadata(forKey: asset.localIdentifier) { $0.status = status }

        if filter != .all {
            // The photo may have left the filtered list; the next one takes its place.
            rebuild(preferIndex: index)
        } else if advance {
            next()
        }
        objectWillChange.send()
    }

    // MARK: - Deleting

    /// Moves photos to "Recently Deleted". The system shows its own confirmation.
    @discardableResult
    func delete(_ assets: [PHAsset]) async -> Bool {
        guard !assets.isEmpty else { return true }
        let ids = assets.map(\.localIdentifier)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            for id in ids { metadata.removeMetadata(forKey: id) }
            logger.info("Deleted \(ids.count) photos")
            return true
        } catch {
            // Declining the system prompt also lands here; nothing was deleted.
            logger.info("Delete cancelled or failed: \(error.localizedDescription)")
            return false
        }
    }
}
