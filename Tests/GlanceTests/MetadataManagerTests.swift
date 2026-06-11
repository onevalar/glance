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
        let manager = MetadataManager.shared
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
}
