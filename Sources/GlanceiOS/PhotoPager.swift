//
//  PhotoPager.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI
import UIKit

/// What a photo being pulled up / down looks like to the SwiftUI layer.
/// Only the small HUD views observe it, so a drag never re-renders the rest of the screen.
@MainActor
final class DragPhaseModel: ObservableObject {
    enum Phase { case idle, rating, trashing }
    /// Changes only when a pull starts or ends, so the bars that fade away during a pull barely re-render.
    @Published var phase: Phase = .idle
}

@MainActor
final class RatingDragModel: ObservableObject {
    /// Points past the dead zone: > 0 pulled up (stars), < 0 pulled down (trash).
    @Published var offset: CGFloat = 0 {
        didSet {
            let next: DragPhaseModel.Phase = offset > 0 ? .rating : (offset < 0 ? .trashing : .idle)
            if phaseModel.phase != next { phaseModel.phase = next }
        }
    }
    let phaseModel = DragPhaseModel()
    /// Where the photo should land when it is dropped (the opening of the trash, in window coordinates).
    var trashCenter: CGPoint?
    @Published var fingerX: CGFloat = 0.5
    @Published var fingerY: CGFloat = 0.5
    /// Set by the star HUD; used to turn the finger position into a star when the photo is released.
    var screenWidth: CGFloat = 393

    /// Where the star row sits on screen (fraction of the screen height) and how forgiving the hit area is.
    static let bandCenter: CGFloat = 0.33
    static let bandHalfHeight: CGFloat = 0.07

    var isDragging: Bool { offset != 0 }
}

/// Edge-to-edge horizontal paging through the photos, built on `UICollectionView` so that swiping never goes
/// through SwiftUI diffing: only the visible page is alive, neighbours are pre-loaded, and the current photo is
/// reported once a page has settled.
struct PhotoPager: UIViewControllerRepresentable {
    var assets: [PHAsset]
    var currentID: String?
    var drag: RatingDragModel
    var onPageChange: (String) -> Void
    var onSingleTap: () -> Void
    /// +1 = released after pulling up (finger position decides the stars), -1 = dropped into the trash.
    var onCommit: (_ direction: Int, _ x: CGFloat, _ y: CGFloat) -> Void
    var isDiscarded: (String) -> Bool

    func makeUIViewController(context: Context) -> PhotoPagerController {
        PhotoPagerController()
    }

    func updateUIViewController(_ controller: PhotoPagerController, context: Context) {
        controller.onPageChange = onPageChange
        controller.onSingleTap = onSingleTap
        controller.onCommit = onCommit
        controller.drag = drag
        controller.isDiscarded = isDiscarded
        controller.update(assets: assets, currentID: currentID)
        controller.refreshDiscardedDimming()
    }
}

final class PhotoPagerController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                                  UICollectionViewDataSourcePrefetching {
    var onPageChange: ((String) -> Void)?
    var onSingleTap: (() -> Void)?
    var onCommit: ((Int, CGFloat, CGFloat) -> Void)?
    var drag: RatingDragModel?
    /// Asks the store whether a photo is in the discard pile, so it can be dimmed in place.
    var isDiscarded: ((String) -> Bool)?

    private var assets: [PHAsset] = []
    private var ids: [String] = []
    private var pendingID: String?
    private var reportedID: String?
    private var zoomedCells = Set<ObjectIdentifier>()

    private let caching = PHCachingImageManager()
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.prefetchDataSource = self
        view.isPrefetchingEnabled = true
        view.decelerationRate = .fast
        view.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        view.accessibilityIdentifier = "viewer.pager"
        return view
    }()

    private var lastSize: CGSize = .zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(collectionView)
        caching.allowsCachingHighQualityImages = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.frame = view.bounds
        if view.bounds.size != lastSize {
            lastSize = view.bounds.size
            let id = reportedID ?? pendingID
            collectionView.collectionViewLayout.invalidateLayout()
            if let id { scroll(to: id, animated: false) }
        }
    }

    // MARK: - Updates from SwiftUI

    func update(assets newAssets: [PHAsset], currentID: String?) {
        let newIDs = newAssets.map(\.localIdentifier)
        let listChanged = newIDs != ids
        if listChanged {
            assets = newAssets
            ids = newIDs
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
        }
        guard let currentID, ids.contains(currentID) else { return }
        if listChanged || currentID != reportedID {
            // The selection changed from outside (rating advanced, grid tap, filter...): follow it.
            scroll(to: currentID, animated: !listChanged && reportedID != nil)
        }
    }

    /// Dims photos in the discard pile (visible pages only, so this stays cheap).
    func refreshDiscardedDimming() {
        for case let cell as PhotoCell in collectionView.visibleCells {
            cell.setDimmed(isDiscarded?(cell.currentAssetID) ?? false)
        }
    }

    private func scroll(to id: String, animated: Bool) {
        guard let index = ids.firstIndex(of: id), view.bounds.width > 0 else {
            pendingID = id
            return
        }
        pendingID = nil
        reportedID = id
        // A scroll that the app itself asked for is never reported back as "the user turned the page".
        collectionView.setContentOffset(CGPoint(x: CGFloat(index) * view.bounds.width, y: 0), animated: animated)
    }

    // MARK: - Paging

    private func reportCurrentPage() {
        let width = collectionView.bounds.width
        guard width > 0, !ids.isEmpty else { return }
        let index = min(max(Int((collectionView.contentOffset.x / width).rounded()), 0), ids.count - 1)
        let id = ids[index]
        guard id != reportedID else { return }
        reportedID = id
        onPageChange?(id)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { reportCurrentPage() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { reportCurrentPage() }
    }

    // MARK: - Data source

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { ids.count }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize { collectionView.bounds.size }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: indexPath) as! PhotoCell
        cell.configure(asset: assets[indexPath.item], caching: caching)
        cell.setDimmed(isDiscarded?(assets[indexPath.item].localIdentifier) ?? false)
        cell.onSingleTap = { [weak self] in self?.onSingleTap?() }
        cell.onZoomChange = { [weak self, weak cell] zoomed in
            guard let cell else { return }
            self?.zoomChanged(cell: ObjectIdentifier(cell), zoomed: zoomed)
        }
        cell.trashTarget = { [weak self] in self?.drag?.trashCenter }
        cell.onDrag = { [weak self] offset, x, y in self?.dragChanged(offset, x, y) }
        cell.onCommit = { [weak self] direction, x, y in self?.onCommit?(direction, x, y) }
        return cell
    }

    // Warm the neighbours so the next photo is already on screen when the page settles.
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let targets = indexPaths.compactMap { assets.indices.contains($0.item) ? assets[$0.item] : nil }
        caching.startCachingImages(for: targets, targetSize: PhotoCell.pixelSize(for: collectionView.bounds.size),
                                   contentMode: .aspectFit, options: PhotoCell.requestOptions)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let targets = indexPaths.compactMap { assets.indices.contains($0.item) ? assets[$0.item] : nil }
        caching.stopCachingImages(for: targets, targetSize: PhotoCell.pixelSize(for: collectionView.bounds.size),
                                  contentMode: .aspectFit, options: PhotoCell.requestOptions)
    }

    // MARK: - Gestures from the photos

    private func zoomChanged(cell: ObjectIdentifier, zoomed: Bool) {
        if zoomed { zoomedCells.insert(cell) } else { zoomedCells.remove(cell) }
        // Zoomed in: dragging pans the photo instead of turning the page.
        collectionView.isScrollEnabled = zoomedCells.isEmpty
    }

    private func dragChanged(_ offset: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        // While rating the finger also moves sideways to pick a star: the pager must not follow.
        collectionView.isScrollEnabled = offset == 0 && zoomedCells.isEmpty
        guard let drag else { return }
        drag.fingerX = x
        drag.fingerY = y
        if drag.offset != offset { drag.offset = offset }
    }
}

// MARK: - One page

final class PhotoCell: UICollectionViewCell {
    static let reuseID = "PhotoCell"

    static var requestOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic     // a quick small version first, then the sharp one
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true     // photos kept in iCloud
        return options
    }

    static var screenScale: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.screen.scale ?? 3
    }

    static func pixelSize(for size: CGSize) -> CGSize {
        let scale = screenScale
        return CGSize(width: max(size.width, 1) * scale, height: max(size.height, 1) * scale)
    }

    let zoomView = ZoomingScrollView()
    private var assetID = ""
    var currentAssetID: String { assetID }
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var originalRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var loadedOriginal = false
    private var asset: PHAsset?

    var onSingleTap: (() -> Void)?
    var onZoomChange: ((Bool) -> Void)?
    var trashTarget: (() -> CGPoint?)? { didSet { zoomView.trashTarget = trashTarget } }
    var onDrag: ((CGFloat, CGFloat, CGFloat) -> Void)?
    var onCommit: ((Int, CGFloat, CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(zoomView)
        zoomView.frame = contentView.bounds
        zoomView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        zoomView.onSingleTap = { [weak self] in self?.onSingleTap?() }
        zoomView.onZoomChange = { [weak self] zoomed in self?.onZoomChange?(zoomed) }
        zoomView.onVerticalDrag = { [weak self] offset, x, y in self?.onDrag?(offset, x, y) }
        zoomView.onVerticalCommit = { [weak self] direction, x, y in self?.onCommit?(direction, x, y) }
        zoomView.onZoomedIn = { [weak self] in self?.loadOriginal() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRequests()
        zoomView.resetForReuse()
        asset = nil
        assetID = ""
        loadedOriginal = false
    }

    func setDimmed(_ dimmed: Bool) {
        zoomView.restingAlpha = dimmed ? 0.4 : 1
        UIView.animate(withDuration: 0.2) { self.zoomView.imageView.alpha = self.zoomView.restingAlpha }
    }

    private func cancelRequests() {
        if requestID != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(requestID) }
        if originalRequestID != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(originalRequestID) }
        requestID = PHInvalidImageRequestID
        originalRequestID = PHInvalidImageRequestID
    }

    func configure(asset: PHAsset, caching: PHCachingImageManager) {
        self.asset = asset
        assetID = asset.localIdentifier
        zoomView.pixelSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        let id = assetID
        requestID = caching.requestImage(
            for: asset,
            targetSize: Self.pixelSize(for: bounds.size.width > 0 ? bounds.size : CGSize(width: 393, height: 852)),
            contentMode: .aspectFit,
            options: Self.requestOptions
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard let self, self.assetID == id, let image else { return }
                // Never replace the sharp original with a late small version.
                if !self.loadedOriginal { self.zoomView.imageView.image = image }
            }
        }
    }

    /// Full-resolution picture once the user zooms in far enough to need it.
    private func loadOriginal() {
        guard !loadedOriginal, let asset else { return }
        loadedOriginal = true
        let id = assetID
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        originalRequestID = PHImageManager.default().requestImage(
            for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard let self, self.assetID == id, let image else { return }
                self.zoomView.imageView.image = image
            }
        }
    }
}
