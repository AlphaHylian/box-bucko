import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appController = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appController.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
