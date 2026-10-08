import Combine
import Foundation

/// Local launch history. Bookmarks retain only access already granted by the file picker.
@MainActor
final class RecentLocationStore: ObservableObject {
    struct Entry: Codable, Identifiable {
        let id: String
        let url: URL
        var bookmark: Data?
        var openedAt: Date
        var imageCount: Int
        var isDirectory: Bool
    }

    @Published private(set) var entries: [Entry] = []
    private let defaults: UserDefaults
    private let key = "glance.recentLocations.v1"
    private let limit = 6

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key), data.count <= 1_048_576,
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        var seen = Set<String>()
        entries = decoded.sorted { $0.openedAt > $1.openedAt }.filter {
            $0.url.isFileURL && $0.id == $0.url.standardizedFileURL.path && $0.imageCount > 0 &&
            $0.openedAt.timeIntervalSince1970.isFinite && ($0.bookmark?.count ?? 0) <= 131_072 && seen.insert($0.id).inserted
        }.prefix(limit).map { $0 }
    }

    func record(_ url: URL, imageCount: Int, isDirectory: Bool, now: Date = .now) {
        guard url.isFileURL, imageCount > 0 else { return }
        let normalized = url.standardizedFileURL
        let id = normalized.path
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let entry = Entry(id: id, url: normalized, bookmark: bookmark,
                          openedAt: now, imageCount: imageCount, isDirectory: isDirectory)
        entries.removeAll { $0.id == id }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(limit))
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }

    func resolve(_ entry: Entry) throws -> URL {
        guard let bookmark = entry.bookmark else { return entry.url }
        var stale = false
        // Resolving is not an authorization: the open path still checks scoped/readable access.
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
