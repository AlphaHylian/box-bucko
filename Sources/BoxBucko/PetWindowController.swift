import AppKit
import SceneKit

/// Owns the borderless, transparent, always-on-top panel that hosts the 3D
/// pet. No document window, no dock icon, no title bar -- just a little guy
/// floating over everything else.
final class PetWindowController: NSObject {
    let window: NSPanel
    private let petView: PetView
    private let scene: SCNScene
    private let cameraNode: SCNNode
    private let speechLabel: NSTextField
    private let speechBubbleBackground: NSVisualEffectView

    private(set) var rig: SkinModelBuilder.Rig!
    var animationController: AnimationController!

    private let prefs = Preferences.shared
    private var speechHideWorkItem: DispatchWorkItem?

    static let contentSize = NSSize(width: 220, height: 300)

    override init() {
        let size = PetWindowController.contentSize
        window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isMovable = false // we drive movement ourselves so we can add inertia
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false

        scene = SCNScene()
        scene.background.contents = NSColor.clear

        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petView.scene = scene
        petView.backgroundColor = .clear
        petView.autoenablesDefaultLighting = false
        petView.antialiasingMode = .multisampling4X
        petView.isJitteringEnabled = true

        cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 9
        camera.zNear = 0.1
        camera.zFar = 200
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 16, 60)
        cameraNode.look(at: SCNVector3(0, 16, 0))
        scene.rootNode.addChildNode(cameraNode)

        speechLabel = NSTextField(labelWithString: "")
        speechLabel.font = .systemFont(ofSize: 12, weight: .medium)
        speechLabel.textColor = .labelColor
        speechLabel.alignment = .center
        speechLabel.maximumNumberOfLines = 2
        speechLabel.lineBreakMode = .byWordWrapping

        speechBubbleBackground = NSVisualEffectView()
        speechBubbleBackground.material = .popover
        speechBubbleBackground.state = .active
        speechBubbleBackground.wantsLayer = true
        speechBubbleBackground.layer?.cornerRadius = 10
        speechBubbleBackground.layer?.masksToBounds = true
        speechBubbleBackground.alphaValue = 0

        super.init()

        window.contentView = petView
        petView.addSubview(speechBubbleBackground)
        speechBubbleBackground.addSubview(speechLabel)

        petView.onDragStart = { [weak self] in self?.handleDragStart() }
        petView.onDrag = { [weak self] delta in self?.handleDrag(delta: delta) }
        petView.onDragEnd = { [weak self] velocity in self?.handleDragEnd(velocity: velocity) }
        petView.onClick = { [weak self] in self?.handleClick() }
        petView.onDoubleClick = { [weak self] in self?.animationController?.playJump() }
        petView.onRightClick = { [weak self] event in self?.handleRightClick(event) }

        setupLighting()
        positionInitialWindow()
    }

    private func setupLighting() {
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.light!.color = NSColor.white
        key.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .ambient
        fill.light!.intensity = 500
        fill.light!.color = NSColor.white
        scene.rootNode.addChildNode(fill)
    }

    func loadRig(texture: CGImage, slim: Bool) {
        rig?.root.removeFromParentNode()
        let newRig = SkinModelBuilder.buildRig(texture: texture, slim: slim)
        let s = Float(prefs.scale) / 10.0
        newRig.root.scale = SCNVector3(s, s, s)
        scene.rootNode.addChildNode(newRig.root)
        rig = newRig
        animationController = AnimationController(rig: rig, windowController: self, prefs: prefs)
        if prefs.wanderEnabled {
            animationController.startWandering()
        }
    }

    func applyScale(_ scale: CGFloat) {
        prefs.scale = scale
        let s = Float(scale) / 10.0
        rig?.root.scale = SCNVector3(s, s, s)
    }

    private func positionInitialWindow() {
        let screen = currentScreenFrame()
        let defaultOrigin = NSPoint(
            x: screen.maxX - window.frame.width - 40,
            y: screen.maxY - window.frame.height - 40
        )
        let origin = prefs.lastWindowOrigin.map { NSPoint(x: $0.x, y: $0.y) } ?? defaultOrigin
        window.setFrameOrigin(clamped(origin, to: screen))
    }

    func currentScreenFrame() -> NSRect {
        (NSScreen.screens.first(where: { $0.frame.contains(window.frame.origin) }) ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    }

    private func clamped(_ point: NSPoint, to screen: NSRect) -> NSPoint {
        let x = min(max(point.x, screen.minX), screen.maxX - window.frame.width)
        let y = min(max(point.y, screen.minY), screen.maxY - window.frame.height)
        return NSPoint(x: x, y: y)
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    var isVisible: Bool { window.isVisible }

    // MARK: - Dragging

    private func handleDragStart() {
        animationController?.stopWandering()
    }

    private func handleDrag(delta: CGSize) {
        var newOrigin = window.frame.origin
        newOrigin.x += delta.width
        newOrigin.y += delta.height
        window.setFrameOrigin(newOrigin)
    }

    private func handleDragEnd(velocity: CGPoint) {
        prefs.lastWindowOrigin = window.frame.origin
        // Little inertia: keep sliding briefly in the direction you flung it, then settle.
        let screen = currentScreenFrame()
        let flingDistance = CGPoint(x: velocity.x * 0.12, y: velocity.y * 0.12)
        var target = window.frame.origin
        target.x += flingDistance.x
        target.y += flingDistance.y
        target = clamped(target, to: screen)
        NSAnimationContext.runAnimationContext { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(target)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.prefs.lastWindowOrigin = self.window.frame.origin
            if self.prefs.wanderEnabled {
                self.animationController?.startWandering()
            }
        }
    }

    /// Animates the window sliding to a new x/y over `duration` seconds (used by
    /// the wander behaviour), completing on the main run loop.
    func animateFrameOrigin(x: CGFloat, y: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationContext { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            window.animator().setFrameOrigin(NSPoint(x: x, y: y))
        } completionHandler: { [weak self] in
            self?.prefs.lastWindowOrigin = self?.window.frame.origin
            completion()
        }
    }

    // MARK: - Interaction

    private func handleClick() {
        animationController?.playWave()
        if prefs.speechBubblesEnabled {
            say(SpeechBank.randomGreeting())
        }
    }

    private func handleRightClick(_ event: NSEvent) {
        NotificationCenter.default.post(name: .boxBuckoRequestContextMenu, object: event)
    }

    // MARK: - Speech bubble

    func say(_ text: String, duration: TimeInterval = 2.6) {
        guard prefs.speechBubblesEnabled else { return }
        speechHideWorkItem?.cancel()
        speechLabel.stringValue = text
        speechLabel.sizeToFit()

        let hPad: CGFloat = 12, vPad: CGFloat = 6
        let bubbleWidth = min(max(speechLabel.frame.width + hPad * 2, 40), 180)
        speechLabel.frame = NSRect(x: hPad, y: vPad, width: bubbleWidth - hPad * 2, height: speechLabel.frame.height)
        let bubbleHeight = speechLabel.frame.height + vPad * 2
        let bubbleX = (petView.bounds.width - bubbleWidth) / 2
        let bubbleY = petView.bounds.height - bubbleHeight - 8
        speechBubbleBackground.frame = NSRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
        speechLabel.frame = NSRect(x: hPad, y: vPad, width: bubbleWidth - hPad * 2, height: speechLabel.frame.height)

        speechBubbleBackground.animator().alphaValue = 1
        let workItem = DispatchWorkItem { [weak self] in
            self?.speechBubbleBackground.animator().alphaValue = 0
        }
        speechHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}

extension Notification.Name {
    static let boxBuckoRequestContextMenu = Notification.Name("boxBuckoRequestContextMenu")
}
