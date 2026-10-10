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
    @Published private(set) var visible: [PHAsset] = [] {
        didSet { indexByID = Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($1.localIdentifier, $0) }) }
    }
    /// Position of each visible photo, so looking up the current index stays O(1) in huge libraries.
    private var indexByID: [String: Int] = [:]
    private var assetsByID: [String: PHAsset] = [:]
    /// How many photos match each filter. Recomputed when ratings or the library change, never while drawing.
    @Published private(set) var counts: [String: Int] = [:]
    @Published var currentID: String?
    @Published var filter: PhotoFilter = .all {
        didSet { if filter != oldValue { rebuild(preferIndex: currentIndex) } }
    }
    @Published private(set) var totalCount = 0
    /// Discarded photos in the whole library (the discard pile does not depend on the album being viewed).
    @Published private(set) var pileCount = 0
    @Published private(set) var albums: [AlbumChoice] = []
    @Published private(set) var selectedAlbumID = AlbumChoice.allPhotosID

    let metadata = MetadataManager.shared
    private var allAssets: [PHAsset] = []

    // MARK: - Derived

    var currentIndex: Int? {
        guard let currentID else { return nil }
        return indexByID[currentID]
    }

    var currentAsset: PHAsset? {
        currentIndex.map { visible[$0] }
    }

    var discardedAssets: [PHAsset] {
        allAssets.filter { status(of: $0) == .discard }
    }

    /// Every discarded photo in the library, newest first.
    func pileAssets() -> [PHAsset] {
        let ids = pileIDs()
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: imageOptions())
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }

    private func pileIDs() -> [String] {
        metadata.metadataCache.compactMap { $0.value.isDiscarded ? $0.key : nil }
    }

    /// Takes photos back out of the discard pile.
    func restore(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in ids { metadata.updateMetadata(forKey: id) { $0.setDiscarded(false) } }
        refreshCounts()
        if filter != .all { rebuild(preferIndex: currentIndex) }
        objectWillChange.send()
    }

    /// Shows one photo of the pile in the viewer (switching to the whole library, where every pile photo is).
    func openInPile(_ asset: PHAsset) {
        if selectedAlbumID != AlbumChoice.allPhotosID {
            selectedAlbumID = AlbumChoice.allPhotosID
            reload()
        }
        filter = .discarded
        if visible.contains(where: { $0.localIdentifier == asset.localIdentifier }) { currentID = asset.localIdentifier }
    }

    func status(of asset: PHAsset) -> ImageStatus {
        metadata.getMetadata(forKey: asset.localIdentifier).status
    }

    func stars(of asset: PHAsset) -> Int {
        metadata.getMetadata(forKey: asset.localIdentifier).rating
    }

    private func matches(_ asset: PHAsset, _ filter: PhotoFilter) -> Bool {
        filter.matches(metadata.getMetadata(forKey: asset.localIdentifier))
    }

    // MARK: - Permission & loading

    func start() async {
        if UserDefaults.standard.bool(forKey: "resetRatings") {
            // UI tests start from a clean slate: no ratings, default star scale.
            metadata.removeAllMetadata()
            UserDefaults.standard.set(5, forKey: "starScale")
        }
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
        assetsByID = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.localIdentifier, $0) })
        totalCount = allAssets.count
        refreshCounts()
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
        visible = allAssets.filter { matches($0, wanted) }

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

    /// What the last action changed, so it can be undone from the toast.
    struct RatingEvent: Equatable, Identifiable {
        let id = UUID()
        let assetID: String
        let previous: ImageMetadata
        let new: ImageMetadata

        /// Text for the toast.
        var message: String {
            if new.isDiscarded { return "已丢弃" }
            if previous.isDiscarded { return "已恢复" }
            if new.rating > 0 { return "已评 \(new.rating) 星" }
            return "已取消评分"
        }
    }

    @Published private(set) var lastRating: RatingEvent?

    /// Rates the current photo with 1…5 stars. Choosing the rating it already has clears it.
    func rate(stars: Int, advance: Bool) {
        change(advance: advance) { meta in
            if meta.rating == stars { meta.setRating(0) } else { meta.setRating(stars) }
        }
    }

    /// Sets the current photo's rating to exactly `stars` (0 clears it); used by the pull-up gesture.
    func setRating(_ stars: Int, advance: Bool) {
        change(advance: advance) { $0.setRating(stars) }
    }

    /// Puts the current photo in the discard pile (nothing is deleted yet). Doing it again takes it back out.
    func discard(advance: Bool) {
        change(advance: advance) { meta in meta.setDiscarded(!meta.isDiscarded) }
    }

    private func change(advance: Bool, _ edit: (inout ImageMetadata) -> Void) {
        guard let asset = currentAsset, let index = currentIndex else { return }
        apply(to: asset.localIdentifier, edit)

        if filter != .all {
            // The photo may have left the filtered list; the next one takes its place.
            rebuild(preferIndex: index)
        } else if advance {
            next()
        }
        objectWillChange.send()
    }

    /// Edits a specific photo without moving the selection (comparison screen).
    func edit(assetID id: String, _ edit: (inout ImageMetadata) -> Void) {
        apply(to: id, edit)
        objectWillChange.send()
    }

    private func apply(to id: String, _ edit: (inout ImageMetadata) -> Void) {
        let previous = metadata.getMetadata(forKey: id)
        var updated = previous
        edit(&updated)
        guard updated != previous else { return }
        metadata.updateMetadata(forKey: id) { $0 = updated }
        lastRating = RatingEvent(assetID: id, previous: previous, new: updated)
        refreshCounts()
    }

    func undoLastRating() {
        guard let event = lastRating else { return }
        metadata.updateMetadata(forKey: event.assetID) { $0 = event.previous }
        lastRating = nil
        refreshCounts()
        // Bring the photo back into view, even if the active filter had hidden it.
        let index = currentIndex
        rebuild(preferIndex: index)
        if visible.contains(where: { $0.localIdentifier == event.assetID }) { currentID = event.assetID }
        objectWillChange.send()
    }

    /// Number of photos in the current album that match `filter`.
    func count(_ filter: PhotoFilter) -> Int { counts[filter.id] ?? 0 }

    private func refreshCounts() {
        var result: [String: Int] = [:]
        var stars = [Int](repeating: 0, count: 6)
        var unrated = 0, discarded = 0
        for asset in allAssets {
            let meta = metadata.getMetadata(forKey: asset.localIdentifier)
            if meta.isDiscarded { discarded += 1 } else if meta.rating == 0 { unrated += 1 } else { stars[meta.rating] += 1 }
        }
        result[PhotoFilter.all.id] = allAssets.count
        result[PhotoFilter.unrated.id] = unrated
        result[PhotoFilter.discarded.id] = discarded
        for n in 1...5 { result[PhotoFilter.stars(n).id] = stars[n] }
        counts = result
        let ids = pileIDs()
        pileCount = ids.isEmpty ? 0 : PHAsset.fetchAssets(withLocalIdentifiers: ids, options: imageOptions()).count
    }

    func asset(withID id: String) -> PHAsset? { assetsByID[id] }

    // MARK: - Deleting

    nonisolated private static func deletion(of assets: NSArray) -> @Sendable () -> Void {
        nonisolated(unsafe) let list = assets
        return { PHAssetChangeRequest.deleteAssets(list) }
    }

    /// Moves photos to "Recently Deleted". The system shows its own confirmation.
    @discardableResult
    func delete(_ assets: [PHAsset]) async -> Bool {
        guard !assets.isEmpty else { return true }
        let ids = assets.map(\.localIdentifier)
        do {
            // PhotoKit runs the change block on its own queue, so it must not belong to the main actor.
            try await PHPhotoLibrary.shared().performChanges(Self.deletion(of: assets as NSArray))
            for id in ids { metadata.removeMetadata(forKey: id) }
            refreshCounts()
            logger.info("Deleted \(ids.count) photos")
            return true
        } catch {
            // Declining the system prompt also lands here; nothing was deleted.
            logger.info("Delete cancelled or failed: \(error.localizedDescription)")
            return false
        }
    }
}
