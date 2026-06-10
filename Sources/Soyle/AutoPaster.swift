import AppKit
import CoreGraphics
import Carbon.HIToolbox   // kVK_ANSI_V, IsSecureEventInputEnabled

/// Pastes into the frontmost app by synthesising ⌘V. The transcript is already on
/// the clipboard, so if auto-paste is skipped the user can still paste manually.
enum AutoPaster {

    enum Result { case pasted, noAccessibility, secureField }

    /// True while the focused field is a secure input (password) field.
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    /// Try to paste. Skips safely when Accessibility isn't granted (can't post
    /// events to other apps) or a secure input field is focused (OS blocks it).
    @discardableResult
    static func paste() -> Result {
        guard Permissions.hasAccessibility else { return .noAccessibility }
        if IsSecureEventInputEnabled() { return .secureField }

        let src = CGEventSource(stateID: .privateState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        else { return .noAccessibility }

        down.flags = .maskCommand
        up.flags = .maskCommand
        // Post to the session tap (NOT .cghidEventTap): at the HID layer the OS
        // OR-combines currently-held hardware modifiers, so a still-held PTT
        // modifier (Right Option, etc.) would turn this into ⌘⌥V and fail to paste.
        // The session tap honours our explicit .maskCommand flags verbatim.
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return .pasted
    }
}
