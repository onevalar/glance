import AppKit
import Testing
@testable import Glance

@MainActor
@Test("Changing appearance redraws the canvas without resetting zoom or pan")
func appearancePreservesTransform() {
    let view = GlanceImageView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    defer { window.close() }
    view.magnification = 2
    view.offset = CGPoint(x: 24, y: -12)
    view.needsDisplay = false
    view.isDarkMode = true
    #expect(view.needsDisplay)
    #expect(view.magnification == 2)
    #expect(view.offset == CGPoint(x: 24, y: -12))
}
