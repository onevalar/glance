//
//  ContentView.swift
//  Glance
//

import SwiftUI

/// Main window. Layout follows the Paper file "03 · Glance 过目 · 界面与交互":
/// title bar · sidebar (208) · photo canvas · information panel (260).
struct ContentView: View {
    @AppLog(category: "ContentView")
    private var logger

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState

    @State private var scale: CGSize = .init(width: 1, height: 1)
    @State private var isNavBarVisible = true
    @State private var isSearching = false
    @State private var showingBulkClearAlert = false
    @State private var glanceImageView: GlanceImageView?
    @State private var isChromeVisible = true
    @State private var chromeTimer: Timer?
    @StateObject private var compareSession = CompareSession()
    @AppStorage("glance.showInfoPanel") private var isInfoPanelVisible = true
    @AppStorage("glance.autoHideControls") private var autoHideControls = true

    private var isComparing: Bool { appState.selectedImageIndices.count > 1 }

    var body: some View {
        Group {
            if appState.allImageFiles.isEmpty {
                // Start page (or an empty folder); ImagePreviewView renders the welcome view.
                ImagePreviewView(scale: $scale, glanceImageView: $glanceImageView,
                                 onClick: {}, onDelete: confirmDelete, onNavigate: {})
            } else if appState.isCropEditing, let url = appState.currentImageURL, let image = NSImage(contentsOf: url) {
                cropEditor(url: url, image: image)
            } else {
                browser
            }
        }
        .background(GlancePalette.canvas(colorScheme))
        .background(TrafficLightInset(barHeight: GlanceTitleBar<EmptyView, EmptyView>.height))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { showChrome() }
        .alert("清空丢弃的照片", isPresented: $showingBulkClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) { appState.bulkMoveDiscardedToTrash() }
        } message: {
            Text("确定要将这 \(appState.count(for: .discard)) 张标记为“丢弃”的图片移动到系统废纸篓吗？此操作不可撤销。")
        }
    }

    // MARK: - Browsing layout

    private var browser: some View {
        VStack(spacing: 0) {
            if !isComparing { browsingTitleBar }
            HStack(spacing: 0) {
            if isNavBarVisible && !isComparing {
                ThumbnailSidebar(isSearching: $isSearching)
                    .transition(.move(edge: .leading))
            }
            canvas
            if isInfoPanelVisible && !isComparing {
                ImageInfoPanel(imageURL: appState.currentImageURL)
            }
        }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isNavBarVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isInfoPanelVisible)
        }
    }

    private var canvas: some View {
        ZStack {
            if isComparing {
                ImageCompareView(
                    session: compareSession,
                    onScaleChanged: { scale = CGSize(width: $0, height: $0) }
                )
            } else {
                ImagePreviewView(scale: $scale, glanceImageView: $glanceImageView,
                                 onClick: toggleChrome, onDelete: confirmDelete, onNavigate: showChrome)

                if !appState.imageFiles.isEmpty {
                    counterLabel
                    ToolBarView(onHoverEnter: cancelChromeTimer, onHoverExit: resetChromeTimer)
                        .opacity(isChromeVisible ? 1 : 0)
                        .allowsHitTesting(isChromeVisible)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isChromeVisible)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 30)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlancePalette.canvas(colorScheme))
        .clipped()
        .onContinuousHover { phase in
            switch phase {
            case .active:
                showChrome()
                resetChromeTimer()
            case .ended:
                resetChromeTimer()
            }
        }
    }

    /// "01 / 24　　filename" in the top-left corner of the canvas.
    private var counterLabel: some View {
        let total = appState.imageFiles.count
        let width = String(total).count
        let index = String(format: "%0\(width)d", appState.selectedImageIndex + 1)
        return Text("\(index) / \(total)　　\(appState.currentImageURL?.lastPathComponent ?? "")")
            .font(.system(size: 13))
            .foregroundStyle(GlancePalette.muted(colorScheme))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.top, 22)
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityLabel("第 \(appState.selectedImageIndex + 1) 张，共 \(total) 张")
    }

    // MARK: - Title bar

    private var browsingTitleBar: some View {
        GlanceTitleBar {
            TitleBarButton(symbol: "sidebar.left", label: "显示或隐藏侧栏") {
                isNavBarVisible.toggle()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(appState.folderName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GlancePalette.foreground(colorScheme))
                Text("\(appState.allImageFiles.count) 张照片")
                    .font(.system(size: 11))
                    .foregroundStyle(GlancePalette.muted(colorScheme))
            }
        } trailing: {
            TitleBarButton(symbol: "magnifyingglass", label: "按文件名搜索", isOn: isSearching) {
                isNavBarVisible = true
                isSearching.toggle()
                if !isSearching { appState.searchText = "" }
            }
            TitleBarButton(symbol: "square.grid.2x2", label: "并排比较相邻的两张") {
                appState.toggleCompare()
            }
            .disabled(appState.imageFiles.count < 2)
            TitleBarButton(symbol: "photo", label: "显示或隐藏文件信息") {
                isInfoPanelVisible.toggle()
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("打开照片…") { appState.appDelegate?.chooseImages() }
            Divider()
            Button("放大") { glanceImageView?.zoomIn() }
            Button("缩小") { glanceImageView?.zoomOut() }
            Button("适应窗口") { glanceImageView?.fitToWindow() }
            Divider()
            Button("向左旋转") { rotateCurrent(.counterClockwise) }
            Button("向右旋转") { rotateCurrent(.clockwise) }
            Divider()
            Button("删除当前照片…", role: .destructive) { confirmDelete() }
                .disabled(appState.currentImageURL == nil)
            Button("清空丢弃的照片 (\(appState.count(for: .discard)))…", role: .destructive) {
                showingBulkClearAlert = true
            }
            .disabled(appState.count(for: .discard) == 0)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15))
                .foregroundStyle(GlancePalette.muted(colorScheme))
                .frame(width: 32, height: 32)
                .contentShape(.rect(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多")
        .accessibilityLabel("更多")
    }

    // MARK: - Crop

    private func cropEditor(url: URL, image: NSImage) -> some View {
        CropOverlayView(
            image: image,
            filename: url.lastPathComponent,
            cropRect: MetadataManager.shared.getMetadata(for: url).cropRect,
            onCommit: { newRect in
                MetadataManager.shared.updateMetadata(for: url) { meta in
                    meta.cropRect = newRect
                }
                appState.isCropEditing = false
                NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
            },
            onCancel: {
                appState.isCropEditing = false
            }
        )
        .id(url)
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

        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { return }
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

    private func rotateCurrent(_ direction: ImageRotator.Direction) {
        guard !isComparing, let url = appState.currentImageURL else { return }
        rotateImage(at: url, direction: direction)
    }

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
        guard autoHideControls else { isChromeVisible = true; chromeTimer = nil; return }
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
