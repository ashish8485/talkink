import AppKit
import SwiftUI

/// Hosts the SwiftUI settings/onboarding window for the menu-bar app.
final class SettingsWindowController: NSWindowController {
    private let perms = PermissionsModel()

    init(settings: SettingsStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        super.init(window: window)

        window.title = "Söyle"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsView(settings: settings, perms: perms)
        )
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        perms.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
