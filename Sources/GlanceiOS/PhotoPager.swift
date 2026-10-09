//
//  PhotoPager.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI
import UIKit

/// Edge-to-edge horizontal paging through the photos, built on `UICollectionView` so that swiping never goes
/// through SwiftUI diffing: only the visible page is alive, neighbours are pre-loaded, and the current photo is
/// reported once a page has settled.
struct PhotoPager: UIViewControllerRepresentable {
    var assets: [PHAsset]
    var currentID: String?
    var phase: DragPhaseModel
    var starCount: Int
    /// Window y where the star row appears (the centre of the top bar).
    var starRowY: CGFloat
    /// Room kept free for the bars around a resting photo (window edges).
    var fitInsets: UIEdgeInsets
    var onPageChange: (String) -> Void
    var onSingleTap: () -> Void
    var onZoomChange: (Bool) -> Void
    var onCommit: (PullOutcome) -> Void
    var isDiscarded: (String) -> Bool

    func makeUIViewController(context: Context) -> PhotoPagerController {
        PhotoPagerController()
    }

    func updateUIViewController(_ controller: PhotoPagerController, context: Context) {
        controller.onPageChange = onPageChange
        controller.onSingleTap = onSingleTap
        controller.onCommit = onCommit
        controller.onZoomChange = onZoomChange
        controller.phase = phase
        controller.isDiscarded = isDiscarded
        controller.configureStage(starCount: starCount, starRowY: starRowY)
        controller.setFitInsets(fitInsets)
        controller.update(assets: assets, currentID: currentID)
        controller.refreshDiscardedDimming()
    }
}

final class PhotoPagerController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                                  UICollectionViewDataSourcePrefetching {
    var onPageChange: ((String) -> Void)?
    var onSingleTap: (() -> Void)?
    var onCommit: ((PullOutcome) -> Void)?
    var onZoomChange: ((Bool) -> Void)?
    var phase: DragPhaseModel?
    /// Asks the store whether a photo is in the discard pile, so it can be dimmed in place.
    var isDiscarded: ((String) -> Bool)?

    private var assets: [PHAsset] = []
    private var ids: [String] = []
    private var pendingID: String?
    private var reportedID: String?
    private var zoomedCells = Set<ObjectIdentifier>()
    private var fitInsets: UIEdgeInsets = .zero
    private let stage = PullStageView()
    /// The pull that is being followed (a pull that starts while the stage is still busy is ignored).
    private var pulling = false

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
        view.addSubview(stage)
        caching.allowsCachingHighQualityImages = false
        stage.onPhase = { [weak self] phase in
            if self?.phase?.phase != phase { self?.phase?.phase = phase }
        }
        stage.onCommit = { [weak self] outcome in self?.onCommit?(outcome) }
        stage.onFinish = { [weak self] in
            guard let self else { return }
            self.collectionView.isScrollEnabled = self.zoomedCells.isEmpty
        }
    }

    func configureStage(starCount: Int, starRowY: CGFloat) {
        if stage.starCount != starCount { stage.starCount = starCount }
        if stage.starRowWindowY != starRowY { stage.starRowWindowY = starRowY }
    }

    func setFitInsets(_ insets: UIEdgeInsets) {
        guard insets != fitInsets else { return }
        fitInsets = insets
        for case let cell as PhotoCell in collectionView.visibleCells { cell.zoomView.fitInsets = insets }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.frame = view.bounds
        stage.frame = view.bounds
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
        cell.zoomView.fitInsets = fitInsets
        cell.configure(asset: assets[indexPath.item], caching: caching)
        cell.setDimmed(isDiscarded?(assets[indexPath.item].localIdentifier) ?? false)
        cell.onSingleTap = { [weak self] in self?.onSingleTap?() }
        cell.onZoomChange = { [weak self, weak cell] zoomed in
            guard let cell else { return }
            self?.zoomChanged(cell: ObjectIdentifier(cell), zoomed: zoomed)
        }
        cell.zoomView.onPull = { [weak self, weak cell] gesture in
            guard let self, let cell else { return }
            self.handlePull(gesture, on: cell)
        }
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
        let wasZoomed = !zoomedCells.isEmpty
        if zoomed { zoomedCells.insert(cell) } else { zoomedCells.remove(cell) }
        // Zoomed in: dragging pans the photo instead of turning the page.
        collectionView.isScrollEnabled = zoomedCells.isEmpty && !stage.isBusy && !pulling
        if wasZoomed != !zoomedCells.isEmpty { onZoomChange?(!zoomedCells.isEmpty) }
    }

    /// A vertical drag on a resting photo: the photo is lifted onto the stage and follows the finger there.
    private func handlePull(_ gesture: UIPanGestureRecognizer, on cell: PhotoCell) {
        let finger = gesture.location(in: stage)
        let velocity = gesture.velocity(in: stage)
        switch gesture.state {
        case .began:
            guard !stage.isBusy, let image = cell.zoomView.imageView.image else { pulling = false; return }
            pulling = true
            // While the photo is held the pager must not follow the finger sideways.
            collectionView.isScrollEnabled = false
            let imageView = cell.zoomView.imageView
            let frame = imageView.convert(imageView.bounds, to: stage)
            let id = cell.currentAssetID
            stage.begin(image: image, frame: frame, finger: finger) { [weak cell] animated in
                guard let cell else { return }
                // The cell may show another photo by now (recycled): then it only needs to be visible.
                cell.zoomView.showAgain(animated: animated && cell.currentAssetID == id)
            }
            cell.zoomView.setLifted(true)
            stage.move(finger: finger, velocity: velocity)
        case .changed:
            guard pulling else { return }
            stage.move(finger: finger, velocity: velocity)
        case .ended:
            guard pulling else { return }
            pulling = false
            stage.end(finger: finger, velocity: velocity, cancelled: false)
        case .cancelled, .failed:
            guard pulling else { return }
            pulling = false
            stage.end(finger: finger, velocity: velocity, cancelled: true)
        default:
            break
        }
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(zoomView)
        zoomView.frame = contentView.bounds
        zoomView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        zoomView.onSingleTap = { [weak self] in self?.onSingleTap?() }
        zoomView.onZoomChange = { [weak self] zoomed in self?.onZoomChange?(zoomed) }
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
