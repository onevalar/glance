import Combine
import Foundation

/// Normalized transforms remain relative to each photo's own fit, even when unlinked.
@MainActor
final class CompareSession: ObservableObject {
    struct Transform: Equatable {
        var zoom: CGFloat = 1
        var pan: CGPoint = .zero
    }

    @Published private(set) var isSynchronized = true
    @Published private(set) var activeURL: URL?
    @Published private var shared = Transform()
    @Published private var individual: [URL: Transform] = [:]
    private var urls: [URL] = []

    func select(_ selection: [URL]) {
        guard selection != urls else { return }
        urls = selection
        activeURL = selection.first
        shared = Transform()
        individual = Dictionary(uniqueKeysWithValues: selection.map { ($0, Transform()) })
    }

    func focus(_ url: URL) {
        guard urls.contains(url) else { return }
        activeURL = url
    }

    func transform(for url: URL) -> Transform {
        isSynchronized ? shared : individual[url, default: Transform()]
    }

    func update(_ transform: Transform, for url: URL) {
        guard urls.contains(url), transform.zoom.isFinite,
              transform.pan.x.isFinite, transform.pan.y.isFinite else { return }
        var valid = transform
        valid.zoom = valid.zoom.clamped(to: 0.1...16)
        if isSynchronized { shared = valid } else { individual[url] = valid }
    }

    func setSynchronized(_ enabled: Bool) {
        guard enabled != isSynchronized else { return }
        if enabled {
            if let activeURL { shared = individual[activeURL, default: Transform()] }
        } else {
            individual = Dictionary(uniqueKeysWithValues: urls.map { ($0, shared) })
        }
        isSynchronized = enabled
    }

    func zoom(by factor: CGFloat) {
        guard let activeURL, factor.isFinite, factor > 0 else { return }
        var value = transform(for: activeURL)
        value.zoom *= factor
        update(value, for: activeURL)
    }

    func fit() {
        guard let activeURL else { return }
        update(Transform(), for: activeURL)
    }
}
