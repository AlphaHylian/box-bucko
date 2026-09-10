import SceneKit
import CoreGraphics

/// Builds an animatable SceneKit rig (head/body/arms/legs) textured from a
/// Minecraft skin. 1 scene unit == 1 skin-texture pixel, so the whole rig is
/// ~32 units tall; callers scale the root node down to taste.
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

        let baseBox = SCNBox(width: CGFloat(spec.width), height: CGFloat(spec.height), length: CGFloat(spec.depth), chamferRadius: 0)
        baseBox.materials = materials(for: spec.base, texture: texture)
        let baseNode = SCNNode(geometry: baseBox)
        container.addChildNode(baseNode)

        if let overlay = spec.overlay {
            let inflate = spec.overlayInflate
            let overlayBox = SCNBox(
                width: CGFloat(spec.width) + inflate,
                height: CGFloat(spec.height) + inflate,
                length: CGFloat(spec.depth) + inflate,
                chamferRadius: 0
            )
            overlayBox.materials = materials(for: overlay, texture: texture, isOverlay: true)
            let overlayNode = SCNNode(geometry: overlayBox)
            overlayNode.name = spec.name + "_overlay"
            container.addChildNode(overlayNode)
        }

        return container
    }

    private static func materials(for uv: BoxFaceUV, texture: CGImage, isOverlay: Bool = false) -> [SCNMaterial] {
        // SCNBox material order: front, right, back, left, top, bottom.
        return [
            material(rect: uv.front, texture: texture, isOverlay: isOverlay),
            material(rect: uv.right, texture: texture, isOverlay: isOverlay),
            material(rect: uv.back, texture: texture, isOverlay: isOverlay),
            material(rect: uv.left, texture: texture, isOverlay: isOverlay),
            material(rect: uv.top, texture: texture, isOverlay: isOverlay),
            material(rect: uv.bottom, texture: texture, isOverlay: isOverlay),
        ]
    }

    private static func material(rect: PixelRect, texture: CGImage, isOverlay: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = texture
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.diffuse.contentsTransform = uvTransform(for: rect)
        m.isDoubleSided = isOverlay
        if isOverlay {
            m.blendMode = .alpha
            m.transparencyMode = .aOne
            m.writesToDepthBuffer = true
            m.readsFromDepthBuffer = true
        }
        return m
    }

    /// Maps a pixel rect in the *original* (top-left origin) 64x64 skin image
    /// onto the [0,1] UV square SceneKit uses for each SCNBox face, accounting
    /// for the fact that the texture we hand SceneKit was pre-flipped to be
    /// bottom-up (see `SkinTextureLoader.flipBottomUp`).
    private static func uvTransform(for rect: PixelRect) -> SCNMatrix4 {
        let texSize = CGFloat(SkinTextureLoader.textureSize)
        var sx = CGFloat(rect.w) / texSize
        let sy = CGFloat(rect.h) / texSize
        var tx = CGFloat(rect.x) / texSize
        if Preferences.shared.flipTextureH {
            // Escape hatch (menu bar toggle) for the horizontal analogue of
            // flipTextureV below: mirror U within each rect (keep its
            // position in the texture atlas, reverse its horizontal
            // sampling direction), in case SceneKit's per-face UV winding
            // needs it relative to the source PNG for our camera setup.
            sx = -sx
            tx = tx + CGFloat(rect.w) / texSize
        }
        var ty = 1 - (CGFloat(rect.y) + CGFloat(rect.h)) / texSize
        if Preferences.shared.flipTextureV {
            // Escape hatch (menu bar toggle) in case a given macOS/GPU combo
            // flips SceneKit's texture V axis relative to what we assumed.
            ty = 1 - ty - sy
        }
        // SCNMatrix4's fields are CGFloat (confirmed against the real SDK via CI).
        return SCNMatrix4(
            m11: sx, m12: 0, m13: 0, m14: 0,
            m21: 0, m22: sy, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: tx, m42: ty, m43: 0, m44: 1
        )
    }
}
