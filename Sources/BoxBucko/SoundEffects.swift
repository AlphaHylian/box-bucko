import AppKit

/// Tiny wrapper around the system sound bundle so BoxBucko gets some audio
/// personality without shipping any audio assets of its own.
enum SoundEffects {
    static func play(_ effect: Effect) {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: effect.systemSoundName)?.play()
    }

    enum Effect {
        case click
        case jump
        case pickUp
        case drop
        case newSkin
        case timerDone
        case reminder

        var systemSoundName: NSSound.Name {
            switch self {
            case .click: return "Tink"
            case .jump: return "Pop"
            case .pickUp: return "Morse"
            case .drop: return "Bottle"
            case .newSkin: return "Glass"
            case .timerDone: return "Glass"
            case .reminder: return "Ping"
            }
        }
    }
}
