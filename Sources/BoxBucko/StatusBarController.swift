import AppKit

/// Builds and manages the menu-bar (status item) UI: the little icon up top
/// and its dropdown menu of controls. No app windows involved.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var appController: AppController?

    init(appController: AppController) {
        self.appController = appController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "cube.transparent.fill", accessibilityDescription: "BoxBucko")
            image?.isTemplate = true
            button.image = image ?? NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "BoxBucko")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func rebuildMenu() {
        guard let menu = statusItem.menu, let app = appController else { return }
        menu.removeAllItems()

        let title = NSMenuItem(title: "BoxBucko", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let visibilityTitle = app.isPetVisible ? "Hide Bucko" : "Show Bucko"
        menu.addItem(makeItem(visibilityTitle, #selector(AppController.toggleVisibility), app))

        menu.addItem(.separator())

        menu.addItem(makeItem("Choose Skin…", #selector(AppController.chooseSkin), app))
        menu.addItem(makeItem("Reset to Default Skin", #selector(AppController.resetSkin), app))
        menu.addItem(skinLibraryMenuItem(app: app))
        if let isSlim = app.currentSkinIsSlim {
            let modelInfo = NSMenuItem(title: "Detected Model: \(isSlim ? "Slim (Alex)" : "Classic (Steve)")", action: nil, keyEquivalent: "")
            modelInfo.isEnabled = false
            menu.addItem(modelInfo)
        }

        menu.addItem(.separator())

        menu.addItem(makeItem("Spawn Another Bucko", #selector(AppController.spawnCompanion), app))
        menu.addItem(makeItem("Remove Extra Buckos", #selector(AppController.removeAllCompanions), app))

        menu.addItem(.separator())

        menu.addItem(animationsMenuItem(app: app))
        menu.addItem(sizeMenuItem(app: app))

        menu.addItem(.separator())

        menu.addItem(checkItem("Wander Around Screen", #selector(AppController.toggleWander), app, isOn: app.prefs.wanderEnabled))
        menu.addItem(checkItem("Follow Mouse Cursor", #selector(AppController.toggleFollowCursor), app, isOn: app.prefs.followCursorEnabled))
        menu.addItem(checkItem("Speech Bubbles", #selector(AppController.toggleSpeechBubbles), app, isOn: app.prefs.speechBubblesEnabled))
        menu.addItem(checkItem("Random Idle Animations", #selector(AppController.toggleSpontaneous), app, isOn: app.prefs.spontaneousAnimationsEnabled))
        menu.addItem(checkItem("Sound Effects", #selector(AppController.toggleSound), app, isOn: app.prefs.soundEnabled))
        menu.addItem(checkItem("Flip Texture (if skin looks wrong)", #selector(AppController.toggleFlipTexture), app, isOn: app.prefs.flipTextureV))

        let launchItem = checkItem("Launch at Login", #selector(AppController.toggleLaunchAtLogin), app, isOn: LaunchAtLogin.isEnabled)
        launchItem.isEnabled = LaunchAtLogin.isSupported
        if !LaunchAtLogin.isSupported {
            launchItem.toolTip = "Only available when running the packaged BoxBucko.app (see `make bundle`)."
        }
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("Reset All Preferences", #selector(AppController.resetAllPreferences), app))
        menu.addItem(.separator())
        menu.addItem(makeItem("About BoxBucko", #selector(AppController.showAbout), app))
        menu.addItem(makeItem("Quit BoxBucko", #selector(AppController.quit), app, keyEquivalent: "q"))
    }

    /// Swaps the menu bar icon for a little 1:1 render of the current skin's
    /// face, falling back to the generic cube glyph if none is available.
    func updateIcon(with faceIcon: NSImage?) {
        guard let button = statusItem.button else { return }
        if let faceIcon {
            button.image = faceIcon
        } else {
            let fallback = NSImage(systemSymbolName: "cube.transparent.fill", accessibilityDescription: "BoxBucko")
            fallback?.isTemplate = true
            button.image = fallback
        }
    }

    private func skinLibraryMenuItem(app: AppController) -> NSMenuItem {
        let item = NSMenuItem(title: "Skin Library", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let entries = SkinLibrary.shared.entries
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No saved skins yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for entry in entries {
                let entryItem = NSMenuItem(title: entry.name, action: #selector(AppController.selectSkinFromLibrary(_:)), keyEquivalent: "")
                entryItem.target = app
                entryItem.representedObject = entry.id
                entryItem.state = (entry.id == app.prefs.currentSkinID) ? .on : .off
                submenu.addItem(entryItem)
            }
            submenu.addItem(.separator())
            let renameItem = NSMenuItem(title: "Rename Current Skin…", action: #selector(AppController.renameCurrentSkin), keyEquivalent: "")
            renameItem.target = app
            submenu.addItem(renameItem)
            let exportItem = NSMenuItem(title: "Save Current Skin As…", action: #selector(AppController.exportCurrentSkin), keyEquivalent: "")
            exportItem.target = app
            submenu.addItem(exportItem)
            let removeItem = NSMenuItem(title: "Remove Current Skin From Library", action: #selector(AppController.removeCurrentSkinFromLibrary), keyEquivalent: "")
            removeItem.target = app
            submenu.addItem(removeItem)
        }
        item.submenu = submenu
        return item
    }

    private func animationsMenuItem(app: AppController) -> NSMenuItem {
        let item = NSMenuItem(title: "Animations", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(makeItem("Wave 👋", #selector(AppController.playWave), app))
        submenu.addItem(makeItem("Jump 🦘", #selector(AppController.playJump), app))
        submenu.addItem(makeItem("Dance 💃", #selector(AppController.playDance), app))
        submenu.addItem(makeItem("Sit / Stand", #selector(AppController.toggleSit), app))
        item.submenu = submenu
        return item
    }

    private func sizeMenuItem(app: AppController) -> NSMenuItem {
        let item = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let sizes: [(String, CGFloat)] = [("Small", 2.5), ("Medium", 4.0), ("Large", 6.0), ("Huge", 9.0)]
        for (label, value) in sizes {
            let sizeItem = NSMenuItem(title: label, action: #selector(AppController.setSize(_:)), keyEquivalent: "")
            sizeItem.target = app
            sizeItem.representedObject = value
            sizeItem.state = (abs(app.prefs.scale - value) < 0.01) ? .on : .off
            submenu.addItem(sizeItem)
        }
        item.submenu = submenu
        return item
    }

    private func makeItem(_ title: String, _ action: Selector, _ target: AnyObject, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    private func checkItem(_ title: String, _ action: Selector, _ target: AnyObject, isOn: Bool, keyEquivalent: String = "") -> NSMenuItem {
        let item = makeItem(title, action, target, keyEquivalent: keyEquivalent)
        item.state = isOn ? .on : .off
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
