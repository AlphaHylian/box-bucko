import Foundation
import CoreGraphics

/// Pixel-space rectangle within a 64x64 Minecraft skin texture.
struct PixelRect: Equatable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int
}

/// The six faces of a rectangular box, matching SceneKit's SCNBox material order:
/// materials[0] = front (+z), [1] = right (+x), [2] = back (-z),
/// [3] = left (-x), [4] = top (+y), [5] = bottom (-y).
struct BoxFaceUV {
    var front: PixelRect
    var right: PixelRect
    var back: PixelRect
    var left: PixelRect
    var top: PixelRect
    var bottom: PixelRect
}

enum SkinUV {
    /// Computes the standard Minecraft "box unwrap" UV layout for a box of the
    /// given width (x), height (y), depth (z), whose texture region starts at
    /// pixel (originX, originY) in the classic Mojang cross-unwrap arrangement:
    ///
    ///   row 1 (height = depth):   [blank d][ top   w][ bottom w]
    ///   row 2 (height = height):  [right d][ front w][ left  d][ back w]
    ///
    /// This single formula reproduces every limb's UV rectangles (head, body,
    /// arms, legs, and their layer-2 overlays) just by varying the origin and
    /// box dimensions, which is how Mojang's own skin template is laid out.
    static func boxUV(originX ox: Int, originY oy: Int, width w: Int, height h: Int, depth d: Int) -> BoxFaceUV {
        let top = PixelRect(x: ox + d, y: oy, w: w, h: d)
        let bottom = PixelRect(x: ox + d + w, y: oy, w: w, h: d)
        let row2Y = oy + d
        let right = PixelRect(x: ox, y: row2Y, w: d, h: h)
        let front = PixelRect(x: ox + d, y: row2Y, w: w, h: h)
        let left = PixelRect(x: ox + d + w, y: row2Y, w: d, h: h)
        let back = PixelRect(x: ox + d + w + d, y: row2Y, w: w, h: h)
        return BoxFaceUV(front: front, right: right, back: back, left: left, top: top, bottom: bottom)
    }
}

/// A single body part's geometry + texture placement, in "skin pixel" units,
/// where 1 unit == 1 pixel of the 64x64 skin texture (Minecraft's own convention).
struct BodyPartSpec {
    var name: String
    var width: Int   // x
    var height: Int  // y
    var depth: Int   // z
    var base: BoxFaceUV
    var overlay: BoxFaceUV?
    /// Slightly larger scale factor applied to the overlay box so it doesn't z-fight
    /// with the base layer (the classic "hat layer" bulge).
    var overlayInflate: CGFloat = 0.5
}

enum MinecraftModel {
    /// Builds the full set of body parts for a player model.
    /// - Parameter slim: true for the 3px-arm "Alex" style model, false for classic 4px "Steve".
    static func bodyParts(slim: Bool) -> [BodyPartSpec] {
        let armWidth = slim ? 3 : 4

        let head = BodyPartSpec(
            name: "head", width: 8, height: 8, depth: 8,
            base: SkinUV.boxUV(originX: 0, originY: 0, width: 8, height: 8, depth: 8),
            overlay: SkinUV.boxUV(originX: 32, originY: 0, width: 8, height: 8, depth: 8)
        )

        let body = BodyPartSpec(
            name: "body", width: 8, height: 12, depth: 4,
            base: SkinUV.boxUV(originX: 16, originY: 16, width: 8, height: 12, depth: 4),
            overlay: SkinUV.boxUV(originX: 16, originY: 32, width: 8, height: 12, depth: 4)
        )

        let rightArm = BodyPartSpec(
            name: "rightArm", width: armWidth, height: 12, depth: 4,
            base: SkinUV.boxUV(originX: 40, originY: 16, width: armWidth, height: 12, depth: 4),
            overlay: SkinUV.boxUV(originX: 40, originY: 32, width: armWidth, height: 12, depth: 4)
        )

        let leftArm = BodyPartSpec(
            name: "leftArm", width: armWidth, height: 12, depth: 4,
            base: SkinUV.boxUV(originX: 32, originY: 48, width: armWidth, height: 12, depth: 4),
            overlay: SkinUV.boxUV(originX: 48, originY: 48, width: armWidth, height: 12, depth: 4)
        )

        let rightLeg = BodyPartSpec(
            name: "rightLeg", width: 4, height: 12, depth: 4,
            base: SkinUV.boxUV(originX: 0, originY: 16, width: 4, height: 12, depth: 4),
            overlay: SkinUV.boxUV(originX: 0, originY: 32, width: 4, height: 12, depth: 4)
        )

        let leftLeg = BodyPartSpec(
            name: "leftLeg", width: 4, height: 12, depth: 4,
            base: SkinUV.boxUV(originX: 16, originY: 48, width: 4, height: 12, depth: 4),
            overlay: SkinUV.boxUV(originX: 0, originY: 48, width: 4, height: 12, depth: 4)
        )

        return [head, body, rightArm, leftArm, rightLeg, leftLeg]
    }
}
