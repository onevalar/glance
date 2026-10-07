import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Glance

@Suite("Image Rotator Tests")
struct ImageRotatorTests {

    /// 4x2 picture: left half red, right half blue.
    private func makeTestPNG() throws -> URL {
        let context = CGContext(
            data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 2, y: 0, width: 2, height: 2))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rotator-\(UUID().uuidString).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func load(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Returns "r" or "b" for the pixel at (x, y), counted from the top-left.
    private func color(of image: CGImage, x: Int, y: Int) throws -> Character {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // CGContext memory is stored top row first.
        let offset = y * context.bytesPerRow + x * 4
        return bytes[offset] > bytes[offset + 2] ? "r" : "b"
    }

    @Test("Clockwise: left half ends up on top")
    func clockwise() throws {
        let url = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageRotator.rotate(url, direction: .clockwise)
        let image = try load(url)

        #expect(image.width == 2 && image.height == 4)
        #expect(try color(of: image, x: 0, y: 0) == "r")
        #expect(try color(of: image, x: 0, y: 3) == "b")
    }

    @Test("Counter-clockwise: left half ends up at the bottom")
    func counterClockwise() throws {
        let url = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageRotator.rotate(url, direction: .counterClockwise)
        let image = try load(url)

        #expect(image.width == 2 && image.height == 4)
        #expect(try color(of: image, x: 0, y: 0) == "b")
        #expect(try color(of: image, x: 0, y: 3) == "r")
    }

    @Test("Four quarter turns restore the picture")
    func fullTurn() throws {
        let url = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        for _ in 0..<4 { try ImageRotator.rotate(url, direction: .clockwise) }
        let image = try load(url)

        #expect(image.width == 4 && image.height == 2)
        #expect(try color(of: image, x: 0, y: 0) == "r")
        #expect(try color(of: image, x: 3, y: 0) == "b")
    }

    @Test("Unsupported write format leaves the file untouched")
    func webpIsRefused() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-\(UUID().uuidString).webp")
        let original = Data([0x00, 0x01, 0x02])
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: (any Error).self) {
            try ImageRotator.rotate(url, direction: .clockwise)
        }
        #expect(try Data(contentsOf: url) == original)
    }
}
