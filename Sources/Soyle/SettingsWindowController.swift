import AppKit
import SwiftUI

/// Hosts the SwiftUI settings/onboarding window for the menu-bar app.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let perms = PermissionsModel()

    init(settings: SettingsStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        super.init(window: window)

        window.title = "Söyle"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: RootView(settings: settings, perms: perms)
        )
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        perms.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        perms.stopPolling()
    }
}
