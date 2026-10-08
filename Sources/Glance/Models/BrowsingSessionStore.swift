import Foundation

enum GlanceStartup: String, CaseIterable, Identifiable {
    case welcome, resume
    var id: String { rawValue }
}

/// Stores only the local resource already opened and its selected photo, never image bytes.
@MainActor
final class BrowsingSessionStore {
    struct Session: Codable {
        let resource: URL
        let bookmark: Data?
        let selectedPhoto: URL
    }
    private let defaults: UserDefaults
    private let key = "glance.browsingSession.v1"
    private(set) var session: Session?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key), data.count <= 1_048_576,
              let saved = try? JSONDecoder().decode(Session.self, from: data),
              saved.resource.isFileURL, saved.selectedPhoto.isFileURL,
              (saved.bookmark?.count ?? 0) <= 131_072,
              Self.contains(saved.selectedPhoto, in: saved.resource) else { return }
        session = saved
    }

    static func contains(_ photo: URL, in resource: URL) -> Bool {
        let photo = photo.standardizedFileURL
        let resource = resource.standardizedFileURL
        return photo.path == resource.path || photo.deletingLastPathComponent().path == resource.path ||
            photo.deletingLastPathComponent().path == resource.deletingLastPathComponent().path
    }

    func record(resource: URL, selectedPhoto: URL) {
        guard resource.isFileURL, selectedPhoto.isFileURL,
              Self.contains(selectedPhoto, in: resource) else { return }
        let bookmark: Data?
        if session?.resource.path == resource.standardizedFileURL.path { bookmark = session?.bookmark }
        else { bookmark = try? resource.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil) }
        let saved = Session(resource: resource.standardizedFileURL, bookmark: bookmark,
                            selectedPhoto: selectedPhoto.standardizedFileURL)
        guard let data = try? JSONEncoder().encode(saved), data.count <= 1_048_576 else { return }
        defaults.set(data, forKey: key)
        session = saved
    }

    func resolve() throws -> (resource: URL, selectedPhoto: URL)? {
        guard let session else { return nil }
        var resource = session.resource
        if let bookmark = session.bookmark {
            var stale = false
            resource = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        let selected: URL
        if session.selectedPhoto.path == session.resource.path { selected = resource }
        else if session.selectedPhoto.deletingLastPathComponent().path == session.resource.path {
            selected = resource.appendingPathComponent(session.selectedPhoto.lastPathComponent)
        } else { selected = resource.deletingLastPathComponent().appendingPathComponent(session.selectedPhoto.lastPathComponent) }
        return (resource, selected)
    }
}
