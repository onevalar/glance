import Foundation
import Testing
@testable import Glance

@Suite("Non-destructive crop interaction")
struct CropSessionTests {
    private func close(_ first: CGFloat, _ second: CGFloat) -> Bool { abs(first - second) < 0.000001 }
    private func same(_ first: CGRect, _ second: CGRect) -> Bool {
        close(first.minX, second.minX) && close(first.minY, second.minY) && close(first.width, second.width) && close(first.height, second.height)
    }

    @Test("Invalid metadata cannot create nonfinite or empty crop frames")
    func invalidRects() {
        for rect in [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: -1, height: 1), CGRect(x: 2, y: 2, width: 1, height: 1)] {
            #expect(CropSession(rect: rect).rect == CropSession.fullImage)
        }
        #expect(same(CropSession(rect: CGRect(x: -0.1, y: 0.2, width: 0.5, height: 0.6)).rect, CGRect(x: 0, y: 0.2, width: 0.4, height: 0.6)))
        #expect(CropGeometry.imageFrame(imageSize: .zero, viewport: CGSize(width: 900, height: 600)) == .zero)
    }

    @Test("An unsaved crop and its physical aspect ratio survive multiple window sizes")
    func resizedWindow() {
        let image = CGSize(width: 1200, height: 800)
        var session = CropSession(rect: CGRect(x: 0.35, y: 0.2, width: 0.6, height: 0.5))
        session.selectRatio(.sixteenNine, imageSize: image)
        let initial = session.rect
        for viewport in [CGSize(width: 1000, height: 652), CGSize(width: 460, height: 400), CGSize(width: 1400, height: 900)] {
            let frame = CropGeometry.imageFrame(imageSize: image, viewport: viewport)
            let displayed = session.displayRect(in: frame)
            #expect(close(displayed.width / displayed.height, 16 / 9))
            session.update(displayRect: displayed, imageFrame: frame)
            #expect(same(session.rect, initial))
            #expect(session.ratio == .sixteenNine)
        }
        session.reset()
        #expect(session.rect == CropSession.fullImage)
        #expect(session.ratio == .free)
    }

    @Test("Free corner and edge drags use translations, retain opposite edges, and clamp at the image boundary")
    func freeHandles() {
        let bounds = CGRect(x: 80, y: 100, width: 600, height: 400)
        let box = CGRect(x: 180, y: 180, width: 200, height: 160)
        for handle in CropHandle.allCases {
            let direction = handle.direction
            let resized = CropGeometry.resized(box, handle: handle, by: CGSize(width: direction.x * 30, height: direction.y * 20), in: bounds, ratio: nil)
            #expect(close(resized.width, box.width + (direction.x == 0 ? 0 : 30)))
            #expect(close(resized.height, box.height + (direction.y == 0 ? 0 : 20)))
            #expect(close(direction.x < 0 ? resized.maxX : resized.minX, direction.x < 0 ? box.maxX : box.minX))
            #expect(close(direction.y < 0 ? resized.maxY : resized.minY, direction.y < 0 ? box.maxY : box.minY))
            let expanded = CropGeometry.resized(box, handle: handle, by: CGSize(width: direction.x * 9999, height: direction.y * 9999), in: bounds, ratio: nil)
            #expect(bounds.contains(expanded))
            let crossed = CropGeometry.resized(box, handle: handle, by: CGSize(width: -direction.x * 9999, height: -direction.y * 9999), in: bounds, ratio: nil)
            #expect(crossed.width >= 40 && crossed.height >= 40)
        }
    }

    @Test("Locked corners retain their ratio and fixed opposite corner even against boundaries")
    func lockedCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 500)
        let ratios: [CGFloat] = [1, 4 / 3, 16 / 9, 2 / 3]
        for ratio in ratios {
            let box = CropGeometry.applyingRatio(ratio, to: CGRect(x: 300, y: 260, width: 220, height: 180), in: bounds)
            #expect(close(box.width / box.height, ratio))
            #expect(bounds.contains(box))
            for handle in CropHandle.allCases where handle.isCorner {
                for amount in [CGFloat(-9999), -30, 0, 30, 9999] {
                    let direction = handle.direction
                    let changed = CropGeometry.resized(box, handle: handle, by: CGSize(width: direction.x * amount, height: direction.y * amount), in: bounds, ratio: ratio)
                    #expect(close(changed.width / changed.height, ratio))
                    #expect(changed.minX >= bounds.minX - 0.000001 && changed.minY >= bounds.minY - 0.000001)
                    #expect(changed.maxX <= bounds.maxX + 0.000001 && changed.maxY <= bounds.maxY + 0.000001)
                    #expect(close(direction.x < 0 ? changed.maxX : changed.minX, direction.x < 0 ? box.maxX : box.minX))
                    #expect(close(direction.y < 0 ? changed.maxY : changed.minY, direction.y < 0 ? box.maxY : box.minY))
                    if amount == 0 { #expect(same(changed, box)) }
                }
            }
        }
    }

    @Test("Moving a crop keeps its size and clamps all four edges")
    func movingBox() {
        let bounds = CGRect(x: 20, y: 30, width: 600, height: 400)
        let box = CGRect(x: 90, y: 60, width: 220, height: 150)
        for delta in [CGSize(width: -999, height: -999), CGSize(width: 999, height: 999), CGSize(width: 18, height: -12)] {
            let moved = CropGeometry.moved(box, by: delta, in: bounds)
            #expect(moved.size == box.size)
            #expect(bounds.contains(moved))
        }
    }

    @Test("Only commit persists crop metadata; original bytes remain unchanged and reset can be cancelled")
    @MainActor
    func commitAndCancel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("original.png")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: photo)
        let metadata = directory.appendingPathComponent("metadata.json")
        let store = MetadataManager(saveURL: metadata)
        let committed = CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        store.updateMetadata(for: photo) { $0.cropRect = committed }
        var draft = CropSession(rect: store.getMetadata(for: photo).cropRect)
        draft.selectRatio(.square, imageSize: CGSize(width: 1200, height: 800))
        #expect(store.getMetadata(for: photo).cropRect == committed)
        store.updateMetadata(for: photo) { $0.cropRect = draft.rect }
        var persisted = false
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: metadata),
               let saved = try? JSONDecoder().decode([String: ImageMetadata].self, from: data),
               saved[photo.standardizedFileURL.path]?.cropRect == draft.rect { persisted = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(persisted)
        #expect(MetadataManager(saveURL: metadata).getMetadata(for: photo).cropRect == draft.rect)
        draft.reset()
        #expect(store.getMetadata(for: photo).cropRect != draft.rect)
        #expect(try Data(contentsOf: photo) == bytes)
    }
}
