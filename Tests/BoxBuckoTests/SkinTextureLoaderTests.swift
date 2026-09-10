import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import BoxBucko

final class SkinTextureLoaderTests: XCTestCase {
    func testBundledDefaultSkinIsClassicNotSlim() throws {
        // Exercises the real production path end-to-end (PNG decode ->
        // normalize -> slim-detection) against a known-good classic
        // (4px-arm) skin, rather than hand-building a synthetic CGImage --
        // Core Graphics' bitmap row-ordering/flip conventions are subtle
        // enough that a hand-rolled test fixture is more likely to encode a
        // *test* bug than to usefully constrain the implementation.
        let loaded = try SkinTextureLoader.load(data: Self.classicSkinPNG)
        XCTAssertFalse(loaded.isSlim)
        XCTAssertEqual(loaded.texture.width, 64)
        XCTAssertEqual(loaded.texture.height, 64)
    }

    func testAllTransparentSkinReadsAsSlim() {
        // With no arm pixels painted at all, both classic-only markers are
        // (vacuously) transparent, so the heuristic should call it slim.
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let image = Self.makeCGImage(from: &bytes, width: 64, height: 64)
        XCTAssertTrue(SkinTextureLoader.detectSlimArms(in: image))
    }

    func testLegacy64x32SkinUpgradesTo64x64() throws {
        var bytes = [UInt8](repeating: 0, count: 64 * 32 * 4)
        let image = Self.makeCGImage(from: &bytes, width: 64, height: 32)
        let data = try Self.pngData(from: image)
        let loaded = try SkinTextureLoader.load(data: data)
        XCTAssertEqual(loaded.texture.width, 64)
        XCTAssertEqual(loaded.texture.height, 64)
    }

    // MARK: - Test fixtures

    /// A real, known-good classic (4px arm) 64x64 skin PNG, generated the
    /// same way `Sources/BoxBucko/Resources/steve.png` was and embedded here
    /// so the test doesn't depend on cross-target resource bundling.
    private static let classicSkinPNG: Data = {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAABUElEQVR4nO3avUoDQRiF4W8ltUELbfzBQrGyEauYG1ARvABbwUXijVjEIl6FRYrkCmKbWrAR0cY0QUlqrSfIDMtmc5DvfbrJ7LKHw0wSksksobm3/hObvzpvRu+/vHvMUs9QWlIHUKMAdQA1ClAHUKMAdQC1LPU5X7XBy6f0ewIr4Ok+l66A49uH/7EC8nbXGq2OmZk1Wh3L292qMi0UW4AtUECvP7Ref1hVFolakYvPTg+ryiGT7R+cBFugvrIWXPA1Hllsfrq7GoyXN7ajD/z+eCt0/fVkEIx3NsPnv76PovOpLeb+TZAC1AHUKEAdQI0C1AHU3BdQ27Ln8JVxOK7P3jEzP7WL+adaIPcrwH0BAAAAAAAAAHwpfTyl7PmCm6NJMJ73//8p7n8VpgB1ADUKUAdQowB1ADX3BRQ6KfqXsucLzLSnT92vAPcFAPDtF7EeQPC5XeIyAAAAAElFTkSuQmCC"
        return Data(base64Encoded: base64)!
    }()

    /// Builds a CGImage directly from a row-major RGBA byte buffer via a
    /// memcpy into the context's own backing store, sidestepping any
    /// ambiguity about how `draw`/`fill` behave under a flipped CTM.
    private static func makeCGImage(from bytes: inout [UInt8], width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let base = ctx.data!
        bytes.withUnsafeBytes { src in
            base.copyMemory(from: src.baseAddress!, byteCount: bytes.count)
        }
        return ctx.makeImage()!
    }

    private static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "SkinTextureLoaderTests", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "SkinTextureLoaderTests", code: 2)
        }
        return data as Data
    }
}
