//
//  GlanceApp.swift
//  Glance
//
//  Created by 李旭 on 2024/9/1.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A button that opens the app's Settings window via the app menu.
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Preferences...") {
            openWindow(id: Constants.settingsWindowID)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

@main
struct GlanceApp: App {
    @AppStorage("glance.appearance") private var appearance = GlanceAppearance.system.rawValue
    @AppLog(category: "GlanceApp")
    private var logger

    // 设置 App Delegate 以响应 open file 请求
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var appState = AppState()

    init() {
        logger.info("app init .....")
        NSApplication.shared.setActivationPolicy(.regular)
        appDelegate.assignAppState(appState)
    }

    var body: some Scene {
        Window("过目", id: "main") {
            ContentView()
                .preferredColorScheme(GlanceAppearance(rawValue: appearance)?.scheme)
                .tint(GlancePalette.accent)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开照片…") { appDelegate.chooseImages() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton()
            }
            CommandMenu("照片") {
                Button("标记为保留") {
                    appState.setStatusForSelectedImages(.keep)
                }
                .keyboardShortcut("p", modifiers: [])
                
                Button("标记为待定") {
                    appState.setStatusForSelectedImages(.undecided)
                }
                .keyboardShortcut("u", modifiers: [])
                
                Button("标记为丢弃") {
                    appState.setStatusForSelectedImages(.discard)
                }
                .keyboardShortcut("x", modifiers: [])
                
                Divider()
                
                Button(appState.isCropEditing ? "退出裁剪模式" : "进入裁剪模式") {
                    if appState.selectedImageIndices.count <= 1 {
                        appState.isCropEditing.toggle()
                    }
                }
                .keyboardShortcut("r", modifiers: [])
                
                Divider()
                
                Button("评分：1 (丢弃)") {
                    appState.setStatusForSelectedImages(.discard)
                }
                .keyboardShortcut("1", modifiers: [])
                
                Button("评分：2 (待定)") {
                    appState.setStatusForSelectedImages(.undecided)
                }
                .keyboardShortcut("2", modifiers: [])
                
                Button("评分：3 (保留)") {
                    appState.setStatusForSelectedImages(.keep)
                }
                .keyboardShortcut("3", modifiers: [])
            }
        }
        .environmentObject(appState)

        SettingsWindow(appState: appState, onAppear: {})
            .restorationBehavior(.disabled)
    }
}

// AppDelegate 负责处理文件打开请求
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    @AppLog(category: "AppState")
    private var logger

    private var appState: AppState?
    private var hasExplicitOpenRequest = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        logger.info("---- app will finish launch")
        guard let appState else {
            logger.warning("Missing app state in applicationWillFinishLaunching")
            return
        }

        // assign the delegate to the shared app state
        appState.assignAppDelegate(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching  .......")
        appState?.activate(withPolicy: .regular)
        
        // Support launching from CLI with file path argument (e.g. swift run Glance /path/to/image.jpg)
        let arguments = CommandLine.arguments
        // The first argument is the binary path. If we have a second argument, try to open it as a file
        if arguments.count > 1 {
            let path = arguments[1]
            if !path.hasPrefix("-") && FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                hasExplicitOpenRequest = true
                logger.info("Opening image from CLI argument: \(url.path)")
                loadImages(from: url)
                NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
            }
        }
        // Finder's open event has priority over restoring a previous session.
        DispatchQueue.main.async { [weak self] in self?.restoreBrowsingSessionIfNeeded() }
    }

    private func restoreBrowsingSessionIfNeeded() {
        guard !hasExplicitOpenRequest, let appState, appState.allImageFiles.isEmpty,
              UserDefaults.standard.string(forKey: "glance.startup") == GlanceStartup.resume.rawValue,
              let saved = try? appState.browsingSession.resolve() else { return }
        loadImages(from: saved.resource, allowPermissionPrompt: false)
        if let index = appState.imageFiles.firstIndex(of: saved.selectedPhoto) {
            appState.selectSingleImage(index: index)
        }
        NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 当最后一个窗口关闭时，终止应用
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        hasExplicitOpenRequest = true
        logger.info("application open urls")
        guard let currentImageURL = urls.first else {
            logger.warning("no url in urls")
            return
        }
        logger.info("Received file URL: \(currentImageURL)")
        loadImages(from: currentImageURL)
        NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appState?.releaseOpenResource()
        return .terminateNow
    }

    /// Assigns the app state to the delegate.
    func assignAppState(_ appState: AppState) {
        guard self.appState == nil else {
            logger.warning("Multiple attempts made to assign app state")
            return
        }
        self.appState = appState
    }

    func chooseImages() {
        guard let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "过目" }),
              window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.image, .folder]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadImages(from: url)
            NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
        }
    }

    func loadImages(from url: URL, allowPermissionPrompt: Bool = true) {
        logger.info("loadImages from: \(url.path)")
        guard let appState else {
            return
        }

        guard appState.acquireReadAccess(to: url) else { return }

        // Check if URL is a directory
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if fileExists && isDirectory.boolValue {
            logger.info("Opening directory: \(url.path)")
            // Try indexing the directory directly
            switch indexFolder(url, currentURL: url, keepAccess: false) {
            case .indexed:
                appState.recentLocations.record(url, imageCount: appState.allImageFiles.count, isDirectory: true)
                appState.rememberBrowsingResource(url)
                logger.info("Indexed directory via bookmark/FDA: \(url.path)")
            case .noImages:
                if allowPermissionPrompt { showEmptyFolderAlert(for: url) }
            case .noAccess:
                // No permission — request permission for the directory
                logger.info("No access to directory \(url.path), prompting user...")
                if allowPermissionPrompt { promptFolderPermission(for: url, currentURL: url, isFolderOpen: true) }
            }
            return
        }

        // Keep the current photo and history unchanged if a recent file was moved or corrupted.
        guard fileExists, NSImage(contentsOf: url) != nil else {
            guard allowPermissionPrompt else { return }
            let alert = NSAlert()
            alert.messageText = String(localized: "这个最近记录无法打开，请重新选择图片或文件夹。")
            alert.runModal()
            return
        }
        appState.recentLocations.record(url, imageCount: 1, isDirectory: false)

        // Regular file loading
        appState.allImageFiles = [url]
        appState.imageFiles = [url]
        appState.selectedImageIndex = 0
        appState.selectedImageIndices = [0]
        appState.currentImageURL = url
        appState.rememberBrowsingResource(url)

        guard UserDefaults.standard.object(forKey: "showCurDirImg") as? Bool ?? true else {
            return
        }

        let directory = url.deletingLastPathComponent()

        // Try existing bookmark access. A readable folder without other pictures is fine:
        // the opened file is already on screen, so only a real access problem needs a prompt.
        switch indexFolder(directory, currentURL: url) {
        case .indexed:
            appState.recentLocations.record(url, imageCount: appState.allImageFiles.count, isDirectory: false)
            logger.info("Indexed via bookmark: \(directory.path)")
        case .noImages:
            logger.info("No other supported images in \(directory.path)")
        case .noAccess:
            // No permission — request via NSOpenPanel
            logger.info("No access to \(directory.path), prompting user...")
            if allowPermissionPrompt { promptFolderPermission(for: directory, currentURL: url, isFolderOpen: false) }
        }
    }

    private func showEmptyFolderAlert(for directory: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "文件夹里没有可浏览的图片")
        alert.informativeText = "\(directory.lastPathComponent)\n" + String(localized: "支持的格式：PNG、JPG、GIF、WebP")
        alert.alertStyle = .informational
        alert.runModal()
    }

    /// Request folder access permission via NSOpenPanel presented as a sheet on the main window.
    func promptFolderPermission(for directory: URL, currentURL: URL, isFolderOpen: Bool) {
        guard let appState else {
            return
        }
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "过目" }) else {
            logger.warning("No 过目 window found for sheet")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.message = String(localized: "允许 过目 访问此文件夹以浏览所有图片")
        panel.prompt = String(localized: "允许")

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let selectedURL = panel.url else { return }

            let gotAccess = selectedURL.startAccessingSecurityScopedResource()
            guard gotAccess else { return }

            if !appState.dirs.contains(selectedURL) {
                appState.dirs.append(selectedURL)
                appState.storeBookmarkData()
            }

            let result = self.indexFolder(selectedURL, currentURL: currentURL, keepAccess: true)
            if result == .indexed {
                appState.recentLocations.record(isFolderOpen ? selectedURL : currentURL,
                                               imageCount: appState.allImageFiles.count, isDirectory: isFolderOpen)
                appState.rememberBrowsingResource(isFolderOpen ? selectedURL : currentURL)
            }
            if result == .noImages, isFolderOpen {
                self.showEmptyFolderAlert(for: selectedURL)
            }
        }
    }

    enum IndexResult {
        /// Images were found and loaded into the app state.
        case indexed
        /// The folder could not be read (missing permission).
        case noAccess
        /// The folder is readable but holds no supported images.
        case noImages
    }

    /// Scan a directory for images.
    /// - Parameter keepAccess: If `false` (default), the method calls `startAccessingSecurityScopedResource()`
    ///   and manages the scope lifecycle internally. If `true`, the caller already has access established
    ///   (via NSOpenPanel or Full Disk Access) and the security-scope check is skipped.
    @discardableResult
    func indexFolder(_ directory: URL, currentURL: URL, keepAccess: Bool = false) -> IndexResult {
        guard let appState else {
            return .noAccess
        }

        var files: [URL]? = nil
        var startedHere = false

        // 1. First try direct read (no security scope access required, e.g. CLI non-sandbox or full disk access)
        files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        // 2. If direct read failed and we aren't bypassing security scope, try accessing via security scope
        if files == nil && !keepAccess {
            startedHere = directory.startAccessingSecurityScopedResource()
            if startedHere {
                files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            }
        }

        defer {
            if startedHere {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        guard let files = files else {
            logger.warning("Cannot read directory: \(directory.path)")
            return .noAccess
        }

        let imageFiles = files
            .filter { Constants.supportedImageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !imageFiles.isEmpty else {
            return .noImages
        }

        appState.allImageFiles = imageFiles
        appState.updateFilteredImages(preserveSelection: false)
        
        if let idx = appState.imageFiles.firstIndex(of: currentURL) {
            appState.selectedImageIndex = idx
            appState.selectedImageIndices = [idx]
            appState.currentImageURL = appState.imageFiles[idx]
        } else if !appState.imageFiles.isEmpty {
            appState.selectedImageIndex = 0
            appState.selectedImageIndices = [0]
            appState.currentImageURL = appState.imageFiles[0]
        }
        logger.info("Indexed \(imageFiles.count) images in folder, filtered: \(appState.imageFiles.count)")

        return .indexed
    }
}
