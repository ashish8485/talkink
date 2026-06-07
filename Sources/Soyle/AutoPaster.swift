import AppKit
import CoreGraphics
import Carbon.HIToolbox   // kVK_ANSI_V, IsSecureEventInputEnabled

/// Pastes into the frontmost app by synthesising ⌘V. The transcript is already on
/// the clipboard, so if auto-paste is skipped the user can still paste manually.
enum AutoPaster {

    enum Result { case pasted, noAccessibility, secureField }

    /// Try to paste. Skips safely when Accessibility isn't granted (can't post
    /// events to other apps) or a secure input field is focused (OS blocks it).
    @discardableResult
    static func paste() -> Result {
        guard Permissions.hasAccessibility else { return .noAccessibility }
        if IsSecureEventInputEnabled() { return .secureField }

        // Fresh source so the user's physically-held modifiers (e.g. the PTT key)
        // don't contaminate the synthetic ⌘V.
        let src = CGEventSource(stateID: .privateState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        else { return .noAccessibility }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .pasted
    }
}
