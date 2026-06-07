import AppKit

/// Writes transcribed text to the system clipboard, ready to paste anywhere (⌘V).
enum Clipboard {
    @discardableResult
    static func copy(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(text, forType: .string)
    }
}
