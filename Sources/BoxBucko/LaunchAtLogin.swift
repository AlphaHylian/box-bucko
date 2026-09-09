import Foundation
import ServiceManagement

/// Wraps SMAppService, which requires the binary to actually be running from
/// an installed .app bundle (see `make bundle`) to register successfully.
/// When running via `swift run`, this is a harmless no-op that reports itself
/// unavailable so the menu can explain why the toggle is disabled.
enum LaunchAtLogin {
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported, #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("BoxBucko: launch-at-login toggle failed: \(error)")
            return false
        }
    }
}
