//
//  ImagePreviewView.swift
//  Glance
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showFileImporter = false
    @State private var keyMonitor: Any?

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
            } else {
                Button("选择图片或文件夹") {
                    showFileImporter = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .folder]
        ) { result in
            if case .success(let url) = result {
                let gotAccess = url.startAccessingSecurityScopedResource()
                if !gotAccess {
                    logger.warning("Failed to access security-scoped resource")
                    return
                }
                if let delegate = appState.appDelegate {
                    delegate.loadImages(from: url)
                    refreshImage()
                }
            }
        }
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
        if let image = NSImage(contentsOf: url) {
            currentImage = image
        }
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
