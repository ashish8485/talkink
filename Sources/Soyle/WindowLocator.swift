import AppKit
import ApplicationServices

/// Locates the window the user is working in, so the overlay can appear attached
/// to it instead of at a fixed screen position. Tries the focused window via
/// Accessibility first (precise; Talkink usually has it for auto-paste), then the
/// frontmost app's topmost standard window via the window list (no permission
/// needed — window bounds don't require Screen Recording, only names do).
/// Returns AppKit (bottom-left-origin) screen coordinates.
enum WindowLocator {

    static func activeWindowFrame() -> NSRect? {
        focusedWindowFrameViaAX() ?? frontWindowFrameViaWindowList()
    }

    // MARK: Accessibility — the actually-focused window of the frontmost app

    static func focusedWindowFrameViaAX() -> NSRect? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else { return nil }
        let win = winRef as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 1, size.height > 1 else { return nil }
        return appKitRect(fromQuartz: CGRect(origin: pos, size: size))
    }

    // MARK: Window list — topmost standard window of the frontmost app

    static func frontWindowFrameViaWindowList() -> NSRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {  // front-to-back z-order
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            // Skip tooltips/popovers — we want the document window.
            guard rect.width >= 150, rect.height >= 100 else { continue }
            return appKitRect(fromQuartz: rect)
        }
        return nil
    }

    /// Quartz rects have a top-left origin on the primary display; AppKit a bottom-left one.
    private static func appKitRect(fromQuartz r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
