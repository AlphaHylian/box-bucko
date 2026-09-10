import SceneKit
import CoreGraphics

/// Builds an animatable SceneKit rig (head/body/arms/legs) textured from a
/// Minecraft skin. 1 scene unit == 1 skin-texture pixel, so the whole rig is
/// ~32 units tall; callers scale the root node down to taste.
///
/// Each body part's box is built as fully explicit geometry (24 hand-placed
/// vertices, one set of 4 per face, each carrying its own UV coordinates)
/// rather than an `SCNBox` with a `contentsTransform`. `SCNBox`'s default
/// per-face UV winding is undocumented and turned out not to match a uniform
/// affine transform's ability to correct it (a `contentsTransform` can only
/// scale/translate/rotate all four corners of a face together -- it can't
/// independently fix a face whose default winding is different from its
/// neighbors). Building the geometry by hand removes that guesswork
/// entirely: every vertex's position and texture coordinate are both chosen
/// by us, so there's nothing left for SceneKit to interpret ambiguously.
enum SkinModelBuilder {

    struct Rig {
        var root: SCNNode        // overall character node, feet at local y = 0
        var head: SCNNode        // pivots at the neck (bottom of head)
        var body: SCNNode
        var rightArm: SCNNode    // pivots at the shoulder (top of arm)
        var leftArm: SCNNode
        var rightLeg: SCNNode    // pivots at the hip (top of leg)
        var leftLeg: SCNNode
        var nameplateAnchor: SCNNode // sits above the head, for speech bubbles etc.
    }

    static func buildRig(texture: CGImage, slim: Bool) -> Rig {
        let parts = MinecraftModel.bodyParts(slim: slim)
        var nodes: [String: SCNNode] = [:]
        for spec in parts {
            nodes[spec.name] = makePartNode(spec: spec, texture: texture)
        }

        let root = SCNNode()
        root.name = "boxBuckoRoot"

        let legTopY: CGFloat = 12
        let shoulderY: CGFloat = 24
        let neckY: CGFloat = 24

        let body = nodes["body"]!
        body.position = SCNVector3(0, 18, 0) // body spans y 12...24, centered at 18
        root.addChildNode(body)

        let head = nodes["head"]!
        head.pivot = SCNMatrix4MakeTranslation(0, -4, 0) // rotate around neck (bottom of head box)
        head.position = SCNVector3(0, neckY, 0)
        root.addChildNode(head)

        let rightArm = nodes["rightArm"]!
        let rightArmWidth: CGFloat = slim ? 3 : 4
        rightArm.pivot = SCNMatrix4MakeTranslation(0, 6, 0) // rotate around shoulder (top of arm box)
        rightArm.position = SCNVector3(-(4 + rightArmWidth / 2), shoulderY, 0)
        root.addChildNode(rightArm)

        let leftArm = nodes["leftArm"]!
        leftArm.pivot = SCNMatrix4MakeTranslation(0, 6, 0)
        leftArm.position = SCNVector3(4 + rightArmWidth / 2, shoulderY, 0)
        root.addChildNode(leftArm)

        let rightLeg = nodes["rightLeg"]!
        rightLeg.pivot = SCNMatrix4MakeTranslation(0, 6, 0)
        rightLeg.position = SCNVector3(-2, legTopY, 0)
        root.addChildNode(rightLeg)

        let leftLeg = nodes["leftLeg"]!
        leftLeg.pivot = SCNMatrix4MakeTranslation(0, 6, 0)
        leftLeg.position = SCNVector3(2, legTopY, 0)
        root.addChildNode(leftLeg)

        let nameplateAnchor = SCNNode()
        nameplateAnchor.position = SCNVector3(0, 34, 0)
        root.addChildNode(nameplateAnchor)

        return Rig(root: root, head: head, body: body, rightArm: rightArm, leftArm: leftArm,
                   rightLeg: rightLeg, leftLeg: leftLeg, nameplateAnchor: nameplateAnchor)
    }

    private static func makePartNode(spec: BodyPartSpec, texture: CGImage) -> SCNNode {
        let container = SCNNode()
        container.name = spec.name

        let baseGeometry = boxGeometry(
            width: CGFloat(spec.width), height: CGFloat(spec.height), depth: CGFloat(spec.depth),
            uv: spec.base, texture: texture, isOverlay: false
        )
        let baseNode = SCNNode(geometry: baseGeometry)
        container.addChildNode(baseNode)

        if let overlay = spec.overlay {
            let inflate = spec.overlayInflate
            let overlayGeometry = boxGeometry(
                width: CGFloat(spec.width) + inflate,
                height: CGFloat(spec.height) + inflate,
                depth: CGFloat(spec.depth) + inflate,
                uv: overlay, texture: texture, isOverlay: true
            )
            let overlayNode = SCNNode(geometry: overlayGeometry)
            overlayNode.name = spec.name + "_overlay"
            container.addChildNode(overlayNode)
        }

        return container
    }

    /// One face of a hand-built box: 4 vertices in (bottom-left, bottom-right,
    /// top-right, top-left) order as viewed from outside the box, i.e. the
    /// same corner order a viewer would use to describe the *texture* rect
    /// that face is painted with. Because every face uses this same corner
    /// convention for both its 3D positions and its UVs, they can never
    /// drift out of sync with each other the way relying on `SCNBox`'s own
    /// (opaque) per-face vertex order could.
    private struct FaceCorners {
        var bl: SCNVector3
        var br: SCNVector3
        var tr: SCNVector3
        var tl: SCNVector3
        var normal: SCNVector3
    }

    private static func faceCorners(width w: CGFloat, height h: CGFloat, depth d: CGFloat) -> [FaceCorners] {
        let hw = w / 2, hh = h / 2, hd = d / 2
        return [
            // front (+z)
            FaceCorners(bl: SCNVector3(-hw, -hh, hd), br: SCNVector3(hw, -hh, hd),
                        tr: SCNVector3(hw, hh, hd), tl: SCNVector3(-hw, hh, hd),
                        normal: SCNVector3(0, 0, 1)),
            // right (+x)
            FaceCorners(bl: SCNVector3(hw, -hh, hd), br: SCNVector3(hw, -hh, -hd),
                        tr: SCNVector3(hw, hh, -hd), tl: SCNVector3(hw, hh, hd),
                        normal: SCNVector3(1, 0, 0)),
            // back (-z)
            FaceCorners(bl: SCNVector3(hw, -hh, -hd), br: SCNVector3(-hw, -hh, -hd),
                        tr: SCNVector3(-hw, hh, -hd), tl: SCNVector3(hw, hh, -hd),
                        normal: SCNVector3(0, 0, -1)),
            // left (-x)
            FaceCorners(bl: SCNVector3(-hw, -hh, -hd), br: SCNVector3(-hw, -hh, hd),
                        tr: SCNVector3(-hw, hh, hd), tl: SCNVector3(-hw, hh, -hd),
                        normal: SCNVector3(-1, 0, 0)),
            // top (+y)
            FaceCorners(bl: SCNVector3(hw, hh, -hd), br: SCNVector3(-hw, hh, -hd),
                        tr: SCNVector3(-hw, hh, hd), tl: SCNVector3(hw, hh, hd),
                        normal: SCNVector3(0, 1, 0)),
            // bottom (-y)
            FaceCorners(bl: SCNVector3(-hw, -hh, -hd), br: SCNVector3(hw, -hh, -hd),
                        tr: SCNVector3(hw, -hh, hd), tl: SCNVector3(-hw, -hh, hd),
                        normal: SCNVector3(0, -1, 0)),
        ]
    }

    /// Same (bottom-left, bottom-right, top-right, top-left) UV corners for a
    /// pixel rect from the *original*, top-left-origin skin texture. SceneKit
    /// samples image contents with (0,0) at the bottom-left of the image (see
    /// `LoadedSkin.texture`'s doc comment), so a pixel row `y` measured down
    /// from the visual top becomes `v = 1 - y/texSize`.
    private static func faceUVCorners(rect: PixelRect, texSize: CGFloat) -> (bl: CGPoint, br: CGPoint, tr: CGPoint, tl: CGPoint) {
        let u0 = CGFloat(rect.x) / texSize
        let u1 = CGFloat(rect.x + rect.w) / texSize
        let vTop = 1 - CGFloat(rect.y) / texSize
        let vBottom = 1 - CGFloat(rect.y + rect.h) / texSize
        return (
            bl: CGPoint(x: u0, y: vBottom),
            br: CGPoint(x: u1, y: vBottom),
            tr: CGPoint(x: u1, y: vTop),
            tl: CGPoint(x: u0, y: vTop)
        )
    }

    private static func boxGeometry(width: CGFloat, height: CGFloat, depth: CGFloat, uv: BoxFaceUV, texture: CGImage, isOverlay: Bool) -> SCNGeometry {
        let faces = faceCorners(width: width, height: height, depth: depth)
        // Order must match `faces` above and the materials array below.
        let rects = [uv.front, uv.right, uv.back, uv.left, uv.top, uv.bottom]
        let texSize = CGFloat(SkinTextureLoader.textureSize)

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var elements: [SCNGeometryElement] = []

        for (i, face) in faces.enumerated() {
            let base = Int32(positions.count)
            positions.append(contentsOf: [face.bl, face.br, face.tr, face.tl])
            normals.append(contentsOf: [face.normal, face.normal, face.normal, face.normal])

            let uvCorners = faceUVCorners(rect: rects[i], texSize: texSize)
            texcoords.append(contentsOf: [uvCorners.bl, uvCorners.br, uvCorners.tr, uvCorners.tl])

            let indices: [Int32] = [base, base + 1, base + 2, base, base + 2, base + 3]
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            elements.append(element)
        }

        let vertexSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let texcoordSource = SCNGeometrySource(textureCoordinates: texcoords)

        let geometry = SCNGeometry(sources: [vertexSource, normalSource, texcoordSource], elements: elements)
        geometry.materials = rects.map { rect in material(rect: rect, texture: texture, isOverlay: isOverlay) }
        return geometry
    }

    private static func material(rect: PixelRect, texture: CGImage, isOverlay: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = texture
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.isDoubleSided = isOverlay
        if isOverlay {
            m.blendMode = .alpha
            m.transparencyMode = .aOne
            m.writesToDepthBuffer = true
            m.readsFromDepthBuffer = true
        }
        return m
    }
}
