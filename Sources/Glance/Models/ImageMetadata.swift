import Foundation
import CoreGraphics
import OSLog

public enum ImageStatus: String, Codable, Sendable {
    case discard
    case undecided
    case keep
}

public enum PhotoFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case keep = "保留"
    case undecided = "待定"
    case discard = "丢弃"
    
    public var id: String { self.rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .keep: return "flag.fill"
        case .undecided: return "questionmark.circle"
        case .discard: return "xmark.circle"
        }
    }
}

extension ImageStatus {
    /// Label used in the UI (matches the design: 丢弃 / 待定 / 保留).
    public var title: String {
        switch self {
        case .discard: return "丢弃"
        case .undecided: return "待定"
        case .keep: return "保留"
        }
    }
}

public struct ImageMetadata: Codable, Equatable, Sendable {
    public var status: ImageStatus
    public var cropRect: CGRect? // Normalized crop rectangle (values in 0.0...1.0)
    
    public init(status: ImageStatus = .undecided, cropRect: CGRect? = nil) {
        self.status = status
        self.cropRect = cropRect
    }
}

@MainActor
public class MetadataManager: ObservableObject {
    public static let shared = MetadataManager()
    
    @Published public var metadataCache: [String: ImageMetadata] = [:]
    
    private let queue = DispatchQueue(label: "com.glance.metadata.save", qos: .background)
    
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "Metadata")

    private let customSaveURL: URL?

    private var saveURL: URL {
        if let customSaveURL { return customSaveURL }
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Glance", isDirectory: true)
        // Ensure folder exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("metadata.json")
    }
    
    private convenience init() {
        self.init(saveURL: nil)
    }

    /// Pass a custom `saveURL` (e.g. in tests) to keep the user's real metadata file untouched.
    public init(saveURL: URL?) {
        self.customSaveURL = saveURL
        loadMetadata()
    }
    
    private func loadMetadata() {
        guard let data = try? Data(contentsOf: saveURL), !data.isEmpty else { return }
        do {
            let decoder = JSONDecoder()
            self.metadataCache = try decoder.decode([String: ImageMetadata].self, from: data)
        } catch {
            Self.logger.error("Failed to decode metadata: \(error), resetting cache.")
            self.metadataCache = [:]
            saveMetadata()
        }
    }
    
    public func saveMetadata() {
        let cache = self.metadataCache
        let url = self.saveURL
        queue.async {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(cache)
                try data.write(to: url)
            } catch {
                Self.logger.error("Failed to save metadata: \(error)")
            }
        }
    }
    
    private func cacheKey(for url: URL) -> String {
        return url.standardizedFileURL.path
    }
    
    public func getMetadata(for url: URL) -> ImageMetadata {
        getMetadata(forKey: cacheKey(for: url))
    }
    
    public func updateMetadata(for url: URL, update: (inout ImageMetadata) -> Void) {
        updateMetadata(forKey: cacheKey(for: url), update: update)
    }
    
    public func removeMetadata(for url: URL) {
        removeMetadata(forKey: cacheKey(for: url))
    }

    // MARK: - Raw key access (iOS stores ratings under the photo library identifier)

    public func getMetadata(forKey key: String) -> ImageMetadata {
        metadataCache[key] ?? ImageMetadata()
    }

    public func updateMetadata(forKey key: String, update: (inout ImageMetadata) -> Void) {
        var meta = metadataCache[key] ?? ImageMetadata()
        update(&meta)
        metadataCache[key] = meta
        saveMetadata()
    }

    public func removeMetadata(forKey key: String) {
        guard metadataCache.removeValue(forKey: key) != nil else { return }
        saveMetadata()
    }
}
