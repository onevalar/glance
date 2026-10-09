import Foundation
import CoreGraphics
import OSLog

public enum ImageStatus: String, Codable, Sendable {
    case discard
    case undecided
    case keep
}

/// Which photos are shown: everything, unrated, one star level, or the discard pile.
public enum PhotoFilter: Hashable, Identifiable, Sendable {
    case all
    case unrated
    case stars(Int)
    case discarded

    public var id: String {
        switch self {
        case .all: return "all"
        case .unrated: return "unrated"
        case .stars(let n): return "stars\(n)"
        case .discarded: return "discarded"
        }
    }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .unrated: return "未评分"
        case .stars(let n): return "\(n) 星"
        case .discarded: return "已丢弃"
        }
    }

    public var symbol: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .unrated: return "star.slash"
        case .stars: return "star.fill"
        case .discarded: return "trash"
        }
    }

    /// Options offered for the chosen star scale (3 or 5), best rating first.
    public static func options(scale: Int) -> [PhotoFilter] {
        [.all, .unrated] + (1...max(1, min(scale, 5))).reversed().map { .stars($0) } + [.discarded]
    }

    public func matches(_ meta: ImageMetadata) -> Bool {
        switch self {
        case .all: return true
        case .unrated: return meta.status == .undecided
        case .stars(let n): return meta.rating == n
        case .discarded: return meta.status == .discard
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

/// One photo's rating.
/// - `status == .discard`: marked for removal (nothing is deleted until the user confirms).
/// - `status == .keep`: rated with `stars` (1…5).
/// - `status == .undecided`: not rated yet.
public struct ImageMetadata: Codable, Equatable, Sendable {
    public var status: ImageStatus
    /// 1…5 while `status == .keep`; 0 otherwise.
    public var stars: Int
    public var cropRect: CGRect? // Normalized crop rectangle (values in 0.0...1.0)

    public init(status: ImageStatus = .undecided, stars: Int? = nil, cropRect: CGRect? = nil) {
        self.status = status
        self.stars = status == .keep ? min(max(stars ?? 5, 1), 5) : 0
        self.cropRect = cropRect
    }

    private enum CodingKeys: String, CodingKey { case status, stars, cropRect }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decodeIfPresent(ImageStatus.self, forKey: .status) ?? .undecided
        // Files written before star ratings existed stored "keep" only: treat it as the top rating.
        let stars = try container.decodeIfPresent(Int.self, forKey: .stars)
        self.init(status: status, stars: stars, cropRect: try container.decodeIfPresent(CGRect.self, forKey: .cropRect))
    }

    /// Rating shown to the user: 0 (none), or 1…5.
    public var rating: Int { status == .keep ? stars : 0 }

    public var isDiscarded: Bool { status == .discard }

    public mutating func setRating(_ value: Int) {
        let clamped = min(max(value, 0), 5)
        status = clamped == 0 ? .undecided : .keep
        stars = clamped
    }

    public mutating func setDiscarded(_ discarded: Bool) {
        if discarded {
            status = .discard
            stars = 0
        } else if status == .discard {
            status = .undecided
        }
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

    /// Forgets every rating and crop (used by UI tests to start from a clean slate).
    public func removeAllMetadata() {
        metadataCache.removeAll()
        saveMetadata()
    }

    public func removeMetadata(forKey key: String) {
        guard metadataCache.removeValue(forKey: key) != nil else { return }
        saveMetadata()
    }
}
