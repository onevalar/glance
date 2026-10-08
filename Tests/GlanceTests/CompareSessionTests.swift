import AppKit
import Testing
@testable import Glance

@Suite("Compare interaction")
@MainActor
struct CompareSessionTests {
    private let first = URL(fileURLWithPath: "/tmp/compare-a.png")
    private let second = URL(fileURLWithPath: "/tmp/compare-b.png")

    @Test("Unlink preserves framing; individual gestures and toolbar affect only the focused photo")
    func unlinkAndRelink() {
        let session = CompareSession()
        session.select([first, second])
        session.update(.init(zoom: 2, pan: CGPoint(x: 0.2, y: -0.1)), for: first)
        #expect(session.transform(for: second) == session.transform(for: first))
        session.setSynchronized(false)
        session.focus(second)
        session.zoom(by: 1.25)
        #expect(session.transform(for: first).zoom == 2)
        #expect(session.transform(for: second).zoom == 2.5)
        session.setSynchronized(true)
        #expect(session.transform(for: first) == session.transform(for: second))
        #expect(session.transform(for: first).zoom == 2.5)
        session.fit()
        #expect(session.transform(for: first) == CompareSession.Transform())
    }

    @Test("A changed selection clears stale transforms and rejects late callbacks from removed photos")
    func selectionChanges() {
        let session = CompareSession()
        session.select([first, second])
        session.focus(second)
        session.setSynchronized(false)
        session.zoom(by: 4)
        session.select([first])
        session.update(.init(zoom: 5), for: second)
        session.focus(second)
        #expect(session.activeURL == first)
        #expect(session.transform(for: first).zoom == 1)
        session.update(.init(zoom: .nan), for: first)
        #expect(session.transform(for: first).zoom == 1)
    }

    @Test("Different image dimensions use their own fit and the same normalized pan")
    func normalizedRendering() {
        let landscape = GlanceImageView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        landscape.image = NSImage(size: NSSize(width: 600, height: 300))
        let portrait = GlanceImageView(frame: landscape.frame)
        portrait.image = NSImage(size: NSSize(width: 200, height: 400))
        landscape.applyShared(zoom: 2, pan: CGPoint(x: 0.1, y: -0.2))
        portrait.applyShared(zoom: 2, pan: CGPoint(x: 0.1, y: -0.2))
        #expect(landscape.magnification == 1)
        #expect(portrait.magnification == 1.5)
        #expect(landscape.offset == CGPoint(x: 60, y: -60))
        #expect(portrait.offset == CGPoint(x: 30, y: -120))
    }
}
