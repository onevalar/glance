//
//  LibraryStore.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// Photo-library state for the culling flow: which photos are shown, which one is current,
/// and the keep / undecided / discard rating of each (stored by photo identifier).
/// A place photos can be browsed from: the whole library, a smart album or one of the user's albums.
struct AlbumChoice: Identifiable, Equatable {
    static let allPhotosID = "all"
    let id: String
    let title: String
    let count: Int
    let symbol: String
}

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
    @Published private(set) var albums: [AlbumChoice] = []
    @Published private(set) var selectedAlbumID = AlbumChoice.allPhotosID

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
        if UserDefaults.standard.bool(forKey: "resetRatings") { metadata.removeAllMetadata() }
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
        loadAlbums()
        allAssets = fetchAssets(inAlbum: selectedAlbumID)
        totalCount = allAssets.count
        rebuild(preferIndex: currentIndex)
    }

    private func imageOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return options
    }

    private func fetchAssets(inAlbum id: String) -> [PHAsset] {
        let result: PHFetchResult<PHAsset>
        if id != AlbumChoice.allPhotosID,
           let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            result = PHAsset.fetchAssets(in: collection, options: imageOptions())
        } else {
            result = PHAsset.fetchAssets(with: imageOptions())
        }
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }

    private func loadAlbums() {
        var choices = [AlbumChoice(
            id: AlbumChoice.allPhotosID, title: "全部照片",
            count: PHAsset.fetchAssets(with: imageOptions()).count, symbol: "photo.on.rectangle"
        )]

        let smart: [(PHAssetCollectionSubtype, String, String)] = [
            (.smartAlbumFavorites, "个人收藏", "heart"),
            (.smartAlbumScreenshots, "截屏", "camera.viewfinder"),
            (.smartAlbumSelfPortraits, "自拍", "person.crop.square"),
            (.smartAlbumRecentlyAdded, "最近添加", "clock"),
        ]
        for (subtype, title, symbol) in smart {
            if let collection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).firstObject {
                let count = PHAsset.fetchAssets(in: collection, options: imageOptions()).count
                if count > 0 { choices.append(AlbumChoice(id: collection.localIdentifier, title: title, count: count, symbol: symbol)) }
            }
        }

        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        user.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: self.imageOptions()).count
            if count > 0 {
                choices.append(AlbumChoice(
                    id: collection.localIdentifier, title: collection.localizedTitle ?? "未命名相册",
                    count: count, symbol: "rectangle.stack"
                ))
            }
        }
        albums = choices
        if !choices.contains(where: { $0.id == selectedAlbumID }) { selectedAlbumID = AlbumChoice.allPhotosID }
    }

    var selectedAlbum: AlbumChoice? { albums.first { $0.id == selectedAlbumID } }

    func selectAlbum(_ album: AlbumChoice) {
        guard album.id != selectedAlbumID else { return }
        selectedAlbumID = album.id
        currentID = nil
        reload()
    }

    /// File name without extension, e.g. "IMG_0421" — shown next to the position counter.
    func displayName(of asset: PHAsset) -> String {
        guard let name = PHAssetResource.assetResources(for: asset).first?.originalFilename else { return "" }
        return (name as NSString).deletingPathExtension
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

    /// What the last rating changed, so it can be undone from the toast.
    struct RatingEvent: Equatable, Identifiable {
        let id = UUID()
        let assetID: String
        let previous: ImageStatus
        let new: ImageStatus
    }

    @Published private(set) var lastRating: RatingEvent?

    /// Rates the current photo. Choosing the status it already has clears it back to 待定,
    /// so a wrong swipe is fixed by swiping the same way again.
    func rate(_ status: ImageStatus, advance: Bool) {
        guard let asset = currentAsset, let index = currentIndex else { return }
        let previous = self.status(of: asset)
        let result: ImageStatus = previous == status ? .undecided : status
        apply(result, to: asset.localIdentifier, previous: previous)

        if filter != .all {
            // The photo may have left the filtered list; the next one takes its place.
            rebuild(preferIndex: index)
        } else if advance {
            next()
        }
        objectWillChange.send()
    }

    /// Sets a specific photo's rating without moving the selection (used by the comparison screen).
    func setStatus(_ status: ImageStatus, forAssetID id: String) {
        let previous = metadata.getMetadata(forKey: id).status
        let result: ImageStatus = previous == status ? .undecided : status
        apply(result, to: id, previous: previous)
        objectWillChange.send()
    }

    private func apply(_ status: ImageStatus, to id: String, previous: ImageStatus) {
        metadata.updateMetadata(forKey: id) { $0.status = status }
        lastRating = RatingEvent(assetID: id, previous: previous, new: status)
    }

    func undoLastRating() {
        guard let event = lastRating else { return }
        metadata.updateMetadata(forKey: event.assetID) { $0.status = event.previous }
        lastRating = nil
        // Bring the photo back into view, even if the active filter had hidden it.
        let index = currentIndex
        rebuild(preferIndex: index)
        if visible.contains(where: { $0.localIdentifier == event.assetID }) { currentID = event.assetID }
        objectWillChange.send()
    }

    /// Number of photos in the current album with the given rating (all photos for `.all`).
    func count(_ filter: PhotoFilter) -> Int {
        switch filter {
        case .all: return allAssets.count
        case .keep: return allAssets.reduce(0) { $0 + (status(of: $1) == .keep ? 1 : 0) }
        case .undecided: return allAssets.reduce(0) { $0 + (status(of: $1) == .undecided ? 1 : 0) }
        case .discard: return allAssets.reduce(0) { $0 + (status(of: $1) == .discard ? 1 : 0) }
        }
    }

    func asset(withID id: String) -> PHAsset? {
        allAssets.first { $0.localIdentifier == id }
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
