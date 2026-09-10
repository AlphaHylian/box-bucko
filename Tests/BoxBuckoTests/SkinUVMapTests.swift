import XCTest
@testable import BoxBucko

/// Regression tests for the pure UV-layout math in `SkinUVMap.swift`. These
/// coordinates are load-bearing (they're how the 3D model gets textured
/// correctly), so any accidental change here should fail loudly.
final class SkinUVMapTests: XCTestCase {
    func testHeadUVMatchesKnownLayout() {
        let head = SkinUV.boxUV(originX: 0, originY: 0, width: 8, height: 8, depth: 8)
        XCTAssertEqual(head.top, PixelRect(x: 8, y: 0, w: 8, h: 8))
        XCTAssertEqual(head.bottom, PixelRect(x: 16, y: 0, w: 8, h: 8))
        XCTAssertEqual(head.right, PixelRect(x: 0, y: 8, w: 8, h: 8))
        XCTAssertEqual(head.front, PixelRect(x: 8, y: 8, w: 8, h: 8))
        XCTAssertEqual(head.left, PixelRect(x: 16, y: 8, w: 8, h: 8))
        XCTAssertEqual(head.back, PixelRect(x: 24, y: 8, w: 8, h: 8))
    }

    func testBodyUVMatchesKnownLayout() {
        let body = SkinUV.boxUV(originX: 16, originY: 16, width: 8, height: 12, depth: 4)
        XCTAssertEqual(body.top, PixelRect(x: 20, y: 16, w: 8, h: 4))
        XCTAssertEqual(body.bottom, PixelRect(x: 28, y: 16, w: 8, h: 4))
        XCTAssertEqual(body.right, PixelRect(x: 16, y: 20, w: 4, h: 12))
        XCTAssertEqual(body.front, PixelRect(x: 20, y: 20, w: 8, h: 12))
        XCTAssertEqual(body.left, PixelRect(x: 28, y: 20, w: 4, h: 12))
        XCTAssertEqual(body.back, PixelRect(x: 32, y: 20, w: 8, h: 12))
    }

    func testClassicRightArmUVMatchesKnownLayout() {
        let arm = SkinUV.boxUV(originX: 40, originY: 16, width: 4, height: 12, depth: 4)
        XCTAssertEqual(arm.front, PixelRect(x: 44, y: 20, w: 4, h: 12))
        XCTAssertEqual(arm.back, PixelRect(x: 52, y: 20, w: 4, h: 12))
    }

    func testSlimArmIsNarrowerButSameOrigin() {
        let classic = SkinUV.boxUV(originX: 40, originY: 16, width: 4, height: 12, depth: 4)
        let slim = SkinUV.boxUV(originX: 40, originY: 16, width: 3, height: 12, depth: 4)
        XCTAssertEqual(slim.front.x, classic.front.x)
        XCTAssertEqual(slim.front.w, 3)
        XCTAssertEqual(classic.front.w, 4)
        // The slim back face starts earlier since it's packed right after a
        // narrower front face -- and must not overlap the classic layout's
        // last (transparent, in slim skins) column.
        XCTAssertLessThan(slim.back.x, classic.back.x)
    }

    func testBodyPartsProduceSixParts() {
        XCTAssertEqual(MinecraftModel.bodyParts(slim: false).count, 6)
        XCTAssertEqual(MinecraftModel.bodyParts(slim: true).count, 6)
    }

    func testSlimVsClassicArmWidth() {
        let classicArm = MinecraftModel.bodyParts(slim: false).first { $0.name == "rightArm" }!
        let slimArm = MinecraftModel.bodyParts(slim: true).first { $0.name == "rightArm" }!
        XCTAssertEqual(classicArm.width, 4)
        XCTAssertEqual(slimArm.width, 3)
    }
}
