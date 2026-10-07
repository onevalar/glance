//
//  AppState.swift
//  Glance
//
//  Created by 李旭 on 2024/9/5.
//

import Combine
import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @AppLog(category: "AppState")
    private var logger

    // Master list of all images in the folder
    var allImageFiles: [URL] = []

    @Published var currentImageURL: URL?
    @Published var imageFiles: [URL] = []
    @Published var selectedImageIndex: Int = 0
    @Published var selectedImageIndices: Set<Int> = []
    @Published var activeFilter: PhotoFilter = .all
    @Published var isCropEditing: Bool = false
    
    // Track last clicked index for Shift selection
    private var lastClickedIndex: Int?

    @Published var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general

    func updateFilteredImages(preserveSelection: Bool = true) {
        let oldSelectedURL = currentImageURL
        
        let manager = MetadataManager.shared
        self.imageFiles = allImageFiles.filter { url in
            let meta = manager.getMetadata(for: url)
            switch activeFilter {
            case .all:
                return true
            case .keep:
                return meta.status == .keep
            case .undecided:
                return meta.status == .undecided
            case .discard:
                return meta.status == .discard
            }
        }
        
        if preserveSelection, let oldSelectedURL, let newIndex = imageFiles.firstIndex(of: oldSelectedURL) {
            self.selectedImageIndex = newIndex
            self.selectedImageIndices = [newIndex]
            self.currentImageURL = oldSelectedURL
        } else {
            if !imageFiles.isEmpty {
                self.selectedImageIndex = 0
                self.selectedImageIndices = [0]
                self.currentImageURL = imageFiles[0]
            } else {
                self.selectedImageIndex = 0
                self.selectedImageIndices = []
                self.currentImageURL = nil
            }
        }
    }

    func selectSingleImage(index: Int) {
        guard index >= 0 && index < imageFiles.count else { return }
        selectedImageIndex = index
        selectedImageIndices = [index]
        currentImageURL = imageFiles[index]
        lastClickedIndex = index
    }
    
    func toggleImageSelection(index: Int) {
        guard index >= 0 && index < imageFiles.count else { return }
        if selectedImageIndices.contains(index) {
            selectedImageIndices.remove(index)
            if selectedImageIndices.isEmpty {
                selectedImageIndices.insert(index)
            }
        } else {
            selectedImageIndices.insert(index)
        }
        selectedImageIndex = index
        currentImageURL = imageFiles[index]
        lastClickedIndex = index
    }
    
    func selectRangeOfImages(toIndex: Int) {
        guard toIndex >= 0 && toIndex < imageFiles.count else { return }
        let start = lastClickedIndex ?? selectedImageIndex
        let end = toIndex
        
        let range = start < end ? start...end : end...start
        for idx in range {
            selectedImageIndices.insert(idx)
        }
        
        selectedImageIndex = toIndex
        currentImageURL = imageFiles[toIndex]
    }
    
    func navigateToNextImage() {
        guard selectedImageIndex < imageFiles.count - 1 else { return }
        selectSingleImage(index: selectedImageIndex + 1)
    }
    
    func navigateToPrevImage() {
        guard selectedImageIndex > 0 else { return }
        selectSingleImage(index: selectedImageIndex - 1)
    }

    func setStatusForSelectedImages(_ status: ImageStatus) {
        let manager = MetadataManager.shared
        let urlsToUpdate = selectedImageIndices.compactMap { idx -> URL? in
            guard idx >= 0 && idx < imageFiles.count else { return nil }
            return imageFiles[idx]
        }
        
        guard !urlsToUpdate.isEmpty else { return }
        
        for url in urlsToUpdate {
            manager.updateMetadata(for: url) { meta in
                meta.status = status
            }
        }
        
        // Trigger UI update
        objectWillChange.send()
        
        NotificationCenter.default.post(name: Notification.Name("metadata-updated"), object: nil)
        
        // If filter is active and hides updated status, re-filter
        if activeFilter != .all {
            let firstSelectedIdx = selectedImageIndices.min() ?? selectedImageIndex
            updateFilteredImages(preserveSelection: false)
            if !imageFiles.isEmpty {
                let targetIdx = min(firstSelectedIdx, imageFiles.count - 1)
                selectedImageIndex = targetIdx
                selectedImageIndices = [targetIdx]
                currentImageURL = imageFiles[targetIdx]
            } else {
                selectedImageIndex = 0
                selectedImageIndices = []
                currentImageURL = nil
            }
            NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
        }
    }

    /// Drops an image that no longer exists on disk from every list and cache,
    /// then selects the neighbour that slid into its place.
    func removeImage(_ url: URL) {
        let previousIndex = selectedImageIndex

        allImageFiles.removeAll { $0 == url }
        imageFiles.removeAll { $0 == url }
        MetadataManager.shared.removeMetadata(for: url)

        guard !imageFiles.isEmpty else {
            selectedImageIndex = 0
            selectedImageIndices = []
            currentImageURL = nil
            isCropEditing = false
            return
        }

        let index = min(previousIndex, imageFiles.count - 1)
        selectedImageIndex = index
        selectedImageIndices = [index]
        currentImageURL = imageFiles[index]
    }

    func bulkMoveDiscardedToTrash() {
        let manager = MetadataManager.shared
        let discardedURLs = allImageFiles.filter { url in
            manager.getMetadata(for: url).status == .discard
        }
        
        guard !discardedURLs.isEmpty else { return }
        
        NSWorkspace.shared.recycle(discardedURLs) { [weak self] recycledURLs, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.logger.error("Bulk trash failed: \(error.localizedDescription)")
                    return
                }
                
                for url in discardedURLs {
                    manager.removeMetadata(for: url)
                }
                
                self.allImageFiles.removeAll { url in discardedURLs.contains(url) }
                self.imageFiles.removeAll { url in discardedURLs.contains(url) }
                
                self.updateFilteredImages(preserveSelection: false)
                
                self.logger.info("Bulk moved \(discardedURLs.count) images to trash.")
                NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
            }
        }
    }

    // Permission
    @Published var dirs: [URL] = []

    /// Manager for app permissions.
    private(set) lazy var permissionsManager = PermissionsManager(appState: self)

    /// The app's delegate.
    private(set) weak var appDelegate: AppDelegate?

    init() {
        if UserDefaults.standard.object(forKey: "showCurDirImg") as? Bool ?? true {
            restoreBookmarkData()
        }
    }

    func storeBookmarkData() {
        var bookmarkArray: [Data] = []
        for url in dirs {
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                bookmarkArray.append(bookmarkData)
            } catch {
                logger.warning("Failed to create bookmark for \(url): \(error)")
            }
        }

        UserDefaults.standard.set(bookmarkArray, forKey: Constants.dirBookmarkDataKey)
    }

    func restoreBookmarkData() {
        guard let bookmarkArray = UserDefaults.standard.array(forKey: Constants.dirBookmarkDataKey) as? [Data] else {
            logger.warning("userDefaults get data fail")
            return
        }

        var urls: [URL] = []

        for bookmarkData in bookmarkArray {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    logger.warning("Bookmark is stale, need to reselect folder. \(url.path)")
                } else {
                    if url.startAccessingSecurityScopedResource() {
                        urls.append(url)
                    } else {
                        logger.warning("Failed to access security-scoped resource for \(url.path).")
                    }
                }
            } catch {
                logger.error("Failed to resolve bookmark: \(error)")
            }
        }

        dirs = urls
    }

    /// Assigns the app delegate to the app state.
    func assignAppDelegate(_ appDelegate: AppDelegate) {
        guard self.appDelegate == nil else {
            logger.warning("Multiple attempts made to assign app delegate")
            return
        }
        self.appDelegate = appDelegate
    }

    /// Activates the app and sets its activation policy to the given value.
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {
        NSApp.setActivationPolicy(policy)
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            NSRunningApplication.current.activate(from: frontApp)
        } else {
            NSApp.activate()
        }
    }
}

public enum PhotoFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case keep = "保留"
    case undecided = "不确定"
    case discard = "丢弃"
    
    public var id: String { self.rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .keep: return "flag.fill"
        case .undecided: return "questionmark.circle"
        case .discard: return "xmark.circle"
        }
    }
}

