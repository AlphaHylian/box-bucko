import Foundation
import CoreGraphics

/// Thin UserDefaults-backed settings store. Kept as plain properties (no
/// Combine/SwiftUI dependency) so it's usable from both AppKit and SceneKit code.
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let scale = "boxbucko.scale"
        static let wander = "boxbucko.wander"
        static let followCursor = "boxbucko.followCursor"
        static let speechBubbles = "boxbucko.speechBubbles"
        static let spontaneousAnimations = "boxbucko.spontaneousAnimations"
        static let flipTextureV = "boxbucko.flipTextureV"
        static let flipTextureH = "boxbucko.flipTextureH"
        static let currentSkinID = "boxbucko.currentSkinID"
        static let windowX = "boxbucko.windowX"
        static let windowY = "boxbucko.windowY"
        static let launchAtLogin = "boxbucko.launchAtLogin"
        static let soundEnabled = "boxbucko.soundEnabled"
        static let hasShownWelcome = "boxbucko.hasShownWelcome"
        static let pomodoroWorkMinutes = "boxbucko.pomodoroWorkMinutes"
        static let pomodoroBreakMinutes = "boxbucko.pomodoroBreakMinutes"
    }

    var scale: CGFloat {
        get {
            let v = defaults.double(forKey: Key.scale)
            return v == 0 ? 4.0 : CGFloat(v)
        }
        set { defaults.set(Double(newValue), forKey: Key.scale) }
    }

    var wanderEnabled: Bool {
        get { defaults.object(forKey: Key.wander) == nil ? true : defaults.bool(forKey: Key.wander) }
        set { defaults.set(newValue, forKey: Key.wander) }
    }

    var followCursorEnabled: Bool {
        get { defaults.bool(forKey: Key.followCursor) }
        set { defaults.set(newValue, forKey: Key.followCursor) }
    }

    var speechBubblesEnabled: Bool {
        get { defaults.object(forKey: Key.speechBubbles) == nil ? true : defaults.bool(forKey: Key.speechBubbles) }
        set { defaults.set(newValue, forKey: Key.speechBubbles) }
    }

    var spontaneousAnimationsEnabled: Bool {
        get { defaults.object(forKey: Key.spontaneousAnimations) == nil ? true : defaults.bool(forKey: Key.spontaneousAnimations) }
        set { defaults.set(newValue, forKey: Key.spontaneousAnimations) }
    }

    /// Escape hatch in case SceneKit's texture V-orientation doesn't match
    /// what `SkinModelBuilder` assumes on a given macOS/GPU combo.
    var flipTextureV: Bool {
        get { defaults.bool(forKey: Key.flipTextureV) }
        set { defaults.set(newValue, forKey: Key.flipTextureV) }
    }

    /// Escape hatch (menu bar toggle) for the horizontal analogue of
    /// `flipTextureV`, in case SceneKit's per-face UV winding turns out to
    /// need the opposite of what we assumed. Defaults to off.
    var flipTextureH: Bool {
        get { defaults.bool(forKey: Key.flipTextureH) }
        set { defaults.set(newValue, forKey: Key.flipTextureH) }
    }

    var currentSkinID: String? {
        get { defaults.string(forKey: Key.currentSkinID) }
        set { defaults.set(newValue, forKey: Key.currentSkinID) }
    }

    var soundEnabled: Bool {
        get { defaults.object(forKey: Key.soundEnabled) == nil ? true : defaults.bool(forKey: Key.soundEnabled) }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    /// Resets everything except the current skin selection (imported skin
    /// files themselves live in `SkinLibrary` and are untouched either way).
    func resetToDefaults() {
        for key in [
            Key.scale, Key.wander, Key.followCursor, Key.speechBubbles,
            Key.spontaneousAnimations, Key.flipTextureV, Key.flipTextureH, Key.windowX, Key.windowY,
            Key.soundEnabled,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Key.hasShownWelcome) }
        set { defaults.set(newValue, forKey: Key.hasShownWelcome) }
    }

    var pomodoroWorkMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.pomodoroWorkMinutes)
            return v == 0 ? 25 : v
        }
        set { defaults.set(newValue, forKey: Key.pomodoroWorkMinutes) }
    }

    var pomodoroBreakMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.pomodoroBreakMinutes)
            return v == 0 ? 5 : v
        }
        set { defaults.set(newValue, forKey: Key.pomodoroBreakMinutes) }
    }

    var lastWindowOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.windowX) != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.windowX), y: defaults.double(forKey: Key.windowY))
        }
        set {
            defaults.set(newValue.map { Double($0.x) }, forKey: Key.windowX)
            defaults.set(newValue.map { Double($0.y) }, forKey: Key.windowY)
        }
    }
}
