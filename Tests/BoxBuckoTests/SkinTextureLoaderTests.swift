import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import BoxBucko

final class SkinTextureLoaderTests: XCTestCase {
    func testDetectSlimArmsFalseWhenClassicMarkersOpaque() {
        // Both classic-only marker pixels painted -> should read as NOT slim.
        let image = makeTestImage(opaqueAt: [(54, 20), (46, 52)])
        XCTAssertFalse(SkinTextureLoader.detectSlimArms(in: image))
    }

    func testDetectSlimArmsTrueWhenMarkersTransparent() {
        // Neither marker painted (as on a real slim skin, where that extra
        // arm-width column is never drawn) -> should read as slim.
        let image = makeTestImage(opaqueAt: [])
        XCTAssertTrue(SkinTextureLoader.detectSlimArms(in: image))
    }

    func testDetectSlimArmsFalseWhenOnlyOneMarkerOpaque() {
        // Mixed signal (e.g. an unusual skin) should default to classic
        // rather than slim, since it takes both markers agreeing to call it slim.
        let image = makeTestImage(opaqueAt: [(54, 20)])
        XCTAssertFalse(SkinTextureLoader.detectSlimArms(in: image))
    }

    func testLegacy64x32SkinUpgradesTo64x64() throws {
        let legacyImage = makeTestImage(opaqueAt: [(4, 4)], width: 64, height: 32)
        let data = try pngData(from: legacyImage)
        let loaded = try SkinTextureLoader.load(data: data)
        XCTAssertEqual(loaded.texture.width, 64)
        XCTAssertEqual(loaded.texture.height, 64)
    }

    // MARK: - Test helpers

    /// Builds a 64x`height` RGBA test image where the given top-left-origin
    /// pixel coordinates are opaque white and everything else is transparent.
    /// Mirrors the exact flip `SkinTextureLoader.pixelData` uses internally,
    /// so a point drawn here at (x, y) is read back at (x, y).
    private func makeTestImage(opaqueAt points: [(Int, Int)], width: Int = 64, height: Int = 64) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for (x, y) in points {
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
        return ctx.makeImage()!
    }

    private func pngData(from image: CGImage) throws -> Data {
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
