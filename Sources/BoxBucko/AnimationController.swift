import SceneKit
import AppKit

/// Drives all the little-guy behaviour: idle breathing, walking legs/arms,
/// one-shot gestures (wave/jump/dance/sit), and autonomous wandering around
/// the screen. Kept deliberately simple (no physics engine) so it's cheap to
/// run continuously in a menu-bar-class app.
final class AnimationController {
    private let rig: SkinModelBuilder.Rig
    private weak var windowController: PetWindowController?
    private let prefs: Preferences

    private var wanderTimer: Timer?
    private var idleBehaviorTimer: Timer?
    private var sleepCheckTimer: Timer?
    private var zzzTimer: Timer?
    private var isWalking = false
    private var isGesturing = false
    private var isSitting = false
    private var isSleeping = false
    private var facingRight = true
    private var lastInteraction = Date()

    /// How long BoxBucko has to be left completely alone before it dozes off.
    private let sleepThreshold: TimeInterval = 4 * 60
    var onSleepStateChanged: ((Bool) -> Void)?

    init(rig: SkinModelBuilder.Rig, windowController: PetWindowController, prefs: Preferences) {
        self.rig = rig
        self.windowController = windowController
        self.prefs = prefs
        startIdleBreathing()
        startHeadLook()
        scheduleRandomIdleBehaviors()
        startSleepWatch()
    }

    deinit {
        wanderTimer?.invalidate()
        idleBehaviorTimer?.invalidate()
        sleepCheckTimer?.invalidate()
        zzzTimer?.invalidate()
    }

    // MARK: - Sleep

    /// Call whenever the user actively interacts with this pet (click, drag,
    /// right-click) so it knows not to doze off, and wakes back up if it had.
    func notifyInteraction() {
        lastInteraction = Date()
        if isSleeping {
            wakeUp()
        }
    }

    private func startSleepWatch() {
        sleepCheckTimer?.invalidate()
        sleepCheckTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self else { return }
            let idleFor = Date().timeIntervalSince(self.lastInteraction)
            if !self.isSleeping && idleFor >= self.sleepThreshold && !self.isWalking && !self.isGesturing && !self.isSitting {
                self.fallAsleep()
            }
        }
    }

    private func fallAsleep() {
        guard !isSleeping else { return }
        isSleeping = true
        stopWandering()
        rig.body.removeAction(forKey: "breathe")
        let lieDown = SCNAction.rotateTo(x: -.pi / 2, y: 0, z: 0, duration: 0.6, usesShortestUnitArc: true)
        lieDown.timingMode = .easeInEaseOut
        rig.root.runAction(lieDown)
        let doze = SCNAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.2, z: 0, duration: 1.6),
            .moveBy(x: 0, y: -0.2, z: 0, duration: 1.6),
        ]))
        rig.body.runAction(doze, forKey: "sleepBreathe")
        onSleepStateChanged?(true)
        scheduleZzz()
    }

    private func wakeUp() {
        isSleeping = false
        zzzTimer?.invalidate()
        rig.body.removeAction(forKey: "sleepBreathe")
        let standUp = SCNAction.rotateTo(x: 0, y: CGFloat(rig.root.eulerAngles.y), z: 0, duration: 0.4, usesShortestUnitArc: true)
        standUp.timingMode = .easeInEaseOut
        rig.root.runAction(standUp) { [weak self] in
            self?.startIdleBreathing()
        }
        onSleepStateChanged?(false)
        if prefs.wanderEnabled {
            startWandering()
        }
    }

    private func scheduleZzz() {
        guard isSleeping else { return }
        zzzTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, self.isSleeping else { return }
            self.onZzz?()
            self.scheduleZzz()
        }
    }

    var onZzz: (() -> Void)?

    // MARK: - Idle

    private func startIdleBreathing() {
        let up = SCNAction.moveBy(x: 0, y: 0.35, z: 0, duration: 1.1)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        rig.body.runAction(.repeatForever(.sequence([up, down])), forKey: "breathe")

        let armIn = SCNAction.rotateBy(x: 0.05, y: 0, z: 0, duration: 1.1)
        armIn.timingMode = .easeInEaseOut
        rig.rightArm.runAction(.repeatForever(.sequence([armIn, armIn.reversed()])), forKey: "idleArm")
        rig.leftArm.runAction(.repeatForever(.sequence([armIn, armIn.reversed()])), forKey: "idleArm")
    }

    private func startHeadLook() {
        scheduleNextHeadLook()
    }

    private func scheduleNextHeadLook() {
        let ry = CGFloat.random(in: -0.35...0.35)
        let rx = CGFloat.random(in: -0.12...0.18)
        let wait = SCNAction.wait(duration: Double.random(in: 1.5...4.0))
        let move = SCNAction.rotateTo(x: rx, y: ry, z: 0, duration: 0.6, usesShortestUnitArc: true)
        move.timingMode = .easeInEaseOut
        rig.head.runAction(.sequence([wait, move])) { [weak self] in
            self?.scheduleNextHeadLook()
        }
    }

    /// Occasionally throws in a spontaneous animation (stretch, look around,
    /// sit down for a bit) so the pet doesn't feel like it's on rails.
    private func scheduleRandomIdleBehaviors() {
        idleBehaviorTimer?.invalidate()
        idleBehaviorTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 12...30), repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.isWalking && !self.isGesturing && !self.isSleeping && self.prefs.spontaneousAnimationsEnabled {
                let roll = Int.random(in: 0..<4)
                switch roll {
                case 0: self.playWave()
                case 1: self.playJump()
                case 2: self.toggleSit()
                default: break
                }
            }
            self.scheduleRandomIdleBehaviors()
        }
    }

    // MARK: - One-shot gestures

    func playWave() {
        guard !isGesturing else { return }
        isGesturing = true
        rig.rightArm.removeAction(forKey: "idleArm")
        let raise = SCNAction.rotateTo(x: -2.4, y: 0, z: 0.3, duration: 0.25, usesShortestUnitArc: true)
        raise.timingMode = .easeOut
        let wag = SCNAction.rotateBy(x: 0, y: 0, z: 0.5, duration: 0.15)
        let wagBack = wag.reversed()
        let wave = SCNAction.repeat(.sequence([wag, wagBack]), count: 3)
        let lower = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.25)
        lower.timingMode = .easeIn
        rig.rightArm.runAction(.sequence([raise, wave, lower])) { [weak self] in
            self?.isGesturing = false
            self?.startIdleBreathing()
        }
    }

    func playJump() {
        guard !isGesturing else { return }
        isGesturing = true
        let crouch = SCNAction.moveBy(x: 0, y: -1.2, z: 0, duration: 0.12)
        crouch.timingMode = .easeIn
        let launch = SCNAction.moveBy(x: 0, y: 7, z: 0, duration: 0.22)
        launch.timingMode = .easeOut
        let land = SCNAction.moveBy(x: 0, y: -5.8, z: 0, duration: 0.22)
        land.timingMode = .easeIn
        let settle = SCNAction.moveBy(x: 0, y: 0, z: 0, duration: 0.08)
        rig.root.runAction(.sequence([crouch, launch, land, settle])) { [weak self] in
            self?.isGesturing = false
        }

        let legKick = SCNAction.rotateBy(x: -0.6, y: 0, z: 0, duration: 0.3)
        rig.rightLeg.runAction(.sequence([legKick, legKick.reversed()]))
        rig.leftLeg.runAction(.sequence([legKick, legKick.reversed()]))
        let armFling = SCNAction.rotateBy(x: -1.2, y: 0, z: 0, duration: 0.3)
        rig.rightArm.runAction(.sequence([armFling, armFling.reversed()]))
        rig.leftArm.runAction(.sequence([armFling, armFling.reversed()]))
    }

    func playDance() {
        guard !isGesturing else { return }
        isGesturing = true
        rig.body.removeAction(forKey: "breathe")
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.0)
        let bob = SCNAction.repeat(.sequence([
            .moveBy(x: 0, y: 1.2, z: 0, duration: 0.18),
            .moveBy(x: 0, y: -1.2, z: 0, duration: 0.18),
        ]), count: 3)
        let armWiggle = SCNAction.repeat(.sequence([
            .rotateBy(x: 0, y: 0, z: 0.9, duration: 0.18),
            .rotateBy(x: 0, y: 0, z: -1.8, duration: 0.18),
            .rotateBy(x: 0, y: 0, z: 0.9, duration: 0.18),
        ]), count: 2)
        rig.rightArm.runAction(armWiggle)
        rig.leftArm.runAction(.sequence([.wait(duration: 0.18), armWiggle]))
        rig.root.runAction(.group([spin, bob])) { [weak self] in
            self?.isGesturing = false
            self?.startIdleBreathing()
        }
    }

    /// A quick squash-and-stretch bounce, used when BoxBucko lands after being
    /// dropped/falling. Purely cosmetic, doesn't touch `isGesturing` so it
    /// can't get stuck blocking other animations if interrupted.
    func playLandingSquash() {
        let squash = SCNAction.scaleBy(x: 1.25, y: 0.7, z: 1.25, duration: 0.08)
        squash.timingMode = .easeOut
        let recover = SCNAction.scaleBy(x: 1 / 1.25, y: 1 / 0.7, z: 1 / 1.25, duration: 0.18)
        recover.timingMode = .easeOut
        rig.root.runAction(.sequence([squash, recover]))
    }

    func toggleSit() {
        if isSitting {
            standUp()
        } else {
            sitDown()
        }
    }

    private func sitDown() {
        guard !isGesturing else { return }
        isSitting = true
        let legRotate = SCNAction.rotateTo(x: -1.4, y: 0, z: 0, duration: 0.3, usesShortestUnitArc: true)
        let lower = SCNAction.moveBy(x: 0, y: -5, z: 0, duration: 0.3)
        rig.rightLeg.runAction(legRotate)
        rig.leftLeg.runAction(legRotate)
        rig.root.runAction(lower)
    }

    private func standUp() {
        isSitting = false
        let legRotate = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.3, usesShortestUnitArc: true)
        let raise = SCNAction.moveBy(x: 0, y: 5, z: 0, duration: 0.3)
        rig.rightLeg.runAction(legRotate)
        rig.leftLeg.runAction(legRotate)
        rig.root.runAction(raise)
    }

    // MARK: - Walking / wandering

    func startWandering() {
        guard wanderTimer == nil else { return }
        scheduleNextWanderStep()
    }

    func stopWandering() {
        wanderTimer?.invalidate()
        wanderTimer = nil
        stopWalkCycle()
    }

    private func scheduleNextWanderStep() {
        guard prefs.wanderEnabled else { return }
        let pause = Double.random(in: 2.0...6.0)
        wanderTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
            self?.takeWanderStep()
        }
    }

    private func takeWanderStep() {
        guard let wc = windowController, prefs.wanderEnabled else { return }
        let distance = CGFloat.random(in: 120...360)
        let goingRight = Bool.random()
        let screen = wc.currentScreenFrame()
        let currentX = wc.window.frame.origin.x
        var targetX = goingRight ? currentX + distance : currentX - distance
        targetX = min(max(targetX, screen.minX), screen.maxX - wc.window.frame.width)
        let actualDistance = abs(targetX - currentX)
        guard actualDistance > 8 else {
            scheduleNextWanderStep()
            return
        }
        face(right: targetX > currentX)
        startWalkCycle()
        let speed: CGFloat = 60 // points per second
        let duration = TimeInterval(actualDistance / speed)
        wc.animateFrameOrigin(x: targetX, y: wc.window.frame.origin.y, duration: duration) { [weak self] in
            self?.stopWalkCycle()
            self?.scheduleNextWanderStep()
        }
    }

    private func face(right: Bool) {
        guard right != facingRight else { return }
        facingRight = right
        let target: CGFloat = right ? 0 : .pi
        let turn = SCNAction.rotateTo(x: 0, y: target, z: 0, duration: 0.25, usesShortestUnitArc: true)
        rig.root.runAction(turn)
    }

    private func startWalkCycle() {
        guard !isWalking else { return }
        isWalking = true
        rig.rightArm.removeAction(forKey: "idleArm")
        rig.leftArm.removeAction(forKey: "idleArm")

        let swing = SCNAction.rotateTo(x: 0.9, y: 0, z: 0, duration: 0.28, usesShortestUnitArc: true)
        let swingBack = SCNAction.rotateTo(x: -0.9, y: 0, z: 0, duration: 0.28, usesShortestUnitArc: true)
        swing.timingMode = .easeInEaseOut
        swingBack.timingMode = .easeInEaseOut

        rig.rightLeg.runAction(.repeatForever(.sequence([swing, swingBack])), forKey: "walk")
        rig.leftLeg.runAction(.repeatForever(.sequence([swingBack, swing])), forKey: "walk")
        rig.rightArm.runAction(.repeatForever(.sequence([swingBack, swing])), forKey: "walk")
        rig.leftArm.runAction(.repeatForever(.sequence([swing, swingBack])), forKey: "walk")

        let bob = SCNAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.6, z: 0, duration: 0.28),
            .moveBy(x: 0, y: -0.6, z: 0, duration: 0.28),
        ]))
        rig.body.removeAction(forKey: "breathe")
        rig.body.runAction(bob, forKey: "walkBob")
    }

    private func stopWalkCycle() {
        guard isWalking else { return }
        isWalking = false
        for node in [rig.rightLeg, rig.leftLeg, rig.rightArm, rig.leftArm] {
            node.removeAction(forKey: "walk")
            node.runAction(.rotateTo(x: 0, y: CGFloat(node.eulerAngles.y), z: 0, duration: 0.2))
        }
        rig.body.removeAction(forKey: "walkBob")
        startIdleBreathing()
    }
}
