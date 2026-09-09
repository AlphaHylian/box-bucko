import AppKit
import SceneKit

/// Central coordinator: owns the pet window, the status bar menu, and wires
/// menu actions to behaviour. This is the closest thing the app has to a
/// "view controller" -- everything else is either UI (StatusBarController,
/// PetWindowController) or a plain data/model type.
final class AppController: NSObject {
    let prefs = Preferences.shared
    private(set) lazy var windowController = PetWindowController()
    private var companions: [PetWindowController] = []
    private var statusBarController: StatusBarController!
    private var cursorFollowTimer: Timer?
    private var idleSpeechTimer: Timer?

    /// The primary pet plus any spawned companions -- most behaviour (cursor
    /// follow, idle chatter) applies uniformly across all of them.
    private var allPets: [PetWindowController] { [windowController] + companions }

    func start() {
        NSApp.setActivationPolicy(.accessory) // no dock icon, no app switcher entry

        statusBarController = StatusBarController(appController: self)
        loadInitialSkin()
        windowController.show()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleContextMenuRequest(_:)),
            name: .boxBuckoRequestContextMenu, object: nil
        )

        if prefs.followCursorEnabled {
            startCursorFollow()
        }
        scheduleIdleSpeech()
    }

    private func loadInitialSkin() {
        if let id = prefs.currentSkinID, let entry = SkinLibrary.shared.entry(withID: id) {
            applySkin(url: SkinLibrary.shared.url(for: entry))
        } else {
            loadBundledDefaultSkin()
        }
    }

    private func loadBundledDefaultSkin() {
        guard let url = Bundle.module.url(forResource: "steve", withExtension: "png") else {
            NSLog("BoxBucko: missing bundled default skin")
            return
        }
        applySkin(url: url)
    }

    private var currentSkinURL: URL?

    private func applySkin(url: URL) {
        do {
            let loaded = try SkinTextureLoader.load(url: url)
            windowController.loadRig(texture: loaded.texture, slim: loaded.isSlim)
            currentSkinURL = url
        } catch {
            NSLog("BoxBucko: failed to load skin at \(url): \(error)")
        }
    }

    // MARK: - Companions

    @objc func spawnCompanion() {
        let companion = PetWindowController()
        if let url = currentSkinURL, let loaded = try? SkinTextureLoader.load(url: url) {
            companion.loadRig(texture: loaded.texture, slim: loaded.isSlim)
        } else if let url = Bundle.module.url(forResource: "steve", withExtension: "png"),
                  let loaded = try? SkinTextureLoader.load(url: url) {
            companion.loadRig(texture: loaded.texture, slim: loaded.isSlim)
        }
        // Nudge it away from wherever the main pet currently is so they don't overlap.
        let base = windowController.window.frame.origin
        let offset = CGPoint(x: CGFloat.random(in: -240...240), y: 0)
        let screen = companion.currentScreenFrame()
        let target = NSPoint(
            x: min(max(base.x + offset.x, screen.minX), screen.maxX - companion.window.frame.width),
            y: screen.minY
        )
        companion.window.setFrameOrigin(target)
        companion.show()
        if prefs.wanderEnabled {
            companion.animationController?.startWandering()
        }
        companions.append(companion)
        windowController.say("hi, meet my friend!")
    }

    @objc func removeAllCompanions() {
        for companion in companions {
            companion.animationController?.stopWandering()
            companion.hide()
        }
        companions.removeAll()
    }

    // MARK: - Menu actions

    var isPetVisible: Bool { windowController.isVisible }

    @objc func toggleVisibility() {
        if windowController.isVisible {
            windowController.hide()
        } else {
            windowController.show()
        }
    }

    @objc func chooseSkin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose a Minecraft Skin"
        panel.message = "Pick a 64x64 (or legacy 64x32) Minecraft skin PNG."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAndApply(url: url)
    }

    private func importAndApply(url: URL) {
        do {
            let entry = try SkinLibrary.shared.importSkin(from: url)
            prefs.currentSkinID = entry.id
            applySkin(url: SkinLibrary.shared.url(for: entry))
            SoundEffects.play(.newSkin)
            windowController.say("new fit! 😎")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't load that skin"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc func resetSkin() {
        prefs.currentSkinID = nil
        loadBundledDefaultSkin()
    }

    @objc func selectSkinFromLibrary(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let entry = SkinLibrary.shared.entry(withID: id) else { return }
        prefs.currentSkinID = id
        applySkin(url: SkinLibrary.shared.url(for: entry))
        SoundEffects.play(.newSkin)
        windowController.say("new fit! 😎")
    }

    @objc func removeCurrentSkinFromLibrary() {
        guard let id = prefs.currentSkinID, let entry = SkinLibrary.shared.entry(withID: id) else { return }
        SkinLibrary.shared.remove(entry)
        prefs.currentSkinID = nil
        loadBundledDefaultSkin()
    }

    @objc func playWave() { windowController.animationController?.playWave() }
    @objc func playJump() { windowController.animationController?.playJump() }
    @objc func playDance() { windowController.animationController?.playDance() }
    @objc func toggleSit() { windowController.animationController?.toggleSit() }

    @objc func setSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? CGFloat else { return }
        windowController.applyScale(value)
    }

    @objc func toggleWander() {
        prefs.wanderEnabled.toggle()
        for pet in allPets {
            if prefs.wanderEnabled {
                pet.animationController?.startWandering()
            } else {
                pet.animationController?.stopWandering()
            }
        }
    }

    @objc func toggleFollowCursor() {
        prefs.followCursorEnabled.toggle()
        if prefs.followCursorEnabled {
            startCursorFollow()
        } else {
            cursorFollowTimer?.invalidate()
            cursorFollowTimer = nil
        }
    }

    @objc func toggleSpeechBubbles() { prefs.speechBubblesEnabled.toggle() }
    @objc func toggleSpontaneous() { prefs.spontaneousAnimationsEnabled.toggle() }
    @objc func toggleSound() { prefs.soundEnabled.toggle() }

    @objc func toggleFlipTexture() {
        prefs.flipTextureV.toggle()
        // Re-apply the current skin so the texture transform picks up the change.
        if let id = prefs.currentSkinID, let entry = SkinLibrary.shared.entry(withID: id) {
            applySkin(url: SkinLibrary.shared.url(for: entry))
        } else {
            loadBundledDefaultSkin()
        }
    }

    @objc func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "BoxBucko"
        alert.informativeText = "A little Minecraft-skinned friend that lives in your menu bar.\nDrag it around, click it, or let it wander your screen."
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc private func handleContextMenuRequest(_ note: Notification) {
        guard let event = note.object as? NSEvent else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Wave", action: #selector(playWave), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Jump", action: #selector(playJump), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Dance", action: #selector(playDance), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Sit / Stand", action: #selector(toggleSit), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Choose Skin…", action: #selector(chooseSkin), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Bucko", action: #selector(toggleVisibility), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit BoxBucko", action: #selector(quit), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: event.locationInWindow, in: windowController.window.contentView)
    }

    // MARK: - Cursor follow

    private func startCursorFollow() {
        cursorFollowTimer?.invalidate()
        cursorFollowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateHeadTowardsCursor()
        }
    }

    private func updateHeadTowardsCursor() {
        let mouse = NSEvent.mouseLocation
        for pet in allPets {
            guard let rig = pet.rig else { continue }
            let windowFrame = pet.window.frame
            let headWorldX = windowFrame.midX
            let headWorldY = windowFrame.maxY - 40
            let dx = mouse.x - headWorldX
            let dy = mouse.y - headWorldY
            let maxDistance: CGFloat = 500
            let clampedDx = max(-maxDistance, min(maxDistance, dx))
            let clampedDy = max(-maxDistance, min(maxDistance, dy))
            let yaw = Float(max(-0.7, min(0.7, clampedDx / 220)))
            let pitch = Float(max(-0.5, min(0.5, -clampedDy / 260)))
            rig.head.eulerAngles.y = rig.head.eulerAngles.y * 0.7 + yaw * 0.3
            rig.head.eulerAngles.x = rig.head.eulerAngles.x * 0.7 + pitch * 0.3
        }
    }

    // MARK: - Idle speech

    private func scheduleIdleSpeech() {
        idleSpeechTimer?.invalidate()
        idleSpeechTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 20...50), repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.prefs.speechBubblesEnabled, let pet = self.allPets.filter({ $0.isVisible }).randomElement() {
                pet.say(SpeechBank.randomIdleThought())
            }
            self.scheduleIdleSpeech()
        }
    }
}
