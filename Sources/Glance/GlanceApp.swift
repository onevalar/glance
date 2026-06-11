//
//  GlanceApp.swift
//  Glance
//
//  Created by 李旭 on 2024/9/1.
//

import AppKit
import SwiftUI

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
}
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton()
            }
            CommandMenu("照片") {
                Button("标记为保留") {
                    appState.setStatusForSelectedImages(.keep)
                }
                .keyboardShortcut("p", modifiers: [])
                
                Button("标记为不确定") {
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
                
                Button("评分：2 (不确定)") {
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
        print("[GLANCE DEBUG] applicationDidFinishLaunching started")
        appState?.activate(withPolicy: .regular)
        print("[GLANCE DEBUG] appState activated")
        
        // Support launching from CLI with file path argument (e.g. swift run Glance /path/to/image.jpg)
        let arguments = CommandLine.arguments
        print("[GLANCE DEBUG] arguments: \(arguments)")
        // The first argument is the binary path. If we have a second argument, try to open it as a file
        if arguments.count > 1 {
            let path = arguments[1]
            print("[GLANCE DEBUG] argument path: \(path)")
            if !path.hasPrefix("-") && FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                print("[GLANCE DEBUG] file url: \(url)")
                logger.info("Opening image from CLI argument: \(url.path)")
                loadImages(from: url)
                print("[GLANCE DEBUG] loadImages finished")
                NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
                print("[GLANCE DEBUG] notification posted")
            } else {
                print("[GLANCE DEBUG] path does not exist or is flag: \(path)")
            }
        } else {
            print("[GLANCE DEBUG] no arguments count > 1")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 当最后一个窗口关闭时，终止应用
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
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
        print("applicationShouldTerminate")
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

    func loadImages(from url: URL) {
        print("[GLANCE DEBUG] loadImages called with: \(url.path)")
        logger.info("loadImages from: \(url.path)")
        guard let appState else {
            print("[GLANCE DEBUG] loadImages failed: appState is nil")
            return
        }

        // Check if URL is a directory
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        print("[GLANCE DEBUG] fileExists: \(fileExists), isDirectory: \(isDirectory.boolValue)")
        
        if fileExists && isDirectory.boolValue {
            logger.info("Opening directory: \(url.path)")
            // Try indexing the directory directly
            print("[GLANCE DEBUG] loadImages: indexing directory directly...")
            if indexFolder(url, currentURL: url, keepAccess: false) {
                logger.info("Indexed directory via bookmark/FDA: \(url.path)")
                print("[GLANCE DEBUG] loadImages: indexFolder succeeded for \(url.path)")
                return
            }
            
            // No permission — request permission for the directory
            logger.info("No access to directory \(url.path), prompting user...")
            print("[GLANCE DEBUG] loadImages: indexFolder failed, prompting permission...")
            promptFolderPermission(for: url, currentURL: url)
            return
        }

        // Regular file loading
        print("[GLANCE DEBUG] loadImages: loading single file...")
        appState.allImageFiles = [url]
        appState.imageFiles = [url]
        appState.selectedImageIndex = 0
        appState.selectedImageIndices = [0]
        appState.currentImageURL = url

        guard UserDefaults.standard.object(forKey: "showCurDirImg") as? Bool ?? true else {
            print("[GLANCE DEBUG] loadImages: showCurDirImg is false, skipping sibling folder indexing")
            return
        }

        let directory = url.deletingLastPathComponent()
        print("[GLANCE DEBUG] loadImages: trying bookmark indexing for parent: \(directory.path)")

        // Try existing bookmark access
        if indexFolder(directory, currentURL: url) {
            logger.info("Indexed via bookmark: \(directory.path)")
            print("[GLANCE DEBUG] loadImages: indexFolder bookmark succeeded for parent")
            return
        }

        // No permission — request via NSOpenPanel
        logger.info("No access to \(directory.path), prompting user...")
        print("[GLANCE DEBUG] loadImages: parent indexing failed, prompting permission for parent...")
        promptFolderPermission(for: directory, currentURL: url)
    }

    /// Request folder access permission via NSOpenPanel presented as a sheet on the main window.
    func promptFolderPermission(for directory: URL, currentURL: URL) {
        print("[GLANCE DEBUG] promptFolderPermission called for: \(directory.path)")
        guard let appState else {
            print("[GLANCE DEBUG] promptFolderPermission: appState is nil")
            return
        }
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "过目" }) else {
            logger.warning("No 过目 window found for sheet")
            print("[GLANCE DEBUG] promptFolderPermission: NO WINDOW FOUND named '过目' for sheet!")
            return
        }

        print("[GLANCE DEBUG] promptFolderPermission: presenting NSOpenPanel...")
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.message = String(localized: "允许 过目 访问此文件夹以浏览所有图片")
        panel.prompt = String(localized: "允许")

        panel.beginSheetModal(for: window) { response in
            print("[GLANCE DEBUG] promptFolderPermission NSOpenPanel sheet completion, response: \(response.rawValue)")
            guard response == .OK, let selectedURL = panel.url else { return }

            print("[GLANCE DEBUG] promptFolderPermission: user approved, trying security scoped resource")
            let gotAccess = selectedURL.startAccessingSecurityScopedResource()
            print("[GLANCE DEBUG] promptFolderPermission: startAccessingSecurityScopedResource: \(gotAccess)")
            guard gotAccess else { return }

            if !appState.dirs.contains(selectedURL) {
                appState.dirs.append(selectedURL)
                appState.storeBookmarkData()
            }

            self.indexFolder(selectedURL, currentURL: currentURL, keepAccess: true)
        }
    }

    /// Scan a directory for images.
    /// - Parameter keepAccess: If `false` (default), the method calls `startAccessingSecurityScopedResource()`
    ///   and manages the scope lifecycle internally. If `true`, the caller already has access established
    ///   (via NSOpenPanel or Full Disk Access) and the security-scope check is skipped.
    @discardableResult
    func indexFolder(_ directory: URL, currentURL: URL, keepAccess: Bool = false) -> Bool {
        print("[GLANCE DEBUG] indexFolder called for: \(directory.path), keepAccess: \(keepAccess)")
        guard let appState else {
            print("[GLANCE DEBUG] indexFolder: appState is nil")
            return false
        }

        var files: [URL]? = nil
        var startedHere = false

        // 1. First try direct read (no security scope access required, e.g. CLI non-sandbox or full disk access)
        print("[GLANCE DEBUG] indexFolder: attempting direct directory read...")
        files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        print("[GLANCE DEBUG] indexFolder: direct read got files: \(files != nil ? "\(files!.count) files" : "nil")")

        // 2. If direct read failed and we aren't bypassing security scope, try accessing via security scope
        if files == nil && !keepAccess {
            print("[GLANCE DEBUG] indexFolder: direct read failed, trying startAccessingSecurityScopedResource...")
            startedHere = directory.startAccessingSecurityScopedResource()
            print("[GLANCE DEBUG] indexFolder: startAccessingSecurityScopedResource returned: \(startedHere)")
            if startedHere {
                files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                print("[GLANCE DEBUG] indexFolder: security scoped read got files: \(files != nil ? "\(files!.count) files" : "nil")")
            }
        }

        defer {
            if startedHere {
                print("[GLANCE DEBUG] indexFolder: stopping security scoped resource access")
                directory.stopAccessingSecurityScopedResource()
            }
        }

        guard let files = files else {
            logger.warning("Cannot read directory: \(directory.path)")
            print("[GLANCE DEBUG] indexFolder: files is nil (access denied), returning false")
            return false
        }

        let imageFiles = files
            .filter { Constants.supportedImageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        print("[GLANCE DEBUG] indexFolder: found \(imageFiles.count) image files")
        guard !imageFiles.isEmpty else {
            print("[GLANCE DEBUG] indexFolder: imageFiles is empty, returning false")
            return false
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
        print("[GLANCE DEBUG] indexFolder complete, returning true")

        return true
    }
}
