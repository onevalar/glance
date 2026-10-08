import Foundation
import Testing
@testable import Glance

@Suite("Browsing session")
@MainActor
struct BrowsingSessionTests {
    private func withDefaults(_ check: (UserDefaults) throws -> Void) rethrows {
        let name = "GlanceTests.session.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try check(defaults)
    }

    @Test("Restart keeps the last selected photo rather than the first image in a folder")
    func folderSession() throws {
        try withDefaults { defaults in
            let folder = URL(fileURLWithPath: "/tmp/session-photos")
            let first = folder.appendingPathComponent("01.png")
            let last = folder.appendingPathComponent("03.png")
            let store = BrowsingSessionStore(defaults: defaults)
            store.record(resource: folder, selectedPhoto: first)
            store.record(resource: folder, selectedPhoto: last)
            let restored = try BrowsingSessionStore(defaults: defaults).resolve()
            #expect(restored?.resource == folder)
            #expect(restored?.selectedPhoto == last)
        }
    }

    @Test("A single-file launch can remember a sibling selected through folder indexing")
    func fileSession() throws {
        try withDefaults { defaults in
            let first = URL(fileURLWithPath: "/tmp/session-file/01.png")
            let second = URL(fileURLWithPath: "/tmp/session-file/02.png")
            let store = BrowsingSessionStore(defaults: defaults)
            store.record(resource: first, selectedPhoto: second)
            let restored = try BrowsingSessionStore(defaults: defaults).resolve()
            #expect(restored?.selectedPhoto == second)
            store.record(resource: URL(string: "https://example.com/image.png")!, selectedPhoto: second)
            store.record(resource: first, selectedPhoto: URL(fileURLWithPath: "/tmp/unrelated/image.png"))
            #expect(store.session?.selectedPhoto == second)
        }
    }

    @Test("Missing or corrupt local state falls back without inventing a photo or requiring a prompt")
    func invalidSession() {
        withDefaults { defaults in
            #expect(BrowsingSessionStore(defaults: defaults).session == nil)
            defaults.set(Data("broken".utf8), forKey: "glance.browsingSession.v1")
            #expect(BrowsingSessionStore(defaults: defaults).session == nil)
            defaults.set(Data(repeating: 0, count: 1_048_577), forKey: "glance.browsingSession.v1")
            #expect(BrowsingSessionStore(defaults: defaults).session == nil)
        }
    }
}
