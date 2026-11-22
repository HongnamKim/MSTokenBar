import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

/// No NSApplication, hosting view, or window: exercise the exact load path used by SpriteView and the
/// menu bar. Sprites are bundled or already on disk, so a miss is final and nothing retries.
@MainActor
final class SpriteAnimationRecoveryTests: XCTestCase {
    private func gifData() throws -> Data {
        func pixels(_ red: CGFloat, _ green: CGFloat) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            return try XCTUnwrap(context.makeImage())
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        for (red, green) in [(CGFloat(1), CGFloat(0)), (CGFloat(0), CGFloat(1))] {
            CGImageDestinationAddImage(destination, try pixels(red, green),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("animation-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testWarmGIFCacheReturnsFramesWithoutFallback() async throws {
        let dir = try directory()
        try gifData().write(to: dir.appendingPathComponent("176-sha.gif"))
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 176, shiny: true, store: SpriteStore(directory: dir),
            onUnavailable: { XCTFail("a warm GIF needs no static fallback") })
        XCTAssertEqual(frames.map(\.delay), [0.1, 0.1])
    }

    func testShinyMissStillUsesTheNormalGIF() async throws {
        let dir = try directory()
        try gifData().write(to: dir.appendingPathComponent("176-a.gif"))
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 176, shiny: true, store: SpriteStore(directory: dir),
            onUnavailable: { XCTFail("a normal GIF fallback needs no static placeholder") })
        XCTAssertEqual(frames.count, 2)
    }

    func testMissingGIFShowsTheStaticFallbackOnceAndDoesNotRetry() async throws {
        let dir = try directory()
        var fallbackCount = 0
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 176, shiny: false, store: SpriteStore(directory: dir),
            onUnavailable: { fallbackCount += 1 })
        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(fallbackCount, 1)
    }

    func testBundledGunplaArtLoadsWithoutAnyCacheFile() async throws {
        let id = GunplaID.encode(machineID: 1, grade: .hg)
        let frames = await SpriteLoader.animationFrames(speciesID: id, shiny: false,
                                                        store: SpriteStore(directory: try directory()))
        XCTAssertFalse(frames.isEmpty)
    }

    func testBackRequestFallsBackToTheFrontGIF() async throws {
        let id = GunplaID.encode(machineID: 1, grade: .hg)
        let dir = try directory()
        let back = await SpriteLoader.animationFrames(speciesID: id, shiny: false,
                                                      store: SpriteStore(directory: dir), back: true)
        let front = await SpriteLoader.animationFrames(speciesID: id, shiny: false,
                                                       store: SpriteStore(directory: dir))
        XCTAssertEqual(back.count, front.count, "Gunpla has no back art by design: the front animation plays")
    }

    func testUnsupportedSpeciesLoadsStaticOnce() async throws {
        let dir = try directory()
        var fallbackCount = 0
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 1000, shiny: false, store: SpriteStore(directory: dir),
            onUnavailable: { fallbackCount += 1 })
        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(fallbackCount, 1)
    }

    func testAlreadyCancelledLoadDoesNotApplyFallback() async throws {
        let dir = try directory()
        let task = Task<Void, Never> { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            let frames = await SpriteLoader.recoveringAnimationFrames(
                speciesID: 176, shiny: false, store: SpriteStore(directory: dir),
                onUnavailable: { XCTFail("cancelled views must not apply a fallback") })
            XCTAssertTrue(frames.isEmpty)
        }
        await task.value
    }
}
