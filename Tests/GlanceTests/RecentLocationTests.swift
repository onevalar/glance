import Foundation
import Testing
@testable import Glance

@Suite("Recent locations")
@MainActor
struct RecentLocationTests {
    private func withDefaults(_ check: (UserDefaults) throws -> Void) rethrows {
        let suite = "GlanceTests.recent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(defaults)
    }

    @Test("Reopening updates the row and persists recency without duplicate locations")
    func reopening() throws {
        try withDefaults { (defaults: UserDefaults) throws in
            let store = RecentLocationStore(defaults: defaults)
            let first = URL(fileURLWithPath: "/tmp/glance-recent-a")
            let second = URL(fileURLWithPath: "/tmp/glance-recent-b")
            store.record(first, imageCount: 2, isDirectory: true, now: Date(timeIntervalSince1970: 100))
            store.record(second, imageCount: 3, isDirectory: true, now: Date(timeIntervalSince1970: 200))
            store.record(first, imageCount: 4, isDirectory: true, now: Date(timeIntervalSince1970: 300))
            let restored = RecentLocationStore(defaults: defaults)
            #expect(restored.entries.map(\.url) == [first, second])
            #expect(restored.entries.first?.imageCount == 4)
            #expect(restored.entries.first?.openedAt == Date(timeIntervalSince1970: 300))
            let resolved = try restored.resolve(restored.entries[0])
            #expect(resolved == first)
        }
    }

    @Test("History is bounded and does not accept remote URLs or unsuccessful empty opens")
    func bounded() {
        withDefaults { defaults in
            let store = RecentLocationStore(defaults: defaults)
            for index in 0..<10 {
                store.record(URL(fileURLWithPath: "/tmp/glance-recent-\(index)"), imageCount: 1, isDirectory: false)
            }
            let validIDs = store.entries.map(\.id)
            store.record(URL(string: "https://example.com/photo.png")!, imageCount: 1, isDirectory: false)
            store.record(URL(fileURLWithPath: "/tmp/empty-folder"), imageCount: 0, isDirectory: true)
            #expect(store.entries.count == 6)
            #expect(store.entries.map(\.id) == validIDs)
            #expect(RecentLocationStore(defaults: defaults).entries.count == 6)
        }
    }

    @Test("Unreadable saved preferences do not crash or fabricate recent rows")
    func corrupt() {
        withDefaults { defaults in
            defaults.set(Data("invalid".utf8), forKey: "glance.recentLocations.v1")
            #expect(RecentLocationStore(defaults: defaults).entries.isEmpty)
            defaults.set(Data(repeating: 0, count: 1_048_577), forKey: "glance.recentLocations.v1")
            #expect(RecentLocationStore(defaults: defaults).entries.isEmpty)
        }
    }
}
