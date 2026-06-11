import Foundation
import CoreGraphics

public enum ImageStatus: String, Codable {
    case discard
    case undecided
    case keep
}

public struct ImageMetadata: Codable, Equatable {
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
    
    private var saveURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Glance", isDirectory: true)
        // Ensure folder exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("metadata.json")
    }
    
    private init() {
        loadMetadata()
    }
    
    private func loadMetadata() {
        guard let data = try? Data(contentsOf: saveURL), !data.isEmpty else { return }
        do {
            let decoder = JSONDecoder()
            self.metadataCache = try decoder.decode([String: ImageMetadata].self, from: data)
        } catch {
            print("Failed to decode metadata: \(error), resetting cache.")
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
                print("Failed to save metadata: \(error)")
            }
        }
    }
    
    private func cacheKey(for url: URL) -> String {
        return url.standardizedFileURL.path
    }
    
    public func getMetadata(for url: URL) -> ImageMetadata {
        let key = cacheKey(for: url)
        return metadataCache[key] ?? ImageMetadata()
    }
    
    public func updateMetadata(for url: URL, update: (inout ImageMetadata) -> Void) {
        let key = cacheKey(for: url)
        var meta = metadataCache[key] ?? ImageMetadata()
        update(&meta)
        metadataCache[key] = meta
        saveMetadata()
    }
    
    public func removeMetadata(for url: URL) {
        let key = cacheKey(for: url)
        metadataCache.removeValue(forKey: key)
        saveMetadata()
    }
}
