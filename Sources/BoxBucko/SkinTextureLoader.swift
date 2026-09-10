import Foundation
import CoreGraphics
import ImageIO
import AppKit

struct LoadedSkin {
    /// A 64x64 RGBA texture image, stored bottom-up (row 0 = visual bottom of the
    /// original skin) so it matches the standard OpenGL/Metal texture V=0-at-bottom
    /// convention that SceneKit's `contentsTransform` math assumes.
    var texture: CGImage
    var isSlim: Bool
    var sourceURL: URL?
    /// A tiny cropped/upscaled render of just the face, suitable for use as
    /// the menu bar status item icon.
    var faceIcon: NSImage?
}

enum SkinLoadError: Error {
    case couldNotDecodeImage
    case unsupportedSize
}

enum SkinTextureLoader {
    static let textureSize = 64

    static func load(url: URL) throws -> LoadedSkin {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SkinLoadError.couldNotDecodeImage
        }
        return try build(from: raw, sourceURL: url)
    }

    static func load(data: Data) throws -> LoadedSkin {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SkinLoadError.couldNotDecodeImage
        }
        return try build(from: raw, sourceURL: nil)
    }

    private static func build(from raw: CGImage, sourceURL: URL?) throws -> LoadedSkin {
        let normalized = try normalizeTo64x64(raw)
        let flipped = try flipBottomUp(normalized)
        let slim = detectSlimArms(in: normalized)
        let faceIcon = makeFaceIcon(from: normalized)
        return LoadedSkin(texture: flipped, isSlim: slim, sourceURL: sourceURL, faceIcon: faceIcon)
    }

    /// Crops the head's front face (base skin tone + hat-layer overlay) out of
    /// a normalized, top-left-origin 64x64 skin and renders it as a small,
    /// crisp (nearest-neighbor upscaled) icon for the menu bar.
    private static func makeFaceIcon(from normalized: CGImage) -> NSImage? {
        // CGImage.cropping(to:) uses CGImage's own coordinate space, which --
        // unlike the top-left-origin pixel coordinates used everywhere else in
        // this file (and in the Minecraft skin spec) -- has its origin at the
        // BOTTOM-left. Convert our top-left-origin face rects (front face at
        // pixel (8,8)-(16,16); hat-layer overlay at (40,8)-(48,16)) accordingly.
        let h = normalized.height
        func flippedRect(x: Int, topY: Int, size: Int) -> CGRect {
            CGRect(x: x, y: h - topY - size, width: size, height: size)
        }
        guard let baseFace = normalized.cropping(to: flippedRect(x: 8, topY: 8, size: 8)) else {
            return nil
        }
        let overlayFace = normalized.cropping(to: flippedRect(x: 40, topY: 8, size: 8))

        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        if let ctx = NSGraphicsContext.current?.cgContext {
            let rect = CGRect(origin: .zero, size: CGSize(width: 32, height: 32))
            ctx.draw(baseFace, in: rect)
            if let overlayFace {
                ctx.draw(overlayFace, in: rect)
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Legacy 64x32 skins only contain the "base" layer and use a mirrored-limb
    /// scheme for the (missing) left arm/leg. Upgrade them to the modern 64x64
    /// layout so the rest of the pipeline never has to think about the old format.
    private static func normalizeTo64x64(_ image: CGImage) throws -> CGImage {
        if image.width == 64 && image.height == 64 {
            return image
        }
        guard image.width == 64 && image.height == 32 else {
            // Best effort: just scale whatever we got onto a 64x64 canvas.
            return try resample(image, width: 64, height: 64)
        }

        return try mirrorLegacyLimbs(image)
    }

    /// Builds a proper 64x64 texture from a 64x32 legacy skin by copying the
    /// right arm/leg pixel data into the left arm/leg slots (mirrored), which is
    /// exactly what Minecraft itself does when it upgrades an old skin.
    private static func mirrorLegacyLimbs(_ image: CGImage) throws -> CGImage {
        guard let srcData = pixelData(of: image, width: 64, height: 32) else {
            throw SkinLoadError.couldNotDecodeImage
        }
        var dst = [UInt8](repeating: 0, count: 64 * 64 * 4)

        func srcPixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let i = (y * 64 + x) * 4
            return (srcData[i], srcData[i + 1], srcData[i + 2], srcData[i + 3])
        }
        func setDst(_ x: Int, _ y: Int, _ p: (UInt8, UInt8, UInt8, UInt8)) {
            let i = (y * 64 + x) * 4
            dst[i] = p.0; dst[i + 1] = p.1; dst[i + 2] = p.2; dst[i + 3] = p.3
        }

        // Copy the whole legacy top half as-is (head, body, right arm, right leg,
        // and legacy's own top-row overlays which live at y0-16 already).
        for y in 0..<32 {
            for x in 0..<64 {
                setDst(x, y, srcPixel(x, y))
            }
        }

        // Mirror right leg (0,16)-(16,32) -> left leg base (16,48)-(32,64), flipped horizontally per-face.
        mirrorLimbRegion(src: srcPixel, dst: &dst, srcOriginX: 0, srcOriginY: 16, dstOriginX: 16, dstOriginY: 48, width: 16, height: 16)
        // Mirror right arm (40,16)-(56,32) -> left arm base (32,48)-(48,64).
        mirrorLimbRegion(src: srcPixel, dst: &dst, srcOriginX: 40, srcOriginY: 16, dstOriginX: 32, dstOriginY: 48, width: 16, height: 16)

        return makeCGImage(from: dst, width: 64, height: 64)
    }

    /// Mirrors a 16x16 limb UV block (right arm/leg's combined base region) into
    /// the destination block, flipping the horizontal order of the 4 sub-columns
    /// (right/front/left/back become left/front/right/back) the way Mojang's
    /// legacy-skin upgrader does, so the limb reads correctly from both sides.
    private static func mirrorLimbRegion(
        src: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8),
        dst: inout [UInt8],
        srcOriginX: Int, srcOriginY: Int,
        dstOriginX: Int, dstOriginY: Int,
        width: Int, height: Int
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let mirroredX = width - 1 - x
                let p = src(srcOriginX + mirroredX, srcOriginY + y)
                let i = ((dstOriginY + y) * 64 + (dstOriginX + x)) * 4
                dst[i] = p.0; dst[i + 1] = p.1; dst[i + 2] = p.2; dst[i + 3] = p.3
            }
        }
    }

    /// Renders `image` into a scratch bitmap context and copies out its raw
    /// pixel bytes. Deliberately lets CGContext own its own buffer (`data:
    /// nil`) rather than pointing it at a Swift Array's storage -- a pointer
    /// obtained from `&someArray` is only valid for the duration of the single
    /// call it's passed to, not for the context's whole lifetime.
    private static func pixelData(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let base = ctx.data else { return nil }
        // Flip so row 0 of the buffer == top row of the source image (normal reading order).
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let count = width * height * 4
        let typed = base.bindMemory(to: UInt8.self, capacity: count)
        return Array(UnsafeBufferPointer(start: typed, count: count))
    }

    private static func makeCGImage(from data: [UInt8], width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        if let base = ctx.data {
            data.withUnsafeBytes { src in
                base.copyMemory(from: src.baseAddress!, byteCount: min(src.count, width * height * 4))
            }
        }
        return ctx.makeImage()!
    }

    private static func resample(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SkinLoadError.couldNotDecodeImage }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else { throw SkinLoadError.couldNotDecodeImage }
        return out
    }

    /// Flips a top-left-origin image into a bottom-up buffer (row 0 in memory ==
    /// visual bottom of the picture), matching standard GPU texture row order.
    private static func flipBottomUp(_ image: CGImage) throws -> CGImage {
        let w = image.width, h = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SkinLoadError.couldNotDecodeImage }
        // A freshly-created CGContext already has a bottom-left origin, and
        // `draw(_:in:)` draws the CGImage's row 0 at the *top* of the given
        // rect in the context's own coordinate space. Net effect: the pixel
        // buffer backing `ctx` ends up bottom-up relative to the image's
        // normal (top-left origin) reading order -- exactly what we want.
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw SkinLoadError.couldNotDecodeImage }
        return out
    }

    /// Heuristically detects "slim" (Alex-style, 3px arm) skins by sampling a
    /// handful of pixels that are only ever opaque on the classic 4px arm
    /// template. If every sampled pixel is transparent, we call it slim.
    /// `image` here must be a normalized, top-left-origin 64x64 texture.
    private static func detectSlimArms(in image: CGImage) -> Bool {
        guard let data = pixelData(of: image, width: 64, height: 64) else { return false }
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            let i = (y * 64 + x) * 4 + 3
            guard i >= 0 && i < data.count else { return 0 }
            return data[i]
        }
        // These two pixels sit in the extra pixel-column that only exists on
        // the classic 4px-wide arm's "back" face -- on a slim (3px) arm the
        // back face is narrower and shifted, so this column is never painted
        // and stays transparent. Only sample the *base* layer (not the hat/
        // jacket overlay), since plenty of legitimate classic skins leave the
        // overlay fully transparent, which would otherwise look "slim".
        let rightArmMarker = (54, 20) // right arm base, back face
        let leftArmMarker = (46, 52)  // left arm base, back face
        return alpha(rightArmMarker.0, rightArmMarker.1) <= 10 && alpha(leftArmMarker.0, leftArmMarker.1) <= 10
    }
}
