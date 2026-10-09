import AppKit
import SwiftUI
import Testing
@testable import Glance

/// Renders the main window off-screen to a PNG so the layout can be compared with the Paper design.
/// Runs only when GLANCE_SNAPSHOT_DIR points to a folder of photos (output is written next to them).
@MainActor
@Suite("Snapshots")
struct SnapshotTests {
    @Test("Render browsing window")
    func renderBrowsing() async throws {
        guard let dir = ProcessInfo.processInfo.environment["GLANCE_SNAPSHOT_DIR"] else { return }
        let scheme: ColorScheme = ProcessInfo.processInfo.environment["GLANCE_SNAPSHOT_DARK"] == "0" ? .light : .dark
        let folder = URL(fileURLWithPath: dir)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { Constants.supportedImageExtensions.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix("snapshot") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let mode = ProcessInfo.processInfo.environment["GLANCE_SNAPSHOT_MODE"] ?? "browse"
        let state = AppState()
        if mode != "welcome" {
            state.allImageFiles = files
            state.updateFilteredImages(preserveSelection: false)
        }
        if mode == "compare" { state.selectedImageIndices = [0, 1] }
        if mode == "crop" { state.isCropEditing = true }

        let size = NSSize(width: 1280, height: 780)
        let root = ContentView()
            .environmentObject(state)
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: 100, y: 100))
        window.orderBack(nil)

        // Give async thumbnails and the image view a moment to load and lay out.
        for _ in 0..<30 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        hosting.layoutSubtreeIfNeeded()

        let frameView = try #require(window.contentView?.superview)
        let rep = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("snapshot-\(mode)-\(scheme == .dark ? "dark" : "light").png"))
    }
}
