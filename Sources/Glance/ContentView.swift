//
//  ContentView.swift
//  Glance
//

import SwiftUI

struct ContentView: View {
    @AppLog(category: "ContentView")
    private var logger

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState

    @State private var scale: CGSize = .init(width: 1, height: 1)
    @State private var isNavBarVisible = true
    @State private var window: NSWindow?
    @State private var glanceImageView: GlanceImageView?
    @State private var isChromeVisible = true
    @State private var chromeTimer: Timer?
    @State private var isInfoPanelVisible = false
    @State private var compareZoom: CGFloat = 1.0
    @State private var comparePan: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if isNavBarVisible && appState.imageFiles.count > 1 {
                    ThumbnailSidebar(windowHeight: window?.frame.size.height ?? 720)
                        .zIndex(20)
                }

                if isInfoPanelVisible {
                    ImageInfoPanel(
                        imageURL: appState.currentImageURL,
                        windowHeight: window?.frame.size.height ?? 720,
                        onClose: { isInfoPanelVisible = false }
                    )
                    .zIndex(20)
                    .position(x: geometry.size.width - 130, y: (window?.frame.size.height ?? 720) / 2)
                }

                Group {
                    if appState.selectedImageIndices.count > 1 {
                        ImageCompareView(
                            sharedZoom: $compareZoom,
                            sharedPan: $comparePan,
                            onScaleChanged: { scale = CGSize(width: $0, height: $0) }
                        )
                            .frame(width: geometry.size.width, height: geometry.size.height + 28)
                            .zIndex(10)
                    } else {
                        ImagePreviewView(scale: $scale, glanceImageView: $glanceImageView, onClick: toggleChrome, onDelete: confirmDelete, onNavigate: showChrome)
                            .frame(width: geometry.size.width, height: geometry.size.height + 28)
                            .zIndex(10)
                    }
                }

                // Left navigation arrow
                if appState.selectedImageIndex > 0 && !appState.isCropEditing && appState.selectedImageIndices.count <= 1 {
                    navArrowButton(
                        systemName: "chevron.left",
                        action: { navigateToPrevious() }
                    )
                    .opacity(isChromeVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: isChromeVisible)
                    .zIndex(20)
                    .position(x: (isNavBarVisible && appState.imageFiles.count > 1) ? 160 : 32,
                              y: geometry.size.height / 2)
                }

                // Right navigation arrow
                if appState.selectedImageIndex < appState.imageFiles.count - 1 && !appState.isCropEditing && appState.selectedImageIndices.count <= 1 {
                    navArrowButton(
                        systemName: "chevron.right",
                        action: { navigateToNext() }
                    )
                    .opacity(isChromeVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: isChromeVisible)
                    .zIndex(20)
                    .position(x: geometry.size.width - 32, y: geometry.size.height / 2)
                }

                if !appState.isCropEditing {
                    ToolBarView(scale: scale, onTap: { actionID in
                        handleToolbarTap(actionID)
                    }, onHoverEnter: cancelChromeTimer, onHoverExit: resetChromeTimer)
                    .opacity(isChromeVisible ? 1 : 0)
                    .allowsHitTesting(isChromeVisible)
                    .animation(.easeInOut(duration: 0.3), value: isChromeVisible)
                    .zIndex(20)
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 32)
                }
                
                // Crop Overlay View
                if appState.isCropEditing && appState.selectedImageIndices.count <= 1,
                   let currentURL = appState.currentImageURL,
                   let image = NSImage(contentsOf: currentURL) {
                    CropOverlayView(
                        imageSize: image.size,
                        // Same box as the preview underneath (which is 28pt taller than the
                        // GeometryReader), otherwise the frame and the picture drift apart.
                        viewSize: CGSize(width: geometry.size.width, height: geometry.size.height + 28),
                        cropRect: Binding(
                            get: { MetadataManager.shared.getMetadata(for: currentURL).cropRect },
                            set: { _ in }
                        ),
                        onCommit: { newRect in
                            MetadataManager.shared.updateMetadata(for: currentURL) { meta in
                                meta.cropRect = newRect
                            }
                            appState.isCropEditing = false
                            NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
                        },
                        onCancel: {
                            appState.isCropEditing = false
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height + 28)
                    .zIndex(30)
                }
            }
            .ignoresSafeArea(.container)
            .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
            .onAppear(perform: appearHandler)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    if point.y > geometry.size.height - 48 {
                        showChrome()
                    } else if isChromeVisible {
                        resetChromeTimer()
                    }
                case .ended:
                    if isChromeVisible {
                        resetChromeTimer()
                    }
                }
            }
        }
    }

    // MARK: - Navigation Arrow Button

    func navArrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.ultraThinMaterial).opacity(0.7))
        }
        .buttonStyle(PlainButtonStyle())
        .help(Text(systemName.contains("left") ? "Previous picture" : "Next picture"))
    }

    // MARK: - Toolbar Actions

    private var isComparing: Bool { appState.selectedImageIndices.count > 1 }

    func handleToolbarTap(_ id: ToolbarActionIdentifier) {
        switch id {
        case .toggleNav:
            isNavBarVisible.toggle()

        case .scaleMinis:
            if isComparing {
                compareZoom = (compareZoom * 0.8).clamped(to: 0.1...16)
            } else {
                glanceImageView?.zoomOut()
            }

        case .scalePlus:
            if isComparing {
                compareZoom = (compareZoom * 1.25).clamped(to: 0.1...16)
            } else {
                glanceImageView?.zoomIn()
            }

        case .showPrev:
            navigateToPrevious()

        case .showNext:
            navigateToNext()

        case .centerFill:
            if isComparing {
                compareZoom = 1.0
                comparePan = .zero
            } else {
                glanceImageView?.fitToWindow()
            }

        case .toggleInfo:
            isInfoPanelVisible.toggle()

        case .rotateLeft:
            if let url = appState.currentImageURL {
                rotateImage(at: url, direction: .counterClockwise)
            }

        case .rotateRight:
            if let url = appState.currentImageURL {
                rotateImage(at: url, direction: .clockwise)
            }

        case .deleteImage:
            confirmDelete()
        }
    }

    // MARK: - Navigation

    func navigateToPrevious() {
        appState.navigateToPrevImage()
    }

    func navigateToNext() {
        appState.navigateToNextImage()
    }

    // MARK: - Delete

    func confirmDelete() {
        guard let url = appState.currentImageURL else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Delete Picture")
        let format = String(localized: "Are you sure you want to move \"%@\" to the Trash?")
        alert.informativeText = String(format: format, url.lastPathComponent)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        guard let window = NSApplication.shared.windows.first else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                performDelete(url: url)
            }
        }
    }

    func performDelete(url: URL) {
        NSWorkspace.shared.recycle([url]) { recycledURLs, error in
            DispatchQueue.main.async {
                if let error {
                    logger.error("Failed to move to trash: \(error.localizedDescription)")
                    return
                }
                appState.removeImage(url)
                NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
                logger.info("Moved to trash: \(url.lastPathComponent)")
            }
        }
    }

    // MARK: - Rotation

    func rotateImage(at url: URL, direction: ImageRotator.Direction) {
        do {
            try ImageRotator.rotate(url, direction: direction)
            NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
        } catch {
            logger.error("Failed to rotate image: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = String(localized: "无法旋转")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    // MARK: - Chrome Visibility

    func appearHandler() {
        if let window = NSApplication.shared.windows.first {
            self.window = window
        }
        showChrome()
    }

    func toggleChrome() {
        if isChromeVisible {
            hideChrome()
        } else {
            showChrome()
        }
    }

    func showChrome() {
        isChromeVisible = true
        cancelChromeTimer()
    }

    func hideChrome() {
        isChromeVisible = false
        chromeTimer?.invalidate()
        chromeTimer = nil
    }

    func resetChromeTimer() {
        chromeTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: false) { _ in
            DispatchQueue.main.async {
                self.isChromeVisible = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        chromeTimer = timer
    }

    func cancelChromeTimer() {
        chromeTimer?.invalidate()
        chromeTimer = nil
    }
}

#Preview {
    ContentView()
}
