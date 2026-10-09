import Testing
import Foundation
import CoreGraphics
@testable import Glance

@Suite("Metadata Tests")
struct MetadataTests {
    
    @Test("ImageMetadata default values and serialization")
    func testImageMetadataSerialization() async throws {
        let meta = ImageMetadata(status: .keep, cropRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(meta)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ImageMetadata.self, from: data)
        
        #expect(decoded.status == .keep)
        #expect(decoded.cropRect == CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    }
    
    @Test("MetadataManager update and retrieve cache")
    @MainActor
    func testMetadataManagerCache() async throws {
        // Use a throwaway file so the test never touches the real metadata.json.
        let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: saveURL) }
        let manager = MetadataManager(saveURL: saveURL)
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy_image.jpg")
        
        // Initial state should be default (.undecided, nil)
        let initialMeta = manager.getMetadata(for: dummyURL)
        #expect(initialMeta.status == .undecided)
        #expect(initialMeta.cropRect == nil)
        
        // Update status to keep
        manager.updateMetadata(for: dummyURL) { meta in
            meta.status = .keep
        }
        
        let keepMeta = manager.getMetadata(for: dummyURL)
        #expect(keepMeta.status == .keep)
        
        // Update cropRect
        manager.updateMetadata(for: dummyURL) { meta in
            meta.cropRect = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        }
        
        let finalMeta = manager.getMetadata(for: dummyURL)
        #expect(finalMeta.status == .keep)
        #expect(finalMeta.cropRect == CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5))
        
        // Clean up
        manager.removeMetadata(for: dummyURL)
        let cleanedMeta = manager.getMetadata(for: dummyURL)
        #expect(cleanedMeta.status == .undecided)
    }

    @Test("Star rating, discard and legacy files")
    func testStarRating() throws {
        var meta = ImageMetadata()
        #expect(meta.rating == 0 && !meta.isDiscarded)

        meta.setRating(3)
        #expect(meta.rating == 3 && meta.status == .keep)

        meta.setDiscarded(true)
        #expect(meta.isDiscarded && meta.rating == 0)

        meta.setDiscarded(false)
        #expect(!meta.isDiscarded && meta.status == .undecided)

        meta.setRating(9)
        #expect(meta.rating == 5, "ratings are clamped to 5 stars")

        // Files written before stars existed only said "keep": that becomes the top rating.
        let legacy = try JSONDecoder().decode(ImageMetadata.self, from: Data(#"{"status":"keep"}"#.utf8))
        #expect(legacy.rating == 5)

        let roundTrip = try JSONDecoder().decode(ImageMetadata.self, from: JSONEncoder().encode(ImageMetadata(status: .keep, stars: 2)))
        #expect(roundTrip.rating == 2)
    }

    @Test("Filters match star levels, unrated and the discard pile")
    func testFilters() {
        let three = ImageMetadata(status: .keep, stars: 3)
        let discarded = ImageMetadata(status: .discard)
        let fresh = ImageMetadata()
        #expect(PhotoFilter.stars(3).matches(three) && !PhotoFilter.stars(4).matches(three))
        #expect(PhotoFilter.unrated.matches(fresh) && !PhotoFilter.unrated.matches(three))
        #expect(PhotoFilter.discarded.matches(discarded))
        #expect(PhotoFilter.all.matches(discarded))
        #expect(PhotoFilter.options(scale: 3).count == 6) // all, unrated, 3 stars, discarded
    }
}
