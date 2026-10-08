//
//  ImagePreviewView.swift
//  Glance
//

import AppKit
import SwiftUI

@MainActor
struct ImagePreviewView: View {
    @AppLog(category: "ImagePreview")
    private var logger

    @EnvironmentObject var appState: AppState

    @Binding var scale: CGSize
    @Binding var glanceImageView: GlanceImageView?

    var onClick: (() -> Void)?
    var onDelete: (() -> Void)?
    var onNavigate: (() -> Void)?

    @State private var currentImage: NSImage?
    @State private var keyMonitor: Any?
    @State private var isDropTargeted = false
    @State private var openError: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let currentImage = currentImage {
                ZoomableImageView(
                    image: currentImage,
                    cropRect: appState.currentImageURL.map { MetadataManager.shared.getMetadata(for: $0).cropRect } ?? nil,
                    isCropEditing: appState.isCropEditing,
                    onScaleChanged: { newScale in
                        scale = CGSize(width: newScale, height: newScale)
                    },
                    onViewCreated: { imageView in
                        glanceImageView = imageView
                    },
                    onClick: onClick
                )
                .contextMenu {
                    Button("Copy Image Path") {
                        let path = appState.currentImageURL?.path ?? ""
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    }
                    Button("Copy Image") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([currentImage])
                    }
                }
            } else if !appState.allImageFiles.isEmpty && appState.activeFilter != .all {
                ContentUnavailableView {
                    Label("这个筛选下没有照片", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("查看全部") {
                        appState.activeFilter = .all
                        appState.updateFilteredImages(preserveSelection: false)
                        refreshImage()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                WelcomeView(recents: appState.recentLocations, onChoose: { appState.appDelegate?.chooseImages() }) { entry in
                    do { open(try appState.recentLocations.resolve(entry)) }
                    catch { openError = String(localized: "这个最近记录无法打开，请重新选择图片或文件夹。") }
                }
                .overlay { if isDropTargeted { GlancePalette.accent.opacity(0.06).allowsHitTesting(false) } }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            open(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .alert("无法打开图片", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("确定", role: .cancel) { openError = nil }
        } message: { Text(openError ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("open-image"))) { _ in
            refreshImage()
        }
        .onAppear {
            setupKeyEvents()
            refreshImage()
        }
        .onDisappear {
            removeKeyEvents()
        }
    }

    private func open(_ url: URL) {
        guard appState.acquireReadAccess(to: url) else {
            openError = String(localized: "无法读取这个位置，请通过选择器重新授权。")
            logger.warning("Failed to access selected resource")
            return
        }
        appState.appDelegate?.loadImages(from: url)
        refreshImage()
    }

    func setupKeyEvents() {
        // onAppear can fire more than once for the same view; never stack monitors.
        removeKeyEvents()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if appState.isCropEditing {
                return event
            }
            switch event.keyCode {
            case 124, 125: // Right / Down Arrow
                Task { @MainActor in
                    showNextImage()
                    onNavigate?()
                }
                return nil
            case 123, 126: // Left / Up Arrow
                Task { @MainActor in
                    showPreviousImage()
                    onNavigate?()
                }
                return nil
            case 51, 117: // Backspace / Forward Delete
                Task { @MainActor in
                    onDelete?()
                }
                return nil
            default:
                return event
            }
        }
    }

    func removeKeyEvents() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    func refreshImage() {
        guard appState.imageFiles.indices.contains(appState.selectedImageIndex) else {
            currentImage = nil
            return
        }
        let url = appState.imageFiles[appState.selectedImageIndex]
        currentImage = NSImage(contentsOf: url)
    }

    private func showNextImage() {
        appState.navigateToNextImage()
        refreshImage()
    }

    private func showPreviousImage() {
        appState.navigateToPrevImage()
        refreshImage()
    }
}
